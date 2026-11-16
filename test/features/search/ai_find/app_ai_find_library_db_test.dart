import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/book_type.dart';
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
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/search/ai_find/app_ai_find_library.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 書籍詳情照書源給：[infos] 照書源網址，精確搜尋找回同一本。
class _Sites extends BookSourceService {
  _Sites(this.infos);

  final Map<String, Book> infos;
  final List<String> asked = [];

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    asked.add(source.bookSourceUrl);
    return infos[source.bookSourceUrl]!;
  }

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author, {
    CancelToken? cancelToken,
  }) async => [
    SearchBook(
      bookUrl: '${source.bookSourceUrl}/$name',
      name: name,
      author: author,
      origin: source.bookSourceUrl,
      originName: source.bookSourceUrl,
    ),
  ];
}

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

  test('a detail without a word count or intro fills them from the other '
      'sources of the same book, keeping the main one', () async {
    for (final url in ['https://a.test', 'https://b.test', 'https://c.test']) {
      await addSource(url);
    }
    final sites = _Sites({
      'https://a.test': Book(
        bookUrl: 'https://a.test/x',
        name: '獵魔人',
        origin: 'https://a.test',
        kind: '玄幻',
      ),
      'https://b.test': Book(
        bookUrl: 'https://b.test/x',
        name: '獵魔人',
        origin: 'https://b.test',
        intro: '穿越後獵魔',
      ),
      'https://c.test': Book(
        bookUrl: 'https://c.test/x',
        name: '獵魔人',
        origin: 'https://c.test',
        intro: '別的簡介',
        wordCount: '120萬字',
      ),
    });
    final library = AppAiFindLibrary(scope: SearchScope(), service: sites);
    final book = found('https://a.test', '獵魔人')
      ..origins.addAll(['https://b.test', 'https://c.test']);
    final detail = await library.detail(book, CancelToken());
    expect(detail.origin, 'https://a.test', reason: '還是主要書源那一本');
    expect(detail.kind, '玄幻');
    expect(detail.intro, '穿越後獵魔', reason: '先補到的為準');
    expect(detail.wordCount, '120萬字');
    expect(sites.asked, ['https://a.test', 'https://b.test', 'https://c.test']);
  });

  test('a comic with an intro but no word count is not looked up elsewhere: '
      'comic sources rarely give one', () async {
    for (final url in ['https://a.test', 'https://b.test']) {
      await addSource(url);
    }
    final sites = _Sites({
      'https://a.test': Book(
        bookUrl: 'https://a.test/x',
        name: '海賊',
        origin: 'https://a.test',
        intro: '航海冒險',
      ),
      'https://b.test': Book(
        bookUrl: 'https://b.test/x',
        name: '海賊',
        origin: 'https://b.test',
        wordCount: '300話',
      ),
    });
    final library = AppAiFindLibrary(scope: SearchScope(), service: sites);
    final comic = found('https://a.test', '海賊')
      ..type = BookType.image
      ..origins.add('https://b.test');
    final detail = await library.detail(comic, CancelToken());
    expect(detail.intro, '航海冒險');
    expect(sites.asked, ['https://a.test']);
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
