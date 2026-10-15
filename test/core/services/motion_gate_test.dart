import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';

/// 動畫播放時背景工作要等（ADR 0018）。
void main() {
  final gate = MotionGate.instance;

  /// 進出場各 300ms 的頁面。
  Route<void> route(WidgetBuilder builder) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, _, _) => builder(context),
  );

  testWidgets('background work waits until every animation has stopped', (
    tester,
  ) async {
    final first = gate.hold();
    final second = gate.hold();
    var resumed = false;
    unawaited(gate.idle.then((_) => resumed = true));

    first();
    first(); // 重複放開只算一次。
    await tester.pump();
    expect(resumed, isFalse);

    second();
    // 同一幀裡又有動畫接上：不放行。
    final third = gate.hold();
    await tester.pump();
    expect(resumed, isFalse);

    third();
    await tester.pump();
    expect(resumed, isTrue);
    expect(gate.isMoving, isFalse);
  });

  testWidgets('page transitions hold the gate until they finish', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [MotionGateNavigatorObserver()],
        home: const Text('首頁'),
      ),
    );
    expect(gate.isMoving, isFalse);

    navigator.currentState!.push(route((_) => const Text('新頁')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(gate.isMoving, isTrue);
    await tester.pumpAndSettle();
    expect(gate.isMoving, isFalse);

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(gate.isMoving, isTrue);
    await tester.pumpAndSettle();
    await tester.pump();
    expect(gate.isMoving, isFalse);
  });

  testWidgets('a page loads only after its entrance has played', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('首頁')),
    );
    var entered = false;
    navigator.currentState!.push(
      route((context) {
        TransitionSettled.entered(context).then((_) => entered = true);
        return const Text('新頁');
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(entered, isFalse);
    await tester.pumpAndSettle();
    expect(entered, isTrue);
  });

  testWidgets('the page underneath waits until the page above has gone', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            home = context;
            return const Text('首頁');
          },
        ),
      ),
    );
    // 只有 MaterialPageRoute 之間會帶動底下那一頁（書架與閱讀器都是）。
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('新頁')),
    );
    await tester.pumpAndSettle();

    var uncovered = false;
    navigator.currentState!.pop();
    unawaited(TransitionSettled.uncovered(home).then((_) => uncovered = true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(uncovered, isFalse);
    await tester.pumpAndSettle();
    expect(uncovered, isTrue);
  });
}
