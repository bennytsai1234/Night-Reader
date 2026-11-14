import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/search_keyword.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<SearchBookDao>(SearchBookDao(db))
      ..registerSingleton<SearchKeywordDao>(SearchKeywordDao(db))
      ..registerSingleton<AiFindDao>(AiFindDao(db));
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('deleting a keyword keeps what the next page opens with in step with '
      'the database', () async {
    final dao = GetIt.instance<SearchKeywordDao>();
    // 51 筆：一次列最近 50 筆，刪掉一筆後第 51 筆補上來。
    for (var i = 0; i < 51; i++) {
      await dao.upsert(SearchKeyword(word: '詞$i', usage: 1, lastUseTime: i));
    }
    final provider = SearchProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    await provider.ready;
    expect(provider.history, hasLength(50));

    await provider.deleteHistoryKeyword(provider.historyKeywords.first);
    expect(provider.history, hasLength(50));
    expect(provider.history, contains('詞0'));

    // 下一次推入搜尋頁的第一幀就是資料庫會給的那 50 筆。
    final next = SearchProvider(entrance: Completer<void>().future);
    addTearDown(next.dispose);
    expect(next.historyLoaded, isTrue);
    expect(next.history, provider.history);
  });

  test('a submitted search is in progress before the engine starts', () async {
    final provider = SearchProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);

    final searching = provider.search('斗羅');
    // 存歷史、讀書源清單的空檔裡不能被當成「沒有結果」。
    expect(provider.isSearching, isTrue);
    expect(provider.results, isEmpty);

    await searching;
    expect(provider.isSearching, isFalse);
  });

  group('held result order', () {
    SearchBook book(String name, {int sources = 1}) {
      final card = SearchBook(
        bookUrl: 'https://b.example/$name',
        name: name,
        author: '作者',
        origin: 'https://s0.example',
        originName: '書源0',
      );
      for (var i = 1; i < sources; i++) {
        card.addOrigin('https://s$i.example', name: '書源$i');
      }
      return card;
    }

    List<String> names(SearchProvider provider) =>
        provider.results.map((b) => b.name).toList();

    /// 等建構時的非同步載入跑完，測試結束關掉資料庫後才不會再去讀。
    Future<SearchProvider> settledProvider() async {
      final provider = SearchProvider(entrance: Future<void>.value());
      addTearDown(provider.dispose);
      await pumpEventQueue();
      return provider;
    }

    test(
      'once held, shown books stay put and new books go to the end',
      () async {
        final provider = await settledProvider();
        provider.updateSortMode(SearchResultSortMode.sourceCount);

        provider.onSearchSuccess([book('甲', sources: 2), book('乙')]);
        provider.holdResultOrder();
        // 乙多了來源、新來的丙來源最多：照排序都該往前，但順序已固定。
        provider.onSearchSuccess([
          book('丙', sources: 5),
          book('乙', sources: 3),
          book('甲', sources: 2),
        ]);

        expect(names(provider), ['甲', '乙', '丙']);
        expect(provider.results[1].origins.length, 3);
      },
    );

    test('屏蔽詞：書名或作者含有的不列，記在手機上，「清除」不清它', () async {
      SearchBook by(String name, String author) => SearchBook(
        bookUrl: 'https://b.example/$name',
        name: name,
        author: author,
        origin: 'https://s0.example',
        originName: '書源0',
      );
      final provider = await settledProvider();
      provider.onSearchSuccess([
        by('夜雨聽書', '沈知秋'),
        by('穿越之霸道總裁', '某人'),
        by('山海經異聞錄', '廣告作者'),
      ]);
      await provider.setBlockedWords('霸道、 廣告');
      expect(names(provider), ['夜雨聽書']);

      provider.clearResultFilters();
      expect(names(provider), ['夜雨聽書']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('search_blocked_words'), '霸道、 廣告');

      final again = await settledProvider();
      expect(again.blockedWords, '霸道、 廣告');
    });

    test('choosing a sort order re-sorts and releases the hold', () async {
      final provider = await settledProvider();
      provider.updateSortMode(SearchResultSortMode.sourceCount);

      provider.onSearchSuccess([book('甲')]);
      provider.holdResultOrder();
      provider.onSearchSuccess([book('甲'), book('乙', sources: 2)]);
      expect(names(provider), ['甲', '乙']);

      provider.updateSortMode(SearchResultSortMode.sourceCount);
      expect(names(provider), ['乙', '甲']);
    });

    test('a cover found on the detail page stays on the card until the next '
        'search', () async {
      final provider = await settledProvider();
      final opened = book('甲');
      provider.onSearchSuccess([opened, book('乙')]);
      provider.rememberOpenedCard(opened);

      // 詳情還沒回報封面，同一本書就換了代表來源（bookUrl 不同）。
      final replaced = book('甲')..bookUrl = 'https://other.example/甲';
      provider.onSearchSuccess([replaced, book('乙')]);
      AppEventBus().fire(
        AppEventBus.bookCover,
        data: const BookCoverEvent(
          bookUrl: 'https://b.example/甲',
          cover: 'local:///covers/甲.jpg',
        ),
      );
      await pumpEventQueue();
      expect(provider.coverOf(replaced), 'local:///covers/甲.jpg');
      expect(provider.coverOf(provider.results.last), isNull);

      await provider.search('另一本');
      expect(provider.coverOf(replaced), isNull);
    });
  });

  test('suggestions list matching history first, then shelf titles, each '
      'word once', () async {
    await GetIt.instance<SearchKeywordDao>().saveKeyword('夜讀');
    await GetIt.instance<BookDao>().upsertAll([
      for (final name in ['夜讀', '夜讀外傳', '白晝'])
        Book(
          bookUrl: 'https://b.example/$name',
          origin: 'https://s.example',
          name: name,
          author: '作者',
          isInBookshelf: true,
        ),
    ]);
    final provider = SearchProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    await pumpEventQueue();

    final suggestions = provider.suggestionsFor('夜');
    expect(suggestions.map((s) => s.word), ['夜讀', '夜讀外傳']);
    expect(suggestions.map((s) => s.fromBookshelf), [false, true]);
    expect(provider.suggestionsFor('  '), isEmpty);
  });

  test('leaving search clears the stored results', () async {
    final dao = GetIt.instance<SearchBookDao>();
    await dao.insertList([
      SearchBook(
        bookUrl: 'https://b.example/夜讀',
        name: '夜讀',
        author: '作者',
        origin: 'https://s.example',
      ),
    ]);
    final provider = SearchProvider(entrance: Future<void>.value());
    await pumpEventQueue();

    provider.dispose();
    await pumpEventQueue();

    expect(await dao.getByNames(['夜讀']), isEmpty);
  });

  test('the chosen search scope is remembered', () async {
    final provider = SearchProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);

    await provider.updateSearchScope(SearchScope.fromGroups(['精選']));
    await Future<void>.delayed(Duration.zero);

    final restored = SearchScope.fromPrefs(
      await SharedPreferences.getInstance(),
    );
    expect(restored.displayNames, ['精選']);
  });

  group('search by kind', () {
    /// 每個書源搜到一本書，書名是書源名；聚合源搜到的是漫畫。
    final asked = <String>[];
    Future<List<SearchBook>> loader(
      BookSource source,
      String key, {
      CancelToken? cancelToken,
    }) async {
      asked.add(source.bookSourceName);
      return [
        SearchBook(
          bookUrl: '${source.bookSourceUrl}/book',
          name: source.bookSourceName,
          author: '作者',
          origin: source.bookSourceUrl,
          originName: source.bookSourceName,
          type: source.isAggregateSource
              ? SourceType.image
              : source.bookSourceType,
        ),
      ];
    }

    BookSource source(String name, int type, {bool aggregate = false}) =>
        BookSource(
          bookSourceUrl: 'https://$name.example',
          bookSourceName: name,
          bookSourceType: type,
          jsLib: aggregate ? 'function m(){ book.type = 64; }' : null,
        );

    Future<SearchProvider> provider({BookSourceKind? initialKind}) async {
      asked.clear();
      final provider = SearchProvider(
        entrance: Future<void>.value(),
        initialKind: initialKind,
        searchLoader: loader,
      );
      // 等離開搜尋頁的清理寫完，才關資料庫。
      addTearDown(() async {
        provider.dispose();
        await pumpEventQueue();
      });
      await provider.ready;
      return provider;
    }

    List<String> names(SearchProvider provider) =>
        provider.results.map((b) => b.name).toList();

    test('starts with novels: only novel sources and aggregates are asked, '
        'and only novels are listed', () async {
      await GetIt.instance<BookSourceDao>().upsertAll([
        source('小說站', SourceType.book),
        source('漫畫站', SourceType.image),
        source('聽書站', SourceType.audio),
        source('聚合站', SourceType.book, aggregate: true),
      ]);
      final search = await provider();
      expect(search.kinds, [
        BookSourceKind.novel,
        BookSourceKind.comic,
        BookSourceKind.audio,
      ]);
      expect(search.kind, BookSourceKind.novel);

      await search.search('夜');
      expect(asked..sort(), ['小說站', '聚合站']);
      expect(names(search), ['小說站']);

      // 換成漫畫就照新的類別重搜：聚合站搜到的漫畫列出來。
      asked.clear();
      search.setKind(BookSourceKind.comic);
      await pumpEventQueue();
      expect(asked..sort(), ['漫畫站', '聚合站']);
      expect(names(search)..sort(), ['漫畫站', '聚合站']);
    });

    test('a search opened for a comic starts with comics', () async {
      await GetIt.instance<BookSourceDao>().upsertAll([
        source('小說站', SourceType.book),
        source('漫畫站', SourceType.image),
      ]);
      final search = await provider(initialKind: BookSourceKind.comic);
      expect(search.kind, BookSourceKind.comic);
    });

    test('with one kind of source nothing is filtered: an aggregate\'s comic '
        'is still listed', () async {
      await GetIt.instance<BookSourceDao>().upsertAll([
        source('小說站', SourceType.book),
        source('聚合站', SourceType.book, aggregate: true),
      ]);
      final search = await provider();
      expect(search.kinds, [BookSourceKind.novel]);

      await search.search('夜');
      expect(names(search)..sort(), ['小說站', '聚合站']);
    });

    test('a chosen kind with no sources falls back to the first kind there '
        'is', () async {
      await GetIt.instance<BookSourceDao>().upsertAll([
        source('漫畫站', SourceType.image),
        source('聽書站', SourceType.audio),
      ]);
      final search = await provider();
      expect(search.kind, BookSourceKind.comic);
    });

    test(
      'the next search page draws the kind capsule on its first frame',
      () async {
        await GetIt.instance<BookSourceDao>().upsertAll([
          source('小說站', SourceType.book),
          source('漫畫站', SourceType.image),
        ]);
        await provider();
        await pumpEventQueue();

        final next = SearchProvider(entrance: Completer<void>().future);
        addTearDown(() async {
          next.dispose();
          await pumpEventQueue();
        });
        expect(next.kinds, [BookSourceKind.novel, BookSourceKind.comic]);
        expect(next.kindCounts[BookSourceKind.comic], 1);
      },
    );
  });
}
