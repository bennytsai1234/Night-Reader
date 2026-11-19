import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/skeleton/snapshot_sweep.dart';

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

  group('between taking the pictures, waiting and sweeping', () {
    final boundary = GlobalKey();
    var taps = 0;

    /// 400×100 的畫面，底下是 [color] 的一整片，數按下了幾次。
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller = SnapshotSweepController();
      color = Colors.black;
      taps = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: SnapshotSweep(
            controller: controller,
            child: StatefulBuilder(
              builder: (context, setState) {
                setColor = setState;
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => taps++,
                  child: ColoredBox(color: color),
                );
              },
            ),
          ),
        ),
      );
    }

    /// 螢幕上 [x] 那一欄的紅色（黑 0、白 255）。
    Future<int> redAt(WidgetTester tester, int x) async {
      final bytes = await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData();
        image.dispose();
        return data;
      });
      return bytes!.getUint8((50 * 400 + x) * 4);
    }

    /// [body] 裡建的圖，畫面拆掉後都要放掉。
    Future<void> expectNoImageLeft(
      WidgetTester tester,
      Future<void> Function() body,
    ) async {
      final open = <ui.Image>{};
      ui.Image.onCreate = open.add;
      ui.Image.onDispose = open.remove;
      addTearDown(() {
        ui.Image.onCreate = null;
        ui.Image.onDispose = null;
      });
      await body();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(open, isEmpty, reason: '拍下的圖都放掉了');
    }

    for (final viaPlay in [false, true]) {
      testWidgets('ending the round from the change right after the before '
          'picture (${viaPlay ? 'play' : 'capture'}) shows the real screen '
          'and lets go of the picture', (tester) async {
        await pumpScreen(tester);
        await expectNoImageLeft(tester, () async {
          var done = false;
          void change() {
            setColor(() => color = Colors.white);
            controller.finish();
          }

          final future = viaPlay
              ? controller.play(duration: duration, change: change)
              : controller.capture(change: change, restore: () {});
          unawaited(future.then((_) => done = true));
          for (var i = 0; i < 4; i++) {
            await tester.pump(frame);
          }
          expect(done, isTrue);
          expect(controller.captured, isFalse);
          expect(controller.playing, isFalse);
          await tester.tapAt(const Offset(200, 50));
          expect(taps, 1, reason: '真的畫面照常點得到');
          expect(await redAt(tester, 200), 255);
        });
      });
    }

    testWidgets('pictures taken first leave the real screen on and take '
        'taps; playing them then sweeps from the before to the after', (
      tester,
    ) async {
      await pumpScreen(tester);
      var captured = false;
      unawaited(
        controller
            .capture(
              change: () => setColor(() => color = Colors.white),
              restore: () => setColor(() => color = Colors.black),
            )
            .then((_) => captured = true),
      );
      expect(controller.captured, isFalse);
      for (var i = 0; i < 6 && !captured; i++) {
        await tester.pump(frame);
      }
      expect(captured, isTrue);
      expect(controller.captured, isTrue);
      expect(controller.playing, isFalse);
      expect(await redAt(tester, 200), 0, reason: '換回原本的樣子');
      await tester.tapAt(const Offset(200, 50));
      expect(taps, 1, reason: '拍好、還沒播時照常點得到');

      var done = false;
      unawaited(
        controller
            .play(
              duration: duration,
              change: () => setColor(() => color = Colors.white),
            )
            .then((_) => done = true),
      );
      expect(controller.playing, isTrue);
      expect(controller.captured, isFalse);
      await tester.pump(frame);
      await tester.pump(frame);
      expect(await redAt(tester, 200), 0, reason: '先是「之前」那張');
      await tester.pump(duration ~/ 2);
      expect(await redAt(tester, 5), greaterThan(200), reason: '左邊先換好');
      expect(await redAt(tester, 395), lessThan(50), reason: '右邊還沒換');
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(controller.playing, isFalse);
      expect(await redAt(tester, 200), 255, reason: '播完換回真的畫面');
    });

    testWidgets('while the before picture is being taken taps reach the '
        'screen; during the wait and the sweep a tap ends it and reaches the '
        'content', (tester) async {
      await pumpScreen(tester);
      var done = false;
      unawaited(
        controller
            .play(
              duration: duration,
              gap: gap,
              change: () => setColor(() => color = Colors.white),
            )
            .then((_) => done = true),
      );
      expect(controller.playing, isFalse, reason: '還在拍「之前」');
      await tester.tapAt(const Offset(200, 50));
      expect(taps, 1, reason: '拍「之前」時畫面照常');

      await tester.pump(frame);
      expect(controller.playing, isFalse, reason: '蓋著「之前」、拍「之後」');
      await tester.pump(frame);
      expect(controller.playing, isTrue, reason: '換上「之前」那張，等 gap');
      await tester.pump(frame);
      await tester.tapAt(const Offset(200, 50));
      expect(taps, 2, reason: '換場還沒開始也交給底下');
      await tester.pump();
      expect(done, isTrue, reason: '直接播完');
      expect(await redAt(tester, 200), 255);
    });

    testWidgets('finishing while the pictures are taken ends the capture; '
        'taking new pictures ends a sweep that is playing', (tester) async {
      await pumpScreen(tester);
      var captured = false;
      unawaited(
        controller
            .capture(
              change: () => setColor(() => color = Colors.white),
              restore: () => setColor(() => color = Colors.black),
            )
            .then((_) => captured = true),
      );
      await tester.pump(frame);
      controller.finish();
      await tester.pump();
      expect(captured, isTrue, reason: '拍到一半結束，等待也結束');
      expect(controller.captured, isFalse);
      for (var i = 0; i < 4; i++) {
        await tester.pump(frame);
      }
      expect(controller.captured, isFalse, reason: '之後不再拍好');

      var done = false;
      unawaited(
        controller
            .play(
              duration: duration,
              change: () => setColor(() => color = Colors.white),
            )
            .then((_) => done = true),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(frame);
      }
      expect(controller.playing, isTrue);
      unawaited(
        controller.capture(
          change: () => setColor(() => color = Colors.black),
          restore: () => setColor(() => color = Colors.white),
        ),
      );
      await tester.pump();
      expect(done, isTrue, reason: '換場被新的一輪蓋過就算播完');
      await tester.pumpAndSettle();
      expect(controller.captured, isTrue);
    });
  });
}
