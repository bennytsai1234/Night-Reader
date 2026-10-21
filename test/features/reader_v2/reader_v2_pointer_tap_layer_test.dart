import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';

/// 正文的點擊層和正文的捲動用同一個觸控門檻：拖動一旦讓正文捲動，放開就
/// 不再算點擊（不翻頁、不開選單）。
void main() {
  late int taps;

  setUp(() => taps = 0);

  // 手機上捲動用裝置的觸控門檻（Android 約 8）；測試環境預設是 Flutter 的 18。
  void useDeviceTouchSlop(WidgetTester tester) {
    tester.view.gestureSettings = ui.GestureSettings(
      physicalTouchSlop: 8 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.reset);
  }

  late ScrollController scroll;

  Future<void> pumpPage(WidgetTester tester) async {
    scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2PointerTapLayer(
          onTapUp: (_) => taps++,
          // 和閱讀器一樣，正文上還有長按選字，捲動要越過觸控門檻才接手。
          child: GestureDetector(
            onLongPressStart: (_) {},
            child: ListView(
              controller: scroll,
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('第 $i 行')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> slowDrag(WidgetTester tester, Offset step, int steps) async {
    final gesture = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('拖一小段捲動了正文，放開不算點擊', (tester) async {
    useDeviceTouchSlop(tester);
    await pumpPage(tester);
    await slowDrag(tester, const Offset(0, -2), 7);
    expect(scroll.offset, greaterThan(0));
    expect(taps, 0);
  });

  testWidgets('按著時手指微動仍算點擊', (tester) async {
    useDeviceTouchSlop(tester);
    await pumpPage(tester);
    await slowDrag(tester, const Offset(0, -2), 3);
    expect(scroll.offset, 0);
    expect(taps, 1);
  });
}
