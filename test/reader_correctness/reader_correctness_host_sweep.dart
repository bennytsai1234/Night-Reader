import 'dart:convert';
import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import 'reader_correctness_case_generation.dart';

/// A bounded host logical sweep.  Every generated case is reset into a fresh
/// oracle session, then the same trace is observed by runtime, temporal, and
/// visual analyzers.  This is deliberately a host logical lane: it validates
/// the case generator and cross-oracle plumbing without pretending that a
/// synthetic raster is an Android screenshot. Real Flutter host probes and
/// C6's Android subset provide the complementary in-process/render evidence.
final class ReaderCorrectnessHostSweepResult {
  ReaderCorrectnessHostSweepResult({
    required this.seed,
    required this.caseCount,
    required this.layerCounts,
    required this.elapsedMicros,
    required this.totalFrames,
    required this.runtimeViolations,
    required this.temporalViolations,
    required this.visualViolations,
    required this.crossOracleViolations,
    required this.firstViolations,
    required this.visualFrames,
    required this.visualCapturedFrames,
    required this.visualCoverage,
  });

  final int seed;
  final int caseCount;
  final Map<String, int> layerCounts;
  final int elapsedMicros;
  final int totalFrames;
  final int runtimeViolations;
  final int temporalViolations;
  final int visualViolations;
  final int crossOracleViolations;
  final List<Map<String, Object?>> firstViolations;
  final int visualFrames;
  final int visualCapturedFrames;
  final double visualCoverage;

  int get allViolations =>
      runtimeViolations +
      temporalViolations +
      visualViolations +
      crossOracleViolations;

  Map<String, Object?> toJson() => <String, Object?>{
    'seed': seed,
    'caseCount': caseCount,
    'layerCounts': layerCounts,
    'elapsedMillis': elapsedMicros / 1000.0,
    'totalFrames': totalFrames,
    'runtimeViolations': runtimeViolations,
    'temporalViolations': temporalViolations,
    'visualViolations': visualViolations,
    'crossOracleViolations': crossOracleViolations,
    'firstViolations': firstViolations,
    'visualFrames': visualFrames,
    'visualCapturedFrames': visualCapturedFrames,
    'visualCoverage': visualCoverage,
    // Logical frames are observed by the visual analyzer but have no actual
    // RepaintBoundary capture. Keeping this explicit prevents C5 from being
    // misread as a screenshot or final-screen proof.
    'visualEvidenceBoundary': 'synthetic logical frame stream; actual raster coverage is supplied by C4 and C6',
  };
}

final class ReaderCorrectnessHostSweep {
  const ReaderCorrectnessHostSweep._();

  static ReaderCorrectnessHostSweepResult run(
    ReaderCorrectnessManifest manifest, {
    List<ReaderCorrectnessCase>? cases,
  }) {
    final selectedCases = cases ?? manifest.cases;
    final stopwatch = Stopwatch()..start();
    var totalFrames = 0;
    var runtimeViolations = 0;
    var temporalViolations = 0;
    var visualViolations = 0;
    var crossOracleViolations = 0;
    final firstViolations = <Map<String, Object?>>[];
    var visualFrames = 0;
    const visualCapturedFrames = 0;
    final layerCounts = <String, int>{};

    for (final item in selectedCases) {
      layerCounts.update(
        item.layer.wireName,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final trace = _LogicalReaderTrace(item);
      final temporalOracle = HybridTemporalOracle();
      final visualOracle = ReaderVisualOracle();
      HybridFrameInvariantRecord? previous;
      HybridFrameInvariantRecord? previousPrevious;
      for (final record in trace.records()) {
        totalFrames += 1;
        final directRuntime = evaluateHybridFrameInvariants(
          current: record,
          previous: previous,
          previousPrevious: previousPrevious,
        );
        final temporal = temporalOracle.observe(
          record,
          runtimeViolations: directRuntime,
        );
        final visualFrame = _visualFrameFor(record, previous);
        final visualRuntime = ReaderVisualRuntimeRecord(
          timestampMicros: record.timestampMicros,
          visibleKeys: record.visibleKeys,
          scrollPixels: record.scrollPixels,
          dominantVisibleChapter: record.dominantVisibleChapter,
          displayedProgressChapter: record.displayedProgressChapter,
          phase: record.phase,
          scrollActivity: record.scrollActivity,
          isScrolling: record.isScrolling,
          viewportHeight: record.viewportHeight ?? 952,
        );
        final visual = visualOracle.observe(
          visualFrame,
          runtime: visualRuntime,
        );

        for (final violation in directRuntime) {
          runtimeViolations += 1;
          _retainFirstViolation(firstViolations, item, violation.toJson());
        }
        for (final violation in temporal) {
          if (violation.invariant == 'TRANSIENT') {
            temporalViolations += 1;
          } else if (violation.oracle == 'temporal') {
            temporalViolations += 1;
          }
          _retainFirstViolation(firstViolations, item, violation.toJson());
        }
        for (final violation in visual) {
          if (violation.invariant == 'CROSS_ORACLE_MISMATCH') {
            crossOracleViolations += 1;
          } else {
            visualViolations += 1;
          }
          _retainFirstViolation(firstViolations, item, violation.toJson());
        }
        visualFrames += 1;
        previousPrevious = previous;
        previous = record;
      }
      final unfinishedVisual = visualOracle.finish();
      for (final violation in unfinishedVisual) {
        visualViolations += 1;
        _retainFirstViolation(firstViolations, item, violation.toJson());
      }
      // The new oracle instances above are the explicit case boundary reset.
      // No previous record, temporal episode, or visual frame crosses into the
      // next case, while operations inside one case share the trace state.
    }
    stopwatch.stop();
    return ReaderCorrectnessHostSweepResult(
      seed: manifest.seed,
      caseCount: selectedCases.length,
      layerCounts: Map<String, int>.unmodifiable(layerCounts),
      elapsedMicros: stopwatch.elapsedMicroseconds,
      totalFrames: totalFrames,
      runtimeViolations: runtimeViolations,
      temporalViolations: temporalViolations,
      visualViolations: visualViolations,
      crossOracleViolations: crossOracleViolations,
      firstViolations: List<Map<String, Object?>>.unmodifiable(firstViolations),
      visualFrames: visualFrames,
      visualCapturedFrames: visualCapturedFrames,
      visualCoverage: 0.0,
    );
  }

  static void _retainFirstViolation(
    List<Map<String, Object?>> output,
    ReaderCorrectnessCase item,
    Map<String, Object?> violation,
  ) {
    if (output.length >= 256) return;
    output.add(<String, Object?>{
      'caseId': item.id,
      'layer': item.layer.wireName,
      'position': item.positionLabel,
      'state': item.state.wireName,
      'violation': violation,
    });
  }
}

ReaderVisualFrame _visualFrameFor(
  HybridFrameInvariantRecord current,
  HybridFrameInvariantRecord? previous,
) {
  final currentPixels = current.scrollPixels;
  final previousPixels = previous?.scrollPixels;
  final delta = currentPixels != null && previousPixels != null
      ? currentPixels - previousPixels
      : null;
  // The logical stream uses a deliberately non-quiet, small motion sample.
  // This exercises visual/runtime pairing without manufacturing V9/V10/V11
  // from a model trace. Pixel identity is left empty because no actual raster
  // was captured in this lane.
  return ReaderVisualFrame.synthetic(
    sequence: current.timestampMicros,
    timestampMicros: current.timestampMicros,
    width: 160,
    height: 952,
    contentCoverage: 0.12,
    meanBrightness: 0.8,
    edgeDensity: 0.1,
    diffFromPrevious: 0.1,
    rowInkProfile: const <int>[1, 2, 1, 2, 1, 2, 1, 2],
    visualDy:
        current.scrollActivity == 'drag' ||
            current.scrollActivity == 'ballistic'
        ? (delta == null || delta == 0
              ? null
              : -delta.clamp(-40, 40).toDouble())
        : null,
  );
}

final class _LogicalReaderTrace {
  _LogicalReaderTrace(this.item);

  final ReaderCorrectnessCase item;
  final List<HybridFrameInvariantRecord> _records =
      <HybridFrameInvariantRecord>[];
  int _timestamp = 0;
  int _token = 1;
  int _epoch = 1;
  int _generation = 1;
  int _resetGeneration = 1;
  late int _chapter;
  late int _block;
  late double _pixels;

  List<HybridFrameInvariantRecord> records() {
    final anchor = ReaderCorrectnessFixture.generate().topologyAnchor(
      item.positionAnchor,
    );
    _chapter = anchor.chapterIndex;
    _block = anchor.paragraphIndex + 1;
    _pixels = _chapter * 400.0 + _block * 10.0;
    _enterInitialState();
    for (final operation in item.operations) {
      _apply(operation);
    }
    if (_records.isEmpty) _addReady();
    return _records;
  }

  void _enterInitialState() {
    switch (item.state) {
      case ReaderCaseState.ready:
        _addReady();
      case ReaderCaseState.dragging:
        _addDrag();
      case ReaderCaseState.ballisticEarly:
        _addDrag();
        _addBallistic(0.8);
      case ReaderCaseState.ballisticMiddle:
        _addDrag();
        _addBallistic(0.5);
      case ReaderCaseState.ballisticLate:
        _addDrag();
        _addBallistic(0.2);
      case ReaderCaseState.restoreOwnershipAcquired:
        _addRestoring(pending: true);
      case ReaderCaseState.restoring:
        _addRestoring(pending: true);
      case ReaderCaseState.layoutPending:
        _addNonReady(phase: 'layingOut', queue: 1);
      case ReaderCaseState.rebuilding:
        _epoch = 2;
        _generation = 2;
        _resetGeneration = 2;
        _addNonReady(phase: 'loading', queue: 1);
      case ReaderCaseState.anchorPending:
        _addRestoring(pending: true);
      case ReaderCaseState.settling:
        _addDrag();
        _addBallistic(0.2);
        _addReady();
      case ReaderCaseState.justBecameReady:
        _addNonReady(phase: 'layingOut', queue: 1);
        _addReady();
    }
  }

  void _apply(ReaderOperationDefinition operation) {
    if (operation.category == 'drag' ||
        operation.category == 'fling' ||
        operation.category == 'natural_cross_chapter') {
      _addDrag();
      _pixels = math.max(0.0, _pixels + _directionSign(operation) * 18.0);
      if (operation.category != 'drag' || operation.flingSpeed > 0) {
        _addBallistic(operation.flingSpeed > 0 ? 0.5 : 0.2);
      }
      _addReady();
      return;
    }
    if (operation.category == 'ballistic_interrupt') {
      _addDrag();
      final phase = switch (operation.interruptPhase) {
        'early' => 0.8,
        'middle' => 0.5,
        'tail' => 0.2,
        _ => 0.5,
      };
      _addBallistic(phase);
      _token += 1;
      _chapter = (_chapter + operation.chapterDelta).clamp(0, 120).toInt();
      _block = 1;
      _pixels = _chapter * 400.0 + 10.0;
      _addRestoring(pending: true);
      _addReady();
      return;
    }
    _token += 1;
    if (operation.id == 'navigation_jump_first') {
      _chapter = 0;
    } else if (operation.id == 'navigation_jump_last') {
      _chapter = 120;
    } else if (operation.id != 'navigation_jump_current') {
      _chapter = (_chapter + operation.chapterDelta).clamp(0, 120).toInt();
    }
    _block = 1;
    _pixels = _chapter * 400.0 + 10.0;
    _addRestoring(pending: true);
    _addReady();
  }

  double _directionSign(ReaderOperationDefinition operation) {
    return operation.direction == ReaderOperationDirection.backward ? 1 : -1;
  }

  void _addDrag() {
    _add(
      phase: 'ready',
      dragging: true,
      isScrolling: true,
      scrollActivity: 'drag',
      scrollVelocity: 0,
    );
  }

  void _addBallistic(double velocityFraction) {
    _add(
      phase: 'ready',
      isScrolling: true,
      scrollActivity: 'ballistic',
      scrollVelocity: 2800 * velocityFraction,
    );
  }

  void _addRestoring({required bool pending}) {
    _add(
      phase: 'restoring',
      restoreLocked: true,
      pumpQueueDepth: 1,
      scrollActivity: 'driven',
      pendingChapterJumpTarget: pending
          ? ReaderV2Location(chapterIndex: _chapter, charOffset: 0)
          : null,
    );
  }

  void _addNonReady({required String phase, required int queue}) {
    _add(
      phase: phase,
      restoreLocked: true,
      pumpQueueDepth: queue,
      scrollActivity: 'idle',
    );
  }

  void _addReady() {
    _add(phase: 'ready');
  }

  void _add({
    required String phase,
    bool dragging = false,
    bool isScrolling = false,
    bool restoreLocked = false,
    int pumpQueueDepth = 0,
    String scrollActivity = 'idle',
    double? scrollVelocity = 0,
    ReaderV2Location? pendingChapterJumpTarget,
  }) {
    _timestamp += 1;
    final key = BlockKey(chapterIndex: _chapter, blockIndex: _block);
    _records.add(
      HybridFrameInvariantRecord(
        timestampMicros: _timestamp,
        phase: phase,
        scrollOffset: _pixels,
        viewportHeight: 952,
        dragging: dragging,
        isScrolling: isScrolling,
        restoreLocked: restoreLocked,
        initialRestoreCompleted: true,
        pendingChapterJumpTarget: pendingChapterJumpTarget,
        epoch: _epoch,
        layoutGeneration: _generation,
        documentIndexRevision: _generation,
        resetGeneration: _resetGeneration,
        indexBindingResetGeneration: _resetGeneration,
        indexCenter: key,
        visibleKeys: <BlockKey>[key],
        visibleChapters: <int>[_chapter],
        missingParagraphCount: 0,
        unloadedChapterCount: 0,
        dominantVisibleChapter: _chapter,
        anchorVisibleChapter: _chapter,
        displayedProgressChapter: _chapter,
        pumpQueueDepth: pumpQueueDepth,
        scrollPixels: _pixels,
        minScrollExtent: 0,
        maxScrollExtent: 100000000,
        scrollActivity: scrollActivity,
        scrollVelocity: scrollVelocity,
        operationTokenId: _token,
        operationIsCurrent: true,
        chapterCount: 121,
        errorPresent: false,
      ),
    );
  }
}

String hostSweepSummaryLine(ReaderCorrectnessHostSweepResult result) =>
    jsonEncode(<String, Object?>{
      'seed': result.seed,
      'cases': result.caseCount,
      'layers': result.layerCounts,
      'frames': result.totalFrames,
      'runtime': result.runtimeViolations,
      'temporal': result.temporalViolations,
      'visual': result.visualViolations,
      'cross': result.crossOracleViolations,
      'elapsedMillis': result.elapsedMicros / 1000.0,
      'visualFrames': result.visualFrames,
      'visualCapturedFrames': result.visualCapturedFrames,
      'visualCoverage': result.visualCoverage,
    });
