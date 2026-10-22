import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness_bar.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import '../../support/app_harness.dart';
import '../../support/glass_motion.dart';
import '../../support/navigation_budget.dart';

void main() {
  testWidgets('拖動章內進度只更新拖動條與提示，玻璃選單和正文不重建', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);

    const centre = Offset(196, 420);
    await tester.tapAt(centre);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 128));
    expectNoGlassUnderFade(tester);
    await rest(tester);

    final slider = find.descendant(
      of: find.byType(ReaderV2BottomMenu),
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(slider);
    final before = tester.widget<Slider>(slider).value;
    final runtime = tester
        .widget<HybridReaderScreen>(find.byType(HybridReaderScreen))
        .runtime;
    final beforeLocation = runtime.state.visibleLocation;
    final content = (await tester.runAsync(
      () => runtime.loadContentAt(beforeLocation.chapterIndex),
    ))!;
    final targets = <ReaderV2Location>[];
    void captureTarget() {
      if (runtime.pendingLocation case final location?) targets.add(location);
    }

    runtime.addListener(captureTarget);
    addTearDown(() => runtime.removeListener(captureTarget));
    late double selected;
    final rebuilds = <Type, int>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final type = element.widget.runtimeType;
      rebuilds[type] = (rebuilds[type] ?? 0) + 1;
    };
    final gesture = await tester.startGesture(
      Offset(rect.left + 24, rect.center.dy),
    );
    try {
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(
        Offset(rect.center.dx, rect.center.dy),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(
        Offset(rect.left + rect.width * 0.75, rect.center.dy),
        timeStamp: const Duration(milliseconds: 32),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // Page 把重建排在幀後；多推一幀才能看見這一條無關的通知。
      await tester.pump(const Duration(milliseconds: 16));

      selected = tester.widget<Slider>(slider).value;
      expect(selected, greaterThan(before));
      expect(
        find.descendant(
          of: find.byType(ReaderV2BottomMenu),
          matching: find.text('本章 ${(selected / 10).round()}/10'),
        ),
        findsOneWidget,
      );
      expectNoGlassUnderFade(tester);
      for (final type in [
        ReaderV2Page,
        ReaderV2TopMenu,
        ReaderV2BottomMenu,
        ReaderV2BrightnessBar,
        HybridReaderScreen,
      ]) {
        expect(rebuilds[type] ?? 0, 0, reason: '拖動中的數值不應重建 $type');
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
      await gesture.up(timeStamp: const Duration(milliseconds: 64));
    }
    await settle(tester, const Duration(seconds: 3));
    expect(
      targets,
      contains(
        ReaderV2Location(
          chapterIndex: beforeLocation.chapterIndex,
          charOffset: (content.displayText.length * selected / 100).round(),
        ),
      ),
      reason: '放開後仍須把選定的章內位置交給閱讀器跳轉',
    );
    expect(runtime.stateMachine.currentOperation, isNull);
    expect(runtime.state.visibleLocation, isNot(beforeLocation));

    // 面板和上下玻璃同時進出時，模糊也必須持續取樣底下的正文。
    for (final label in ['排版', '朗讀', '替換規則']) {
      await tester.tap(
        label == '替換規則' ? find.byTooltip(label) : find.text(label),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 128));
      expectNoGlassUnderFade(tester);
      await rest(tester);
      await goBack(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 128));
      expectNoGlassUnderFade(tester);
      await rest(tester);
    }
    await tester.tapAt(centre);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 128));
    expectNoGlassUnderFade(tester);
    await tearDownApp(tester);
  });
}
