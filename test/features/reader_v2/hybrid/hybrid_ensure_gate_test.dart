import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_ensure_gate.dart';

void main() {
  test(
    'holds an ensure command until user scrolling is fully released',
    () async {
      final gate = HybridEnsureGate();
      var calls = 0;
      gate.beginUserScroll();

      final result = gate.submit(() async {
        calls += 1;
        return true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
      await gate.releaseAndFlush();

      expect(calls, 1);
      expect(await result, isTrue);
      gate.dispose();
    },
  );

  test('keeps only the newest deferred ensure target', () async {
    final gate = HybridEnsureGate();
    final calls = <int>[];
    gate.beginUserScroll();

    final first = gate.submit(() async {
      calls.add(1);
      return true;
    });
    final second = gate.submit(() async {
      calls.add(2);
      return true;
    });
    await gate.releaseAndFlush();

    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(calls, [2]);
    gate.dispose();
  });
}
