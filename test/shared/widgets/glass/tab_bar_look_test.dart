import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/audiobook/audiobook_mini_button.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_style.dart';
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
      // 置中：三個 72 寬的分頁加兩側內距 4 × 2；撐滿：螢幕扣掉兩側 16、搜尋鈕和間距 8。
      expect(
        barWidth,
        look.isCentered ? 224 : 393 - 16 * 2 - look.searchSize - 8,
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

  /// 主頁的樣子：分頁列在底部，內容區（[Scaffold] 延伸到分頁列底下）裡
  /// 照收聽圓鈕與書架多選工具列的定位各放一塊，系統區 24。
  Future<void> pumpHome(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(
            extendBody: true,
            body: Builder(
              builder: (context) {
                final slot = FloatingTabBar.toolbarSlotOf(context);
                return Stack(
                  children: [
                    Positioned(
                      right: 16,
                      bottom: AudiobookMiniButton.bottomOf(context),
                      child: SizedBox.square(
                        key: const ValueKey('mini'),
                        dimension: AudiobookMiniButton.size,
                      ),
                    ),
                    Positioned(
                      left: slot.left,
                      right: slot.right,
                      bottom: slot.bottom,
                      child: BookshelfEditToolbar(
                        actions: [
                          for (final label in ['全選', '移動', '刪除'])
                            BookshelfToolbarAction(
                              icon: Icons.check_rounded,
                              label: label,
                              onPressed: () {},
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
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

  for (final look in TabBarLook.values) {
    testWidgets('${look.label}：手機底部有系統區時，收聽圓鈕疊在搜尋鈕上方空 10，'
        '多選工具列和分頁列在同一個位置', (tester) async {
      TabBarLook.current.value = look;
      await pumpHome(tester);
      final mini = tester.getRect(find.byKey(const ValueKey('mini')));
      expect(
        searchRect(tester).top - mini.bottom,
        moreOrLessEquals(AudiobookMiniButton.gap),
      );
      final toolbar = tester.getRect(find.byType(BookshelfEditToolbar));
      // 分頁列與搜尋鈕垂直置中在同一列：工具列對準搜尋鈕的中線就是對準分頁列。
      expect(toolbar.height, look.barHeight);
      expect(toolbar.center.dy, moreOrLessEquals(searchRect(tester).center.dy));
    });

    testWidgets('${look.label}：系統字級 200% 時多選工具列的圖示與字縮小放進去，不溢出', (tester) async {
      TabBarLook.current.value = look;
      await pumpHome(tester, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }

  test('還原舊備份：只有試用開關時換成對應的樣子，有新設定時照新設定', () {
    expect(TabBarLook.migrateBackup({'trial_compact_tab_bar': true, 'x': 1}), {
      PreferKey.tabBarLook: TabBarLook.centered.name,
      'x': 1,
    });
    expect(TabBarLook.migrateBackup({'trial_compact_tab_bar': false}), {
      PreferKey.tabBarLook: TabBarLook.full.name,
    });
    expect(
      TabBarLook.migrateBackup({
        'trial_compact_tab_bar': true,
        PreferKey.tabBarLook: TabBarLook.tall.name,
      }),
      {PreferKey.tabBarLook: TabBarLook.tall.name},
    );
    expect(TabBarLook.migrateBackup({'x': 1}), {'x': 1});
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
