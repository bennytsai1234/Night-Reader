import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';

import 'reader_correctness_host_harness.dart';

const Size _visualTestViewport = Size(
  readerCorrectnessViewportWidth,
  readerCorrectnessViewportHeight,
);

List<BookChapter> _fixtureChapters() {
  final fixture = ReaderCorrectnessFixture.generate();
  return [
    for (final chapter in fixture.chapters)
      BookChapter(
        url: 'fixture://${chapter.index}',
        title: chapter.title,
        bookUrl: 'correctness://reader-v2',
        index: chapter.index,
        content: chapter.content,
      ),
  ];
}

Future<void> _allowVisualFutures(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 8));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 180)),
  );
}

Future<void> _pumpVisualFrames(WidgetTester tester, {int count = 80}) async {
  for (var i = 0; i < count; i += 1) {
    await tester.pump(const Duration(milliseconds: 8));
    if (i % 8 == 0) await _allowVisualFutures(tester);
  }
  await _allowVisualFutures(tester);
}

dynamic _screenState(WidgetTester tester) =>
    tester.state(find.byType(HybridReaderScreen).last);

void main() {
  setUp(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
    HybridReaderScreen.debugVisualOracleEnabled = true;
  });

  tearDown(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
    HybridReaderScreen.debugVisualOracleEnabled = false;
  });

  testWidgets(
    'C4 host representative run records coverage, cost, and profile matches',
    (tester) async {
      final stopwatch = Stopwatch()..start();
      final harness = ReaderCorrectnessHostHarness(
        tester,
        chapters: _fixtureChapters(),
      );
      addTearDown(harness.dispose);
      await tester.binding.setSurfaceSize(_visualTestViewport);
      await harness.mount();
      await harness.open();
      await harness.settle();
      harness.resetVisualOracle();
      await _pumpVisualFrames(tester, count: 320);
      await harness.drag(
        const Offset(0, -180),
        duration: const Duration(milliseconds: 240),
      );
      await harness.settle();
      await _pumpVisualFrames(tester, count: 80);
      stopwatch.stop();

      final state = _screenState(tester);
      final summary = Map<String, Object?>.from(
        state.debugVisualOracleSummary() as Map,
      );
      final frames = [
        for (final frame in (state.debugVisualOracleFrames() as List))
          Map<String, Object?>.from(frame as Map),
      ];
      final decodedFrames = frames
          .where((frame) => (frame['decodedProfiles'] as List).isNotEmpty)
          .length;
      debugPrint(
        'C4_HOST_CAPTURE totalFrames=${summary['totalFrames']} '
        'capturedFrames=${summary['capturedFrames']} '
        'droppedFrames=${summary['droppedFrames']} '
        'coverage=${summary['coverage']} '
        'analysisWidth=${summary['analysisWidth']} '
        'captureCostP50Micros=${summary['captureCostP50Micros']} '
        'captureCostP95Micros=${summary['captureCostP95Micros']} '
        'decodedFrames=$decodedFrames '
        'decodedProfiles=${summary['decodedProfiles']} '
        'matchingProfiles=${summary['matchingProfiles']} '
        'matchRate=${summary['matchRate']} '
        'elapsedMillis=${stopwatch.elapsedMilliseconds}',
      );
      expect(summary['totalFrames'], greaterThan(0));
      expect(summary['capturedFrames'], greaterThan(0));
      expect(summary['maxObservedInFlight'], lessThanOrEqualTo(2));
      expect(summary['analysisWidth'], 160);
      expect(summary['matchingProfiles'], summary['decodedProfiles']);
      if ((summary['decodedProfiles'] as int) > 0) {
        expect(summary['matchRate'], 1.0);
      }
      expect(summary['violations'], isEmpty);
    },
  );

  testWidgets('C4 visual oracle disabled path performs no frame captures', (
    tester,
  ) async {
    // setUp enables the oracle for the other C4 tests; explicitly override
    // it here to exercise the normal flag-off path in the same host
    // harness and finite workload shape.
    HybridReaderScreen.debugVisualOracleEnabled = false;
    final stopwatch = Stopwatch()..start();
    final harness = ReaderCorrectnessHostHarness(
      tester,
      chapters: _fixtureChapters(),
    );
    addTearDown(harness.dispose);
    await tester.binding.setSurfaceSize(_visualTestViewport);
    await harness.mount();
    await harness.open();
    await harness.settle();
    await _pumpVisualFrames(tester, count: 320);
    await harness.drag(
      const Offset(0, -180),
      duration: const Duration(milliseconds: 240),
    );
    await harness.settle();
    await _pumpVisualFrames(tester, count: 80);
    stopwatch.stop();

    final summary = Map<String, Object?>.from(
      (_screenState(tester).debugVisualOracleSummary() as Map),
    );
    debugPrint(
      'C4_HOST_CAPTURE_OFF totalFrames=${summary['totalFrames']} '
      'capturedFrames=${summary['capturedFrames']} '
      'droppedFrames=${summary['droppedFrames']} '
      'elapsedMillis=${stopwatch.elapsedMilliseconds}',
    );
    expect(summary['enabled'], isFalse);
    expect(summary['totalFrames'], 0);
    expect(summary['capturedFrames'], 0);
    expect(summary['droppedFrames'], 0);
  });

  testWidgets('C4 real Reader blank injection retains three raw frames', (
    tester,
  ) async {
    final harness = ReaderCorrectnessHostHarness(
      tester,
      chapters: _fixtureChapters(),
    );
    addTearDown(harness.dispose);
    await tester.binding.setSurfaceSize(_visualTestViewport);
    await harness.mount();
    await harness.open();
    await harness.settle();
    await _pumpVisualFrames(tester, count: 16);
    harness.resetVisualOracle();
    harness.stopVisualMotionForTesting();
    await _pumpVisualFrames(tester, count: 12);
    harness.setVisualInjection(ReaderVisualInjection.blankNextFrame);
    await _pumpVisualFrames(tester, count: 16);
    final state = _screenState(tester);
    final violations = [
      for (final violation in (state.debugVisualOracleViolations() as List))
        Map<String, Object?>.from(violation as Map),
    ];
    final blank = violations.firstWhere(
      (violation) => violation['invariant'] == 'V1',
      orElse: () => <String, Object?>{},
    );
    debugPrint('C4_HOST_INJECT_V1 ${blank.isEmpty ? violations : blank}');
    expect(blank, isNotEmpty);
    expect(blank['retainedRawFrames'], hasLength(3));
    expect(blank['evidence'], containsPair('recoveredOnNextFrame', true));
  });

  testWidgets('C4 real Reader visual motion while idle injects V19', (
    tester,
  ) async {
    final harness = ReaderCorrectnessHostHarness(
      tester,
      chapters: _fixtureChapters(),
    );
    addTearDown(harness.dispose);
    await tester.binding.setSurfaceSize(_visualTestViewport);
    await harness.mount();
    await harness.open();
    await harness.settle();
    await _pumpVisualFrames(tester, count: 16);
    harness.resetVisualOracle();
    harness.stopVisualMotionForTesting();
    await _pumpVisualFrames(tester, count: 12);
    _screenState(tester).debugVisualOracleViolations(clear: true);
    harness.setVisualInjection(ReaderVisualInjection.visualScrollWhileIdle);
    await _pumpVisualFrames(tester, count: 20);
    final state = _screenState(tester);
    final violations = [
      for (final violation in (state.debugVisualOracleViolations() as List))
        Map<String, Object?>.from(violation as Map),
    ];
    debugPrint('C4_HOST_INJECT_V19 $violations');
    expect(
      violations.map((violation) => violation['invariant']),
      contains('V19'),
    );
  });

  testWidgets('C4 real Reader cross injection reports high-priority mismatch', (
    tester,
  ) async {
    final harness = ReaderCorrectnessHostHarness(
      tester,
      chapters: _fixtureChapters(),
    );
    addTearDown(harness.dispose);
    await tester.binding.setSurfaceSize(_visualTestViewport);
    await harness.mount();
    await harness.open();
    await harness.settle();
    await _pumpVisualFrames(tester, count: 16);
    harness.resetVisualOracle();
    harness.stopVisualMotionForTesting();
    await _pumpVisualFrames(tester, count: 12);
    await _pumpVisualFrames(tester, count: 24);
    _screenState(tester).debugVisualOracleViolations(clear: true);
    harness.setVisualInjection(ReaderVisualInjection.crossOracleMismatch);
    await _pumpVisualFrames(tester, count: 12);
    final state = _screenState(tester);
    final frames = [
      for (final frame in (state.debugVisualOracleFrames() as List))
        Map<String, Object?>.from(frame as Map),
    ];
    final violations = [
      for (final violation in (state.debugVisualOracleViolations() as List))
        Map<String, Object?>.from(violation as Map),
    ];
    debugPrint(
      'C4_HOST_INJECT_CROSS decodedFrames=${frames.where((frame) => (frame['decodedProfiles'] as List).isNotEmpty).length} '
      'highPriority=${violations.where((violation) => violation['priority'] == 'high').toList()}',
    );
    final cross = violations.firstWhere(
      (violation) => violation['invariant'] == 'CROSS_ORACLE_MISMATCH',
      orElse: () => <String, Object?>{},
    );
    expect(cross, isNotEmpty);
    expect(cross['priority'], 'high');
    expect(cross['evidence'], containsPair('phaseToleranceFrames', 1));
  });
}
