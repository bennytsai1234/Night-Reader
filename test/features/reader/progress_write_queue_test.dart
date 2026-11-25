import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/session/progress_write_queue.dart';

void main() {
  testWidgets('continuous movement cannot postpone a checkpoint forever', (
    tester,
  ) async {
    final saved = <int>[];
    final queue = ProgressWriteQueue<int>(
      write: (value) async {
        saved.add(value);
      },
    );
    for (var i = 0; i < 8; i++) {
      queue.schedule(i);
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(saved, [7]);
    queue.schedule(8);
    await tester.pump(const Duration(milliseconds: 400));
    expect(saved, [7, 8]);
  });

  test('flush awaits active and newer writes in order', () async {
    final gate = Completer<void>();
    final started = <int>[];
    final saved = <int>[];
    final queue = ProgressWriteQueue<int>(
      write: (value) async {
        started.add(value);
        if (value == 1) await gate.future;
        saved.add(value);
      },
    );
    final first = queue.saveImmediately(1);
    queue.schedule(2);
    var done = false;
    final flushing = queue.flush().then((_) => done = true);
    await pumpEventQueue();
    expect(started, [1]);
    expect(done, isFalse);
    gate.complete();
    await first;
    await flushing;
    expect(saved, [1, 2]);
  });

  test('failed writes remain pending for a later flush', () async {
    var fail = true;
    final saved = <int>[];
    final queue = ProgressWriteQueue<int>(
      write: (value) async {
        if (fail) throw StateError('write failed');
        saved.add(value);
      },
    );
    await expectLater(queue.saveImmediately(1), throwsStateError);
    fail = false;
    await queue.flush();
    expect(saved, [1]);
  });
}
