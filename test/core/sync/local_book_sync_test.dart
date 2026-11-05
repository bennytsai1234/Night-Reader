import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/local_book/local_book_fingerprint.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/sync/local_book_sync.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/sync_store_blobs.dart';

/// 記在記憶體裡的同步空間；版本是寫入次數。
class _MemoryStore with SyncStoreBlobs implements SyncStore {
  final Map<String, (String, int)> files = {};

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async {
    final file = files[name];
    return file == null ? null : SyncFile(file.$1, version: '${file.$2}');
  }

  @override
  Future<String?> version(String name) async {
    final file = files[name];
    return file == null ? null : '${file.$2}';
  }

  /// 寫入前先跑它（模擬別台同時寫入）；傳回 null 時照常寫。
  Future<void> Function(String name)? beforeWrite;

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    await beforeWrite?.call(name);
    final current = files[name];
    if (ifAbsent && current != null) throw const SyncConflict();
    if (ifVersion != null && '${current?.$2}' != ifVersion) {
      throw const SyncConflict();
    }
    files[name] = (content, (current?.$2 ?? 0) + 1);
  }

  Map<String, SyncRecord> get records => files[LocalBookSync.fileName] == null
      ? {}
      : SyncDocument.decode(files[LocalBookSync.fileName]!.$1).records;
}

/// 一台手機自己的 App 資料夾（本地書、封面、上次同步的紀錄）。
class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'docs');

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'temp');
}

class _Phone {
  _Phone(this.store, this.root)
    : db = AppDatabase.forTesting(NativeDatabase.memory()),
      paths = _Paths(root.path) {
    books = BookDao(db);
    chapters = ChapterDao(db);
    bases = SyncBaseStorage(
      directory: () async => Directory(p.join(root.path, 'sync')),
    );
    sync = SyncService(
      settings: SyncSettings(),
      bases: bases,
      storeFactory: (_, _, _) => store,
      bookDao: books,
      chapterDao: chapters,
      database: db,
      kinds: (service) => [
        ProgressSync(
          bookDao: books,
          chapterDao: chapters,
          isOpen: service.isBookOpen,
        ),
      ],
    );
  }

  final _MemoryStore store;
  final Directory root;
  final AppDatabase db;
  final _Paths paths;
  late final BookDao books;
  late final ChapterDao chapters;
  late final SyncBaseStorage bases;
  late final SyncService sync;

  /// 之後的檔案操作用這台的 App 資料夾。
  void use() => PathProviderPlatform.instance = paths;

  LocalBookSync localBooks() {
    use();
    return LocalBookSync(
      store: store,
      bases: bases,
      bookDao: books,
      chapterDao: chapters,
      storage: BookStorageService(bookDao: books, chapterDao: chapters),
    );
  }

  /// 選一個檔匯入（同書架的「匯入本地書」）。
  Future<Book> import(String name, String content) async {
    use();
    final picked = File(p.join(root.path, 'picked', name));
    await picked.parent.create(recursive: true);
    await picked.writeAsString(content);
    return (await LocalBookService().addToShelf(
      picked.path,
      bookDao: books,
      chapterDao: chapters,
    ))!;
  }

  Future<List<Book>> shelf() async => [
    for (final book in await books.getInBookshelf())
      if (book.isLocal) book,
  ];

  Future<LocalBookSyncResult> syncLocalBooks() async {
    final session = localBooks();
    return session.run(await session.plan());
  }
}

const String _novel = '第一章 夜航\n船在夜裡出港。\n第二章 霧\n霧從海上來。\n第三章 燈塔\n燈還亮著。\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late _MemoryStore store;
  late _Phone a;
  late _Phone b;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousPaths = PathProviderPlatform.instance;
    store = _MemoryStore();
    final temp = await Directory.systemTemp.createTemp('nr-local-book-sync');
    a = _Phone(store, Directory(p.join(temp.path, 'a')));
    b = _Phone(store, Directory(p.join(temp.path, 'b')));
    addTearDown(() async {
      PathProviderPlatform.instance = previousPaths;
      await LocalBookService().closeOpenFile();
      await a.db.close();
      await b.db.close();
      await temp.delete(recursive: true);
    });
  });

  group('fingerprint', () {
    test('the same file under another name is the same book', () async {
      final first = await a.import('夜航.txt', _novel);
      final again = await a.import('夜航 (下載).txt', _novel);

      expect(first.fileFingerprint, hasLength(64));
      expect(again.bookUrl, first.bookUrl);
      expect(await a.shelf(), hasLength(1));
    });

    test('another file with the name of a book whose original is missing is '
        'a new book; it does not take the old book\'s place', () async {
      // 還原備份帶回了書、沒帶回原檔。
      final first = await a.import('夜航.txt', _novel);
      await File(LocalBookService.filePathOf(first)).delete();

      final other = await a.import('夜航.txt', '第一章 別的書\n不一樣的內容。\n');

      expect(other.bookUrl, isNot(first.bookUrl));
      expect(await a.shelf(), hasLength(2));
      expect(await File(LocalBookService.filePathOf(first)).exists(), isFalse);
    });

    test('books imported before this version get a fingerprint; progress, '
        'bookmarks and the book itself stay where they were', () async {
      final imported = await a.import('夜航.txt', _novel);
      final print = imported.fileFingerprint!;
      // 退回這一版以前的樣子：沒有指紋，讀到第三章。
      await a.db.customStatement(
        'UPDATE books SET fileFingerprint = NULL, chapterIndex = 2, '
        "charOffset = 3, durChapterTitle = '第三章 燈塔'",
      );
      expect((await a.books.getByUrl(imported.bookUrl))!.fileFingerprint, null);

      expect(await fillLocalBookFingerprints(a.books), 1);

      final moved = (await a.books.getByUrl(imported.bookUrl))!;
      expect(moved.fileFingerprint, print);
      expect(moved.chapterIndex, 2);
      expect(moved.charOffset, 3);
      expect(await a.chapters.titlesByBook(imported.bookUrl), hasLength(3));
    });

    test('writing back a book read before its fingerprint was filled keeps '
        'the fingerprint', () async {
      final imported = await a.import('夜航.txt', _novel);
      final stale = imported.copyWith()..fileFingerprint = null;

      await a.books.upsert(stale..charOffset = 9);

      final saved = (await a.books.getByUrl(imported.bookUrl))!;
      expect(saved.charOffset, 9);
      expect(saved.fileFingerprint, imported.fileFingerprint);
    });

    test('progress follows the file, not its name', () async {
      final mine = await a.import('夜航.txt', _novel);
      await a.books.updateProgress(mine.bookUrl, 2, '第三章 燈塔', 4);
      // 另一台自己匯入同一個檔，檔名不同。
      final theirs = await b.import('別的名字.txt', _novel);
      expect(theirs.name, isNot(mine.name));

      a.use();
      await a.sync.syncAll();
      b.use();
      await b.sync.syncAll();

      final read = (await b.books.getByUrl(theirs.bookUrl))!;
      expect(read.chapterIndex, 2);
      expect(read.charOffset, 4);
      expect(
        store.files['progress.json']!.$1,
        contains('local:${mine.fileFingerprint}'),
      );
    });
  });

  group('plan', () {
    const shelfBook = LocalShelfBook(
      name: '夜航',
      author: '本地',
      extension: 'txt',
      size: 2048,
      addedTime: 100,
      path: '/books/夜航.txt',
      bookUrls: ['local:///books/夜航.txt'],
    );
    SyncRecord alive(int time) => SyncRecord(
      time: time,
      data: const {'name': '霧', 'author': '某人', 'ext': 'epub', 'size': 4096},
    );
    SyncRecord gone(int time) =>
        SyncRecord(time: time, data: const {}, deleted: true);
    SyncBaseEntry synced(int time) =>
        SyncBaseEntry(local: 'txt', remote: 'txt', time: time);
    List<(LocalBookAction, String)> tasksOf(LocalBookSyncPlan plan) => [
      for (final task in plan.tasks) (task.action, task.fingerprint),
    ];

    test('a book only on this phone is uploaded; one only in the cloud is '
        'downloaded; one on both needs nothing', () {
      final plan = planLocalBookSync(
        local: {'mine': shelfBook, 'both': shelfBook},
        remote: {'theirs': alive(50), 'both': alive(60)},
        base: const {},
      );

      expect(tasksOf(plan), [
        (LocalBookAction.upload, 'mine'),
        (LocalBookAction.download, 'theirs'),
      ]);
      expect(plan.bytesOf(LocalBookAction.upload), 2048);
      expect(plan.bytesOf(LocalBookAction.download), 4096);
      expect(plan.settled.keys, ['both']);
    });

    test('a synced book removed here is deleted from the cloud; removed on '
        'the other phone it leaves this shelf', () {
      // 這台加進書架的時間是 100，另一台 120 移出。
      final plan = planLocalBookSync(
        local: {'kept-here': shelfBook},
        remote: {'removed-here': alive(50), 'kept-here': gone(120)},
        base: {'removed-here': synced(50), 'kept-here': synced(60)},
      );

      expect(tasksOf(plan), [
        (LocalBookAction.removeHere, 'kept-here'),
        (LocalBookAction.deleteRemote, 'removed-here'),
      ]);
    });

    test('a book added again here after this phone deleted it from the cloud '
        'goes up again', () {
      final plan = planLocalBookSync(
        local: {'again': shelfBook},
        remote: {'again': gone(80)},
        base: {'again': synced(50)},
      );
      expect(tasksOf(plan), [(LocalBookAction.upload, 'again')]);
    });

    test('a book whose file is missing here is downloaded back', () {
      final plan = planLocalBookSync(
        local: {
          'lost': const LocalShelfBook(
            name: '夜航',
            author: '本地',
            extension: 'txt',
            size: 0,
            hasFile: false,
            addedTime: 100,
            path: '/books/夜航.txt',
            bookUrls: ['local:///books/夜航.txt'],
          ),
        },
        remote: {'lost': alive(50)},
        base: {'lost': synced(50)},
      );
      expect(tasksOf(plan), [(LocalBookAction.download, 'lost')]);
      expect(plan.settled, isEmpty);
    });

    test('a file sent up whose record never made it, then removed here, is '
        'deleted from the cloud', () {
      final plan = planLocalBookSync(
        local: const {},
        remote: const {},
        base: {'orphan': synced(0)},
      );
      expect(tasksOf(plan), [(LocalBookAction.deleteRemote, 'orphan')]);
      expect(plan.tasks.single.extension, 'txt');
    });

    test('a book re-uploaded after this phone removed it comes back', () {
      final plan = planLocalBookSync(
        local: const {},
        remote: {'again': alive(90)},
        base: {'again': synced(50)},
      );
      expect(tasksOf(plan), [(LocalBookAction.download, 'again')]);
    });

    test('a book never synced here and removed elsewhere: whichever came '
        'later wins', () {
      final plan = planLocalBookSync(
        local: {'added-later': shelfBook, 'added-earlier': shelfBook},
        // 加進書架的時間是 100。
        remote: {'added-later': gone(80), 'added-earlier': gone(120)},
        base: const {},
      );
      expect(tasksOf(plan), [
        (LocalBookAction.upload, 'added-later'),
        (LocalBookAction.removeHere, 'added-earlier'),
      ]);
    });

    test('deleted or unreadable cloud records with no book here need '
        'nothing', () {
      final plan = planLocalBookSync(
        local: const {},
        remote: {
          'gone': gone(50),
          'pdf': const SyncRecord(time: 1, data: {'ext': 'pdf', 'name': 'x'}),
        },
        base: const {},
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('two phones', () {
    test('a book uploaded on one phone joins the other shelf with its '
        'progress; the file goes up once, compressed', () async {
      final mine = await a.import('夜航.txt', _novel);
      await a.books.updateProgress(mine.bookUrl, 1, '第二章 霧', 2);
      a.use();
      await a.sync.syncAll();

      final upload = await a.localBooks().plan();
      expect(upload.of(LocalBookAction.upload), hasLength(1));
      expect(
        upload.bytesOf(LocalBookAction.upload),
        File(LocalBookService.filePathOf(mine)).lengthSync(),
      );
      final result = await a.localBooks().run(upload);
      expect(result.failures, isEmpty);
      final fileName = LocalBookSync.originalName(mine.fileFingerprint!, 'txt');
      expect(store.blobs.keys, [fileName]);
      expect(
        gzip.decode(store.blobs[fileName]!),
        File(LocalBookService.filePathOf(mine)).readAsBytesSync(),
      );
      expect(store.records[mine.fileFingerprint]!.data['name'], '夜航');
      // 再按一次沒有事要做，不再傳。
      expect((await a.localBooks().plan()).isEmpty, isTrue);

      final download = await b.localBooks().plan();
      expect(download.of(LocalBookAction.download), hasLength(1));
      expect((await b.localBooks().run(download)).failures, isEmpty);
      b.use();
      await b.sync.syncAll();

      final shelf = await b.shelf();
      expect(shelf, hasLength(1));
      expect(shelf.single.name, '夜航');
      expect(shelf.single.fileFingerprint, mine.fileFingerprint);
      expect(shelf.single.chapterIndex, 1);
      expect(shelf.single.charOffset, 2);
      expect((await b.localBooks().plan()).isEmpty, isTrue);
    });

    test('a book removed on one phone is deleted from the cloud when that '
        'phone syncs, and leaves the other shelf when it does', () async {
      final mine = await a.import('夜航.txt', _novel);
      await a.syncLocalBooks();
      await b.syncLocalBooks();
      final theirs = (await b.shelf()).single;

      a.use();
      await BookStorageService(
        bookDao: a.books,
        chapterDao: a.chapters,
      ).discardBook(mine);
      expect(File(LocalBookService.filePathOf(mine)).existsSync(), isFalse);
      final delete = await a.localBooks().plan();
      expect(delete.of(LocalBookAction.deleteRemote), hasLength(1));
      await a.localBooks().run(delete);
      expect(store.blobs, isEmpty);
      expect(store.records[mine.fileFingerprint]!.deleted, isTrue);

      final remove = await b.localBooks().plan();
      expect(remove.of(LocalBookAction.removeHere), hasLength(1));
      await b.localBooks().run(remove);
      expect(await b.shelf(), isEmpty);
      expect(File(LocalBookService.filePathOf(theirs)).existsSync(), isFalse);
      expect((await a.localBooks().plan()).isEmpty, isTrue);
      expect((await b.localBooks().plan()).isEmpty, isTrue);
    });

    test('a phone that never pressed the button does not show the book, and '
        'importing the same file there picks up the progress', () async {
      final mine = await a.import('夜航.txt', _novel);
      await a.books.updateProgress(mine.bookUrl, 2, '第三章 燈塔', 1);
      a.use();
      await a.sync.syncAll();
      b.use();
      await b.sync.syncAll();
      expect(await b.shelf(), isEmpty);

      final theirs = await b.import('夜航.txt', _novel);
      b.use();
      await b.sync.syncAll();
      expect((await b.books.getByUrl(theirs.bookUrl))!.chapterIndex, 2);
    });
  });

  group('repairs', () {
    test(
      'a phone that already had the book remembers it even when there is '
      'nothing to send, so removing it later deletes it from the cloud',
      () async {
        final mine = await a.import('夜航.txt', _novel);
        await a.syncLocalBooks();
        await b.import('別的名字.txt', _novel);

        // 兩邊都有：沒有事要做，按了也要記成同步過。
        expect((await b.localBooks().plan()).isEmpty, isTrue);
        b.use();
        await BookStorageService(
          bookDao: b.books,
          chapterDao: b.chapters,
        ).discardBook((await b.shelf()).single);

        final next = await b.localBooks().plan();
        expect(next.tasks.map((task) => task.action), [
          LocalBookAction.deleteRemote,
        ]);
        expect(next.tasks.single.fingerprint, mine.fileFingerprint);
      },
    );

    test(
      'importing the same file again puts a missing original back',
      () async {
        final mine = await a.import('夜航.txt', _novel);
        final path = LocalBookService.filePathOf(mine);
        File(path).deleteSync();

        final again = await a.import('夜航 (找回來的).txt', _novel);

        expect(again.bookUrl, mine.bookUrl);
        expect(File(path).readAsStringSync(), _novel);
        expect(await a.shelf(), hasLength(1));
      },
    );

    test('a missing original is downloaded back into place', () async {
      await a.import('夜航.txt', _novel);
      await a.syncLocalBooks();
      await b.syncLocalBooks();
      final theirs = (await b.shelf()).single;
      final path = LocalBookService.filePathOf(theirs);
      File(path).deleteSync();

      final plan = await b.localBooks().plan();
      expect(plan.tasks.map((task) => task.action), [LocalBookAction.download]);
      expect((await b.localBooks().run(plan)).failures, isEmpty);

      expect(File(path).readAsStringSync(), _novel);
      expect((await b.shelf()).single.bookUrl, theirs.bookUrl);
      final dir = Directory(p.join(b.root.path, 'docs', 'InkpageBooks'));
      expect(dir.listSync(), hasLength(1), reason: '下載的那份用完就刪');
    });

    test('removing one of two books that share an original keeps the '
        'file', () async {
      final mine = await a.import('夜航.txt', _novel);
      // 還原的舊資料：另一筆書指著同一個檔。
      await a.books.upsert(
        mine.copyWith(bookUrl: LocalBookService.filePathOf(mine)),
      );

      a.use();
      await BookStorageService(
        bookDao: a.books,
        chapterDao: a.chapters,
      ).discardBook(mine);

      expect(File(LocalBookService.filePathOf(mine)).existsSync(), isTrue);
    });

    test('a file sent up whose record never made it is deleted from the '
        'cloud once the book is removed here', () async {
      final mine = await a.import('夜航.txt', _novel);
      store.beforeWrite = (name) async =>
          throw const SyncStoreException.file('同步空間拒絕存取這份檔案（HTTP 403）');
      final failed = await a.syncLocalBooks();
      expect(failed.failures, hasLength(1));
      expect(store.blobs, hasLength(1));
      store.beforeWrite = null;

      a.use();
      await BookStorageService(
        bookDao: a.books,
        chapterDao: a.chapters,
      ).discardBook(mine);
      final cleanup = await a.localBooks().plan();
      expect(cleanup.tasks.map((task) => task.action), [
        LocalBookAction.deleteRemote,
      ]);
      await a.localBooks().run(cleanup);
      expect(store.blobs, isEmpty);
    });

    test('a removal another phone wrote at the same moment is not '
        'overwritten', () async {
      await a.import('甲.txt', '甲的內容\n');
      await a.import('乙.txt', '乙的內容\n');
      await a.syncLocalBooks();
      await b.syncLocalBooks();
      // B 移出甲、按下同步本地書；A 同時在改小紀錄，一直被 B 搶先。
      final bookA = (await b.shelf()).firstWhere((book) => book.name == '甲');
      b.use();
      await BookStorageService(
        bookDao: b.books,
        chapterDao: b.chapters,
      ).discardBook(bookA);
      await b.syncLocalBooks();
      expect(store.records[bookA.fileFingerprint]!.deleted, isTrue);

      await a.import('丙.txt', '丙的內容\n');
      store.beforeWrite = (name) async {
        final current = store.files[name]!;
        store.files[name] = (current.$1, current.$2 + 1);
      };
      final result = await a.syncLocalBooks();
      store.beforeWrite = null;

      expect(result.failures.single.reason, '另一台手機同時在同步本地書，稍後再按一次');
      expect(store.records[bookA.fileFingerprint]!.deleted, isTrue);
    });
  });

  group('stopping', () {
    test('cancelling stops between books and keeps the ones done; the rest '
        'go next time', () async {
      await a.import('甲.txt', '甲的內容\n');
      await a.import('乙.txt', '乙的內容\n');
      final session = a.localBooks();
      final plan = await session.plan();
      expect(plan.tasks, hasLength(2));

      final steps = <int>[];
      var cancel = false;
      final result = await session.run(
        plan,
        onProgress: (progress) {
          steps.add(progress.step);
          cancel = true;
        },
        cancelled: () => cancel,
      );

      expect(result.cancelled, isTrue);
      expect(result.done, 1);
      expect(steps, [1]);
      expect(store.blobs, hasLength(1));
      final rest = await a.localBooks().plan();
      expect(rest.tasks.map((task) => task.name), [plan.tasks.last.name]);
    });

    test('a book that fails is reported with the reason, the others go on, '
        'and it is sent again next time', () async {
      final first = await a.import('甲.txt', '甲的內容\n');
      await a.import('乙.txt', '乙的內容\n');
      final name = LocalBookSync.originalName(first.fileFingerprint!, 'txt');
      store.failingBlobs[name] = const SyncStoreException.file(
        '同步空間拒絕存取這份檔案（HTTP 403）',
      );

      final result = await a.syncLocalBooks();
      expect(result.done, 1);
      expect(result.failures.single.task.name, '甲');
      expect(result.failures.single.reason, '同步空間拒絕存取這份檔案（HTTP 403）');

      store.failingBlobs.clear();
      final retry = await a.localBooks().plan();
      expect(retry.tasks.map((task) => task.name), ['甲']);
      expect((await a.localBooks().run(retry)).failures, isEmpty);
      expect(store.blobs, hasLength(2));
    });

    test('a space that is down stops at the first book', () async {
      await a.import('甲.txt', '甲的內容\n');
      await a.import('乙.txt', '乙的內容\n');
      final session = a.localBooks();
      final plan = await session.plan();
      final first = plan.tasks.first;
      store.failingBlobs[LocalBookSync.originalName(first.fingerprint, 'txt')] =
          const SyncStoreException('連不上同步空間，檢查網址與網路');

      final result = await session.run(plan);
      expect(result.done, 0);
      expect(result.failures, hasLength(1));
      expect(store.blobs, isEmpty);
    });

    test('a download whose content does not match its fingerprint is not '
        'added', () async {
      final mine = await a.import('夜航.txt', _novel);
      await a.syncLocalBooks();
      final name = LocalBookSync.originalName(mine.fileFingerprint!, 'txt');
      store.blobs[name] = Uint8List.fromList(gzip.encode('被改過的內容'.codeUnits));

      final result = await b.syncLocalBooks();
      expect(result.failures.single.reason, '下載的原檔不完整，下次再試');
      expect(await b.shelf(), isEmpty);
      b.use();
      final dir = Directory(p.join(b.root.path, 'docs', 'InkpageBooks'));
      expect(dir.existsSync() ? dir.listSync() : const [], isEmpty);
    });
  });
}
