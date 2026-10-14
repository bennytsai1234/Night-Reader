import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
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
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<SearchBookDao>(SearchBookDao(db))
      ..registerSingleton<SearchKeywordDao>(SearchKeywordDao(db));
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('a submitted search is in progress before the engine starts', () async {
    final provider = SearchProvider();
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
      final provider = SearchProvider();
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
    final provider = SearchProvider();
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
    final provider = SearchProvider();
    await pumpEventQueue();

    provider.dispose();
    await pumpEventQueue();

    expect(await dao.getSearchBooks('夜讀', '作者'), isEmpty);
  });

  test('the chosen search scope is remembered', () async {
    final provider = SearchProvider();
    addTearDown(provider.dispose);

    provider.updateSearchScope(SearchScope.fromGroups(['精選']));
    await Future<void>.delayed(Duration.zero);

    final restored = await SearchScope.load();
    expect(restored.displayNames, ['精選']);
  });
}
