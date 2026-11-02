import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/sync/bookshelf_sync.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_kind.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 記在記憶體裡的同步空間；版本是寫入次數。
class _MemoryStore implements SyncStore {
  final Map<String, (String, int)> files = {};
  int writes = 0;

  /// 下一次寫入前先插進別台的一次寫入（模擬兩台同時同步）。
  Future<void> Function()? beforeNextWrite;

  @override
  Future<void> check() async {}

  /// 每份檔整份讀了幾次。
  final Map<String, int> reads = {};

  /// 讀檔前先等它傳回的（模擬網路慢）；傳回 null 就不等。
  Future<void>? Function(String name)? beforeNextRead;

  @override
  Future<SyncFile?> read(String name) async {
    await beforeNextRead?.call(name);
    reads.update(name, (count) => count + 1, ifAbsent: () => 1);
    final file = files[name];
    return file == null ? null : SyncFile(file.$1, version: '${file.$2}');
  }

  @override
  Future<String?> version(String name) async {
    final file = files[name];
    return file == null ? null : '${file.$2}';
  }

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    final hook = beforeNextWrite;
    beforeNextWrite = null;
    if (hook != null) await hook();
    final current = files[name];
    if (ifAbsent && current != null) throw const SyncConflict();
    if (ifVersion != null && '${current?.$2}' != ifVersion) {
      throw const SyncConflict();
    }
    writes++;
    files[name] = (content, (current?.$2 ?? 0) + 1);
  }
}

/// 移出書架只刪資料庫裡的書；正文、封面檔這些不在測試裡。
class _Storage implements BookStorageService {
  _Storage(this.books, [List<String>? discarded]) : discarded = discarded ?? [];

  final BookDao books;

  /// 被移出書架、清掉正文與目錄的書（網址）。
  final List<String> discarded;

  @override
  Future<void> discardBook(Book book) {
    discarded.add(book.bookUrl);
    return books.deleteByUrl(book.bookUrl);
  }
}

/// 指定檔案讀不了的同步空間（模擬雲端對某一份檔回 403、或整個連不上）。
class _FailingStore extends _MemoryStore {
  /// 檔名 → 讀這份檔時丟的錯。
  final Map<String, SyncStoreException> failing = {};

  @override
  Future<SyncFile?> read(String name) {
    if (failing[name] case final error?) throw error;
    return super.read(name);
  }
}

/// 只有幾筆固定紀錄的資料種類，用來測整輪同步的流程。
class _FakeKind extends SyncKind {
  _FakeKind(this.name, this.records);

  @override
  final String name;
  final Map<String, SyncRecord> records;
  final Map<String, SyncRecord> received = {};

  @override
  bool get hasOwnTime => true;

  @override
  Future<Map<String, SyncRecord>> local() async => records;

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    received.addAll(remote);
    return remote;
  }
}

class _Phone {
  _Phone(
    _MemoryStore store,
    Directory dir,
    this.prefs, {
    DateTime Function()? clock,
  }) : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    books = BookDao(db);
    chapters = ChapterDao(db);
    sources = BookSourceDao(db);
    rules = ReplaceRuleDao(db);
    sync = SyncService(
      settings: SyncSettings(),
      bases: SyncBaseStorage(directory: () async => dir),
      storeFactory: (_, _, _) => store,
      bookDao: books,
      chapterDao: chapters,
      database: db,
      clock: clock,
      // 和 App 一樣的順序：進度最先，書架之後再一次。
      kinds: (service) => [
        progress(service),
        SourceSync(
          dao: sources,
          bookDao: books,
          prefs: prefs,
          move: (source, previousUrl) =>
              sources.saveEdited(source, previousUrl: previousUrl),
        ),
        ReplaceRuleSync(dao: rules),
        BookshelfSync(
          bookDao: books,
          storage: _Storage(books, discarded),
          isOpen: service.isBookOpen,
          download: downloaded.add,
          // 偏好設定兩台共用，改名的紀錄要各記各的。
          renames: BookRenames(prefs, namespace: dir.path),
        ),
        progress(service),
      ],
    );
  }

  ProgressSync progress(SyncService service) => ProgressSync(
    bookDao: books,
    chapterDao: chapters,
    isOpen: service.isBookOpen,
  );

  final AppDatabase db;

  /// 偏好設定在測試裡只有一份，兩台共用（書源改網址的紀錄、同步設定）。
  final SharedPreferences prefs;
  late final BookDao books;
  late final ChapterDao chapters;
  late final BookSourceDao sources;
  late final ReplaceRuleDao rules;
  late final SyncService sync;

  /// 照書架自動下載的書（網址）。
  final List<String> downloaded = [];

  /// 被移出書架、清掉的書（網址）。
  final List<String> discarded = [];

  Future<void> addBook(
    String url, {
    required List<String> toc,
    int chapterIndex = 0,
    int charOffset = 0,
    int time = 0,
    String name = '夜航',
    String author = '某人',
  }) async {
    await books.upsert(
      Book(
        bookUrl: url,
        name: name,
        author: author,
        isInBookshelf: true,
        chapterIndex: chapterIndex,
        charOffset: charOffset,
        durChapterTitle: toc[chapterIndex],
        durChapterTime: time,
        progressTime: time,
      ),
    );
    await chapters.insertChapters([
      for (final (i, title) in toc.indexed)
        BookChapter(url: '$url/$i', title: title, bookUrl: url, index: i),
    ]);
  }

  Future<Book> book(String url) async => (await books.getByUrl(url))!;
}

void main() {
  // 刪書源時會清它在快取裡的登入資料，快取找存放的資料夾要用到。
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryStore store;
  late _Phone a;
  late _Phone b;
  late Directory baseDir;

  // 兩台手機各一個資料庫，是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = _MemoryStore();
    final temp = await Directory.systemTemp.createTemp('nr-sync-test');
    baseDir = temp;
    addTearDown(() => temp.delete(recursive: true));
    a = _Phone(store, Directory('${temp.path}/a'), prefs);
    b = _Phone(store, Directory('${temp.path}/b'), prefs);
    addTearDown(a.db.close);
    addTearDown(b.db.close);
  });

  const toc = ['序', '第一章', '第二章', '第三章'];

  test('progress read on one phone lands on the other, matched by chapter '
      'title', () async {
    await a.addBook(
      'a-src',
      toc: toc,
      chapterIndex: 3,
      charOffset: 120,
      time: 200,
    );
    // B 的書源目錄多一章「楔子」，同一章的序號多 1。
    await b.addBook('b-src', toc: ['楔子', ...toc], time: 100);

    await a.sync.syncNow();
    await b.sync.syncNow();

    final book = await b.book('b-src');
    expect(book.chapterIndex, 4);
    expect(book.durChapterTitle, '第三章');
    expect(book.charOffset, 120);
    expect(b.sync.status.value.error, isNull);
  });

  test('opening a book without moving does not upload it again', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 2, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();
    await b.sync.syncNow();
    final writes = store.writes;

    // B 開書沒翻頁：位置一樣，時間更新。
    await b.books.updateProgress('b-src', 2, '第二章', 0);
    await b.sync.syncNow();
    await a.sync.syncNow();

    expect(store.writes, writes);
    expect((await a.book('a-src')).chapterIndex, 2);
  });

  test('two phones syncing at once keep both books', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 1, time: 200);
    await b.books.upsert(
      Book(
        bookUrl: 'other',
        name: '別本',
        author: '別人',
        isInBookshelf: true,
        chapterIndex: 5,
        durChapterTitle: 'x',
        durChapterTime: 300,
      ),
    );
    // A 讀完雲端、還沒寫回時，B 先寫了一次。
    store.beforeNextWrite = () => b.sync.syncNow();
    await a.sync.syncNow();
    await b.sync.syncNow();

    expect(store.files['progress.json']!.$1, contains('別本'));
    expect(store.files['progress.json']!.$1, contains('夜航'));
  });

  test(
    'an open book is left to the reader, which commits after jumping',
    () async {
      await a.addBook('a-src', toc: toc, chapterIndex: 3, time: 200);
      await b.addBook('b-src', toc: toc, time: 100);
      await a.sync.syncNow();

      final opened = await b.book('b-src');
      b.sync.openBook(opened);
      await b.sync.syncNow();
      expect((await b.book('b-src')).chapterIndex, 0, reason: '開著的書不在背景改');

      final pulled = await b.sync.pullProgress('b-src');
      expect(pulled, isNotNull);
      expect(pulled!.progress.chapterIndex, 3);

      // 閱讀器跳過去、存好位置後記成已同步；之後同步不再把它當新改動上傳。
      await b.books.updateProgress('b-src', 3, '第三章', 7);
      await pulled.commit(ProgressSync.recordOf(await b.book('b-src')));
      b.sync.closeBook(opened);
      final writes = store.writes;
      await b.sync.syncNow();
      expect(store.writes, writes);
      expect(await b.sync.pullProgress('b-src'), isNull);
    },
  );

  test('nothing configured: nothing happens', () async {
    final idle = SyncService(
      settings: SyncSettings(),
      storeFactory: (space, _, _) => space == SyncSpace.none ? null : store,
    );
    await idle.syncNow();
    expect(await idle.pullProgress('x'), isNull);
    expect(store.writes, 0);
  });

  test('a chapter inserted before the reading position does not make the '
      'phones overwrite each other', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 1, time: 100);
    await b.addBook('b-src', toc: toc, chapterIndex: 1, time: 100);
    await a.sync.syncNow();
    await b.sync.syncNow();

    // B 的書源在前面插了一章：同一章的序號從 1 變 2，讀到的地方沒變
    // （書架檢查更新照章節網址重新對位，時間不動）。
    final moved = (await b.book('b-src')).copyWith(chapterIndex: 2);
    await b.books.upsert(moved);
    final writes = store.writes;
    for (var round = 0; round < 3; round++) {
      await a.sync.syncNow();
      await b.sync.syncNow();
    }

    expect(store.writes, writes);
    expect((await a.book('a-src')).chapterIndex, 1);
    expect((await b.book('b-src')).chapterIndex, 2);
  });

  test('opening a book that never synced does not beat newer progress from '
      'the other phone', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 3, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();

    // B 還沒同步過就開書，沒翻頁：最近閱讀時間變新，位置移動的時間不變。
    expect(await b.books.updateProgress('b-src', 0, '序', 0), isNull);
    await b.sync.syncNow();

    expect((await b.book('b-src')).chapterIndex, 3);
    expect(store.files['progress.json']!.$1, contains('第三章'));
  });

  test('reading on after the jump, before commit, is still uploaded', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 2, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();

    final pulled = await b.sync.pullProgress('b-src');
    await b.books.updateProgress('b-src', 2, '第二章', 0);
    final saved = ProgressSync.recordOf(await b.book('b-src'));
    // 等 commit 的期間又讀到第三章。
    await b.books.updateProgress('b-src', 3, '第三章', 123);
    await pulled!.commit(saved);
    await b.sync.syncNow();

    expect(store.files['progress.json']!.$1, contains('第三章'));
  });

  test('a book opened while the sync is writing is left alone', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 2, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();
    // B 另一本書讀過，這次同步要寫雲端；寫的時候使用者打開了夜航、讀到第三章。
    await b.books.upsert(
      Book(
        bookUrl: 'other',
        name: '別本',
        author: '別人',
        isInBookshelf: true,
        durChapterTitle: 'x',
        progressTime: 300,
      ),
    );
    store.beforeNextWrite = () async {
      b.sync.openBook(await b.book('b-src'));
      await b.books.updateProgress('b-src', 3, '第三章', 5);
    };
    await b.sync.syncNow();

    final book = await b.book('b-src');
    expect(book.chapterIndex, 3);
    expect(book.charOffset, 5);
  });

  test('after coming back to the app, progress is ready before the rest of '
      'the sync, and a book added on the other phone gets its progress in the '
      'same sync', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 2, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.books.upsert(
      Book(
        bookUrl: 'new',
        name: '新書',
        author: '別人',
        origin: 'src',
        isInBookshelf: true,
        chapterIndex: 3,
        durChapterTitle: '第三章',
        progressTime: 300,
      ),
    );
    await a.sync.syncNow();

    // B 回到 App：書源那一步卡在讀雲端（例如網路慢）時，進度已經好了。
    final stuck = Completer<void>();
    store.beforeNextRead = (name) =>
        name == 'sources.json' ? stuck.future : null;
    b.sync.syncAfterResume();
    await b.sync.progressReady!.timeout(const Duration(seconds: 5));
    expect((await b.book('b-src')).chapterIndex, 2);
    expect(b.sync.progressReady, isNull);

    stuck.complete();
    await b.sync.syncNow();
    expect((await b.book('new')).chapterIndex, 3);
  });

  test('the open reader pulls its progress without waiting for the sync '
      'running in the background', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 2, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();

    // B 另有一本書要送上去；背景同步卡在寫雲端（例如網路慢）的時候開書。
    await b.books.upsert(
      Book(
        bookUrl: 'other',
        name: '別本',
        author: '別人',
        isInBookshelf: true,
        durChapterTitle: 'x',
        progressTime: 300,
      ),
    );
    final stuck = Completer<void>();
    final writing = Completer<void>();
    store.beforeNextWrite = () {
      writing.complete();
      return stuck.future;
    };
    final background = b.sync.syncNow();
    await writing.future;

    final pulled = await b.sync
        .pullProgress('b-src')
        .timeout(const Duration(seconds: 5));
    expect(pulled?.progress.chapterIndex, 2);

    stuck.complete();
    await background;
  });

  test('progress saved while a sync is running is uploaded right after the '
      'step in progress, not after the whole sync', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 1, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();

    // A 的完整同步卡在讀書源（例如網路慢）。
    final order = <String>[];
    final reading = Completer<void>();
    final stuck = Completer<void>();
    store.beforeNextRead = (name) {
      order.add(name);
      if (name != 'sources.json' || reading.isCompleted) return null;
      reading.complete();
      return stuck.future;
    };
    final running = a.sync.syncNow();
    await reading.future;

    // 這時 A 離開閱讀器：進度存好，要求同步。
    await a.books.updateProgress('a-src', 3, '第三章', 77);
    a.sync.requestSyncProgressFirst();
    stuck.complete();
    await running;

    // 書源那一步做完，馬上把進度送上去，再做替換規則這些。
    final afterSources = order.sublist(order.indexOf('sources.json'));
    expect(
      afterSources.indexOf('progress.json'),
      lessThan(afterSources.indexOf('replace_rules.json')),
    );
    expect(store.files['progress.json']!.$1, contains('第三章'));

    store.beforeNextRead = null;
    await b.sync.syncNow();
    final read = await b.book('b-src');
    expect(read.durChapterTitle, '第三章');
    expect(read.charOffset, 77);
  });

  test('progress asked for first while nothing is running is the first thing '
      'uploaded', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 1, time: 200);
    await a.sync.syncNow();
    await a.books.updateProgress('a-src', 2, '第二章', 5);
    final order = <String>[];
    store.beforeNextRead = (name) {
      order.add(name);
      return null;
    };

    a.sync.requestSyncProgressFirst();
    await a.sync.syncNow();

    expect(order.first, 'progress.json');
    expect(store.files['progress.json']!.$1, contains('第二章'));
  });

  test('progress pulled before turning sync off is not recorded', () async {
    await a.addBook('a-src', toc: toc, chapterIndex: 2, time: 200);
    await b.addBook('b-src', toc: toc, time: 100);
    await a.sync.syncNow();

    final pulled = await b.sync.pullProgress('b-src');
    await b.sync.disable();
    await pulled!.commit(ProgressSync.recordOf(await b.book('b-src')));

    final base = await SyncBaseStorage(
      directory: () async => Directory('${baseDir.path}/b'),
    ).read(ProgressSync.kind);
    expect(base, isEmpty);
  });

  group('bookshelf', () {
    test('a book added on one phone joins the other shelf with its progress, '
        'and starts downloading', () async {
      await a.addBook(
        'a-src',
        toc: toc,
        chapterIndex: 2,
        charOffset: 30,
        time: 200,
      );
      await a.sync.syncNow();
      await b.sync.syncNow();

      final book = await b.book('a-src');
      expect(book.isInBookshelf, isTrue);
      expect(book.name, '夜航');
      expect(book.durChapterTitle, '第二章');
      expect(book.charOffset, 30);
      expect(b.downloaded, ['a-src']);
      expect(b.sync.status.value.error, isNull);
    });

    test('a book removed from one shelf leaves the other shelf too', () async {
      await a.addBook('a-src', toc: toc, time: 200);
      await a.sync.syncNow();
      await b.sync.syncNow();
      expect(await b.books.getByUrl('a-src'), isNotNull);

      await a.books.deleteByUrl('a-src');
      await a.sync.syncNow();
      await b.sync.syncNow();

      expect(await b.books.getByUrl('a-src'), isNull);
    });

    test('a book open in the reader is removed only after it closes', () async {
      await a.addBook('a-src', toc: toc, time: 200);
      await a.sync.syncNow();
      await b.sync.syncNow();
      await a.books.deleteByUrl('a-src');
      await a.sync.syncNow();

      final open = await b.book('a-src');
      b.sync.openBook(open);
      await b.sync.syncNow();
      expect(await b.books.getByUrl('a-src'), isNotNull);

      b.sync.closeBook(open);
      await b.sync.syncNow();
      expect(await b.books.getByUrl('a-src'), isNull);
    });

    test('a book opened while the sync is applying is not removed', () async {
      await a.addBook('a-src', toc: toc, time: 200);
      await a.sync.syncNow();
      await b.sync.syncNow();
      await a.books.deleteByUrl('a-src');
      await a.sync.syncNow();

      // 合併時還沒開，套用前一刻才打開。
      var checks = 0;
      final late = SyncService(
        settings: SyncSettings(),
        bases: SyncBaseStorage(
          directory: () async => Directory('${baseDir.path}/b'),
        ),
        storeFactory: (_, _, _) => store,
        kinds: (_) => [
          BookshelfSync(
            bookDao: b.books,
            storage: _Storage(b.books),
            isOpen: (_) => ++checks > 2,
          ),
        ],
      );
      await late.syncNow();

      expect(await b.books.getByUrl('a-src'), isNotNull);
    });

    test('a cover changed on one phone reaches the other; different sources '
        'for the same book are left alone', () async {
      await a.addBook('a-src', toc: toc, time: 200);
      await b.addBook('b-src', toc: toc, time: 100);
      await a.sync.syncNow();
      await b.sync.syncNow();

      await a.books.upsert(
        (await a.book('a-src'))..customCoverUrl = 'https://img/cover.jpg',
      );
      await a.sync.syncNow();
      await b.sync.syncNow();

      final book = await b.book('b-src');
      expect(book.customCoverUrl, 'https://img/cover.jpg');
      expect(await b.books.getByUrl('a-src'), isNull, reason: 'B 照舊用自己的書源');
    });
    group('renamed on one phone', () {
      Future<void> syncBoth() async {
        await a.sync.syncNow();
        await b.sync.syncNow();
      }

      Future<void> rename(
        _Phone phone,
        String url, {
        String? name,
        String? author,
      }) async {
        final book = await phone.book(url);
        if (name != null) book.name = name;
        if (author != null) book.author = author;
        await phone.books.upsert(book);
      }

      test('a new title keeps the other phone\'s book, chapters and '
          'download', () async {
        await a.addBook('src', toc: toc, time: 200);
        await b.addBook('src', toc: toc, time: 100);
        await syncBoth();
        b.downloaded.clear();

        await rename(a, 'src', name: '新夜航');
        await syncBoth();

        final book = await b.book('src');
        expect(book.name, '新夜航');
        expect(book.author, '某人');
        expect(book.isInBookshelf, isTrue);
        expect(await b.chapters.titlesByBook('src'), toc);
        expect(b.discarded, isEmpty);
        expect(b.downloaded, isEmpty);
        expect(await b.books.getInBookshelf(), hasLength(1));
        expect(b.sync.status.value.error, isNull);

        // 之後兩台都不再有東西要送。
        final writes = store.writes;
        await syncBoth();
        await syncBoth();
        expect(store.writes, writes);
        expect((await a.book('src')).name, '新夜航');
        expect(b.discarded, isEmpty);
      });

      test('a new author works the same way', () async {
        await a.addBook('src', toc: toc, time: 200);
        await b.addBook('src', toc: toc, time: 100);
        await syncBoth();

        await rename(a, 'src', author: '另一個人');
        await syncBoth();

        final book = await b.book('src');
        expect(book.name, '夜航');
        expect(book.author, '另一個人');
        expect(await b.chapters.titlesByBook('src'), toc);
        expect(b.discarded, isEmpty);
      });

      test('the other phone on another source keeps its own book', () async {
        await a.addBook('a-src', toc: toc, time: 200);
        await b.addBook('b-src', toc: ['楔子', ...toc], time: 100);
        await syncBoth();

        await rename(a, 'a-src', name: '新夜航', author: '新作者');
        await syncBoth();

        final book = await b.book('b-src');
        expect(book.name, '新夜航');
        expect(book.author, '新作者');
        expect(await b.chapters.titlesByBook('b-src'), ['楔子', ...toc]);
        expect(await b.books.getByUrl('a-src'), isNull);
        expect(b.discarded, isEmpty);
        expect(b.downloaded, isEmpty);
      });

      test('renamed twice before syncing still lands as one rename', () async {
        await a.addBook('src', toc: toc, time: 200);
        await b.addBook('src', toc: toc, time: 100);
        await syncBoth();

        await rename(a, 'src', name: '第二個名字');
        await a.sync.syncNow();
        await rename(a, 'src', name: '第三個名字');
        await syncBoth();

        expect((await b.book('src')).name, '第三個名字');
        expect(b.discarded, isEmpty);
        expect(await b.books.getInBookshelf(), hasLength(1));
      });

      test(
        'reading on after the rename still reaches the other phone',
        () async {
          await a.addBook('src', toc: toc, time: 200);
          await b.addBook('src', toc: toc, time: 100);
          await syncBoth();

          await rename(a, 'src', name: '新夜航');
          await a.books.updateProgress('src', 3, '第三章', 40);
          await syncBoth();

          final book = await b.book('src');
          expect(book.name, '新夜航');
          expect(book.chapterIndex, 3);
          expect(book.charOffset, 40);
        },
      );

      test('further progress on the other phone survives the rename', () async {
        await a.addBook('src', toc: toc, chapterIndex: 1, time: 200);
        await b.addBook('src', toc: toc, chapterIndex: 1, time: 200);
        await syncBoth();

        await b.books.updateProgress('src', 3, '第三章', 70);
        await rename(a, 'src', name: '新夜航');
        await syncBoth();
        await a.sync.syncNow();

        expect((await b.book('src')).name, '新夜航');
        expect((await b.book('src')).chapterIndex, 3);
        expect((await a.book('src')).chapterIndex, 3);
        expect((await a.book('src')).charOffset, 70);
      });

      test('a book open in the reader is renamed after it closes', () async {
        await a.addBook('src', toc: toc, time: 200);
        await b.addBook('src', toc: toc, time: 100);
        await syncBoth();

        await rename(a, 'src', name: '新夜航');
        await a.sync.syncNow();
        final open = await b.book('src');
        b.sync.openBook(open);
        await b.sync.syncNow();
        expect((await b.book('src')).name, '夜航');
        expect(b.discarded, isEmpty);

        b.sync.closeBook(open);
        await b.sync.syncNow();
        expect((await b.book('src')).name, '新夜航');
        expect(b.discarded, isEmpty);
        expect(await b.books.getInBookshelf(), hasLength(1));
      });

      test('a book really removed from the shelf is still removed', () async {
        await a.addBook('src', toc: toc, time: 200);
        await b.addBook('src', toc: toc, time: 100);
        await syncBoth();

        await rename(a, 'src', name: '新夜航');
        await a.sync.syncNow();
        await a.books.deleteByUrl('src');
        await syncBoth();

        expect(await b.books.getByUrl('src'), isNull);
      });

      test('an old title the other phone added again is not renamed', () async {
        await a.addBook('src', toc: toc, time: 200);
        await b.addBook('src', toc: toc, time: 100);
        await syncBoth();
        await rename(a, 'src', name: '新夜航');
        await syncBoth();

        // B 之後另外加了一本和舊書名同名的書（不同網址）。
        await b.addBook('other', toc: toc, time: 300);
        await syncBoth();
        await syncBoth();

        expect((await b.book('src')).name, '新夜航');
        expect((await b.book('other')).name, '夜航');
        expect((await a.book('other')).name, '夜航');
        expect(b.discarded, isEmpty);
      });
    });
  });

  group('sources', () {
    BookSource source(String name, {int respondTime = 180000}) => BookSource(
      bookSourceUrl: 'https://src.example',
      bookSourceName: name,
      respondTime: respondTime,
    );

    test('an edited source reaches the other phone; the response time '
        'measured on each phone stays its own', () async {
      await a.sources.upsert(source('書源'));
      await a.sync.syncNow();
      await b.sync.syncNow();

      // B 量到的回應時間不算改了書源。
      await b.sources.upsert(source('書源', respondTime: 999));
      final writes = store.writes;
      await b.sync.syncNow();
      expect(store.writes, writes);

      await a.sources.upsert(source('改名的書源'));
      await a.sync.syncNow();
      await b.sync.syncNow();
      final synced = (await b.sources.getByUrl('https://src.example'))!;
      expect(synced.bookSourceName, '改名的書源');
      expect(synced.respondTime, 999);
    });

    test('a source deleted on one phone is deleted on the other', () async {
      await a.sources.upsert(source('書源'));
      await a.sync.syncNow();
      await b.sync.syncNow();

      await a.sources.deleteByUrl('https://src.example');
      await a.sync.syncNow();
      await b.sync.syncNow();

      expect(await b.sources.getByUrl('https://src.example'), isNull);
    });

    test('sources unchanged on both sides are not read again; an edit is '
        'still sent', () async {
      await a.sources.upsert(source('書源'));
      await a.sync.start();
      await a.sync.syncNow();
      final reads = store.reads['sources.json'];

      await a.sync.syncNow();
      expect(store.reads['sources.json'], reads, reason: '兩邊都沒變，只問版本');

      await a.sources.upsert(source('改名的書源'));
      await pumpEventQueue();
      await a.sync.syncNow();
      expect(store.files['sources.json']!.$1, contains('改名的書源'));

      // 別台改了雲端：版本不同，整份讀回來。
      await b.sync.syncNow();
      await b.sources.upsert(source('別台改的'));
      await b.sync.syncNow();
      await a.sync.syncNow();
      expect(
        (await a.sources.getByUrl('https://src.example'))!.bookSourceName,
        '別台改的',
      );
    });

    test('a source whose address changed moves the other phone\'s books to '
        'the new address', () async {
      await a.sources.upsert(source('書源'));
      await b.sources.upsert(source('書源'));
      await b.books.upsert(
        Book(
          bookUrl: 'b-book',
          name: '夜航',
          author: '某人',
          origin: 'https://src.example',
          isInBookshelf: true,
        ),
      );
      await a.sync.syncNow();
      await b.sync.syncNow();

      // A 編輯書源改了網址（同 BookSourceService.saveEditedSource）。
      final moved = BookSource(
        bookSourceUrl: 'https://new.example',
        bookSourceName: '書源',
      );
      await a.sources.saveEdited(moved, previousUrl: 'https://src.example');
      await SourceMoves(a.prefs)
          .record(from: 'https://src.example', to: 'https://new.example');
      await a.sync.syncNow();
      await b.sync.syncNow();

      expect(await b.sources.getByUrl('https://src.example'), isNull);
      expect(await b.sources.getByUrl('https://new.example'), isNotNull);
      expect((await b.book('b-book')).origin, 'https://new.example');
    });

    test('a phone syncing for the first time does not overwrite the cloud '
        'with its own copy', () async {
      await a.sources.upsert(source('新的'));
      await a.sync.syncNow();
      await b.sources.upsert(source('舊的'));
      await b.sync.syncNow();

      expect(
        (await b.sources.getByUrl('https://src.example'))!.bookSourceName,
        '新的',
      );
      expect(store.files['sources.json']!.$1, contains('新的'));
    });
  });

  group('replace rules', () {
    test('new rules are numbered by the time they were made', () async {
      final id = await a.rules.insert(ReplaceRule(name: '新', pattern: 'x'));
      expect(id, greaterThan(1000000000000));
    });

    test('old rules sharing a number keep both; the same rule under another '
        'number is not duplicated', () async {
      await a.rules.upsertAll([
        ReplaceRule(id: 1, name: '甲', pattern: 'a'),
        ReplaceRule(id: 2, name: '乙', pattern: 'b'),
      ]);
      await b.rules.upsertAll([
        ReplaceRule(id: 1, name: '丙', pattern: 'c'),
        ReplaceRule(id: 3, name: '乙', pattern: 'b', order: 5),
      ]);

      await a.sync.syncNow();
      await b.sync.syncNow();
      await a.sync.syncNow();

      Future<Map<int, String>> rulesOf(_Phone phone) async => {
        for (final rule in await phone.rules.getAll()) rule.id: rule.name,
      };
      final onA = await rulesOf(a);
      final onB = await rulesOf(b);
      expect(onA.values, unorderedEquals(['甲', '乙', '丙']));
      expect(onB, onA);
    });

    test('rules that swapped numbers on the two phones are not '
        'duplicated', () async {
      await a.rules.upsertAll([
        ReplaceRule(id: 1, name: '甲', pattern: 'a'),
        ReplaceRule(id: 2, name: '乙', pattern: 'b'),
      ]);
      await b.rules.upsertAll([
        ReplaceRule(id: 1, name: '乙', pattern: 'b'),
        ReplaceRule(id: 2, name: '甲', pattern: 'a'),
      ]);
      await a.sync.syncNow();
      await b.sync.syncNow();

      final onB = {
        for (final rule in await b.rules.getAll()) rule.id: rule.name,
      };
      expect(onB, {1: '甲', 2: '乙'});
    });

    test('rules added at the same moment both stay', () async {
      // 已有的規則編號比現在的時間還大，兩條新的都會想接在它後面。
      final future = DateTime.now().millisecondsSinceEpoch + 600000;
      await a.rules.upsert(ReplaceRule(id: future, name: '舊', pattern: 'o'));
      await Future.wait([
        a.rules.upsert(ReplaceRule(name: '一', pattern: '1')),
        a.rules.upsert(ReplaceRule(name: '二', pattern: '2')),
      ]);
      expect(await a.rules.getAll(), hasLength(3));
    });

    test('undoing a hidden selection still works after the rule took the '
        'cloud\'s number', () async {
      await b.rules.insert(ReplaceRule(name: '選字隱藏', pattern: '廣告'));
      await b.sync.syncNow();
      // A 也隱藏了同一段，還沒同步；拿著新增時的編號等使用者按復原。
      final id = await a.rules.insert(ReplaceRule(name: '選字隱藏', pattern: '廣告'));
      await a.sync.syncNow();
      expect(await a.rules.getAll(), hasLength(1));

      await a.rules.deleteById(id);
      expect(await a.rules.getAll(), isEmpty);
    });
  });

  test('a sync space changed behind the service\'s back (restoring a backup) '
      'starts over instead of pushing old data', () async {
    final other = _MemoryStore();
    var useOther = false;
    final prefs = a.prefs;
    final phone = SyncService(
      settings: SyncSettings(prefs),
      bases: SyncBaseStorage(
        directory: () async => Directory('${baseDir.path}/restore'),
      ),
      storeFactory: (_, _, _) => useOther ? other : store,
      kinds: (_) => [
        SourceSync(dao: a.sources, bookDao: a.books, prefs: prefs),
      ],
    );
    Future<void> useAccount(String url) async {
      await prefs.setString('sync.space', 'webdav');
      await prefs.setString('sync.webdav.url', url);
    }

    BookSource named(String name) =>
        BookSource(bookSourceUrl: 'https://src.example', bookSourceName: name);

    await useAccount('https://one.example');
    await a.sources.upsert(named('舊'));
    await phone.syncNow();

    // 另一個空間裡已經有較新的；還原備份直接把設定換成那個空間。
    await b.sources.upsert(named('另一個空間較新的'));
    await SyncService(
      settings: SyncSettings(prefs),
      bases: SyncBaseStorage(
        directory: () async => Directory('${baseDir.path}/other'),
      ),
      storeFactory: (_, _, _) => other,
      kinds: (_) => [
        SourceSync(dao: b.sources, bookDao: b.books, prefs: prefs),
      ],
    ).syncNow();
    useOther = true;
    await useAccount('https://two.example');
    await a.sources.upsert(named('備份裡的舊資料'));
    await phone.syncNow();

    expect(other.files['sources.json']!.$1, contains('另一個空間較新的'));
    expect(
      (await a.sources.getByUrl('https://src.example'))!.bookSourceName,
      '另一個空間較新的',
    );
  });

  group('one failing file', () {
    late _FailingStore failing;
    late _FakeKind first;
    late _FakeKind second;
    late SyncService service;
    final syncedAt = DateTime.utc(2026, 11, 2);

    setUp(() {
      failing = _FailingStore();
      first = _FakeKind('first', {
        'a': const SyncRecord(time: 1, data: {'v': 1}),
      });
      second = _FakeKind('second', {
        'b': const SyncRecord(time: 1, data: {'v': 2}),
      });
      service = SyncService(
        settings: SyncSettings(),
        bases: SyncBaseStorage(
          directory: () async => Directory('${baseDir.path}/failing'),
        ),
        storeFactory: (_, _, _) => failing,
        kinds: (_) => [first, second],
        clock: () => syncedAt,
      );
    });

    test('a refused file does not stop the other kinds, but the round still '
        'fails and keeps the first error', () async {
      failing.failing['first.json'] = const SyncStoreException.file('單一檔案拒絕存取');

      await service.syncNow();

      expect(failing.files['second.json'], isNotNull);
      expect(failing.files['first.json'], isNull);
      expect(service.status.value.error, '單一檔案拒絕存取');
      expect(service.status.value.running, isFalse);
      expect(service.status.value.lastSyncAt, isNull);

      // 好了之後，下一輪補上，錯誤清掉、成功時間更新。
      failing.failing.clear();
      await service.syncNow();
      expect(failing.files['first.json'], isNotNull);
      expect(service.status.value.error, isNull);
      expect(service.status.value.lastSyncAt, syncedAt);
    });

    test('the first error is the one reported', () async {
      failing.failing['first.json'] = const SyncStoreException.file('第一個');
      failing.failing['second.json'] = const SyncStoreException.file('第二個');

      await service.syncNow();

      expect(service.status.value.error, '第一個');
    });

    test('a space that is down stops the whole round', () async {
      failing.failing['first.json'] = const SyncStoreException('連不上同步空間');

      await service.syncNow();

      expect(failing.files['second.json'], isNull);
      expect(service.status.value.error, '連不上同步空間');
      expect(service.status.value.lastSyncAt, isNull);
    });
  });
}
