import 'dart:ui' show DartPerformanceMode;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/animation_latency.dart';

/// 一個由測試控制的動畫，包在 [AnimationLatency] 底下。
class _Host extends StatefulWidget {
  const _Host({required this.onController});

  final ValueChanged<AnimationController> onController;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    widget.onController(controller);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: controller,
    child: const SizedBox(width: 10, height: 10),
  );
}

DartPerformanceMode? _mode() =>
    SchedulerBinding.instance.debugGetRequestedPerformanceMode();

void main() {
  late AnimationController controller;

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    AnimationLatency(child: _Host(onController: (c) => controller = c)),
  );

  testWidgets('動畫在播時開著，畫面靜止一段時間才放開', (tester) async {
    await mount(tester);
    expect(_mode(), isNull);

    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_mode(), DartPerformanceMode.latency);

    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.isCompleted, isTrue);
    // 兩段動畫之間的預留停頓比 settle 短：還開著，下一段接著用。
    await tester.pump(const Duration(milliseconds: 100));
    expect(_mode(), DartPerformanceMode.latency);
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_mode(), DartPerformanceMode.latency);

    await tester.pump(AnimationLatency.settle * 2);
    expect(_mode(), isNull);
  });

  testWidgets('一直在播的動畫開滿 maxHold 就放開，靜止過才再開', (tester) async {
    await mount(tester);
    controller.repeat();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_mode(), DartPerformanceMode.latency);

    for (
      var t = Duration.zero;
      t <= AnimationLatency.maxHold;
      t += const Duration(milliseconds: 100)
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_mode(), isNull);
    // 還在播（一幀接一幀）：不再開。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_mode(), isNull);

    // 在幀外停掉、之後沒有再畫：照樣算靜止。
    controller.stop();
    await tester.pump(AnimationLatency.settle * 2);
    controller.forward(from: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_mode(), DartPerformanceMode.latency);
    controller.stop();
  });

  testWidgets('拆掉時放開', (tester) async {
    await mount(tester);
    controller.repeat();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_mode(), DartPerformanceMode.latency);

    await tester.pumpWidget(const SizedBox());
    expect(_mode(), isNull);
  });
}
