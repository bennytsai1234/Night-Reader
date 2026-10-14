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
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/features/search/widgets/search_app_bar.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
