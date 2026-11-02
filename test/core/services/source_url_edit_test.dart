import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const oldUrl = 'https://old.example';
  const newUrl = 'https://new.example';
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('editing a source URL moves its books, downloaded chapters, search '
      'results and login with it', () async {
    await getIt<BookSourceDao>().upsert(
      BookSource(bookSourceUrl: oldUrl, bookSourceName: '舊名'),
    );
    await getIt<BookDao>().upsert(
      Book(
        bookUrl: '$oldUrl/book/1',
        name: '甲書',
        origin: oldUrl,
        originName: '舊名',
        isInBookshelf: true,
      ),
    );
    final contentDao = ReaderChapterContentDao(db);
    String keyAt(String origin) => ReaderChapterContentDao.contentKey(
      origin: origin,
      bookUrl: '$oldUrl/book/1',
      chapterUrl: '$oldUrl/book/1/c1',
    );
    await contentDao.saveContent(
      contentKey: keyAt(oldUrl),
      origin: oldUrl,
      bookUrl: '$oldUrl/book/1',
      chapterUrl: '$oldUrl/book/1/c1',
      chapterIndex: 0,
      content: '已下載的第一章',
      updatedAt: 1,
    );
    await getIt<SearchBookDao>().upsert(
      SearchBook(
        bookUrl: '$oldUrl/book/2',
        name: '乙書',
        origin: oldUrl,
        originName: '舊名',
      ),
    );
    final cache = CacheManager();
    await cache.put('userInfo_$oldUrl', '{"user":"讀者"}');
    await cache.put('v_${oldUrl}_token', 'abc');

    await BookSourceService().saveEditedSource(
      BookSource(bookSourceUrl: newUrl, bookSourceName: '新名'),
      previousUrl: oldUrl,
    );

    expect(await getIt<BookSourceDao>().getByUrl(oldUrl), isNull);
    final book = (await getIt<BookDao>().getByUrl('$oldUrl/book/1'))!;
    expect(book.origin, newUrl, reason: '書架上的書指向新網址');
    expect(book.originName, '新名');
    expect(await getIt<BookSourceDao>().getByUrl(book.origin), isNotNull);
    expect(
      await contentDao.getContent(contentKey: keyAt(newUrl)),
      '已下載的第一章',
      reason: '已下載的章節照新網址讀得到',
    );
    expect(await contentDao.getContent(contentKey: keyAt(oldUrl)), isNull);
    final search = await getIt<SearchBookDao>().getByNames(['乙書']);
    expect(search.single.origin, newUrl);
    expect(await cache.get('userInfo_$newUrl'), '{"user":"讀者"}');
    expect(await cache.get('userInfo_$oldUrl'), isNull);
    expect(await cache.get('v_${newUrl}_token'), 'abc');
    expect(await cache.get('v_${oldUrl}_token'), isNull);
    // 同步時別台照這份紀錄搬。
    expect(SourceMoves(await SharedPreferences.getInstance()).read(), {
      newUrl: [oldUrl],
    });
  });

  test('rule variables of another source whose URL starts with this one are '
      'left alone', () async {
    const nested = '${oldUrl}_child';
    for (final url in [oldUrl, nested]) {
      await getIt<BookSourceDao>().upsert(
        BookSource(bookSourceUrl: url, bookSourceName: url),
      );
    }
    final cache = CacheManager();
    await cache.put('v_${oldUrl}_token', '這個書源的');
    await cache.put('v_${nested}_token', '另一個書源的');

    await BookSourceService().saveEditedSource(
      BookSource(bookSourceUrl: newUrl, bookSourceName: '新名'),
      previousUrl: oldUrl,
    );

    expect(await cache.get('v_${newUrl}_token'), '這個書源的');
    expect(await cache.get('v_${nested}_token'), '另一個書源的');
    expect(await cache.get('v_${newUrl}_child_token'), isNull);
  });

  test(
    'when saving to the database fails, the login stays where it was',
    () async {
      final cache = CacheManager();
      await cache.put('userInfo_$oldUrl', '{"user":"讀者"}');
      await cache.put('v_${oldUrl}_token', 'abc');

      await expectLater(
        BaseSource.moveCachedIdentity(
          oldUrl,
          newUrl,
          commit: () async => throw StateError('資料庫寫不進去'),
        ),
        throwsStateError,
      );

      expect(await cache.get('userInfo_$oldUrl'), '{"user":"讀者"}');
      expect(await cache.get('v_${oldUrl}_token'), 'abc');
      expect(await cache.get('userInfo_$newUrl'), isNull, reason: '複製的刪掉');
      expect(await cache.get('v_${newUrl}_token'), isNull);
    },
  );

  test('saving without changing the URL leaves the books alone', () async {
    await getIt<BookSourceDao>().upsert(
      BookSource(bookSourceUrl: oldUrl, bookSourceName: '舊名'),
    );
    await getIt<BookDao>().upsert(
      Book(bookUrl: '$oldUrl/book/1', name: '甲書', origin: oldUrl),
    );

    await BookSourceService().saveEditedSource(
      BookSource(bookSourceUrl: oldUrl, bookSourceName: '改了名'),
      previousUrl: oldUrl,
    );

    expect(
      (await getIt<BookSourceDao>().getByUrl(oldUrl))!.bookSourceName,
      '改了名',
    );
    expect((await getIt<BookDao>().getByUrl('$oldUrl/book/1'))!.origin, oldUrl);
  });
}
