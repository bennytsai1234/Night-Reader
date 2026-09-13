import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/startup/startup_retry_gate.dart';

void main() {
  test('rapid retry calls share one reset/start operation', () async {
    final gate = StartupRetryGate();
    final resetCompleter = Completer<void>();
    var resetCalls = 0;
    var startCalls = 0;

    Future<void> reset() async {
      resetCalls += 1;
      await resetCompleter.future;
    }

    Future<void> start() async {
      startCalls += 1;
    }

    final first = gate.run(reset: reset, start: start);
    final second = gate.run(reset: reset, start: start);
    final third = gate.run(reset: reset, start: start);

    expect(identical(first, second), isTrue);
    expect(identical(second, third), isTrue);
    expect(resetCalls, 1);
    expect(startCalls, 0);

    resetCompleter.complete();
    await Future.wait(<Future<void>>[first, second, third]);

    expect(resetCalls, 1);
    expect(startCalls, 1);

    await gate.run(reset: reset, start: start);
    expect(resetCalls, 2);
    expect(startCalls, 2);
  });

  test('a failed retry clears the gate for a later retry', () async {
    final gate = StartupRetryGate();
    var starts = 0;

    Future<void> reset() async {}

    Future<void> start() async {
      starts += 1;
      if (starts == 1) throw StateError('startup failed');
    }

    await expectLater(gate.run(reset: reset, start: start), throwsStateError);
    await gate.run(reset: reset, start: start);
    expect(starts, 2);
  });
}
