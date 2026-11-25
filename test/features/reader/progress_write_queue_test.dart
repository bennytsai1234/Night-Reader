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

  testWidgets('slow writes during nonstop movement neither overlap nor pile '
      'up, and leaving writes the latest position', (tester) async {
    var inFlight = 0;
    var maxInFlight = 0;
    final saved = <int>[];
    final queue = ProgressWriteQueue<int>(
      write: (value) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        saved.add(value);
        inFlight--;
      },
    );
    // 每幀（16ms）一個新位置，連續十秒；每筆寫入要半秒。
    var value = 0;
    for (var frame = 0; frame < 625; frame++) {
      queue.schedule(value++);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(maxInFlight, 1);
    // 兩秒一次的定期寫入加上半秒的寫入時間：十秒內不超過五、六筆。
    expect(saved.length, inInclusiveRange(4, 6));
    expect(saved, orderedEquals([...saved]..sort()));
    final leaving = queue.flush();
    await tester.pump(const Duration(seconds: 2));
    await leaving;
    expect(saved.last, value - 1);
    expect(maxInFlight, 1);
  });
}
