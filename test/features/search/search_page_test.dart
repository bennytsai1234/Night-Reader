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
