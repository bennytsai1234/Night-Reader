import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBookDao extends Fake implements BookDao {
  _FakeBookDao(this.shelf);

  final List<Book> shelf;

  @override
  Future<List<Book>> getInBookshelf() async => List.of(shelf);
}

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

void main() {
  // 最近閱讀：甲、乙、丙；依書名（Unicode）：丙、乙、甲。
  final books = [
    Book(bookUrl: 'u1', origin: 'o', name: '甲', durChapterTime: 3),
    Book(bookUrl: 'u2', origin: 'o', name: '乙', durChapterTime: 2),
    Book(bookUrl: 'u3', origin: 'o', name: '丙', durChapterTime: 1),
  ]..forEach((book) => book.isInBookshelf = true);

  late BookshelfProvider provider;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(_FakeBookDao(books))
      ..registerSingleton<BookSourceDao>(_FakeBookSourceDao())
      ..registerSingleton<ChapterDao>(_FakeChapterDao());
    provider = BookshelfProvider(
      keepBookDownloaded: (url, {hasNewChapters = false}) async {},
    );
  });

  tearDown(() async {
    provider.dispose();
    await GetIt.instance.reset();
  });

  Future<void> pumpShelf(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: ChangeNotifierProvider<BookshelfProvider>.value(
          value: provider,
          child: const BookshelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset slotOf(WidgetTester tester, String name) =>
      tester.getTopLeft(find.widgetWithText(BookshelfGridTile, name).first);

  testWidgets('換排序後書卡滑到新位置，結束時位置正確且沒有殘留位移', (tester) async {
    await pumpShelf(tester);
    final slots = [
      for (final name in ['甲', '乙', '丙']) slotOf(tester, name),
    ];
    expect(slots[0].dx, lessThan(slots[1].dx));

    unawaited(provider.setSortMode(BookshelfSortMode.bookName));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 甲正從第一格往第三格移動。
    final midway = slotOf(tester, '甲').dx;
    expect(midway, greaterThan(slots[0].dx));
    expect(midway, lessThan(slots[2].dx));

    await tester.pumpAndSettle();
    expect(slotOf(tester, '丙'), slots[0]);
    expect(slotOf(tester, '乙'), slots[1]);
    expect(slotOf(tester, '甲'), slots[2]);
  });

  testWidgets('網格與列表互換時交叉淡化，結束後只留新的檢視', (tester) async {
    await pumpShelf(tester);
    expect(find.byType(GridView), findsOneWidget);

    provider.setGridView(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.widgetWithText(BookshelfListCard, '甲'), findsWidgets);
  });

  testWidgets('交叉淡化途中換頁，封面 Hero 不重複', (tester) async {
    await pumpShelf(tester);

    provider.setGridView(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GridView), findsOneWidget);

    // 換頁時收集來源路由的 Hero；淡出中的網格若還帶著 tag 會和列表重複。
    Navigator.of(tester.element(find.byType(ListView)))
        .push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
