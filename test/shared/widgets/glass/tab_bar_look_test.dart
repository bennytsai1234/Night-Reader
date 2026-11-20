import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass/tab_bar_look.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => TabBarLook.current.value = TabBarLook.defaultLook);

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

  /// 搜尋鈕：搜尋圖示外面那個玻璃圓（和圖示同中心、直徑是鈕的大小）。
  Rect searchRect(WidgetTester tester) {
    final icon = tester.getRect(find.byIcon(Icons.search_rounded).first);
    final size = TabBarLook.current.value.searchSize;
    return Rect.fromCenter(center: icon.center, width: size, height: size);
  }

  for (final look in TabBarLook.values) {
    testWidgets('${look.label}：分頁列與搜尋鈕照這個樣子的大小畫，'
        '系統字級 200% 也不溢出', (tester) async {
      TabBarLook.current.value = look;
      await pumpBar(tester, width: 393);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(FloatingTabBar));
      final barWidth = FloatingTabBar.barWidthOf(
        context,
        count: 3,
        search: true,
      );
      expect(
        barWidth,
        look.isCentered
            ? TabBarLook.centeredTabWidth * 3 + AppGlass.tabInnerInset * 2
            : 393 - 16 * 2 - look.searchSize - AppGlass.tabBarGap,
      );
      final right = FloatingTabBar.searchRightOf(context, tabCount: 3);
      expect(393 - searchRect(tester).right, moreOrLessEquals(right));

      await pumpBar(tester, width: 393, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('很窄的視窗放不下置中的分頁列時照切齊排，不溢出', (tester) async {
    TabBarLook.current.value = TabBarLook.centeredLargeSearch;
    await pumpBar(tester, width: 300);
    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(FloatingTabBar));
    expect(FloatingTabBar.searchRightOf(context, tabCount: 3), 16);
    expect(300 - searchRect(tester).right, moreOrLessEquals(16));
  });

  group('從偏好設定讀', () {
    test('沒選過是撐滿；選過的照選的', () async {
      SharedPreferences.setMockInitialValues({});
      TabBarLook.restore(await SharedPreferences.getInstance());
      expect(TabBarLook.current.value, TabBarLook.full);

      SharedPreferences.setMockInitialValues({
        PreferKey.tabBarLook: TabBarLook.tall.name,
      });
      TabBarLook.restore(await SharedPreferences.getInstance());
      expect(TabBarLook.current.value, TabBarLook.tall);
    });

    test('之前開著試用的「分頁列置中」換成置中，試用的鍵刪掉', () async {
      SharedPreferences.setMockInitialValues({'trial_compact_tab_bar': true});
      final prefs = await SharedPreferences.getInstance();
      TabBarLook.restore(prefs);
      expect(TabBarLook.current.value, TabBarLook.centered);
      expect(prefs.getString(PreferKey.tabBarLook), TabBarLook.centered.name);
      expect(prefs.containsKey('trial_compact_tab_bar'), isFalse);
    });

    test('試用開關關著、或已經選過樣子時照選過的', () async {
      SharedPreferences.setMockInitialValues({
        'trial_compact_tab_bar': true,
        PreferKey.tabBarLook: TabBarLook.tall.name,
      });
      final prefs = await SharedPreferences.getInstance();
      TabBarLook.restore(prefs);
      expect(TabBarLook.current.value, TabBarLook.tall);
      expect(prefs.containsKey('trial_compact_tab_bar'), isFalse);
    });
  });
}
