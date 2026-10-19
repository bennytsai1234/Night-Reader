import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/glass_motion.dart';

class _FakeBookDao extends Fake implements BookDao {
  _FakeBookDao(this.shelf);

  final List<Book> shelf;

  @override
  Future<List<Book>> getInBookshelf() async => List.of(shelf);
}

class _FakeBookSourceDao extends Fake implements BookSourceDao {
  final StreamController<bool> hasAny = StreamController<bool>.broadcast();

  @override
  Stream<bool> watchHasAny() => hasAny.stream;
}

class _FakeChapterDao extends Fake implements ChapterDao {}

void main() {
  // 最近閱讀：甲、乙、丙；依書名（Unicode）：丙、乙、甲。
  final books = [
    Book(bookUrl: 'u1', origin: 'o', name: '甲', durChapterTime: 3),
    Book(bookUrl: 'u2', origin: 'o', name: '乙', durChapterTime: 2),
    Book(bookUrl: 'u3', origin: 'o', name: '丙', durChapterTime: 1),
  ]..forEach((book) => book.isInBookshelf = true);

  late BookshelfProvider provider;
  late _FakeBookDao bookDao;
  late _FakeBookSourceDao sourceDao;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(bookDao = _FakeBookDao(List.of(books)))
      ..registerSingleton<BookSourceDao>(sourceDao = _FakeBookSourceDao())
      ..registerSingleton<ChapterDao>(_FakeChapterDao());
    provider = BookshelfProvider(
      keepBookDownloaded: (url, {hasNewChapters = false}) async {},
    );
  });

  tearDown(() async {
    provider.dispose();
    await GetIt.instance.reset();
  });

  Future<void> pumpShelf(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: ChangeNotifierProvider<BookshelfProvider>.value(
          value: provider,
          child: const BookshelfPage(),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  /// 照書架重新建立 provider（例如換成空書架或很多本書）。
  void reshelve(List<Book> shelf) {
    provider.dispose();
    bookDao.shelf
      ..clear()
      ..addAll(shelf);
    provider = BookshelfProvider(
      keepBookDownloaded: (url, {hasNewChapters = false}) async {},
    );
  }

  Future<void> enterSelect(WidgetTester tester) async {
    await tester.tap(find.byTooltip('整理書架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取'));
    await tester.pump();
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

  testWidgets('移出的書先淡出，淡完其他書卡才移過去補位', (tester) async {
    await pumpShelf(tester);
    final slots = [
      for (final name in ['甲', '乙', '丙']) slotOf(tester, name),
    ];

    bookDao.shelf.removeWhere((book) => book.name == '乙');
    unawaited(provider.loadBooks());
    await tester.pump();
    await tester.pump();
    await tester.pump(AppMotion.fade ~/ 2);
    // 乙還在原位淡出，丙還沒動。
    expect(slotOf(tester, '乙'), slots[1]);
    expect(slotOf(tester, '丙'), slots[2]);

    await tester.pump(AppMotion.fade);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.widgetWithText(BookshelfGridTile, '乙'), findsNothing);
    final midway = slotOf(tester, '丙').dx;
    expect(midway, lessThan(slots[2].dx));
    expect(midway, greaterThan(slots[1].dx));

    await tester.pumpAndSettle();
    expect(slotOf(tester, '丙'), slots[1]);
  });

  testWidgets('進出多選時標題淡換、頁首按鈕的玻璃留著只改寬度', (tester) async {
    await pumpShelf(tester);
    double leadingWidth() =>
        tester.getSize(find.byType(GlassMorph).first).width;
    final iconWidth = leadingWidth();

    await enterSelect(tester);
    await tester.pump(AppMotion.fade ~/ 2);
    // 淡換途中新舊標題都在，玻璃不在淡入裡，寬度在半路。
    expect(find.text('書架'), findsOneWidget);
    expect(find.text('已選 0 本'), findsOneWidget);
    expectNoGlassUnderFade(tester);
    final midway = leadingWidth();
    expect(midway, greaterThan(iconWidth));

    await tester.pumpAndSettle();
    expect(find.text('書架'), findsNothing);
    final textWidth = leadingWidth();
    expect(midway, lessThan(textWidth));
    // 頁首兩側各只有一塊玻璃（按鈕自己的玻璃交給 GlassMorph）。
    expect(
      find.descendant(
        of: find.byType(GlassNavHeader),
        matching: find.byType(BackdropFilter),
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('書架'), findsOneWidget);
    expect(leadingWidth(), iconWidth);
  });

  testWidgets('自訂排序的列表進出多選時保留捲動位置，勾選圈滑進來', (tester) async {
    reshelve([
      for (var i = 0; i < 30; i++)
        Book(bookUrl: 'm$i', origin: 'o', name: '書$i', order: i)
          ..isInBookshelf = true,
    ]);
    await provider.setSortMode(BookshelfSortMode.custom);
    provider.setGridView(false);
    await pumpShelf(tester);
    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.drag(find.byType(ReorderableListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      ),
    );
    final offset = scrollable.position.pixels;
    expect(offset, greaterThan(0));

    await enterSelect(tester);
    await tester.pump(AppMotion.menu ~/ 2);
    // 同一個清單、同一個捲動位置；勾選圈的位子正在讓出來。
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels,
      offset,
    );
    final slot = tester
        .getSize(
          find
              .ancestor(
                of: find.byType(BookshelfCheckMark).first,
                matching: find.byType(ClipRect),
              )
              .first,
        )
        .width;
    expect(slot, inExclusiveRange(0, BookshelfCheckMark.size + 10));

    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, offset);
  });

  testWidgets('全新安裝的空書架等查到書源才換場，不先畫搜尋書籍', (tester) async {
    reshelve([]);
    await pumpShelf(tester, settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('書架還是空的'), findsNothing);
    expect(find.text('搜尋書籍'), findsNothing);

    sourceDao.hasAny.add(false);
    await tester.pump();
    expect(find.text('搜尋書籍'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('匯入書源'), findsOneWidget);

    // 之後加了書源：兩種空書架交叉淡換。
    sourceDao.hasAny.add(true);
    await tester.pump();
    await tester.pump(AppMotion.fade ~/ 2);
    expect(find.text('匯入書源'), findsOneWidget);
    expect(find.text('搜尋書籍'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('匯入書源'), findsNothing);
    expect(find.text('搜尋書籍'), findsOneWidget);
  });

  testWidgets('書名要轉換時等字典好了才換場，書名一出現就是轉換後的字', (tester) async {
    reshelve([
      Book(bookUrl: 's1', origin: 'o', name: '斗罗大陆')..isInBookshelf = true,
    ]);
    ChineseDisplay.mode.value = 1;
    addTearDown(() => ChineseDisplay.mode.value = 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        builder: (context, child) => ChineseDisplayScope(child: child!),
        home: ChangeNotifierProvider<BookshelfProvider>.value(
          value: provider,
          child: const BookshelfPage(),
        ),
      ),
    );
    // 骨架一直呼吸，等不到靜止。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('斗罗大陆'), findsNothing, reason: '書到了，字典還沒好');
    expect(find.text('斗羅大陸'), findsNothing);

    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
    ChineseDisplay.mode.refresh();
    await tester.pumpAndSettle();
    expect(find.text('斗羅大陸'), findsOneWidget);
    expect(find.text('斗罗大陆'), findsNothing);
  });
}
