import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';

void main() {
  Widget app({required GestureTapUpCallback onTapUp}) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderV2PointerTapLayer(
          onTapUp: onTapUp,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  testWidgets('primary tap tolerates movement within Flutter touch slop', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(app(onTapUp: (_) => taps += 1));

    final gesture = await tester.startGesture(const Offset(120, 220));
    await gesture.moveBy(Offset(kTouchSlop / 3, kTouchSlop / 4));
    await gesture.up();

    expect(taps, 1);
  });

  testWidgets('movement beyond Flutter touch slop is not a tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(app(onTapUp: (_) => taps += 1));

    final gesture = await tester.startGesture(const Offset(120, 220));
    await gesture.moveBy(const Offset(kTouchSlop + 1, 0));
    await gesture.up();

    expect(taps, 0);
  });

  testWidgets('second pointer cancels the tracked tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(onTapUp: (_) => taps += 1));

    final first = await tester.startGesture(const Offset(120, 220), pointer: 1);
    final second = await tester.startGesture(
      const Offset(180, 220),
      pointer: 2,
    );
    await second.up();
    await first.up();

    expect(taps, 0);
  });

  testWidgets('secondary mouse button does not trigger reading action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(app(onTapUp: (_) => taps += 1));

    final gesture = await tester.startGesture(
      const Offset(120, 220),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();

    expect(taps, 0);
  });
}
