import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/lifecycle_flush_gate.dart';

void main() {
  test('one foreground exit produces one persistence flush', () {
    final gate = LifecycleFlushGate();

    expect(gate.shouldFlush(AppLifecycleState.inactive), isTrue);
    expect(gate.shouldFlush(AppLifecycleState.hidden), isFalse);
    expect(gate.shouldFlush(AppLifecycleState.paused), isFalse);
    expect(gate.shouldFlush(AppLifecycleState.detached), isFalse);
  });

  test('resumed starts a new foreground lifecycle transaction', () {
    final gate = LifecycleFlushGate();

    expect(gate.shouldFlush(AppLifecycleState.inactive), isTrue);
    expect(gate.shouldFlush(AppLifecycleState.resumed), isFalse);
    expect(gate.shouldFlush(AppLifecycleState.inactive), isTrue);
  });

  test('paused or detached still flush when no inactive event was observed', () {
    final paused = LifecycleFlushGate();
    final detached = LifecycleFlushGate();

    expect(paused.shouldFlush(AppLifecycleState.paused), isTrue);
    expect(detached.shouldFlush(AppLifecycleState.detached), isTrue);
  });

  test('hidden alone does not change the existing flush contract', () {
    final gate = LifecycleFlushGate();

    expect(gate.shouldFlush(AppLifecycleState.hidden), isFalse);
    expect(gate.shouldFlush(AppLifecycleState.paused), isTrue);
  });
}
