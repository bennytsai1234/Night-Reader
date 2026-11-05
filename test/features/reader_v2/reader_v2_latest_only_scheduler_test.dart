import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_latest_only_scheduler.dart';

void main() {
  testWidgets('sends only the newest value requested before the frame', (
    tester,
  ) async {
    final sent = <int>[];
    final scheduler = LatestOnlyScheduler<int>(
      isMounted: () => true,
      send: (value) async => sent.add(value),
    );

    scheduler.request(1);
    scheduler.request(2);
    scheduler.request(3);
    await tester.pump();

    expect(sent, [3]);
    expect(scheduler.requested, isNull);
  });

  testWidgets(
    'a request made while a send is in flight waits for it and then sends only the newest',
    (tester) async {
      final sent = <int>[];
      final sends = <Completer<void>>[];
      final settled = <(int, bool)>[];
      final scheduler = LatestOnlyScheduler<int>(
        isMounted: () => true,
        send: (value) {
          sent.add(value);
          final done = Completer<void>();
          sends.add(done);
          return done.future;
        },
        onSettled: (value, {required completed}) =>
            settled.add((value, completed)),
      );

      scheduler.request(1);
      await tester.pump();
      expect(sent, [1]);
      expect(scheduler.inFlight, 1);

      scheduler.request(2);
      scheduler.request(3);
      await tester.pump();
      await tester.pump();
      expect(sent, [1], reason: '送出中不另送，等送完再看一次。');
      expect(scheduler.requested, 3);

      sends[0].complete();
      await tester.pump();
      await tester.pump();
      expect(settled, [(1, true)]);
      expect(sent, [1, 3], reason: '送完後只送最新的 3，中間的 2 不送。');

      sends[1].complete();
      await tester.pump();
      expect(settled, [(1, true), (3, true)]);
      expect(scheduler.inFlight, isNull);
    },
  );

  testWidgets('quiet frames send only after a frame without a new request', (
    tester,
  ) async {
    final sent = <int>[];
    final scheduler = LatestOnlyScheduler<int>(
      isMounted: () => true,
      quietFrames: true,
      send: (value) async => sent.add(value),
    );

    scheduler.request(1);
    await tester.pump();
    expect(sent, isEmpty);

    scheduler.request(2);
    await tester.pump();
    expect(sent, isEmpty, reason: '這一幀還有新的 request，要再等一幀。');

    await tester.pump();
    expect(sent, [2]);
  });

  testWidgets(
    'gate is read at send time, so a value no longer wanted is dropped',
    (tester) async {
      final sent = <int>[];
      var wanted = true;
      final scheduler = LatestOnlyScheduler<int>(
        isMounted: () => true,
        gate: (_) => wanted,
        send: (value) async => sent.add(value),
      );

      scheduler.request(1);
      wanted = false;
      await tester.pump();
      expect(sent, isEmpty);
      expect(scheduler.requested, isNull);

      wanted = true;
      scheduler.request(2);
      await tester.pump();
      expect(sent, [2]);
    },
  );

  testWidgets('an unmounted scheduler neither sends nor keeps the request', (
    tester,
  ) async {
    final sent = <int>[];
    var mounted = false;
    final scheduler = LatestOnlyScheduler<int>(
      isMounted: () => mounted,
      send: (value) async => sent.add(value),
    );

    scheduler.request(1);
    await tester.pump();
    expect(sent, isEmpty);
    expect(scheduler.requested, isNull);

    mounted = true;
    scheduler.request(2);
    await tester.pump();
    expect(sent, [2]);
  });
}
