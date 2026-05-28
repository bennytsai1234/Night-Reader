import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/engine/app_event_bus.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/database/dao/search_keyword_dao.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_keyword.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/features/search/search_model.dart';
import 'package:reader/features/search/search_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake DAOs
// ---------------------------------------------------------------------------

class _FakeSourceDao extends Fake implements BookSourceDao {
  List<BookSource> sources = [];

  @override
  Future<List<BookSource>> getAllPart() async => sources;

  @override
  Future<List<BookSource>> getEnabled() async =>
      sources.where((s) => s.enabled).toList();

  @override
  Future<List<BookSource>> getAll() async => sources;

  @override
  Future<BookSource?> getByUrl(String url) async =>
      sources.where((s) => s.bookSourceUrl == url).firstOrNull;
}

class _FakeKeywordDao extends Fake implements SearchKeywordDao {
  final List<SearchKeyword> _keywords = [];

  @override
  Future<List<SearchKeyword>> getByTime() async => _keywords;

  @override
  Future<List<SearchKeyword>> getAll() async => _keywords;

  @override
  Future<void> saveKeyword(String word) async {
    final idx = _keywords.indexWhere((k) => k.word == word);
    if (idx != -1) {
      _keywords[idx].usage += 1;
      _keywords[idx].lastUseTime = DateTime.now().millisecondsSinceEpoch;
    } else {
      _keywords.add(
        SearchKeyword(
          word: word,
          usage: 1,
          lastUseTime: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  @override
  Future<void> clearAll() async => _keywords.clear();

  @override
  Future<void> deleteByWord(String word) async =>
      _keywords.removeWhere((k) => k.word == word);

  @override
  Future<SearchKeyword?> getByWord(String word) async =>
      _keywords.where((k) => k.word == word).firstOrNull;
}

class _FakeBookDao extends Fake implements BookDao {
  List<Book> shelf = [];

  @override
  Future<List<Book>> getInBookshelf() async => shelf;
}

Book _makeBook({
  required String bookUrl,
  required String name,
  required String author,
  String origin = 'source://main',
}) {
  return Book(
    bookUrl: bookUrl,
    name: name,
    author: author,
    origin: origin,
    originName: '主書源',
    isInBookshelf: true,
  );
}

SearchBook _makeSearchBook({
  required String bookUrl,
  required String name,
  required String author,
  String origin = 'source://main',
  String originName = '主書源',
  String? kind,
  String? coverUrl,
  String? latestChapterTitle,
  int originOrder = 0,
}) {
  return SearchBook(
    bookUrl: bookUrl,
    name: name,
    author: author,
    origin: origin,
    originName: originName,
    kind: kind,
    coverUrl: coverUrl,
    latestChapterTitle: latestChapterTitle,
    originOrder: originOrder,
  );
}

Future<void> _settleAsync() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

// ---------------------------------------------------------------------------
// 測試
// ---------------------------------------------------------------------------

void main() {
  late _FakeSourceDao fakeSourceDao;
  late _FakeKeywordDao fakeKeywordDao;
  late _FakeBookDao fakeBookDao;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeSourceDao = _FakeSourceDao();
    fakeKeywordDao = _FakeKeywordDao();
    fakeBookDao = _FakeBookDao();

    final getIt = GetIt.instance;
    getIt.registerLazySingleton<BookDao>(() => fakeBookDao);
    getIt.registerLazySingleton<BookSourceDao>(() => fakeSourceDao);
    getIt.registerLazySingleton<SearchKeywordDao>(() => fakeKeywordDao);
  });

  tearDown(() async => GetIt.instance.reset());

  Future<SearchProvider> makeProvider() async {
    final p = SearchProvider();
    addTearDown(p.dispose);
    await _settleAsync(); // 等 constructor async 完成
    return p;
  }

  group('SearchProvider - 書源群組', () {
    test('無書源時 sourceGroups 為空', () async {
      final p = await makeProvider();
      expect(p.sourceGroups, isEmpty);
    });

    test('有群組的書源會加入 sourceGroups', () async {
      fakeSourceDao.sources = [
        BookSource(
          bookSourceUrl: 'http://a.com',
          bookSourceName: 'A',
          bookSourceGroup: '玄幻',
        ),
        BookSource(
          bookSourceUrl: 'http://b.com',
          bookSourceName: 'B',
          bookSourceGroup: '都市',
        ),
      ];
      final p = await makeProvider();
      expect(p.sourceGroups, containsAll(['玄幻', '都市']));
    });

    test('searchScope 初始為全部', () async {
      final p = await makeProvider();
      expect(p.searchScope.isAll, isTrue);
    });
  });

  group('SearchProvider - 精準搜尋', () {
    test('初始 precisionSearch 為 false', () async {
      final p = await makeProvider();
      expect(p.precisionSearch, isFalse);
    });

    test('togglePrecisionSearch 切換狀態並寫入 prefs', () async {
      final p = await makeProvider();
      await p.togglePrecisionSearch();
      expect(p.precisionSearch, isTrue);
      await p.togglePrecisionSearch();
      expect(p.precisionSearch, isFalse);
    });
  });

  group('SearchProvider - 搜尋狀態', () {
    test('search 空字串不啟動搜尋', () async {
      final p = await makeProvider();
      await p.search('');
      expect(p.isSearching, isFalse);
      expect(p.lastSearchKey, isEmpty);
    });

    test('stopSearch 設定 isSearching = false', () async {
      final p = await makeProvider();
      // 直接呼叫 stopSearch，不實際觸發網路
      p.stopSearch();
      expect(p.isSearching, isFalse);
    });

    test('無啟用書源時 search 完成後 isSearching = false', () async {
      fakeSourceDao.sources = [];
      final p = await makeProvider();
      await p.search('測試');
      expect(p.isSearching, isFalse);
      expect(p.lastSearchKey, '測試');
    });
  });

  group('SearchProvider - 搜尋歷史', () {
    test('初始歷史為空', () async {
      final p = await makeProvider();
      expect(p.history, isEmpty);
    });

    test('搜尋後歷史更新', () async {
      fakeSourceDao.sources = [];
      final p = await makeProvider();
      await p.search('閱讀');
      expect(p.history, contains('閱讀'));
    });

    test('clearHistory 清空歷史', () async {
      fakeSourceDao.sources = [];
      final p = await makeProvider();
      await p.search('閱讀');
      await p.clearHistory();
      expect(p.history, isEmpty);
    });

    test('deleteHistoryKeyword 刪除單條記錄', () async {
      fakeSourceDao.sources = [];
      final p = await makeProvider();
      await p.search('閱讀');
      await p.search('搜尋');
      expect(p.history.length, 2);

      final keyword = p.historyKeywords.firstWhere((k) => k.word == '閱讀');
      await p.deleteHistoryKeyword(keyword);
      expect(p.history, isNot(contains('閱讀')));
      expect(p.history, contains('搜尋'));
    });
  });

  group('SearchProvider - progress', () {
    test('無書源時 progress 為 0', () async {
      final p = await makeProvider();
      expect(p.progress, 0.0);
    });

    test('totalSources 初始為 0', () async {
      final p = await makeProvider();
      expect(p.totalSources, 0);
    });
  });

  group('SearchProvider - 書架狀態', () {
    test('初始載入只同步相同書源與 bookUrl', () async {
      fakeBookDao.shelf = [
        _makeBook(
          bookUrl: 'https://example.com/books/1',
          name: '測試書',
          author: '作者甲',
        ),
      ];
      final p = await makeProvider();

      expect(
        p.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/1',
            name: '測試書',
            author: '作者甲',
          ),
        ),
        isTrue,
      );

      expect(
        p.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/1',
            name: '測試書',
            author: '作者甲',
            origin: 'source://other',
          ),
        ),
        isFalse,
      );

      expect(
        p.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/redirected',
            name: '測試書',
            author: '作者甲',
          ),
        ),
        isFalse,
      );

      expect(
        p.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/other',
            name: '其他書',
            author: '作者乙',
          ),
        ),
        isFalse,
      );
    });

    test('收到 upBookshelf 事件後會重新同步書架狀態', () async {
      final p = await makeProvider();
      final targetBook = _makeBook(
        bookUrl: 'https://example.com/books/2',
        name: '事件同步書',
        author: '作者乙',
      );
      final targetSearchBook = _makeSearchBook(
        bookUrl: targetBook.bookUrl,
        name: targetBook.name,
        author: targetBook.author,
      );

      expect(p.isInBookshelf(targetSearchBook), isFalse);

      fakeBookDao.shelf = [targetBook];
      AppEventBus().fire(AppEventBus.upBookshelf);
      await _settleAsync();
      expect(p.isInBookshelf(targetSearchBook), isTrue);

      fakeBookDao.shelf = [];
      AppEventBus().fire(AppEventBus.upBookshelf);
      await _settleAsync();
      expect(p.isInBookshelf(targetSearchBook), isFalse);
    });
  });

  group('SearchProvider - 結果排序與篩選', () {
    test('sorts search results by name', () async {
      final p = await makeProvider();
      p.onSearchSuccess([
        _makeSearchBook(
          bookUrl: 'https://example.com/b',
          name: 'Book B',
          author: '作者乙',
        ),
        _makeSearchBook(
          bookUrl: 'https://example.com/a',
          name: 'Book A',
          author: '作者甲',
        ),
      ]);

      p.updateSortMode(SearchResultSortMode.name);
      expect(p.results.map((book) => book.name), ['Book A', 'Book B']);
    });

    test(
      'filters by source, author, kind, cover, and bookshelf state',
      () async {
        fakeBookDao.shelf = [
          _makeBook(
            bookUrl: 'https://example.com/a',
            name: '甲書',
            author: '作者甲',
            origin: 'source://a',
          ),
        ];
        final p = await makeProvider();
        p.onSearchSuccess([
          _makeSearchBook(
            bookUrl: 'https://example.com/a',
            name: '甲書',
            author: '作者甲',
            origin: 'source://a',
            originName: '來源甲',
            kind: '玄幻',
            coverUrl: 'https://example.com/a.jpg',
          ),
          _makeSearchBook(
            bookUrl: 'https://example.com/b',
            name: '乙書',
            author: '作者乙',
            origin: 'source://b',
            originName: '來源乙',
            kind: '都市',
          ),
        ]);

        p.toggleSourceFilter('來源甲');
        p.setAuthorFilter('作者甲');
        p.setKindFilter('玄幻');
        p.setOnlyWithCover(true);
        p.setOnlyInBookshelf(true);

        expect(p.results, hasLength(1));
        expect(p.results.single.name, '甲書');

        p.clearResultFilters();
        expect(p.results, hasLength(2));
      },
    );

    test('records searchable failure details', () async {
      final p = await makeProvider();
      final source = BookSource(
        bookSourceUrl: 'source://failed',
        bookSourceName: '失敗源',
      );

      p.onSearchFailure(SearchFailure(source: source, message: '連線逾時'));

      expect(p.sourceFailures, hasLength(1));
      expect(p.sourceFailures.single.source.bookSourceName, '失敗源');
      expect(p.sourceFailures.single.message, '連線逾時');
    });
  });
}
