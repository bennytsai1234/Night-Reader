import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/features/search/widgets/search_app_bar.dart';
import 'package:night_reader/features/search/widgets/search_suggestion_view.dart';
import 'package:night_reader/features/search/widgets/search_result_item.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 焦點測試只走畫面的送出回呼，不啟動書源與搜尋紀錄的非同步工作。
class _IdleSearchProvider extends SearchProvider {
  _IdleSearchProvider() : super(entrance: Future<void>.value());

  @override
  Future<void> search(String keyword) async {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
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

  SearchBook book(String name) => SearchBook(
    bookUrl: 'https://b.example/$name',
    name: name,
    author: '作者',
    origin: 'https://s.example',
    originName: '書源',
  );

  /// 這本書的列上還在淡入（透明度未滿）。
  bool fadingIn(WidgetTester tester, String name) => tester
      .widgetList<FadeTransition>(
        find.ancestor(
          of: find.text(name),
          matching: find.byType(FadeTransition),
        ),
      )
      .any((fade) => fade.opacity.value < 1);

  testWidgets('nothing is read until the page has slid in', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SizedBox(),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SearchPage()),
      ),
    );
    SearchProvider provider() => Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );

    // 預設的平移換頁是 0.5 秒：播到一半，搜尋範圍、書架與紀錄都還沒讀。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(provider().scopeLoaded, isFalse);

    await tester.pumpAndSettle();
    await tester.runAsync(() => provider().ready);
    expect(provider().scopeLoaded, isTrue);
  });

  testWidgets('streamed results fade in once; reordering does not replay it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    final provider = Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );

    provider.onSearchStart();
    provider.onSearchSuccess([book('甲書')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fadingIn(tester, '甲書'), isTrue);
    await tester.pumpAndSettle();
    expect(fadingIn(tester, '甲書'), isFalse);

    // 新的一本串流進來：只有它淡入。
    provider.onSearchSuccess([book('甲書'), book('乙書')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fadingIn(tester, '甲書'), isFalse);
    expect(fadingIn(tester, '乙書'), isTrue);
    await tester.pumpAndSettle();

    // 重新排序後兩列都重建，但不再淡入。
    provider.onSearchSuccess([book('乙書'), book('甲書')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fadingIn(tester, '甲書'), isFalse);
    expect(fadingIn(tester, '乙書'), isFalse);

    provider.onSearchFinish(isEmpty: false);
    await tester.pumpAndSettle();
  });

  testWidgets('只有搜尋進度改變時，結果卡與頁首不跟著重建', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    final provider = Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );
    await tester.runAsync(() => provider.ready);
    provider.onSearchStart();
    provider.onSearchSuccess([book('已經顯示的書')]);
    await tester.pumpAndSettle();
    final rebuilt = <Widget>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    provider.onSearchProgress(
      waitingSources: ['書源'],
      completed: 1,
      total: 60,
      failed: 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('正在搜尋 1/60'), findsOneWidget);
    expect(rebuilt.whereType<SearchResultItem>(), isEmpty);
    expect(rebuilt.whereType<SearchAppBar>(), isEmpty);
    debugOnRebuildDirtyWidget = previous;
    provider.onSearchFinish(isEmpty: false);
    await tester.pumpAndSettle();
  });

  testWidgets('送出搜尋後收起輸入焦點不會再重建整頁', (tester) async {
    late _IdleSearchProvider provider;
    await tester.runAsync(() async {
      provider = _IdleSearchProvider();
      await provider.ready;
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<SearchProvider>(
        create: (_) => provider,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: const SearchView(),
        ),
      ),
    );
    tester.widget<SearchAppBar>(find.byType(SearchAppBar)).onSearch('夜');
    provider.onSearchSuccess([book('已經顯示的書')]);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final rebuilt = <Widget>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(rebuilt.whereType<SearchView>(), isEmpty);
    expect(rebuilt.whereType<SearchResultItem>(), isEmpty);
    debugOnRebuildDirtyWidget = previous;
  });

  testWidgets('after the user scrolls, new books join at the end', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    final provider = Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );
    provider.updateSortMode(SearchResultSortMode.sourceCount);

    final shown = [for (var i = 0; i < 20; i++) book('書$i')];
    provider.onSearchStart();
    provider.onSearchSuccess(shown);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // 來源最多的新書照排序該排第一，但使用者已經在捲了。
    final popular = book('熱門')..addOrigin('https://s2.example', name: '書源2');
    provider.onSearchSuccess([popular, ...shown]);
    await tester.pumpAndSettle();
    expect(provider.results.first.name, '書0');
    expect(provider.results.last.name, '熱門');

    provider.onSearchFinish(isEmpty: false);
    await tester.pumpAndSettle();
  });

  testWidgets('typing suggests matching history in either script', (
    tester,
  ) async {
    await tester.runAsync(
      () => GetIt.instance<SearchKeywordDao>().saveKeyword('鬥羅大陸'),
    );
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '斗罗');
    await tester.pump();
    final suggestion = find.descendant(
      of: find.byType(SearchSuggestionView),
      matching: find.text('鬥羅大陸'),
    );
    expect(suggestion, findsOneWidget);

    await tester.tap(suggestion);
    await tester.pump();
    expect(
      Provider.of<SearchProvider>(
        tester.element(find.byType(SearchAppBar)),
        listen: false,
      ).lastSearchKey,
      '鬥羅大陸',
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  });

  testWidgets('the last few sources are named and can be skipped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    final provider = Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );

    provider.onSearchStart();
    provider.onSearchSuccess([book('甲書')]);
    provider.onSearchProgress(
      waitingSources: const ['甲源', '乙源', '丙源', '丁源'],
      completed: 6,
      total: 10,
      failed: 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在搜尋 6/10'), findsOneWidget);

    provider.onSearchProgress(
      waitingSources: const ['甲源', '乙源'],
      completed: 8,
      total: 10,
      failed: 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('還在等：甲源、乙源'), findsOneWidget);

    await tester.tap(find.text('略過'));
    await tester.pumpAndSettle();
    expect(provider.isSearching, isFalse);
  });

  testWidgets('relevance order names each tier above its first book', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    final provider = Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );
    await tester.runAsync(() => provider.search('夜讀'));

    provider.onSearchStart();
    provider.onSearchSuccess([book('夜讀'), book('夜讀外傳'), book('別的書')]);
    provider.onSearchFinish(isEmpty: false);
    await tester.pumpAndSettle();
    expect(find.text('完全相符'), findsOneWidget);
    expect(find.text('部分相符'), findsOneWidget);
    expect(find.text('其他結果'), findsOneWidget);

    provider.updateSortMode(SearchResultSortMode.name);
    await tester.pumpAndSettle();
    expect(find.text('完全相符'), findsNothing);
  });

  testWidgets('results that arrive in the same frame as the finish still fade '
      'in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    final provider = Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );

    provider.onSearchStart();
    provider.onSearchSuccess([book('甲書')]);
    provider.onSearchFinish(isEmpty: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fadingIn(tester, '甲書'), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('search pauses under a full page, not under a dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    final pageContext = tester.element(find.byType(SearchAppBar));
    final provider = Provider.of<SearchProvider>(pageContext, listen: false);
    expect(provider.isSearchPaused, isFalse);

    // 例如點進書籍詳情。
    Navigator.of(pageContext)
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(provider.isSearchPaused, isTrue);

    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    expect(provider.isSearchPaused, isFalse);

    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (_) => const AlertDialog(content: Text('排序')),
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.isSearchPaused, isFalse);
    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
  });

  Future<SearchProvider> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    return Provider.of<SearchProvider>(
      tester.element(find.byType(SearchAppBar)),
      listen: false,
    );
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  /// 之後每一幀（16ms）這些書名所在的高度，直到動畫播完。
  Future<Map<String, List<double>>> trace(
    WidgetTester tester,
    List<String> names,
  ) async {
    final frames = {for (final name in names) name: <double>[]};
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final name in names) {
        frames[name]!.add(top(tester, name));
      }
    }
    return frames;
  }

  /// 每一幀只移動一小段（不跳），途中經過兩端之間，最後停在 [end]。
  void expectGlide(
    List<double> frames, {
    required double start,
    required double end,
  }) {
    var previous = start;
    for (final y in frames) {
      expect((y - previous).abs(), lessThan((end - start).abs() / 4));
      previous = y;
    }
    expect(
      frames.any((y) => (y - start).abs() > 1 && (y - end).abs() > 1),
      isTrue,
    );
    expect(frames.last, moreOrLessEquals(end, epsilon: 1));
  }

  testWidgets('reordered rows slide to their new places', (tester) async {
    final provider = await pumpSearch(tester);
    provider.onSearchStart();
    provider.onSearchSuccess([book('甲書'), book('乙書')]);
    await tester.pumpAndSettle();
    final first = top(tester, '甲書');
    final second = top(tester, '乙書');
    expect(second, greaterThan(first));

    provider.onSearchSuccess([book('乙書'), book('甲書')]);
    await tester.pump();
    // 重排的第一幀：兩列都還畫在原本的位置。
    expect(top(tester, '甲書'), moreOrLessEquals(first, epsilon: 1));
    expect(top(tester, '乙書'), moreOrLessEquals(second, epsilon: 1));

    final frames = await trace(tester, ['甲書', '乙書']);
    expectGlide(frames['甲書']!, start: first, end: second);
    expectGlide(frames['乙書']!, start: second, end: first);

    provider.onSearchFinish(isEmpty: false);
    await tester.pumpAndSettle();
  });

  testWidgets('a new book above pushes the rows below down gradually', (
    tester,
  ) async {
    final provider = await pumpSearch(tester);
    provider.onSearchStart();
    provider.onSearchSuccess([book('甲書')]);
    await tester.pumpAndSettle();
    final before = top(tester, '甲書');

    provider.onSearchSuccess([book('乙書'), book('甲書')]);
    await tester.pump();
    expect(top(tester, '甲書'), moreOrLessEquals(before, epsilon: 1));
    final frames = await trace(tester, ['甲書']);
    await tester.pumpAndSettle();
    final after = top(tester, '甲書');
    expect(after, greaterThan(before + 10));
    expectGlide(frames['甲書']!, start: before, end: after);

    provider.onSearchFinish(isEmpty: false);
    await tester.pumpAndSettle();
  });

  testWidgets('finishing fades the progress out and the toolbar in', (
    tester,
  ) async {
    final provider = await pumpSearch(tester);
    provider.onSearchStart();
    provider.onSearchSuccess([book('甲書')]);
    await tester.pumpAndSettle();
    expect(find.text('正在搜尋'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final resultTop = top(tester, '甲書');

    double opacityOf(Finder finder) => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: finder, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;

    provider.onSearchFinish(isEmpty: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 途中進度條與進度字樣還在、淡出中，工具列淡入中；結果沒有被推動。
    final bar = opacityOf(find.byType(LinearProgressIndicator));
    final progress = opacityOf(find.text('正在搜尋'));
    final toolbar = opacityOf(find.textContaining('排序'));
    for (final value in [bar, progress, toolbar]) {
      expect(value, greaterThan(0));
      expect(value, lessThan(1));
    }
    expect(top(tester, '甲書'), resultTop);

    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('正在搜尋'), findsNothing);
    expect(opacityOf(find.textContaining('排序')), 1);
    expect(top(tester, '甲書'), resultTop);
  });
}
