import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/reader_test_support.dart';

Map<String, Object?> _snapshot({
  String phase = 'ready',
  double scrollPixels = 100,
  int queue = 1,
  int chapter = 3,
}) => <String, Object?>{
  'phase': phase,
  'operationTokenId': 7,
  'runtimeLocationRevision': 9,
  'layoutGeneration': 4,
  'epoch': 4,
  'scrollPixels': scrollPixels,
  'scrollOffset': scrollPixels,
  'pumpQueueDepth': queue,
  'enqueuedCount': 11,
  'isScrolling': true,
  'restoreLocked': false,
  'pendingChapterJumpTarget': null,
  'initialRestoreCompleted': true,
  'capturedLocation': <String, Object?>{
    'chapterIndex': chapter,
    'charOffset': 0,
  },
  'dominantVisibleChapter': chapter,
  'displayedProgressChapter': chapter,
};

void main() {
  test(
    'C6 readiness requires the mounted target and ready runtime together',
    () {
      final ready = _snapshot(queue: 0)..['isScrolling'] = false;

      expect(
        c6HybridScrollViewReadinessSatisfied(targetCount: 0, snapshot: ready),
        isFalse,
      );
      expect(
        c6HybridScrollViewReadinessSatisfied(targetCount: 1, snapshot: ready),
        isTrue,
      );
    },
  );

  test('C6 readiness tracker resets a transient frame before accepting two ready frames', () {
    final tracker = C6HybridScrollViewReadinessTracker();
    final ready = _snapshot(queue: 0)..['isScrolling'] = false;
    final notReady = <String, Object?>{...ready, 'phase': 'restoring'};

    expect(tracker.observe(targetCount: 1, snapshot: ready), isFalse);
    expect(tracker.observe(targetCount: 1, snapshot: notReady), isFalse);
    expect(tracker.observe(targetCount: 1, snapshot: ready), isFalse);
    expect(tracker.observe(targetCount: 1, snapshot: ready), isTrue);
  });

  testWidgets('pumpUntil evaluates deferred timeout reasons after polling', (
    tester,
  ) async {
    String? latest;
    await expectLater(
      pumpUntil(
        tester,
        () {
          latest = 'ready-after-poll';
          return false;
        },
        timeout: Duration.zero,
        reasonBuilder: () => 'latest=$latest',
      ),
      throwsA(
        isA<TestFailure>().having(
          (error) => error.toString(),
          'message',
          contains('latest=ready-after-poll'),
        ),
      ),
    );
  });

  test('C6 watchdog aborts only after all six dimensions are quiet', () {
    var now = DateTime(2026, 9, 14);
    final watchdog = ReaderSixDimensionWatchdog(
      limit: const Duration(seconds: 15),
      clock: () => now,
    );
    final snapshot = _snapshot();
    watchdog.observe(
      snapshot: snapshot,
      operationActive: true,
      operationState: 'dragging',
      visualDy: 4,
      invariantEvaluationCount: 1,
    );
    now = now.add(const Duration(seconds: 14, milliseconds: 999));
    watchdog.observe(
      snapshot: snapshot,
      operationActive: true,
      operationState: 'dragging',
      visualDy: 4,
      invariantEvaluationCount: 1,
    );
    now = now.add(const Duration(milliseconds: 1));
    expect(
      () => watchdog.observe(
        snapshot: snapshot,
        operationActive: true,
        operationState: 'dragging',
        visualDy: 4,
        invariantEvaluationCount: 1,
      ),
      throwsA(
        isA<ReaderSixDimensionWatchdogAbort>().having(
          (error) => error.evidence['dimensions'],
          'dimensions',
          allOf(
            containsPair('runtimeProgress', isA<Map>()),
            containsPair('viewportMovement', isA<Map>()),
            containsPair('renderedMovement', isA<Map>()),
            containsPair('operationState', isA<Map>()),
            containsPair('queueProgression', isA<Map>()),
            containsPair('chapterProgression', isA<Map>()),
          ),
        ),
      ),
    );
  });

  test('C6 watchdog resets on progress and permits legal idle/load quiet', () {
    var now = DateTime(2026, 9, 14);
    final watchdog = ReaderSixDimensionWatchdog(
      limit: const Duration(seconds: 15),
      clock: () => now,
    );
    final snapshot = _snapshot();
    watchdog.observe(
      snapshot: snapshot,
      operationActive: true,
      operationState: 'dragging',
      visualDy: 4,
    );
    now = now.add(const Duration(seconds: 10));
    watchdog.observe(
      snapshot: _snapshot(scrollPixels: 125),
      operationActive: true,
      operationState: 'dragging',
      visualDy: 6,
    );
    now = now.add(const Duration(seconds: 10));
    expect(
      () => watchdog.observe(
        snapshot: _snapshot(scrollPixels: 125),
        operationActive: true,
        operationState: 'dragging',
        visualDy: 6,
      ),
      returnsNormally,
    );

    now = now.add(const Duration(minutes: 5));
    expect(
      () => watchdog.observe(
        snapshot: _snapshot(queue: 0),
        operationActive: false,
        operationState: 'idle',
        visualDy: null,
      ),
      returnsNormally,
    );
    expect(
      () => watchdog.observe(
        snapshot: _snapshot(phase: 'loading'),
        operationActive: true,
        operationState: 'waiting-for-load',
        visualDy: null,
        waitingForLoad: true,
      ),
      returnsNormally,
    );
  });
}
