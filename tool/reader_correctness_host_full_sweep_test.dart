import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import '../test/reader_correctness/reader_correctness_case_generation.dart';
import '../test/reader_correctness/reader_correctness_host_sweep.dart';

void main() {
  test(
    'C5 independent finite full host sweep: two seeds and complete first list',
    () {
      const seeds = <int>[9132051, 9132052];
      final results = <ReaderCorrectnessHostSweepResult>[];
      for (final seed in seeds) {
        final manifest = generateReaderCorrectnessManifest(seed: seed);
        debugPrint(
          'C5_MANIFEST seed=$seed cases=${manifest.cases.length} '
          'sha256=${manifest.sha256} layers=${manifest.layerCounts}',
        );
        final result = ReaderCorrectnessHostSweep.run(manifest);
        results.add(result);
        debugPrint(
          'C5_FIRST_FULL_SWEEP seed=$seed '
          'violations=${result.firstViolations}',
        );
        debugPrint('C5_FULL_SWEEP ${hostSweepSummaryLine(result)}');
        expect(result.caseCount, 4308);
        expect(result.allViolations, 0);
        expect(result.runtimeViolations, 0);
        expect(result.temporalViolations, 0);
        expect(result.visualViolations, 0);
        expect(result.crossOracleViolations, 0);
        expect(result.firstViolations, isEmpty);
        expect(result.visualCapturedFrames, 0);
        expect(result.visualCoverage, 0.0);
      }
      expect(results[0].seed, isNot(results[1].seed));
      expect(
        generateReaderCorrectnessManifest(seed: seeds[0]).sha256,
        isNot(generateReaderCorrectnessManifest(seed: seeds[1]).sha256),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
