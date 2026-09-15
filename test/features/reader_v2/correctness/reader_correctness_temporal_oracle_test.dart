import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';

import 'reader_correctness_host_harness.dart';

const _center = BlockKey(chapterIndex: 0, blockIndex: 0);
const _next = BlockKey(chapterIndex: 0, blockIndex: 1);
const _far = BlockKey(chapterIndex: 0, blockIndex: 2);

HybridFrameInvariantRecord _record({
  int timestampMicros = 1,
  String phase = 'ready',
  double pixels = 0,
  bool dragging = false,
  bool isScrolling = false,
  bool restoreLocked = false,
  bool initialRestoreCompleted = true,
  int documentIndexRevision = 1,
  List<BlockKey> visibleKeys = const [_center],
  int? displayedProgressChapter = 0,
  int? dominantVisibleChapter = 0,
  int pumpQueueDepth = 0,
  String scrollActivity = 'idle',
  int? operationTokenId = 1,
  bool operationIsCurrent = true,
  String? phaseOverride,
}) {
  return HybridFrameInvariantRecord(
    timestampMicros: timestampMicros,
    phase: phaseOverride ?? phase,
    scrollOffset: pixels,
    viewportHeight: 1000,
    dragging: dragging,
    isScrolling: isScrolling,
    restoreLocked: restoreLocked,
    initialRestoreCompleted: initialRestoreCompleted,
    pendingChapterJumpTarget: null,
    epoch: 1,
    layoutGeneration: 1,
    documentIndexRevision: documentIndexRevision,
    resetGeneration: 1,
    indexBindingResetGeneration: 1,
    indexCenter: _center,
    visibleKeys: visibleKeys,
    visibleChapters: const [0],
    missingParagraphCount: 0,
    unloadedChapterCount: 0,
    dominantVisibleChapter: dominantVisibleChapter,
    displayedProgressChapter: displayedProgressChapter,
    pumpQueueDepth: pumpQueueDepth,
    scrollPixels: pixels,
    minScrollExtent: 0,
    maxScrollExtent: 100000,
    scrollActivity: scrollActivity,
    scrollVelocity: 0,
    operationTokenId: operationTokenId,
    operationIsCurrent: operationIsCurrent,
    chapterCount: 121,
    errorPresent: false,
  );
}

List<HybridFrameInvariantViolation> _feed(
  Iterable<HybridFrameInvariantRecord> records,
) {
  final oracle = HybridTemporalOracle();
  final violations = <HybridFrameInvariantViolation>[];
  for (final record in records) {
    violations.addAll(oracle.observe(record));
  }
  return violations;
}

Set<String> _ids(List<HybridFrameInvariantViolation> violations) =>
    violations.map((violation) => violation.invariant).toSet();

List<HybridFrameInvariantRecord> _records({
  required int count,
  double Function(int index)? pixels,
  List<BlockKey> Function(int index)? visibleKeys,
  int? Function(int index)? displayedProgressChapter,
  bool Function(int index)? restoreLocked,
  int Function(int index)? pumpQueueDepth,
  String Function(int index)? phase,
  int Function(int index)? documentIndexRevision,
}) {
  return [
    for (var i = 0; i < count; i += 1)
      _record(
        timestampMicros: i + 1,
        pixels: pixels?.call(i) ?? 0,
        visibleKeys: visibleKeys?.call(i) ?? const [_center],
        displayedProgressChapter: displayedProgressChapter?.call(i) ?? 0,
        restoreLocked: restoreLocked?.call(i) ?? false,
        pumpQueueDepth: pumpQueueDepth?.call(i) ?? 0,
        phaseOverride: phase?.call(i),
        documentIndexRevision: documentIndexRevision?.call(i) ?? 1,
      ),
  ];
}

void main() {
  group('C3 temporal oracle injection proofs', () {
    test('T1 positive: idle drift beyond the viewport-relative budget', () {
      final violations = _feed(_records(count: 8, pixels: (i) => i * 10.0));
      expect(_ids(violations), equals({'T1'}));
    });

    test('T1 negative: stable idle samples stay below the drift budget', () {
      final violations = _feed(_records(count: 8, pixels: (i) => i * 1.0));
      expect(_ids(violations), isEmpty);
    });

    test('T2 positive: four sub-viewport steps form a teleport', () {
      final violations = _feed(_records(count: 5, pixels: (i) => i * 300.0));
      expect(_ids(violations), equals({'T2'}));
    });

    test('T2 negative: four steps at exactly one viewport are accepted', () {
      final violations = _feed(_records(count: 5, pixels: (i) => i * 250.0));
      expect(_ids(violations), isEmpty);
    });

    test('T3 positive: three idle direction reversals close on the anchor', () {
      final positions = <double>[0, 10, 0, 10, 0, 10, 0];
      final violations = _feed(
        _records(count: positions.length, pixels: (i) => positions[i]),
      );
      expect(_ids(violations), equals({'T3'}));
    });

    test('T3 negative: user-like one-way idle movement has no oscillation', () {
      final violations = _feed(_records(count: 7, pixels: (i) => i * 10.0));
      expect(_ids(violations), isEmpty);
    });

    test(
      'T4 positive: a one-frame runtime violation is classified transient',
      () {
        final oracle = HybridTemporalOracle();
        final bad = _record(visibleKeys: const [_center, _far]);
        final runtime = evaluateHybridFrameInvariants(current: bad);
        expect(_ids(runtime), equals({'I1'}));
        final recovered = _record(timestampMicros: 2);
        final temporal = [
          ...oracle.observe(bad, runtimeViolations: runtime),
          ...oracle.observe(recovered),
        ];
        expect(_ids(runtime), contains('I1'));
        expect(_ids(temporal), equals({'TRANSIENT'}));
        expect(temporal.single.sourceInvariant, 'I1');
        expect(temporal.single.toJson()['sourceInvariant'], 'I1');
        debugPrint('C3_TRANSIENT_JSON ${jsonEncode(temporal.single.toJson())}');
      },
    );

    test('T4 negative: a three-frame runtime episode is not transient', () {
      final oracle = HybridTemporalOracle();
      final bad = _record(visibleKeys: const [_center, _far]);
      final runtime = evaluateHybridFrameInvariants(current: bad);
      oracle.observe(bad, runtimeViolations: runtime);
      final badAgain = _record(
        timestampMicros: 2,
        visibleKeys: const [_center, _far],
      );
      final runtimeAgain = evaluateHybridFrameInvariants(current: badAgain);
      oracle.observe(badAgain, runtimeViolations: runtimeAgain);
      final badThird = _record(
        timestampMicros: 3,
        visibleKeys: const [_center, _far],
      );
      final runtimeThird = evaluateHybridFrameInvariants(current: badThird);
      oracle.observe(badThird, runtimeViolations: runtimeThird);
      final result = oracle.observe(_record(timestampMicros: 4));
      expect(result, isEmpty);
    });

    test('T5 positive: 8,8,9,8,8 is an unowned wrong-chapter excursion', () {
      final chapters = <int>[8, 8, 9, 8, 8];
      final violations = _feed(
        _records(
          count: chapters.length,
          displayedProgressChapter: (i) => chapters[i],
        ),
      );
      expect(_ids(violations), equals({'T5'}));
    });

    test(
      'T5 negative: monotonic chapter progress does not return to its origin',
      () {
        final violations = _feed(
          _records(count: 5, displayedProgressChapter: (i) => 8 + i),
        );
        expect(_ids(violations), isEmpty);
      },
    );

    test(
      'T6 positive: a three-chapter progress jump is not explained by motion',
      () {
        final violations = _feed(
          _records(
            count: 2,
            pixels: (i) => i == 0 ? 0 : 10,
            displayedProgressChapter: (i) => i == 0 ? 8 : 11,
          ),
        );
        expect(_ids(violations), equals({'T6'}));
      },
    );

    test('T6 negative: one chapter over a partial viewport is continuous', () {
      final violations = _feed(
        _records(
          count: 2,
          pixels: (i) => i == 0 ? 0 : 600,
          displayedProgressChapter: (i) => i == 0 ? 8 : 9,
        ),
      );
      expect(_ids(violations), isEmpty);
    });

    test(
      'T7 positive: a key disappears and returns within a small displacement',
      () {
        final violations = _feed(
          _records(
            count: 3,
            pixels: (i) => i * 20.0,
            visibleKeys: (i) => i == 1 ? const [_next] : const [_center, _next],
          ),
        );
        expect(_ids(violations), equals({'T7'}));
      },
    );

    test(
      'T7 negative: a key leaving for a large paragraph-sized move is accepted',
      () {
        final violations = _feed(
          _records(
            count: 3,
            pixels: (i) => i == 0 ? 0 : 1100,
            visibleKeys: (i) => i == 1 ? const [_next] : const [_center, _next],
          ),
        );
        expect(_ids(violations), isEmpty);
      },
    );

    test('T8 positive: P3 restore starvation sequence remains observable', () {
      final violations = _feed(
        _records(
          count: 10,
          restoreLocked: (i) => i == 0,
          pumpQueueDepth: (i) => i == 0 ? 0 : 1,
          phase: (i) => i == 0 ? 'restoring' : 'ready',
        ),
      );
      expect(_ids(violations), equals({'T8'}));
      final evidence = violations.single.windowEvidence!;
      expect(evidence['startTimestampMicros'], 1);
      expect(evidence['endTimestampMicros'], 10);
      expect(evidence['pumpQueueDepth'], [0, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
    });

    test('T8 negative: queue drains at the bounded allowance', () {
      final violations = _feed(
        _records(
          count: 9,
          restoreLocked: (i) => i == 0,
          pumpQueueDepth: (i) => i == 0 ? 0 : 1,
          phase: (i) => i == 0 ? 'restoring' : 'ready',
        ),
      );
      expect(_ids(violations), isEmpty);
    });

    test('T9 positive: ready restore lock persists beyond the allowance', () {
      final violations = _feed(_records(count: 9, restoreLocked: (_) => true));
      expect(_ids(violations), equals({'T9'}));
    });

    test('T9 negative: restoring phase may hold the lock for eight frames', () {
      final violations = _feed(
        _records(
          count: 9,
          restoreLocked: (_) => true,
          phase: (_) => 'restoring',
        ),
      );
      expect(_ids(violations), isEmpty);
    });

    test(
      'T10 positive: stable viewport keys change without a navigation owner',
      () {
        final violations = _feed(
          _records(
            count: 9,
            visibleKeys: (i) => i < 8 ? const [_center, _next] : const [_far],
            documentIndexRevision: (i) => i < 8 ? 1 : 2,
          ),
        );
        expect(_ids(violations), equals({'T10'}));
      },
    );

    test(
      'T10 negative: background admission revision keeps the viewport intact',
      () {
        final violations = _feed(
          _records(count: 9, documentIndexRevision: (i) => i + 1),
        );
        expect(_ids(violations), isEmpty);
      },
    );

    test('temporal evidence JSON reconstructs timestamps and displacement sequence', () {
      final violation = _feed(_records(count: 8, pixels: (i) => i * 10.0))
          .single;
      final json = violation.toJson();
      expect(json['oracle'], 'temporal');
      final evidence = json['windowEvidence']! as Map<String, Object?>;
      expect(evidence['timestampsMicros'], [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(evidence['scrollPixels'], [0, 10, 20, 30, 40, 50, 60, 70]);
      expect(evidence['scrollDeltas'], [null, 10, 10, 10, 10, 10, 10, 10]);
      expect(evidence['records'], hasLength(8));
      debugPrint('C3_WINDOW_JSON ${jsonEncode(json)}');
    });
  });

  testWidgets(
    'C1 host drag fling jump has zero temporal violations and separated counts',
    (tester) async {
      HybridReaderScreen.debugFrameInvariantsEnabled = true;
      final fixture = ReaderCorrectnessFixture.generate();
      final chapters = [
        for (final chapter in fixture.chapters)
          BookChapter(
            url: 'fixture://${chapter.index}',
            title: chapter.title,
            bookUrl: 'correctness://reader-v2',
            index: chapter.index,
            content: chapter.content,
          ),
      ];
      final harness = ReaderCorrectnessHostHarness(tester, chapters: chapters);
      addTearDown(harness.dispose);

      await harness.mount();
      await harness.open();
      harness.resetFrameInvariantHistory();
      await harness.drag(
        const Offset(0, -240),
        duration: const Duration(milliseconds: 180),
      );
      await harness.settle();
      await harness.fling(
        const Offset(0, -620),
        duration: const Duration(milliseconds: 180),
      );
      await harness.settle();
      await harness.runtime.jumpToChapter(60);
      await harness.settle();

      final allViolations = harness.frameInvariantViolations();
      final temporalViolations = allViolations
          .where((violation) => violation['oracle'] == 'temporal')
          .toList();
      final state =
          tester.state(find.byType(HybridReaderScreen).last) as dynamic;
      final counts = Map<String, int>.from(
        state.debugFrameInvariantViolationCounts() as Map,
      );
      final temporalOnly =
          state.debugFrameInvariantViolations(oracle: 'temporal') as List;
      final runtimeOnly =
          state.debugFrameInvariantViolations(oracle: 'runtime') as List;
      final records = harness.frameInvariantRecords();
      final activities =
          records
              .map((record) => record['scrollActivity'])
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
      debugPrint(
        'C3_HOST_SAMPLE frames=${records.length} activities=$activities '
        'allViolations=${allViolations.length} '
        'temporalViolations=${temporalViolations.length} '
        'counts=$counts temporalOnly=${temporalOnly.length} '
        'runtimeOnly=${runtimeOnly.length}',
      );
      expect(activities, contains('idle'));
      expect(temporalViolations, isEmpty);
      expect(counts['temporal'], 0);
      expect(temporalOnly, isEmpty);
      expect(runtimeOnly, isEmpty);
    },
  );
}
