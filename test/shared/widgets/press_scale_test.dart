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

  testWidgets('a tap that pushes a page springs back once it is covered', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Center(
          child: PressScale(
            onTap: () {
              busy(const Duration(milliseconds: 40));
              navigator.currentState!.push(
                MaterialPageRoute<void>(builder: (_) => const SizedBox()),
              );
            },
            child: const SizedBox.square(dimension: 80),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    // 換頁中這一頁正被蓋住：停過預留停頓也不回彈，換頁的每一幀都不重畫它。
    await tester.pump(AppMotion.stillGap);
    await tester.pump();
    double scale() => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byType(PressScale, skipOffstage: false),
            matching: find.byType(AnimatedScale, skipOffstage: false),
          ),
        )
        .scale;
    expect(scale(), lessThan(1));

    await tester.pumpAndSettle();
    expect(scale(), 1, reason: '完全蓋住後才回彈');
  });

  testWidgets('pressing and springing back repaint only the button, not '
      'what holds it', (tester) async {
    var barPaints = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: CustomPaint(
            painter: _CountingPainter(() => barPaints++),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: PressScale(
                onTap: () {},
                child: const SizedBox.square(dimension: 80),
              ),
            ),
          ),
        ),
      ),
    );
    barPaints = 0;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
    expect(barPaints, 0, reason: '外面那一條在按壓與回彈的每一幀都不重畫');
  });
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}
