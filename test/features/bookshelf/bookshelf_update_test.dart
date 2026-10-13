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
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;
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
      ..registerSingleton<ChapterDao>(ChapterDao(db));
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

    test('tells listeners while a shelf check is running', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));
      final states = <bool>[];
      provider.addListener(() => states.add(provider.isCheckingShelf));

      final refresh = provider.refreshBookshelf();
      expect(provider.isCheckingShelf, isTrue);
      await refresh;

      expect(provider.isCheckingShelf, isFalse);
      expect(states.first, isTrue);
      expect(states.last, isFalse);
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

      var notified = false;
      shelf.addListener(() => notified = true);
      timers.single.$2();

      expect(notified, isTrue);
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
