// 書架列表檢視的書卡左滑出「檢查更新」「移出書架」；在書卡上橫拖一律滑出
// 動作、不換分頁，在書卡以外的地方橫拖照常換分頁（DESIGN.md「按壓回饋」）。
// 整個 App（記憶體資料庫）跑一次。

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

void main() {
  /// 手機上清單與 PageView 用裝置的觸控門檻（Android 約 8）。
  void useDeviceTouchSlop(WidgetTester tester) {
    tester.view.gestureSettings = ui.GestureSettings(
      physicalTouchSlop: 8 * tester.view.devicePixelRatio,
    );
  }

  /// 從 [start] 以每格 [step] 慢慢拖 [steps] 格。
  Future<void> slowDrag(
    WidgetTester tester,
    Offset start,
    Offset step,
    int steps,
  ) async {
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, const Duration(seconds: 1));
  }

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView).first).controller!.page!;

  for (final (name, step, steps) in [
    ('慢慢拖', const Offset(-3, 0), 40),
    ('快快拖', const Offset(-40, 0), 3),
  ]) {
    testWidgets('$name：在書卡上橫拖滑出動作，不換分頁', (tester) async {
      setUpPhone(tester);
      useDeviceTouchSlop(tester);
      await tester.runAsync(() async {
        await setUpApp(prefs: {'bookshelf_is_grid': false});
        await seedLibrary(withContent: false);
      });
      await pumpApp(tester);
      expect(find.text('移出書架'), findsNothing);

      await slowDrag(
        tester,
        tester.getCenter(find.text('夜雨聽書').first),
        step,
        steps,
      );
      expect(find.text('檢查更新'), findsOneWidget);
      expect(find.text('移出書架'), findsOneWidget);
      expect(page(tester), 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
    });
  }
}
