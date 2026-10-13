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
    provider = BookshelfProvider();
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
  });

  group('launch refresh', () {
    test('does nothing when the setting is off', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));
      AppConfig.autoRefresh = false;

      await provider.refreshBookshelfOnLaunch();

      expect(await lastCheckTimeOf('https://a.example/1'), 0);
    });

    test('checks the shelf when the setting is on', () async {
      await bookDao.upsert(shelfBook('https://a.example/1'));

      await provider.refreshBookshelfOnLaunch();

      expect(await lastCheckTimeOf('https://a.example/1'), greaterThan(0));
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
