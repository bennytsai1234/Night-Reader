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

  @override
  Future<SyncFile?> read(String name) async {
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
  _Storage(this.books);

  final BookDao books;

  @override
  Future<void> discardBook(Book book) => books.deleteByUrl(book.bookUrl);
}

class _Phone {
  _Phone(_MemoryStore store, Directory dir, {DateTime Function()? clock})
    : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    books = BookDao(db);
    chapters = ChapterDao(db);
    sources = BookSourceDao(db);
    rules = ReplaceRuleDao(db);
    sync = SyncService(
      settings: SyncSettings(),
      bases: SyncBaseStorage(directory: () async => dir),
      storeFactory: (_, _) => store,
      bookDao: books,
      chapterDao: chapters,
      database: db,
      clock: clock,
      kinds: (service) => [
        SourceSync(dao: sources),
        ReplaceRuleSync(dao: rules),
        BookshelfSync(
          bookDao: books,
          storage: _Storage(books),
          isOpen: service.isBookOpen,
          download: downloaded.add,
        ),
        service.progressKind,
      ],
    );
  }

  final AppDatabase db;
  late final BookDao books;
  late final ChapterDao chapters;
  late final BookSourceDao sources;
  late final ReplaceRuleDao rules;
  late final SyncService sync;

  /// 照書架自動下載的書（網址）。
  final List<String> downloaded = [];

  Future<void> addBook(
    String url, {
    required List<String> toc,
    int chapterIndex = 0,
    int charOffset = 0,
    int time = 0,
  }) async {
    await books.upsert(
      Book(
        bookUrl: url,
        name: '夜航',
        author: '某人',
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
  late _MemoryStore store;
  late _Phone a;
  late _Phone b;
  late Directory baseDir;

  // 兩台手機各一個資料庫，是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _MemoryStore();
    final temp = await Directory.systemTemp.createTemp('nr-sync-test');
    baseDir = temp;
    addTearDown(() => temp.delete(recursive: true));
    a = _Phone(store, Directory('${temp.path}/a'));
    b = _Phone(store, Directory('${temp.path}/b'));
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
      storeFactory: (space, _) => space == SyncSpace.none ? null : store,
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
  });
}
