import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';

import 'reader_test_support.dart';

const Duration _visualTestTimeout = Duration(minutes: 5);
const int _visualFrameCount = 240;

Future<void> _pumpVisualFrames(
  WidgetTester tester, {
  int count = _visualFrameCount,
}) async {
  for (var index = 0; index < count; index += 1) {
    await tester.pump(const Duration(milliseconds: 8));
    // RepaintBoundary.toImage and toByteData complete outside the synchronous
    // widget-test pump. Give the bounded capture queue a small async window;
    // this is deliberately finite and does not turn the workload into a soak.
    if (index % 8 == 0) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('C4 Android visual oracle captures a bounded continuous Reader run', (
    tester,
  ) async {
    final startedAt = DateTime.now();
    // C4 is debug-only visual instrumentation.  Invariant hook remains off;
    // this test must not become a P2 performance measurement.
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
    HybridReaderScreen.debugVisualOracleEnabled = true;
    final harness = ReaderTestHarness(tester);
    try {
      await harness.startAndProvision();
      await harness.openBook();
      await harness.settleReaderForTesting('C4 Android initial');
      harness.resetVisualOracle();

      // One finite user-like action followed by a settled observation keeps
      // the visual run representative without reusing the long continuous
      // performance workload or any unbounded loop.
      await harness.runVsyncScrollForTesting(
        const Offset(0, -180),
        duration: const Duration(milliseconds: 240),
      );
      await harness.settleReaderForTesting('C4 Android scroll');
      final actionSummary = harness.debugVisualOracleSummary();
      final actionViolations = harness.debugVisualOracleViolations();

      // Start a fresh settled window after the finite action. This keeps
      // normal ballistic hand-off samples from being mistaken for the
      // required idle-drift negative proof, while retaining the action
      // summary above as evidence for the Android run.
      harness.resetVisualOracle();
      harness.stopVisualMotionForTesting();
      await _pumpVisualFrames(tester);

      final settledSummary = harness.debugVisualOracleSummary();
      final settledViolations = harness.debugVisualOracleViolations();
      final snapshot = harness.debugSnapshot();
      final elapsedMillis = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'C4_ANDROID_CAPTURE ${jsonEncode(<String, Object?>{
          'action': <String, Object?>{'totalFrames': actionSummary['totalFrames'], 'capturedFrames': actionSummary['capturedFrames'], 'droppedFrames': actionSummary['droppedFrames'], 'coverage': actionSummary['coverage'], 'sourceRaster': '${actionSummary['sourceRasterWidth']}x${actionSummary['sourceRasterHeight']}', 'captureCostP50Micros': actionSummary['captureCostP50Micros'], 'captureCostP95Micros': actionSummary['captureCostP95Micros'], 'violations': actionSummary['violations']},
          'settled': <String, Object?>{'totalFrames': settledSummary['totalFrames'], 'capturedFrames': settledSummary['capturedFrames'], 'droppedFrames': settledSummary['droppedFrames'], 'coverage': settledSummary['coverage'], 'analysisWidth': settledSummary['analysisWidth'], 'sourceRaster': '${settledSummary['sourceRasterWidth']}x${settledSummary['sourceRasterHeight']}', 'maxObservedInFlight': settledSummary['maxObservedInFlight'], 'captureErrorCount': settledSummary['captureErrorCount'], 'captureCostP50Micros': settledSummary['captureCostP50Micros'], 'captureCostP95Micros': settledSummary['captureCostP95Micros'], 'decodedProfiles': settledSummary['decodedProfiles'], 'matchingProfiles': settledSummary['matchingProfiles'], 'matchRate': settledSummary['matchRate'], 'violations': settledSummary['violations']},
          'displayRefreshRate': snapshot['displayRefreshRate'],
          'elapsedMillis': elapsedMillis,
        })}',
      );
      debugPrint('C4_ANDROID_BOUNDARY ${settledSummary['coverageBoundary']}');

      expect(settledSummary['enabled'], isTrue);
      expect(settledSummary['totalFrames'], greaterThan(0));
      expect(settledSummary['capturedFrames'], greaterThan(0));
      expect(settledSummary['maxObservedInFlight'], lessThanOrEqualTo(2));
      expect(settledSummary['analysisWidth'], 160);
      expect(settledSummary['captureErrorCount'], 0);
      expect(elapsedMillis, lessThan(300000));
      expect(
        settledViolations.where(
          (violation) => const <String>{
            'V7',
            'V9',
            'V10',
            'V11',
            'V12',
            'V17',
          }.contains(violation['invariant']),
        ),
        isEmpty,
      );
      debugPrint(
        'READER_E2E_RESULT status=passed fixture=$readerFixtureHostPath '
        'c4VisualOracle=true actionViolations=${actionViolations.length} '
        'settledViolations=${settledViolations.length} elapsedMillis=$elapsedMillis',
      );
    } finally {
      HybridReaderScreen.debugVisualOracleEnabled = false;
      HybridReaderScreen.debugFrameInvariantsEnabled = false;
    }
  }, timeout: const Timeout(_visualTestTimeout));
}
