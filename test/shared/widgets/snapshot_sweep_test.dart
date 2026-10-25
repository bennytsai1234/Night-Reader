import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/snapshot_sweep.dart';

void main() {
  testWidgets('settle runs once on the still picture, then the gap, then the '
      'sweep', (tester) async {
    final controller = SnapshotSweepController();
    var color = Colors.black;
    late StateSetter setColor;
    await tester.pumpWidget(
      MaterialApp(
        home: SnapshotSweep(
          controller: controller,
          child: StatefulBuilder(
            builder: (context, setState) {
              setColor = setState;
              return ColoredBox(color: color);
            },
          ),
        ),
      ),
    );

    var changed = false;
    var settles = 0;
    var changedWhenSettled = false;
    var done = false;
    const gap = Duration(milliseconds: 100);
    const duration = Duration(milliseconds: 600);
    unawaited(
      controller
          .play(
            duration: duration,
            gap: gap,
            change: () {
              changed = true;
              setColor(() => color = Colors.white);
            },
            settle: () {
              settles++;
              changedWhenSettled = changed;
            },
          )
          .then((_) => done = true),
    );

    // 拍「之前」、換掉、拍「之後」、停住的畫面畫完：一格一格推。
    for (var i = 0; i < 6 && settles == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(settles, 1, reason: '兩張都拍好、停住的畫面畫完後做一次');
    expect(changedWhenSettled, isTrue, reason: '做的時候底下已經換好');

    // gap 從 settle 之後才開始算，換場再播 duration。
    await tester.pump(gap - const Duration(milliseconds: 10));
    await tester.pump(duration);
    expect(done, isFalse, reason: '停滿 gap 才開始換場');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(settles, 1);
  });
}
