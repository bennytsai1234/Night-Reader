import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import '../../../reader_correctness/reader_correctness_case_generation.dart';
import '../../../reader_correctness/reader_correctness_host_sweep.dart';

void main() {
  test('C5 operation catalog has distinct transition definitions', () {
    final ids = readerCorrectnessOperationCatalog.map((item) => item.id);
    expect(readerCorrectnessOperationCatalog, hasLength(36));
    expect(ids.toSet(), hasLength(36));
    expect(
      readerCorrectnessOperationCatalog
          .map((item) => item.transition)
          .toSet()
          .length,
      greaterThan(8),
    );
    expect(
      readerCorrectnessOperationCatalog
          .where((item) => item.interruptPhase != null)
          .map((item) => item.interruptPhase)
          .toSet(),
      containsAll(<String>{'early', 'middle', 'tail'}),
    );
    expect(
      readerCorrectnessOperationCatalog.where(
        (item) => item.requiresUnloadedTarget,
      ),
      isNotEmpty,
    );
  });

  test('C5 manifest layers meet the declared finite coverage budget', () {
    final manifest = generateReaderCorrectnessManifest(seed: 9132051);
    expect(manifest.cases, hasLength(4308));
    expect(
      manifest.layerCounts,
      equals(<String, int>{
        'single_operation': 216,
        'ordered_pair': 1296,
        'boundary_topology': 360,
        'state_interruption': 432,
        'race_timing': 648,
        'three_way': 1296,
        'mixed_journey': 60,
      }),
    );
    expect(manifest.coverage.orderedPairCount, 1296);
    expect(manifest.coverage.threeWayOperationPairs['A_B'], 1296);
    expect(manifest.coverage.threeWayOperationPairs['B_C'], 1296);
    expect(manifest.coverage.threeWayOperationPairs['A_C'], 1296);
    expect(manifest.coverage.threeWayStatePositionPairs, 120);
    expect(manifest.coverage.threeWayOperationStatePairs, 432);
    expect(
      manifest.coverage.orderedPairReverseEvidence.single,
      containsPair('forwardPresent', 'true'),
    );
    expect(
      manifest.coverage.orderedPairReverseEvidence.single,
      containsPair('reversePresent', 'true'),
    );
    expect(
      manifest.cases
          .where((item) => item.layer == ReaderCaseLayer.orderedPair)
          .every((item) => item.resetBetweenOperations == false),
      isTrue,
    );
  });

  test('C5 same seed reproduces identical manifest bytes and hash', () {
    final first = generateReaderCorrectnessManifest(seed: 9132051);
    final second = generateReaderCorrectnessManifest(seed: 9132051);
    final different = generateReaderCorrectnessManifest(seed: 9132052);
    expect(first.canonicalJson, second.canonicalJson);
    expect(first.sha256, second.sha256);
    expect(first.sha256, isNot(different.sha256));
    expect(first.canonicalJson, contains('"caseId"'));
    expect(first.canonicalJson, contains('"resetBetweenOperations":false'));
  });

  test('C6 canonical manifest round-trips and rejects a changed case id', () {
    final original = generateReaderCorrectnessManifest(seed: 9132051);
    final decoded = ReaderCorrectnessManifest.fromJsonString(
      original.canonicalJson,
    );
    expect(decoded.seed, original.seed);
    expect(decoded.cases.length, original.cases.length);
    expect(decoded.cases.first.id, original.cases.first.id);
    expect(decoded.cases.last.id, original.cases.last.id);
    expect(decoded.coverage.layerCounts, original.coverage.layerCounts);

    final tampered = jsonDecode(original.canonicalJson) as Map<String, dynamic>;
    final cases = tampered['cases'] as List<dynamic>;
    (cases.first as Map<String, dynamic>)['caseId'] = 'tampered';
    expect(
      () => ReaderCorrectnessManifest.fromJson(
        Map<String, Object?>.from(tampered),
      ),
      throwsFormatException,
    );
  });

  test(
    'C6 Android subset selection is deterministic and covers every rule',
    () {
      final manifest = generateReaderCorrectnessManifest(seed: 9132051);
      final first = selectReaderCorrectnessAndroidSubset(manifest);
      final second = selectReaderCorrectnessAndroidSubset(manifest);
      expect(first.canonicalJson, second.canonicalJson);
      expect(first.sha256, second.sha256);
      expect(first.cases, isNotEmpty);
      expect(
        first.cases.where((item) => item.layer == ReaderCaseLayer.mixedJourney),
        hasLength(60),
      );
      expect(
        first.ruleCoverage.keys,
        containsAll(<String>[
          'operations',
          'positions',
          'states',
          'racePhases',
          'mixedJourneys',
          'hostFailures',
        ]),
      );
      expect(first.ruleCoverage['operations'], isNotEmpty);
      expect(first.ruleCoverage['positions'], isNotEmpty);
      expect(first.ruleCoverage['states'], isNotEmpty);
      expect(first.ruleCoverage['racePhases'], isNotEmpty);
      expect(first.ruleCoverage['mixedJourneys'], hasLength(60));
      expect(first.ruleCoverage['hostFailures'], isEmpty);
      expect(
        first.cases.where(
          (item) => item.layer == ReaderCaseLayer.singleOperation,
        ),
        hasLength(
          manifest.cases
              .where((item) => item.layer == ReaderCaseLayer.singleOperation)
              .length,
        ),
      );
      // S2's Android policy is intentionally hundreds-scale: retain the
      // finite single-operation matrix plus all mixed journeys, then add only
      // witnesses for uncovered state/race dimensions.
      expect(first.cases.length, greaterThanOrEqualTo(200));
      expect(first.cases.length, lessThanOrEqualTo(manifest.cases.length));

      final hostFailure = manifest.cases.first.id;
      final withFailure = selectReaderCorrectnessAndroidSubset(
        manifest,
        hostFailureCaseIds: <String>[hostFailure],
      );
      expect(withFailure.cases.map((item) => item.id), contains(hostFailure));
      expect(withFailure.hostFailureCaseIds, <String>[hostFailure]);
    },
  );

  test('C6 smoke lane 維度覆蓋與 acceptance 相同但不跑 mixed journey', () {
    for (final seed in <int>[9132051, 9132052]) {
      final manifest = generateReaderCorrectnessManifest(seed: seed);
      final acceptance = selectReaderCorrectnessAndroidSubset(
        manifest,
        lane: ReaderCorrectnessAndroidLane.acceptance,
      );
      final first = selectReaderCorrectnessAndroidSubset(
        manifest,
        lane: ReaderCorrectnessAndroidLane.smoke,
      );
      final second = selectReaderCorrectnessAndroidSubset(
        manifest,
        lane: ReaderCorrectnessAndroidLane.smoke,
      );

      expect(first.canonicalJson, second.canonicalJson);
      expect(first.sha256, second.sha256);

      // Smoke lane 存在的理由就是「同樣的維度覆蓋、少一個數量級的成本」。
      // 這四條斷言是那個理由本身；任何一條鬆掉，降級就失去正當性。
      for (final rule in <String>[
        'operations',
        'positions',
        'states',
        'racePhases',
      ]) {
        expect(
          first.ruleCoverage[rule],
          hasLength(acceptance.ruleCoverage[rule]!.length),
          reason: 'smoke lane 的 $rule 覆蓋必須與 acceptance 相同（seed $seed）',
        );
      }

      expect(
        first.cases.where((item) => item.layer == ReaderCaseLayer.mixedJourney),
        isEmpty,
        reason: 'mixed journey 是被刻意排除的成本來源',
      );
      expect(first.ruleCoverage['mixedJourneys'], isEmpty);

      // 每個 operation 恰好一個代表 single-operation case。
      final singles = first.cases
          .where((item) => item.layer == ReaderCaseLayer.singleOperation)
          .toList(growable: false);
      final representedOperations = <String>{
        for (final item in singles) ...item.operationIds,
      };
      expect(
        representedOperations,
        hasLength(readerCorrectnessOperationCatalog.length),
      );

      expect(
        first.cases.length,
        lessThan(acceptance.cases.length ~/ 4),
        reason: 'smoke lane 必須比 acceptance 小一個數量級才值得存在',
      );

      // acceptance lane 必須逐位元不變，否則既有 evidence 的 subset hash 失效。
      final acceptanceAgain = selectReaderCorrectnessAndroidSubset(
        manifest,
        lane: ReaderCorrectnessAndroidLane.acceptance,
      );
      expect(acceptanceAgain.sha256, acceptance.sha256);
      expect(acceptance.cases, hasLength(279));

      final hostFailure = manifest.cases.last.id;
      final smokeWithFailure = selectReaderCorrectnessAndroidSubset(
        manifest,
        lane: ReaderCorrectnessAndroidLane.smoke,
        hostFailureCaseIds: <String>[hostFailure],
      );
      expect(
        smokeWithFailure.cases.map((item) => item.id),
        contains(hostFailure),
        reason: 'host failure 在兩條 lane 都是硬納入',
      );
    }
  });

  test('C6 smoke lane 的 subset hash 在兩個 seed 上固定', () {
    // 釘住 hash 是為了讓 Android run 的輸入可以被第三方重現；改動選取政策
    // 本來就該讓這條紅，屆時連同 evidence 一起更新。
    const expected = <int, String>{
      9132051:
          '97310352a6713129177f4c0b24f4e59507d03849e3e8b085a7b117ec2f8cbf13',
      9132052:
          'be49a58e04af788a7d40375ba971c1e8382371858d63df00b7ed0b41569a7aeb',
    };
    for (final entry in expected.entries) {
      expect(
        selectReaderCorrectnessAndroidSubset(
          generateReaderCorrectnessManifest(seed: entry.key),
          lane: ReaderCorrectnessAndroidLane.smoke,
        ).sha256,
        entry.value,
        reason: 'seed ${entry.key}',
      );
    }
  });

  test('C5 state dimension names every C2 waitUntil entry condition', () {
    final report = generateReaderCorrectnessManifest(seed: 9132051).coverage;
    expect(
      report.stateEntryConditions.keys,
      containsAll(<String>[
        for (final state in ReaderCaseState.values) state.wireName,
      ]),
    );
    expect(
      report.stateEntryConditions,
      hasLength(ReaderCaseState.values.length),
    );
    for (final condition in report.stateEntryConditions.values) {
      expect(condition, isNotEmpty);
      expect(
        condition,
        anyOf(
          contains('phase'),
          contains('scrollActivity'),
          contains('operationTokenId'),
          contains('pumpQueueDepth'),
          contains('pendingChapterJumpTarget'),
        ),
      );
    }
  });

  test(
    'C5 fast lane runs a representative manifest subset through all oracles',
    () {
      final manifest = generateReaderCorrectnessManifest(seed: 9132051);
      final selected = <ReaderCorrectnessCase>[
        ...manifest.cases.where(
          (item) => item.layer == ReaderCaseLayer.singleOperation,
        ),
        ...manifest.cases
            .where((item) => item.layer == ReaderCaseLayer.boundaryTopology)
            .take(24),
      ];
      final stopwatch = Stopwatch()..start();
      final result = ReaderCorrectnessHostSweep.run(manifest, cases: selected);
      stopwatch.stop();
      debugPrint(
        'C5_FAST_LANE cases=${result.caseCount} '
        'layers=${result.layerCounts} '
        'frames=${result.totalFrames} '
        'runtime=${result.runtimeViolations} '
        'temporal=${result.temporalViolations} '
        'visual=${result.visualViolations} '
        'cross=${result.crossOracleViolations} '
        'visualCoverage=${result.visualCoverage} '
        'elapsedMillis=${stopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        'C5_FAST_LANE_FIRST_VIOLATIONS ${result.firstViolations.take(5)}',
      );
      expect(result.caseCount, 240);
      expect(result.allViolations, 0);
      expect(result.firstViolations, isEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 60)));
    },
  );
}
