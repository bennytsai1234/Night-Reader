import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/snapshot_sweep.dart';

void main() {
  const frame = Duration(milliseconds: 16);
  const gap = Duration(milliseconds: 100);
  const duration = Duration(milliseconds: 600);

  late SnapshotSweepController controller;
  late StateSetter setColor;
  var color = Colors.black;

  Future<void> pumpHost(WidgetTester tester) async {
    controller = SnapshotSweepController();
    color = Colors.black;
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
  }

  testWidgets('settle runs once after the still picture is drawn, then the '
      'gap, then the sweep', (tester) async {
    await pumpHost(tester);
    var changed = false;
    var settles = 0;
    var changedWhenSettled = false;
    var done = false;
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

    // 第一格畫完拍「之前」、換掉底下。
    await tester.pump(frame);
    expect(changed, isTrue);
    // 第二格畫完拍「之後」、切成停住的圖。這一格裡別人先要過這一格的結束，
    // settle 也不能跟著提早。
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      unawaited(SchedulerBinding.instance.endOfFrame);
    });
    await tester.pump(frame);
    expect(settles, 0, reason: '停住的圖還沒畫');
    // 第三格畫出停住的圖，畫完才做。
    await tester.pump(frame);
    expect(settles, 1);
    expect(changedWhenSettled, isTrue);

    // gap 從 settle 之後才開始算，換場再播 duration。
    await tester.pump(gap - const Duration(milliseconds: 10));
    await tester.pump(duration);
    expect(done, isFalse, reason: '停滿 gap 才開始換場');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(settles, 1);
  });

  testWidgets('settle that ends the sweep finishes it; nothing starts later', (
    tester,
  ) async {
    await pumpHost(tester);
    var done = false;
    unawaited(
      controller
          .play(
            duration: duration,
            gap: const Duration(seconds: 10),
            change: () => setColor(() => color = Colors.white),
            settle: () => controller.finish(),
          )
          .then((_) => done = true),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(frame);
    }
    expect(done, isTrue);
    // 原本的 gap 過了也不會再開始換場。
    await tester.pump(const Duration(seconds: 11));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
