import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/book_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;
  late ReaderChapterContentDao contentDao;
  late BookshelfProvider provider;

  /// 排進書架自動下載的書：(bookUrl, hasNewChapters)。
  final downloads = <(String, bool)>[];

  /// 角標計時：記下時長與到時要做的事，由測試決定何時「到時」。
  final timers = <(Duration, void Function())>[];

  // 這個書源不在資料庫裡：檢查會失敗，但仍會記下檢查時間，用來看出
  // 哪些書被檢查過，不必連網。
  const missingOrigin = 'https://missing.example';
  const sourceUrl = 'https://source.example';

  // 詳情與目錄在同一頁，放在 infoHtml 裡就不必連網。
  const detailHtml = '''
<html><body>
  <h1>書源上的書名</h1>
  <p class="author">書源上的作者</p>
  <div class="list">
    <a href="/c/1.html">第一章</a>
    <a href="/c/2.html">第二章</a>
    <a href="/c/3.html">第三章</a>
  </div>
</body></html>
''';

  Book shelfBook(
    String url, {
    String origin = missingOrigin,
    bool canUpdate = true,
  }) => Book(
    bookUrl: url,
    origin: origin,
    name: url,
    author: '作者',
    isInBookshelf: true,
    canUpdate: canUpdate,
  );

  Future<int> lastCheckTimeOf(String url) async =>
      (await bookDao.getByUrl(url))!.lastCheckTime;

  setUpAll(() async {
    await GetIt.instance.reset();
    setupTestDI();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(bookDao)
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db))
      ..registerSingleton<ReaderChapterContentDao>(
        contentDao = ReaderChapterContentDao(db),
      );
    await BookSourceDao(db).upsert(
      BookSource.fromJson({
        'bookSourceName': '測試',
        'bookSourceUrl': sourceUrl,
        'ruleBookInfo': {'name': 'tag.h1@text', 'author': 'class.author@text'},
        'ruleToc': {
          'chapterList': 'class.list@a',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
        },
      }),
    );
  });

  tearDownAll(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  setUp(() async {
    AppConfig.autoRefresh = true;
    await db.delete(db.books).go();
    await db.delete(db.chapters).go();
    await db.delete(db.readerChapterContents).go();
    downloads.clear();
    timers.clear();
    provider = BookshelfProvider(
      keepBookDownloaded: (url, {hasNewChapters = false}) async =>
          downloads.add((url, hasNewChapters)),
    );
  });

  tearDown(() => provider.dispose());

  group('shelf refresh', () {
    test('skips books the user took out of updates and local books', () async {
      await bookDao.upsertAll([
        shelfBook('https://a.example/1'),
        shelfBook('https://a.example/2', canUpdate: false),
        shelfBook('/local/book.txt', origin: BookType.localTag),
      ]);

      await provider.refreshBookshelf();

      expect(await lastCheckTimeOf('https://a.example/1'), greaterThan(0));
      expect(await lastCheckTimeOf('https://a.example/2'), 0);
      expect(await lastCheckTimeOf('/local/book.txt'), 0);
    });

    test('an explicit check still covers a book out of updates', () async {
      await bookDao.upsert(shelfBook('https://a.example/2', canUpdate: false));

      final results = await provider.batchCheckUpdate({'https://a.example/2'});

      expect(results, hasLength(1));
      expect(await lastCheckTimeOf('https://a.example/2'), greaterThan(0));
    });

    test('pulling down while a refresh runs joins it', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));

      final first = provider.refreshBookshelf();
      final second = provider.refreshBookshelf();

      expect(identical(first, second), isTrue);
      await first;
    });

    test(
      'signals a running shelf check without notifying the whole shelf',
      () async {
        await bookDao.upsert(shelfBook('https://a.example/1'));
        final states = <bool>[];
        provider.checkingShelf.addListener(
          () => states.add(provider.checkingShelf.value),
        );

        final refresh = provider.refreshBookshelf();
        expect(provider.checkingShelf.value, isTrue);
        await refresh;

        expect(provider.checkingShelf.value, isFalse);
        expect(states, [true, false]);
      },
    );

    test('a shelf reload with books on it notifies once, at the end', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));
      await provider.loadBooks();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.loadBooks();

      // 書架有書時不換回骨架，開始時不必讓整頁重建。
      expect(notified, 1);
    });

    test('a check that ends after the provider is disposed stays '
        'quiet', () async {
      final shelf = BookshelfProvider(
        keepBookDownloaded: (url, {hasNewChapters = false}) async {},
      );

      final refresh = shelf.refreshBookshelf();
      shelf.dispose();

      await expectLater(refresh, completes);
    });
  });

  group('App launch', () {
    test('does not check for updates when the setting is off', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));
      AppConfig.autoRefresh = false;

      await provider.onAppLaunch();

      expect(await lastCheckTimeOf('https://a.example/1'), 0);
    });

    test('checks the shelf when the setting is on', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));

      await provider.onAppLaunch();

      expect(await lastCheckTimeOf('https://a.example/1'), greaterThan(0));
    });

    test('queues every online shelf book for download, even with checks '
        'off', () async {
      await bookDao.upsertAll([
        shelfBook('https://a.example/1'),
        shelfBook('https://a.example/2', canUpdate: false),
        shelfBook('/local/book.txt', origin: BookType.localTag),
      ]);
      AppConfig.autoRefresh = false;

      await provider.onAppLaunch();

      expect(downloads.map((d) => d.$1).toSet(), {
        'https://a.example/1',
        'https://a.example/2',
      });
    });
  });

  group('update badges', () {
    late _ScriptedShelf shelf;

    setUp(() {
      shelf = _ScriptedShelf(
        startTimer: (duration, callback) {
          timers.add((duration, callback));
          return Timer(const Duration(days: 1), () {});
        },
      );
    });

    tearDown(() => shelf.dispose());

    void scriptNewAndBroken() {
      shelf.results = {
        'https://a.example/new': const BookUpdateCheckResult(
          bookUrl: 'https://a.example/new',
          newChapterCount: 2,
        ),
        'https://a.example/broken': BookUpdateCheckResult(
          bookUrl: 'https://a.example/broken',
          newChapterCount: 0,
          error: StateError('書源壞了'),
        ),
      };
    }

    test('the launch check shows new chapters but hides failures', () async {
      await bookDao.upsertAll([
        shelfBook('https://a.example/new'),
        shelfBook('https://a.example/broken'),
      ]);
      scriptNewAndBroken();

      await shelf.refreshBookshelf();

      expect(shelf.updateBadgeOf('https://a.example/new')?.newChapterCount, 2);
      expect(shelf.updateBadgeOf('https://a.example/broken'), isNull);
    });

    test('pulling down during the launch check shows failures too', () async {
      await bookDao.upsertAll([
        shelfBook('https://a.example/new'),
        shelfBook('https://a.example/broken'),
      ]);
      scriptNewAndBroken();

      final launch = shelf.refreshBookshelf();
      final pull = shelf.refreshBookshelf(userInitiated: true);
      await Future.wait([launch, pull]);

      expect(shelf.updateBadgeOf('https://a.example/broken')?.failed, isTrue);

      // 下一次自動檢查不再沿用這次的手動標記。
      await shelf.refreshBookshelf();
      expect(shelf.updateBadgeOf('https://a.example/broken'), isNull);
    });

    test('a pull-down shows new chapters and failures, then clears after '
        '5 s', () async {
      await bookDao.upsertAll([
        shelfBook('https://a.example/new'),
        shelfBook('https://a.example/broken'),
        shelfBook('https://a.example/same'),
      ]);
      shelf.results = {
        'https://a.example/new': const BookUpdateCheckResult(
          bookUrl: 'https://a.example/new',
          newChapterCount: 3,
        ),
        'https://a.example/broken': BookUpdateCheckResult(
          bookUrl: 'https://a.example/broken',
          newChapterCount: 0,
          error: StateError('書源壞了'),
        ),
        'https://a.example/same': const BookUpdateCheckResult(
          bookUrl: 'https://a.example/same',
          newChapterCount: 0,
        ),
      };

      await shelf.refreshBookshelf(userInitiated: true);

      expect(shelf.updateBadgeOf('https://a.example/new')?.newChapterCount, 3);
      expect(shelf.updateBadgeOf('https://a.example/broken')?.failed, isTrue);
      expect(shelf.updateBadgeOf('https://a.example/same'), isNull);
      expect(timers.single.$1, const Duration(seconds: 5));

      // 角標消失只通知角標，不讓整個書架重建。
      var shelfNotified = false;
      var badgesNotified = false;
      shelf.addListener(() => shelfNotified = true);
      shelf.updateBadges.addListener(() => badgesNotified = true);
      timers.single.$2();

      expect(badgesNotified, isTrue);
      expect(shelfNotified, isFalse);
      expect(shelf.updateBadgeOf('https://a.example/new'), isNull);
      expect(shelf.updateBadgeOf('https://a.example/broken'), isNull);
    });

    test('a check with nothing to show starts no timer', () async {
      await bookDao.upsert(shelfBook('https://a.example/same'));
      shelf.results = {
        'https://a.example/same': const BookUpdateCheckResult(
          bookUrl: 'https://a.example/same',
          newChapterCount: 0,
        ),
      };

      await shelf.refreshBookshelf();

      expect(shelf.updateBadgeOf('https://a.example/same'), isNull);
      expect(timers, isEmpty);
    });
  });

  test('turning updates off for one book is saved', () async {
    final book = shelfBook('https://a.example/1');
    await bookDao.upsert(book);

    await provider.setBookCanUpdate(book, false);

    expect((await bookDao.getByUrl(book.bookUrl))!.canUpdate, isFalse);
    expect(book.canUpdate, isFalse);
  });

  group('writing back a check', () {
    Book onlineBook() =>
        shelfBook('https://source.example/book/1', origin: sourceUrl)
          ..infoHtml = detailHtml;

    test('a check that finds new chapters queues them for download', () async {
      final book = onlineBook()..totalChapterNum = 2;
      await bookDao.upsert(book);

      final result = await provider.checkBookUpdate(book);

      expect(result.newChapterCount, 1);
      expect(downloads, [(book.bookUrl, true)]);
    });

    test('checks of the same book at the same time share one run', () async {
      final book = onlineBook()..totalChapterNum = 2;
      await bookDao.upsert(book);

      // 例如開 App 的檢查還在跑，使用者又對這本按了「檢查更新」。
      final results = await Future.wait([
        provider.checkBookUpdate(book),
        provider.checkBookUpdate(book),
      ]);

      expect(results.map((r) => r.newChapterCount), [1, 1]);
      expect(downloads, [(book.bookUrl, true)]);
    });

    test('a check from book detail joins the running shelf check', () async {
      final book = onlineBook()..totalChapterNum = 2;
      await bookDao.upsert(book);
      // 書籍詳情自己建一個實例，不經過書架的 provider。
      final detail = BookUpdateService(
        keepDownloaded: (url, {hasNewChapters = false}) async =>
            downloads.add((url, hasNewChapters)),
      );

      final results = await Future.wait([
        provider.checkBookUpdate(book),
        detail.check(book.copyWith()),
      ]);

      expect(results.map((r) => r.newChapterCount), [1, 1]);
      expect(downloads, [(book.bookUrl, true)]);
    });

    test('a book not on the shelf is written back', () async {
      // 從搜尋或發現打開的詳情：書還不在書架上，也可能還沒存過。
      final book = onlineBook()..isInBookshelf = false;

      final result = await provider.checkBookUpdate(book);

      expect(result.failed, isFalse);
      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.isInBookshelf, isFalse);
      expect(saved.totalChapterNum, 3);
      expect(await ChapterDao(db).getByBook(book.bookUrl), hasLength(3));
    });

    test('chapters the source dropped leave the TOC', () async {
      final book = onlineBook();
      await bookDao.upsert(book);
      await ChapterDao(db).insertChapters([
        for (var i = 0; i < 4; i++)
          BookChapter(
            url: 'https://source.example/old/$i.html',
            title: '舊第 $i 章',
            bookUrl: book.bookUrl,
            index: i,
          ),
      ]);

      await provider.checkBookUpdate(book);

      final toc = await ChapterDao(db).getByBook(book.bookUrl);
      expect(toc.map((c) => c.title), ['第一章', '第二章', '第三章']);
    });

    /// 舊目錄：照 [chapters] 的（網址路徑, 標題）依序編號。
    Future<void> storeToc(Book book, List<(String, String)> chapters) =>
        ChapterDao(db).insertChapters([
          for (final (i, (path, title)) in chapters.indexed)
            BookChapter(
              url: 'https://source.example$path',
              title: title,
              bookUrl: book.bookUrl,
              index: i,
            ),
        ]);

    test('progress follows its chapter when the source inserts one '
        'before it', () async {
      final book = onlineBook()..totalChapterNum = 2;
      await bookDao.upsert(book);
      await storeToc(book, [('/c/1.html', '第一章'), ('/c/3.html', '第三章')]);
      await bookDao.updateProgress(
        book.bookUrl,
        1,
        '第三章',
        120,
        readerAnchorJson: '{"chapterIndex":1,"charOffset":120}',
      );

      await provider.checkBookUpdate(book);

      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 2);
      expect(saved.durChapterTitle, '第三章');
      expect(saved.charOffset, 120);
      expect(saved.readerAnchorJson, '{"chapterIndex":2,"charOffset":120}');
    });

    test('progress follows its chapter when the source removes one '
        'before it', () async {
      final book = onlineBook()..totalChapterNum = 4;
      await bookDao.upsert(book);
      await storeToc(book, [
        ('/c/1.html', '第一章'),
        ('/c/1b.html', '公告'),
        ('/c/2.html', '第二章'),
        ('/c/3.html', '第三章'),
      ]);
      await bookDao.updateProgress(book.bookUrl, 2, '第二章', 40);

      await provider.checkBookUpdate(book);

      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 1);
      expect(saved.durChapterTitle, '第二章');
      expect(saved.charOffset, 40);
    });

    test('a chapter that changed its address is found by title, from its '
        'start', () async {
      final book = onlineBook()..totalChapterNum = 2;
      await bookDao.upsert(book);
      await storeToc(book, [('/c/1.html', '第一章'), ('/old/3.html', '第三章')]);
      await bookDao.updateProgress(book.bookUrl, 1, '第三章', 80);

      await provider.checkBookUpdate(book);

      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 2);
      expect(saved.durChapterTitle, '第三章');
      // 網址不同，不能確定是同一份正文，從章首開始。
      expect(saved.charOffset, 0);
    });

    test('an empty TOC from the source changes nothing', () async {
      // 網站壞了：詳情頁還在，目錄卻一章都抓不到。
      final book = onlineBook()
        ..totalChapterNum = 2
        ..infoHtml = '<html><body><h1>書源上的書名</h1></body></html>';
      await bookDao.upsert(book);
      await storeToc(book, [('/c/1.html', '第一章'), ('/c/2.html', '第二章')]);

      final result = await provider.checkBookUpdate(book);

      expect(result.failed, isTrue);
      expect(downloads, isEmpty);
      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.totalChapterNum, 2);
      expect(await ChapterDao(db).getByBook(book.bookUrl), hasLength(2));
    });

    test('chapters the source dropped stay when downloaded or being read, '
        'in their old place', () async {
      final book = onlineBook()..totalChapterNum = 6;
      await bookDao.upsert(book);
      await storeToc(book, [
        ('/c/1.html', '第一章'),
        ('/c/notice.html', '公告'),
        ('/c/2.html', '第二章'),
        ('/c/extra.html', '番外'),
        ('/c/gone.html', '刪掉的章'),
        ('/c/3.html', '第三章'),
      ]);
      await contentDao.saveContent(
        contentKey: 'notice',
        origin: sourceUrl,
        bookUrl: book.bookUrl,
        chapterUrl: 'https://source.example/c/notice.html',
        chapterIndex: 1,
        content: '公告內容',
        updatedAt: 1,
      );
      await bookDao.updateProgress(book.bookUrl, 3, '番外', 50);

      await provider.checkBookUpdate(book);

      final toc = await ChapterDao(db).getByBook(book.bookUrl);
      expect(toc.map((c) => c.title), ['第一章', '公告', '第二章', '番外', '第三章']);
      expect(toc.map((c) => c.index), [0, 1, 2, 3, 4]);
      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 3);
      expect(saved.charOffset, 50);
      expect(saved.totalChapterNum, 5);
    });

    test('progress follows a kept chapter that moved down', () async {
      final book = onlineBook()..totalChapterNum = 3;
      await bookDao.upsert(book);
      await storeToc(book, [
        ('/c/2.html', '第二章'),
        ('/c/extra.html', '番外'),
        ('/c/3.html', '第三章'),
      ]);
      await bookDao.updateProgress(book.bookUrl, 1, '番外', 50);

      await provider.checkBookUpdate(book);

      final toc = await ChapterDao(db).getByBook(book.bookUrl);
      expect(toc.map((c) => c.title), ['第一章', '第二章', '番外', '第三章']);
      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 2);
      expect(saved.charOffset, 50);
    });

    test('a chapter at a new address with the same title and place starts '
        'over unless the anchor binds its text', () async {
      final book = onlineBook()..totalChapterNum = 3;
      await bookDao.upsert(book);
      await storeToc(book, [
        ('/c/1.html', '第一章'),
        ('/old/2.html', '第二章'),
        ('/c/3.html', '第三章'),
      ]);
      await bookDao.updateProgress(book.bookUrl, 1, '第二章', 30);

      await provider.checkBookUpdate(book);

      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 1);
      expect(saved.charOffset, 0);
    });

    test('the first chapter at a new address is found by title', () async {
      final book = onlineBook()..totalChapterNum = 2;
      await bookDao.upsert(book);
      await storeToc(book, [('/old/2.html', '第二章'), ('/c/3.html', '第三章')]);
      await bookDao.updateProgress(book.bookUrl, 0, '第二章', 0);

      await provider.checkBookUpdate(book);

      expect((await bookDao.getByUrl(book.bookUrl))!.chapterIndex, 1);
    });

    test('a downloaded chapter that only moved to a new address is not '
        'listed twice', () async {
      final book = onlineBook();
      await bookDao.upsert(book);
      await storeToc(book, [('/old/1.html', '第一章')]);
      await contentDao.saveContent(
        contentKey: 'old-1',
        origin: sourceUrl,
        bookUrl: book.bookUrl,
        chapterUrl: 'https://source.example/old/1.html',
        chapterIndex: 0,
        content: '正文',
        updatedAt: 1,
      );

      await provider.checkBookUpdate(book);

      final toc = await ChapterDao(db).getByBook(book.bookUrl);
      expect(toc.map((c) => c.title), ['第一章', '第二章', '第三章']);
    });

    test('a failed check queues no download', () async {
      final book = shelfBook('https://a.example/1');
      await bookDao.upsert(book);

      await provider.checkBookUpdate(book);

      expect(downloads, isEmpty);
    });

    test('keeps progress saved after the book was read', () async {
      final stale = onlineBook();
      await bookDao.upsert(stale);
      // 書架手上的是舊資料；之後閱讀器寫入了新進度。
      await bookDao.updateProgress(stale.bookUrl, 2, '第三章', 120);

      final result = await provider.checkBookUpdate(stale);

      expect(result.failed, isFalse);
      final saved = (await bookDao.getByUrl(stale.bookUrl))!;
      expect(saved.chapterIndex, 2);
      expect(saved.durChapterTitle, '第三章');
      expect(saved.charOffset, 120);
      expect(saved.totalChapterNum, 3);
      expect(saved.latestChapterTitle, '第三章');
    });

    test('does not bring back a book removed during the check', () async {
      final stale = onlineBook();
      await bookDao.upsert(stale);
      await bookDao.deleteByUrl(stale.bookUrl);

      await provider.checkBookUpdate(stale);

      expect(await bookDao.getByUrl(stale.bookUrl), isNull);
    });

    test('a failed check only records the check time', () async {
      final stale = shelfBook('https://a.example/1');
      await bookDao.upsert(stale);
      await bookDao.updateProgress(stale.bookUrl, 5, '第六章', 30);

      final result = await provider.checkBookUpdate(stale);

      expect(result.failed, isTrue);
      final saved = (await bookDao.getByUrl(stale.bookUrl))!;
      expect(saved.chapterIndex, 5);
      expect(saved.lastCheckTime, greaterThan(0));
    });
  });
}

/// 檢查結果照劇本回傳，不連網。
class _ScriptedShelf extends BookshelfProvider {
  _ScriptedShelf({super.startTimer})
    : super(keepBookDownloaded: (_, {hasNewChapters = false}) async {});

  Map<String, BookUpdateCheckResult> results = {};

  @override
  Future<BookUpdateCheckResult> checkBookUpdate(Book book) async =>
      results[book.bookUrl]!;
}
