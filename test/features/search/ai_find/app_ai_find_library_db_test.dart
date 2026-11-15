import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/ai_find/app_ai_find_library.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 正式書庫接資料庫的那幾段：搜尋的時限與秘密、書架與閱讀紀錄。書源的搜尋
/// 換成記憶體裡的 [SearchBookLoader]，不連網站。
void main() {
  late AppDatabase db;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<BookSource> addSource(String url, {String? header}) async {
    final source = BookSource(
      bookSourceUrl: url,
      bookSourceName: url,
      header: header,
    );
    await getIt<BookSourceDao>().insertOrUpdateAll([source]);
    return source;
  }

  SearchBook found(String origin, String name, {String? intro}) => SearchBook(
    bookUrl: '$origin/$name',
    name: name,
    author: '作者',
    origin: origin,
    originName: origin,
    intro: intro,
  );

  test('secrets of every source in the search results are collected before '
      'the results go to the AI', () async {
    await addSource(
      'https://a.test',
      header: '{"Authorization":"Bearer token-abc-123456"}',
    );
    final library = AppAiFindLibrary(
      scope: SearchScope(),
      searchLoader: (source, key, {cancelToken}) async => [
        found(
          source.bookSourceUrl,
          '海賊王之劍豪',
          intro: '登入後才看得到 Bearer token-abc-123456',
        ),
      ],
    );
    final result = await library.search(
      '海賊王',
      BookSourceKind.novel,
      CancelToken(),
    );
    expect(result.books, hasLength(1));
    expect(
      library.secrets,
      contains(contains('token-abc-123456')),
      reason: '只搜尋、還沒看詳情的書源也要收',
    );
  });

  test('the time limit hands back what has arrived even when a source never '
      'answers', () async {
    await addSource('https://fast.test');
    await addSource('https://stuck.test');
    final stuck = Completer<List<SearchBook>>();
    final library = AppAiFindLibrary(
      scope: SearchScope(),
      searchLimit: const Duration(milliseconds: 200),
      searchLoader: (source, key, {cancelToken}) =>
          source.bookSourceUrl == 'https://stuck.test'
          ? stuck.future
          : Future.value([found(source.bookSourceUrl, '海賊王之劍豪')]),
    );
    final result = await library
        .search('海賊王', BookSourceKind.novel, CancelToken())
        .timeout(const Duration(seconds: 5));
    expect(result.books.map((b) => b.name), ['海賊王之劍豪']);
    expect(result.pending, 1);
    // 放行卡住的書源，等那次搜尋自己收尾（寫回書源回應時間）再關資料庫。
    stuck.complete(const []);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  test('reading time of comics and audiobooks is matched by their record '
      'name; one only in the records keeps its kind', () async {
    await getIt<BookDao>().upsertAll([
      Book(
        bookUrl: 'https://a.test/comic',
        name: '漫畫',
        origin: 'https://a.test',
        type: SourceType.image,
        isInBookshelf: true,
      ),
      Book(
        bookUrl: 'https://a.test/novel',
        name: '小說',
        origin: 'https://a.test',
        isInBookshelf: true,
      ),
    ]);
    for (final (name, seconds) in [
      ('comic:漫畫', 3600),
      ('小說', 1800),
      ('audio:有聲', 600),
    ]) {
      await getIt<ReadRecordDao>().upsert(
        ReadRecord(bookName: name, deviceId: 'a', readTime: seconds),
      );
    }
    final shelf = await AppAiFindLibrary(scope: SearchScope()).shelf();
    final byName = {for (final entry in shelf) entry.name: entry};
    expect(byName.keys, unorderedEquals(['漫畫', '小說', '有聲']));
    expect(byName['漫畫']!.readSeconds, 3600);
    expect(byName['漫畫']!.onShelf, isTrue);
    expect(byName['小說']!.readSeconds, 1800);
    expect(byName['有聲']!.onShelf, isFalse);
    expect(byName['有聲']!.kind, BookSourceKind.audio);
  });
}
