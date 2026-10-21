// 閱讀偏好頁的建構範圍（ADR 0029）：換頁那幾格不重建頁面裡的控制項、
// 進場第一格只建畫面上看得到的組、改一個設定只重建那一列。原本這三件事
// 都不成立：推入第 1 格與返回第 0、1 格各重建約 48 個 Focus，第 0 格把畫面
// 外的狀態列、頁首頁尾也建好，按一下字號整頁的列都重建。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });
  tearDown(GetIt.instance.reset);

  /// 手機大小的畫面，一個按鈕推入閱讀偏好（App 的換頁動畫）。
  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeSettingsProvider(),
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReadingSettingsPage(),
                    ),
                  ),
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool inPage(Element element) =>
      element.findAncestorWidgetOfExactType<ReadingSettingsPage>() != null;

  testWidgets('推入與返回時，頁面裡的控制項不跟著路由的焦點重建', (tester) async {
    await pumpHost(tester);
    // `builtOnce` 只在 debugPrintRebuildDirtyWidgets 開著時才會是 true，
    // 自己記：第二次經過的元素才是重建。
    final built = <Element>{};
    final rebuilt = <String>[];
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is Focus && inPage(element) && !built.add(element)) {
        rebuilt.add(element.widget.toStringShort());
      }
    };
    try {
      await tester.tap(find.text('開啟'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadingSettingsPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReadingSettingsPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ReadingSettingsPage), findsNothing);
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(rebuilt, isEmpty);
  });

  testWidgets('進場第一格只建畫面上看得到的組，畫面外的捲到才建', (tester) async {
    await pumpHost(tester);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    await tester.tap(find.text('開啟'));
    // 推入的第一格：頁面在 offstage 排好位置，還沒畫出來。
    await tester.pump();
    final sections = find.descendant(
      of: find.byType(ReadingSettingsPage, skipOffstage: false),
      matching: find.byType(GroupedSection, skipOffstage: false),
    );
    expect(sections, findsWidgets);
    for (final section in sections.evaluate()) {
      final top = (section.renderObject! as RenderBox)
          .localToGlobal(Offset.zero)
          .dy;
      expect(
        top,
        lessThan(screenHeight),
        reason: '${(section.widget as GroupedSection).header} 在畫面外',
      );
    }

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('音量鍵翻頁'), 300);
    expect(find.text('音量鍵翻頁'), findsOneWidget);
  });

  testWidgets('按一下字號，只重建字號那一列', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    // 每個重建的元件記在它所在的那一列（往上找）；不在任何一列裡的（清單
    // 的 keep-alive、組標題的「恢復預設」）不算。子元件換了新的 widget 也會
    // 經過這個回呼，整頁重建時每一列都會被記到。
    final rebuilt = <String>{};
    String? rowLabel(Widget widget) => switch (widget) {
      NumberStepperRow(:final label) => label,
      GroupedSwitchRow(:final title) => title,
      GroupedRow(:final title) => title,
      GlassSegmented() => 'GlassSegmented',
      _ => null,
    };
    // 頁面已經建好，這之後經過的都是重建。
    debugOnRebuildDirtyWidget = (element, _) {
      if (!inPage(element)) return;
      var label = rowLabel(element.widget);
      element.visitAncestorElements((ancestor) {
        label ??= rowLabel(ancestor.widget);
        return label == null;
      });
      if (label != null) rebuilt.add(label!);
    };
    try {
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      // 步進在 120ms 內沒有再按才提交給設定，提交後設定通知一次。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(find.text('18.5'), findsOneWidget);
    expect(rebuilt, {'字號'});
  });
}
