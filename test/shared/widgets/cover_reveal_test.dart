import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';

void main() {
  testWidgets('slots under a waiting reveal are built one per frame, and '
      'the wait ends only after all of them are', (tester) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                CoverRevealSlot(
                  placeholder: const SizedBox(height: 10),
                  child: SizedBox(height: 10, child: Text('書$i')),
                ),
            ],
          ),
        ),
      ),
    );
    var settled = false;
    unawaited(
      reveal.settle().then((_) {
        settled = true;
      }),
    );

    expect(find.textContaining('書'), findsNothing, reason: '第一幀只佔位置');
    for (var built = 1; built <= 3; built++) {
      await tester.pump();
      expect(find.textContaining('書'), findsNWidgets(built));
      // 最後一張建好的那一幀畫完才結束等待（它的封面在這一幀登記）。
      if (built < 3) expect(reveal.waiting, isTrue);
    }
    await tester.pump();
    expect(settled, isTrue);
    expect(reveal.waiting, isFalse);
  });

  testWidgets('in steps, each frame either builds a slot, paints one, or '
      'shows one decoded cover, and the wait ends after the last of them', (
    tester,
  ) async {
    final reveal = CoverReveal(CoverWait.onDevice, inSteps: true);
    final painted = <int>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: Column(
            children: [
              for (var i = 0; i < 2; i++)
                CoverRevealSlot(
                  placeholder: const SizedBox(height: 10),
                  child: SizedBox(
                    height: 10,
                    child: CustomPaint(
                      key: ValueKey(i),
                      painter: _PaintLog(() => painted.add(i)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // 一張封面在這之後解碼好：排在兩張書卡的建與畫之後，換上之前換場等它。
    reveal.add('cover');
    var coverGranted = false;
    reveal.showCover(() {
      coverGranted = true;
      reveal.remove('cover');
    });
    var settled = false;
    unawaited(
      reveal.settle().then((_) {
        settled = true;
      }),
    );

    int built() => find
        .byType(CustomPaint)
        .evaluate()
        .where((element) => element.widget.key is ValueKey<int>)
        .length;

    // 每一格只走一步（放行在這一格畫完時，下一格才生效）：建第一張、畫
    // 第一張、建第二張、畫第二張；畫第二張的那一格畫完才輪到封面。
    final steps = [
      (built: 1, painted: <int>{}, cover: false),
      (built: 1, painted: {0}, cover: false),
      (built: 2, painted: {0}, cover: false),
      (built: 2, painted: {0, 1}, cover: true),
    ];
    for (final (i, step) in steps.indexed) {
      await tester.pump();
      expect(built(), step.built, reason: '第 ${i + 1} 格建好的書卡');
      expect(painted, step.painted, reason: '第 ${i + 1} 格畫過的書卡');
      expect(coverGranted, step.cover, reason: '第 ${i + 1} 格放行的封面');
      if (!step.cover) expect(settled, isFalse);
    }
    await tester.pump();
    expect(settled, isTrue);
  });

  testWidgets('when the stepped wait is replaced by another round, the old '
      'round steps nothing and a built card is painted by the new round', (
    tester,
  ) async {
    final a = CoverReveal(CoverWait.onDevice, inSteps: true);
    final b = CoverReveal(CoverWait.onDevice, inSteps: true);
    // 只記第一次建、第一次畫（旁邊的書卡建好時，已經畫過的會跟著重畫）。
    final seen = <String>{};
    final log = <String>[];
    void first(String event) {
      if (seen.add(event)) log.add(event);
    }

    Widget page(CoverReveal reveal) => Directionality(
      textDirection: TextDirection.ltr,
      child: CoverRevealScope(
        reveal: reveal,
        child: Column(
          children: [
            for (var i = 0; i < 2; i++)
              CoverRevealSlot(
                key: ValueKey(i),
                child: Builder(
                  builder: (_) {
                    first('build$i');
                    return SizedBox(
                      height: 10,
                      child: CustomPaint(
                        painter: _PaintLog(() => first('paint$i')),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(page(a));
    // 第一張在 a 已經放行、還沒建，就換成 b（書卡保留狀態）。
    await tester.pumpWidget(page(b));
    for (var i = 0; i < 8; i++) {
      log.clear();
      await tester.pump();
      expect(log.length, lessThanOrEqualTo(1), reason: '第 ${i + 1} 格只走一步：$log');
    }
    expect(seen, {'build0', 'paint0', 'build1', 'paint1'});
    var settled = false;
    unawaited(b.settle().then((_) => settled = true));
    await tester.pump();
    expect(settled, isTrue, reason: '兩張都由 b 建好、畫出來');
  });

  testWidgets('a single slot is still under the wait when it is built, so its '
      'cover holds the reveal', (tester) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    bool? waitingWhenBuilt;
    await tester.pumpWidget(
      CoverRevealScope(
        reveal: reveal,
        child: CoverRevealSlot(
          child: Builder(
            builder: (context) {
              // 像封面：建的時候還在等待中就登記，解碼好才拿掉。
              final waiting = CoverRevealScope.waitingOf(context);
              waitingWhenBuilt ??= waiting != null;
              waiting?.add('cover');
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    var settled = false;
    unawaited(
      reveal.settle().then((_) {
        settled = true;
      }),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(waitingWhenBuilt, isTrue);
    expect(settled, isFalse, reason: '封面還沒好，也還沒逾時');
    reveal.remove('cover');
    await tester.pump();
    expect(settled, isTrue);
  });

  testWidgets('a slot built after the wait ends is built right away', (
    tester,
  ) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    // settle 要等一幀畫完。
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(reveal.settle());
    await tester.pump();
    await tester.pump();
    expect(reveal.waiting, isFalse);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: const CoverRevealSlot(child: Text('書')),
        ),
      ),
    );
    expect(find.text('書'), findsOneWidget);
  });
}

/// 每畫一次就記一筆。
class _PaintLog extends CustomPainter {
  _PaintLog(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_PaintLog oldDelegate) => false;
}
