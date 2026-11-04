import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

void main() {
  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  Future<void> pumpButton(WidgetTester tester, VoidCallback onTap) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: PressScale(
              onTap: onTap,
              child: const SizedBox.square(dimension: 80),
            ),
          ),
        ),
      );

  /// 照實際時間忙一段，模擬點擊那一幀推入新頁的重工作。
  void busy(Duration duration) {
    final watch = Stopwatch()..start();
    while (watch.elapsed < duration) {}
  }

  testWidgets('a light tap springs back right after its frame', (tester) async {
    await pumpButton(tester, () {});
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    expect(scaleOf(tester), lessThan(1), reason: '按下縮小');

    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(scaleOf(tester), 1, reason: '點擊那一幀畫完就回彈');
  });

  testWidgets('a heavy tap holds the press until its work is done', (
    tester,
  ) async {
    // 點擊那一幀很重（例如推入閱讀器）：回彈不和它擠在一起。
    await pumpButton(tester, () => busy(const Duration(milliseconds: 40)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();

    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(scaleOf(tester), lessThan(1), reason: '重的那一幀與之後的停頓都停在按下的大小');

    await tester.pump(AppMotion.stillGap);
    await tester.pump();
    expect(scaleOf(tester), 1, reason: '停過預留停頓才回彈');
  });
}
