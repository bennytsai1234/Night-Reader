import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/shelf_trial.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/floating_tab_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    ShelfTrial.setShelfOrder(const []);
    ShelfTrial.compactTabBar.value = false;
  });

  const novel = BookSourceKind.novel;
  const audio = BookSourceKind.audio;

  test('書架位置由上到下是 0 到 1，不在書架上的是 null', () {
    ShelfTrial.setShelfOrder([('甲', novel), ('乙', novel), ('丙', novel)]);
    expect(ShelfTrial.positionOf('甲', novel), 0);
    expect(ShelfTrial.positionOf('乙', novel), 0.5);
    expect(ShelfTrial.positionOf('丙', novel), 1);
    expect(ShelfTrial.positionOf('丁', novel), isNull);

    ShelfTrial.setShelfOrder([('只有一本', novel)]);
    expect(ShelfTrial.positionOf('只有一本', novel), 0);
  });

  test('同名的小說與有聲書各有自己的位置，不在書架上的那一類不借位置', () {
    ShelfTrial.setShelfOrder([('詭秘之主', novel), ('其他', novel), ('詭秘之主', audio)]);
    expect(ShelfTrial.positionOf('詭秘之主', novel), 0);
    expect(ShelfTrial.positionOf('詭秘之主', audio), 1);
    expect(ShelfTrial.positionOf('詭秘之主', BookSourceKind.comic), isNull);
  });

  test('開 App 讀偏好時清掉上一次的書架順序', () async {
    ShelfTrial.setShelfOrder([('甲', novel)]);
    SharedPreferences.setMockInitialValues({
      ShelfTrial.mergedListKey: true,
      ShelfTrial.compactTabBarKey: true,
    });
    ShelfTrial.restore(await SharedPreferences.getInstance());
    expect(ShelfTrial.mergedList.value, isTrue);
    expect(ShelfTrial.compactTabBar.value, isTrue);
    expect(ShelfTrial.positionOf('甲', novel), isNull);
    ShelfTrial.mergedList.value = false;
  });

  test('列表併成一面時只有第一本上緣與最後一本下緣是圓角', () {
    const round = Radius.circular(AppGrouped.radius);
    expect(
      BookshelfListCard.mergedRadius(index: 0, count: 3),
      const BorderRadius.vertical(top: round),
    );
    expect(
      BookshelfListCard.mergedRadius(index: 1, count: 3),
      BorderRadius.zero,
    );
    expect(
      BookshelfListCard.mergedRadius(index: 2, count: 3),
      const BorderRadius.vertical(bottom: round),
    );
    expect(
      BookshelfListCard.mergedRadius(index: 0, count: 1),
      const BorderRadius.all(round),
    );
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(
            bottomNavigationBar: FloatingTabBar(
              currentIndex: 0,
              onTap: (_) {},
              onSearch: () {},
              items: const [
                FloatingTabItem(icon: Icons.book_outlined, label: '書架'),
                FloatingTabItem(icon: Icons.explore_outlined, label: '發現'),
                FloatingTabItem(icon: Icons.person_outline, label: '我的'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect searchRect(WidgetTester tester) =>
      tester.getRect(find.byIcon(Icons.search_rounded).first);

  testWidgets('分頁列置中時整組置中，收聽圓鈕對齊搜尋鈕', (tester) async {
    ShelfTrial.compactTabBar.value = true;
    await pumpBar(tester, width: 393);
    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(FloatingTabBar));
    expect(
      FloatingTabBar.barWidthOf(context, count: 3, search: true),
      72 * 3 + AppGlass.tabInnerInset * 2,
    );
    final right = FloatingTabBar.searchRightOf(context, tabCount: 3);
    // 搜尋圖示置中在搜尋鈕裡：鈕的右緣在圖示中心往右半個鈕寬。
    final searchRight =
        searchRect(tester).center.dx + AppGlass.tabBarHeight / 2;
    expect(393 - searchRight, moreOrLessEquals(right));
  });

  testWidgets('很窄的視窗放不下置中的分頁列時照切齊排，不溢出', (tester) async {
    ShelfTrial.compactTabBar.value = true;
    await pumpBar(tester, width: 300);
    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(FloatingTabBar));
    expect(FloatingTabBar.searchRightOf(context, tabCount: 3), 16);
    final searchRight =
        searchRect(tester).center.dx + AppGlass.tabBarHeight / 2;
    expect(300 - searchRight, moreOrLessEquals(16));
  });

  testWidgets('系統字級 200% 時分頁的圖示與字縮小放進 52 高的列，不溢出', (tester) async {
    await pumpBar(tester, width: 393, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
