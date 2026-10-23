// 書架列表檢視的書卡沒有左滑動作（使用者 2026-10-23 決定）：在書卡上橫拖
// 是主畫面換分頁，不滑出「檢查更新」「移出書架」（DESIGN.md「按壓回饋」）。
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

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView).first).controller!.page!;

  for (final (name, step, steps) in [
    ('慢慢拖', const Offset(-3, 0), 40),
    ('快快拖', const Offset(-40, 0), 3),
  ]) {
    testWidgets('$name：在書卡上橫拖是換分頁，不滑出動作', (tester) async {
      setUpPhone(tester);
      useDeviceTouchSlop(tester);
      await tester.runAsync(() async {
        await setUpApp(prefs: {'bookshelf_is_grid': false});
        await seedLibrary(withContent: false);
      });
      await pumpApp(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('夜雨聽書').first),
      );
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(step);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(page(tester), greaterThan(0), reason: '分頁跟著手指移動');
      expect(find.text('檢查更新'), findsNothing);
      expect(find.text('移出書架'), findsNothing);
      await gesture.up();
      await settle(tester, const Duration(seconds: 1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
    });
  }
}
