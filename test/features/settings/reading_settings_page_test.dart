// 閱讀偏好頁的建構範圍（ADR 0029）：換頁那幾格不重建頁面裡的控制項、
// 進場時只畫骨架、播完才一格建一組，改一個設定只重建那一列。原本這三件事
// 都不成立：推入第 1 格與返回第 0、1 格各重建約 48 個 Focus，第 0 格把整頁
// 的列都建好，按一下字號整頁的列都重建。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
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

  testWidgets('進場時只畫骨架，播完後一格建一列，都建好才換成內容', (tester) async {
    await pumpHost(tester);
    final sections = find.descendant(
      of: find.byType(ReadingSettingsPage, skipOffstage: false),
      matching: find.byType(GroupedSection, skipOffstage: false),
    );
    final skeleton = find.byType(SkeletonShapes, skipOffstage: false);
    // 已經建好的列：排隊的位置（[CoverRevealSlot]）底下不再是佔位的空白。
    int rowsBuilt() {
      var count = 0;
      for (final slot
          in find
              .descendant(
                of: find.byType(ReadingSettingsPage, skipOffstage: false),
                matching: find.byType(CoverRevealSlot, skipOffstage: false),
              )
              .evaluate()) {
        slot.visitChildren((child) {
          if (child.widget is! SizedBox) count++;
        });
      }
      return count;
    }

    await tester.tap(find.text('開啟'));
    // 推入的第一格：整個畫面的骨架是一個元件，一列都還沒建。
    await tester.pump();
    expect(sections, findsNothing);
    expect(skeleton, findsOneWidget);

    final route = ModalRoute.of(
      tester.element(find.byType(ReadingSettingsPage, skipOffstage: false)),
    )!;
    var built = 0;
    for (var frame = 1; skeleton.evaluate().isNotEmpty; frame++) {
      expect(frame, lessThan(300), reason: '骨架一直沒換掉');
      await tester.pump(const Duration(milliseconds: 16));
      final now = rowsBuilt();
      if (!route.animation!.isCompleted) {
        expect(sections, findsNothing, reason: '第 $frame 格還在換頁，不建內容');
      }
      expect(now - built, lessThanOrEqualTo(1), reason: '第 $frame 格建了好幾列');
      built = now;
    }
    expect(built, greaterThan(5));
    expect(sections, findsWidgets);

    await tester.pumpAndSettle();
    // 頁裡還有一個不能捲的清單，指定捲主清單；畫面外的組捲到才建。
    await tester.scrollUntilVisible(
      find.text('音量鍵翻頁'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(GroupedListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    // 每行字數的上限是畫面放得下的字數，跟著字號變（393 寬時 18 號放得下
    // 20 字、18.5 號 19 字），那一列跟著重建；上限沒變時不重建。
    expect(rebuilt.difference({'每行字數'}), {'字號'});
  });
}
