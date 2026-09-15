import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';

/// The state observations used by the C5 generator.  These names intentionally
/// describe observable C2 fields rather than private implementation classes.
enum ReaderCaseState {
  ready,
  dragging,
  ballisticEarly,
  ballisticMiddle,
  ballisticLate,
  restoreOwnershipAcquired,
  restoring,
  layoutPending,
  rebuilding,
  anchorPending,
  settling,
  justBecameReady,
}

extension ReaderCaseStateWireName on ReaderCaseState {
  String get wireName => switch (this) {
    ReaderCaseState.ready => 'ready',
    ReaderCaseState.dragging => 'dragging',
    ReaderCaseState.ballisticEarly => 'ballistic_early',
    ReaderCaseState.ballisticMiddle => 'ballistic_middle',
    ReaderCaseState.ballisticLate => 'ballistic_late',
    ReaderCaseState.restoreOwnershipAcquired => 'restore_ownership_acquired',
    ReaderCaseState.restoring => 'restoring',
    ReaderCaseState.layoutPending => 'layout_pending',
    ReaderCaseState.rebuilding => 'rebuilding',
    ReaderCaseState.anchorPending => 'anchor_pending',
    ReaderCaseState.settling => 'settling',
    ReaderCaseState.justBecameReady => 'just_became_ready',
  };
}

enum ReaderCaseLayer {
  singleOperation,
  orderedPair,
  boundaryTopology,
  stateInterruption,
  raceTiming,
  threeWay,
  mixedJourney,
}

extension ReaderCaseLayerWireName on ReaderCaseLayer {
  String get wireName => switch (this) {
    ReaderCaseLayer.singleOperation => 'single_operation',
    ReaderCaseLayer.orderedPair => 'ordered_pair',
    ReaderCaseLayer.boundaryTopology => 'boundary_topology',
    ReaderCaseLayer.stateInterruption => 'state_interruption',
    ReaderCaseLayer.raceTiming => 'race_timing',
    ReaderCaseLayer.threeWay => 'three_way',
    ReaderCaseLayer.mixedJourney => 'mixed_journey',
  };
}

enum ReaderOperationDirection { forward, backward, none }

extension ReaderOperationDirectionWireName on ReaderOperationDirection {
  String get wireName => switch (this) {
    ReaderOperationDirection.forward => 'forward',
    ReaderOperationDirection.backward => 'backward',
    ReaderOperationDirection.none => 'none',
  };
}

/// One atomic Reader state transition.  The fields are deliberately data-only
/// so host manifest generation and Android subset selection do not depend on a
/// WidgetTester or on wall-clock timing.
final class ReaderOperationDefinition {
  const ReaderOperationDefinition({
    required this.id,
    required this.category,
    required this.direction,
    required this.transition,
    this.distancePx = 0,
    this.durationMillis = 0,
    this.flingSpeed = 0,
    this.chapterDelta = 0,
    this.interruptPhase,
    this.requiresUnloadedTarget = false,
  });

  final String id;
  final String category;
  final ReaderOperationDirection direction;
  final String transition;
  final double distancePx;
  final int durationMillis;
  final double flingSpeed;
  final int chapterDelta;
  final String? interruptPhase;
  final bool requiresUnloadedTarget;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'category': category,
    'direction': direction.wireName,
    'transition': transition,
    'distancePx': distancePx,
    'durationMillis': durationMillis,
    'flingSpeed': flingSpeed,
    'chapterDelta': chapterDelta,
    'interruptPhase': interruptPhase,
    'requiresUnloadedTarget': requiresUnloadedTarget,
  };
}

/// Thirty-six operations are intentionally distinct state transitions.  For
/// example, a slow drag and a short drag are different because their activity
/// and admission windows have different lifetimes; changing only a numeric
/// argument would not create a new entry here.
const List<ReaderOperationDefinition> readerCorrectnessOperationCatalog =
    <ReaderOperationDefinition>[
      ReaderOperationDefinition(
        id: 'drag_forward_micro',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 64,
        durationMillis: 220,
        transition: 'drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_forward_short',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 180,
        durationMillis: 240,
        transition: 'drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_forward_long',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 620,
        durationMillis: 320,
        transition: 'drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_backward_micro',
        category: 'drag',
        direction: ReaderOperationDirection.backward,
        distancePx: 64,
        durationMillis: 220,
        transition: 'drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_backward_short',
        category: 'drag',
        direction: ReaderOperationDirection.backward,
        distancePx: 180,
        durationMillis: 240,
        transition: 'drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_backward_long',
        category: 'drag',
        direction: ReaderOperationDirection.backward,
        distancePx: 620,
        durationMillis: 320,
        transition: 'drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_forward_slow',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 260,
        durationMillis: 520,
        transition: 'long_drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_backward_slow',
        category: 'drag',
        direction: ReaderOperationDirection.backward,
        distancePx: 260,
        durationMillis: 520,
        transition: 'long_drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_forward_fast',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 420,
        durationMillis: 90,
        transition: 'fast_drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_backward_fast',
        category: 'drag',
        direction: ReaderOperationDirection.backward,
        distancePx: 420,
        durationMillis: 90,
        transition: 'fast_drag→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_reverse_mid',
        category: 'drag',
        direction: ReaderOperationDirection.none,
        distancePx: 220,
        durationMillis: 360,
        transition: 'drag_forward→direction_change→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_release_immediate',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 120,
        durationMillis: 80,
        transition: 'drag→immediate_release→settle',
      ),
      ReaderOperationDefinition(
        id: 'drag_pause_then_release',
        category: 'drag',
        direction: ReaderOperationDirection.forward,
        distancePx: 240,
        durationMillis: 420,
        transition: 'drag→waitUntil(dragging)→pause→release→settle',
      ),
      ReaderOperationDefinition(
        id: 'fling_forward_low',
        category: 'fling',
        direction: ReaderOperationDirection.forward,
        distancePx: 560,
        durationMillis: 180,
        flingSpeed: 900,
        transition: 'drag→ballistic→idle',
      ),
      ReaderOperationDefinition(
        id: 'fling_forward_medium',
        category: 'fling',
        direction: ReaderOperationDirection.forward,
        distancePx: 820,
        durationMillis: 180,
        flingSpeed: 1800,
        transition: 'drag→ballistic→idle',
      ),
      ReaderOperationDefinition(
        id: 'fling_forward_high',
        category: 'fling',
        direction: ReaderOperationDirection.forward,
        distancePx: 1100,
        durationMillis: 180,
        flingSpeed: 3200,
        transition: 'drag→ballistic→idle',
      ),
      ReaderOperationDefinition(
        id: 'fling_backward_low',
        category: 'fling',
        direction: ReaderOperationDirection.backward,
        distancePx: 560,
        durationMillis: 180,
        flingSpeed: 900,
        transition: 'drag→ballistic→idle',
      ),
      ReaderOperationDefinition(
        id: 'fling_backward_medium',
        category: 'fling',
        direction: ReaderOperationDirection.backward,
        distancePx: 820,
        durationMillis: 180,
        flingSpeed: 1800,
        transition: 'drag→ballistic→idle',
      ),
      ReaderOperationDefinition(
        id: 'fling_backward_high',
        category: 'fling',
        direction: ReaderOperationDirection.backward,
        distancePx: 1100,
        durationMillis: 180,
        flingSpeed: 3200,
        transition: 'drag→ballistic→idle',
      ),
      ReaderOperationDefinition(
        id: 'ballistic_interrupt_early',
        category: 'ballistic_interrupt',
        direction: ReaderOperationDirection.forward,
        distancePx: 900,
        durationMillis: 180,
        flingSpeed: 2800,
        interruptPhase: 'early',
        chapterDelta: 3,
        transition: 'drag→ballistic(v≥0.66v0)→explicit_jump',
      ),
      ReaderOperationDefinition(
        id: 'ballistic_interrupt_middle',
        category: 'ballistic_interrupt',
        direction: ReaderOperationDirection.forward,
        distancePx: 900,
        durationMillis: 180,
        flingSpeed: 2800,
        interruptPhase: 'middle',
        chapterDelta: 3,
        transition: 'drag→ballistic(0.33v0≤v<0.66v0)→explicit_jump',
      ),
      ReaderOperationDefinition(
        id: 'ballistic_interrupt_tail',
        category: 'ballistic_interrupt',
        direction: ReaderOperationDirection.forward,
        distancePx: 900,
        durationMillis: 180,
        flingSpeed: 2800,
        interruptPhase: 'tail',
        chapterDelta: 3,
        transition: 'drag→ballistic(v<0.33v0)→explicit_jump',
      ),
      ReaderOperationDefinition(
        id: 'natural_forward_slow_cross',
        category: 'natural_cross_chapter',
        direction: ReaderOperationDirection.forward,
        distancePx: 1200,
        durationMillis: 680,
        transition: 'slow_drag→natural_cross_chapter→settle',
      ),
      ReaderOperationDefinition(
        id: 'natural_forward_fling_cross',
        category: 'natural_cross_chapter',
        direction: ReaderOperationDirection.forward,
        distancePx: 1400,
        durationMillis: 180,
        flingSpeed: 3000,
        transition: 'fling→natural_cross_chapter→settle',
      ),
      ReaderOperationDefinition(
        id: 'natural_backward_slow_cross',
        category: 'natural_cross_chapter',
        direction: ReaderOperationDirection.backward,
        distancePx: 1200,
        durationMillis: 680,
        transition: 'slow_drag→natural_cross_chapter→settle',
      ),
      ReaderOperationDefinition(
        id: 'natural_backward_fling_cross',
        category: 'natural_cross_chapter',
        direction: ReaderOperationDirection.backward,
        distancePx: 1400,
        durationMillis: 180,
        flingSpeed: 3000,
        transition: 'fling→natural_cross_chapter→settle',
      ),
      ReaderOperationDefinition(
        id: 'navigation_next',
        category: 'navigation',
        direction: ReaderOperationDirection.forward,
        chapterDelta: 1,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_previous',
        category: 'navigation',
        direction: ReaderOperationDirection.backward,
        chapterDelta: -1,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_forward_n',
        category: 'navigation',
        direction: ReaderOperationDirection.forward,
        chapterDelta: 3,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_backward_n',
        category: 'navigation',
        direction: ReaderOperationDirection.backward,
        chapterDelta: -3,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_jump_first',
        category: 'navigation',
        direction: ReaderOperationDirection.backward,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_jump_last',
        category: 'navigation',
        direction: ReaderOperationDirection.forward,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_jump_current',
        category: 'navigation',
        direction: ReaderOperationDirection.none,
        transition: 'ready→restore_owner→restoring→ready(same location)',
      ),
      ReaderOperationDefinition(
        id: 'navigation_jump_loaded_target',
        category: 'navigation',
        direction: ReaderOperationDirection.forward,
        chapterDelta: 7,
        transition: 'ready→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_jump_unloaded_target',
        category: 'navigation',
        direction: ReaderOperationDirection.forward,
        chapterDelta: 37,
        requiresUnloadedTarget: true,
        transition: 'ready→admit_target→restore_owner→restoring→ready',
      ),
      ReaderOperationDefinition(
        id: 'navigation_far_location',
        category: 'navigation',
        direction: ReaderOperationDirection.forward,
        chapterDelta: 60,
        requiresUnloadedTarget: true,
        transition: 'ready→admit_far_target→restore_owner→restoring→ready',
      ),
    ];

final Map<String, ReaderOperationDefinition> readerCorrectnessOperationById =
    <String, ReaderOperationDefinition>{
      for (final operation in readerCorrectnessOperationCatalog)
        operation.id: operation,
    };

final class ReaderCorrectnessCase {
  const ReaderCorrectnessCase({
    required this.ordinal,
    required this.layer,
    required this.operationIds,
    required this.positionAnchor,
    required this.positionLabel,
    required this.state,
    required this.direction,
    required this.seed,
    this.timingPhase,
    this.resetBetweenOperations = true,
  });

  final int ordinal;
  final ReaderCaseLayer layer;
  final List<String> operationIds;
  final ReaderTopologyAnchor positionAnchor;
  final String positionLabel;
  final ReaderCaseState state;
  final ReaderOperationDirection direction;
  final int seed;
  final String? timingPhase;
  final bool resetBetweenOperations;

  /// Decode a case from the canonical C5 manifest without reconstructing its
  /// meaning in a runner.  The Android lane uses this exact parser after the
  /// manifest is pushed to the app-owned external directory.
  factory ReaderCorrectnessCase.fromJson(Map<String, Object?> json) {
    final operationIds = (json['operationIds'] as List<dynamic>?)
        ?.map((value) => value.toString())
        .toList(growable: false);
    if (operationIds == null || operationIds.isEmpty) {
      throw const FormatException('Reader correctness case has no operations');
    }
    for (final operationId in operationIds) {
      if (!readerCorrectnessOperationById.containsKey(operationId)) {
        throw FormatException('Unknown Reader operation id: $operationId');
      }
    }
    final seed = _requiredInt(json, 'seed');
    final item = ReaderCorrectnessCase(
      ordinal: _requiredInt(json, 'ordinal'),
      layer: _readerCaseLayerFromWireName(_requiredString(json, 'layer')),
      operationIds: List<String>.unmodifiable(operationIds),
      positionAnchor: _readerTopologyAnchorFromName(
        _requiredString(json, 'position'),
      ),
      positionLabel: _requiredString(json, 'positionLabel'),
      state: _readerCaseStateFromWireName(_requiredString(json, 'state')),
      direction: _readerOperationDirectionFromWireName(
        _requiredString(json, 'direction'),
      ),
      seed: seed,
      timingPhase: json['timingPhase']?.toString(),
      resetBetweenOperations: json['resetBetweenOperations'] as bool? ?? true,
    );
    final encodedId = json['caseId']?.toString();
    if (encodedId != null && encodedId != item.id) {
      throw FormatException(
        'Reader case id mismatch: encoded=$encodedId computed=${item.id}',
      );
    }
    return item;
  }

  String get id => readerCaseId(
    layer: layer.wireName,
    opSequence: operationIds.join('__'),
    position: positionLabel,
    state: state.wireName,
    seed: seed,
  );

  List<ReaderOperationDefinition> get operations => [
    for (final operationId in operationIds)
      readerCorrectnessOperationById[operationId]!,
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    'ordinal': ordinal,
    'caseId': id,
    'layer': layer.wireName,
    'operationIds': operationIds,
    'position': positionAnchor.name,
    'positionLabel': positionLabel,
    'state': state.wireName,
    'direction': direction.wireName,
    'timingPhase': timingPhase,
    'seed': seed,
    // Ordered pairs intentionally carry this false value: A and B execute in
    // one mounted logical session. The case boundary, not the pair boundary,
    // is where oracle state is reset.
    'resetBetweenOperations': resetBetweenOperations,
  };
}

final class ReaderCorrectnessCoverageReport {
  const ReaderCorrectnessCoverageReport({
    required this.layerCounts,
    required this.operationCount,
    required this.orderedPairCount,
    required this.orderedPairReverseEvidence,
    required this.threeWayStrength,
    required this.threeWayOperationPairs,
    required this.threeWayStatePositionPairs,
    required this.threeWayOperationStatePairs,
    required this.positionPolicy,
    required this.stateEntryConditions,
  });

  final Map<String, int> layerCounts;
  final int operationCount;
  final int orderedPairCount;
  final List<Map<String, String>> orderedPairReverseEvidence;
  final String threeWayStrength;
  final Map<String, int> threeWayOperationPairs;
  final int threeWayStatePositionPairs;
  final int threeWayOperationStatePairs;
  final Map<String, List<String>> positionPolicy;
  final Map<String, String> stateEntryConditions;

  Map<String, Object?> toJson() => <String, Object?>{
    'layerCounts': layerCounts,
    'operationCount': operationCount,
    'orderedPairCount': orderedPairCount,
    'orderedPairReverseEvidence': orderedPairReverseEvidence,
    'threeWayStrength': threeWayStrength,
    'threeWayOperationPairs': threeWayOperationPairs,
    'threeWayStatePositionPairs': threeWayStatePositionPairs,
    'threeWayOperationStatePairs': threeWayOperationStatePairs,
    'positionPolicy': positionPolicy,
    'stateEntryConditions': stateEntryConditions,
  };
}

final class ReaderCorrectnessManifest {
  const ReaderCorrectnessManifest({
    required this.schemaVersion,
    required this.seed,
    required this.cases,
    required this.coverage,
  });

  final int schemaVersion;
  final int seed;
  final List<ReaderCorrectnessCase> cases;
  final ReaderCorrectnessCoverageReport coverage;

  /// Parse only the data contract that C5 wrote.  Coverage is recomputed from
  /// the cases so a hand-edited or truncated coverage object cannot make an
  /// Android run look complete.
  factory ReaderCorrectnessManifest.fromJson(Map<String, Object?> json) {
    final rawCases = json['cases'];
    if (rawCases is! List) {
      throw const FormatException('Reader correctness manifest has no cases');
    }
    final cases = [
      for (final raw in rawCases)
        ReaderCorrectnessCase.fromJson(Map<String, Object?>.from(raw as Map)),
    ];
    final seed = _requiredInt(json, 'seed');
    final expectedCount = json['caseCount'];
    if (expectedCount is num && expectedCount.toInt() != cases.length) {
      throw FormatException(
        'Reader correctness caseCount mismatch: expected=$expectedCount actual=${cases.length}',
      );
    }
    for (final item in cases) {
      if (item.seed != seed) {
        throw FormatException(
          'Reader case seed mismatch: manifest=$seed case=${item.seed}',
        );
      }
    }
    return ReaderCorrectnessManifest(
      schemaVersion: _requiredInt(json, 'schemaVersion'),
      seed: seed,
      cases: List<ReaderCorrectnessCase>.unmodifiable(cases),
      coverage: _buildCoverageReport(cases),
    );
  }

  static ReaderCorrectnessManifest fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException(
        'Reader correctness manifest JSON is not an object',
      );
    }
    return ReaderCorrectnessManifest.fromJson(
      Map<String, Object?>.from(decoded),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'seed': seed,
    'caseCount': cases.length,
    'coverage': coverage.toJson(),
    'cases': [for (final item in cases) item.toJson()],
  };

  /// JSON insertion order is fixed by [toJson], so equal seeds produce byte
  /// identical manifests on host and Android.
  String get canonicalJson => jsonEncode(toJson());

  String get sha256 => sha256Digest(canonicalJson);

  Map<String, int> get layerCounts => coverage.layerCounts;
}

/// The deterministic, data-only selection result consumed by C6.  It is kept
/// next to the C5 generator so host and Android cannot silently grow separate
/// subset policies.
final class ReaderCorrectnessAndroidSubsetSelection {
  const ReaderCorrectnessAndroidSubsetSelection({
    required this.seed,
    required this.cases,
    required this.hostFailureCaseIds,
    required this.ruleCoverage,
  });

  final int seed;
  final List<ReaderCorrectnessCase> cases;
  final List<String> hostFailureCaseIds;
  final Map<String, List<String>> ruleCoverage;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'seed': seed,
    'caseCount': cases.length,
    'hostFailureCaseIds': hostFailureCaseIds,
    'ruleCoverage': ruleCoverage,
    'cases': [for (final item in cases) item.toJson()],
  };

  String get canonicalJson => jsonEncode(toJson());

  String get sha256 => sha256Digest(canonicalJson);
}

/// Select a reproducible Android subset from a C5 manifest.
///
/// The complete C5 single-operation layer is the finite Android representative
/// matrix: each operation keeps the topology positions selected by the host
/// generator.  Mixed journeys and host failures are hard inclusion sets.  Any
/// remaining dimensions are covered by a deterministic greedy set-cover pass.
/// This deliberately produces a hundreds-scale subset without running the
/// pairwise/three-way Cartesian layers in full.  The algorithm consumes only
/// case metadata; it never reimplements operation semantics or makes a
/// PowerShell-side interpretation of an id.
ReaderCorrectnessAndroidSubsetSelection selectReaderCorrectnessAndroidSubset(
  ReaderCorrectnessManifest manifest, {
  Iterable<String> hostFailureCaseIds = const <String>[],
}) {
  final requestedFailures = <String>{
    for (final value in hostFailureCaseIds)
      if (value.trim().isNotEmpty) value.trim(),
  };
  final byId = <String, ReaderCorrectnessCase>{
    for (final item in manifest.cases) item.id: item,
  };
  final missingFailures = requestedFailures.where(
    (caseId) => !byId.containsKey(caseId),
  );
  if (missingFailures.isNotEmpty) {
    throw StateError(
      'Host failure case ids are not present in seed ${manifest.seed}: '
      '${missingFailures.join(', ')}',
    );
  }

  final selectedIds = <String>{};
  void select(ReaderCorrectnessCase item) => selectedIds.add(item.id);

  // Representative matrix: keep every single-operation case.  C5 already
  // expands each operation over its declared six topology positions, so this
  // is still finite and purposeful rather than an unbounded Cartesian product.
  for (final item in manifest.cases) {
    if (item.layer == ReaderCaseLayer.singleOperation) select(item);
  }
  // Rule 6: every mixed journey, including every topology rotation, is kept.
  for (final item in manifest.cases) {
    if (item.layer == ReaderCaseLayer.mixedJourney) select(item);
  }
  // Rule 5: preserve every host failure before reducing the other dimensions.
  for (final caseId in requestedFailures) select(byId[caseId]!);

  final selected = [...manifest.cases]
    ..sort((left, right) => left.ordinal.compareTo(right.ordinal));

  Set<String> coverWith(ReaderCorrectnessCase item, String dimension) {
    return switch (dimension) {
      'operation' => item.operationIds.toSet(),
      'position' => <String>{item.positionAnchor.name},
      'state' => <String>{item.state.wireName},
      'phase' =>
        item.timingPhase == null
            ? const <String>{}
            : <String>{item.timingPhase == 'tail' ? 'late' : item.timingPhase!},
      _ => const <String>{},
    };
  }

  final ruleRequirements = <String, Set<String>>{
    'operations': {
      for (final operation in readerCorrectnessOperationCatalog) operation.id,
    },
    'positions': {
      for (final position in ReaderTopologyAnchor.values) position.name,
    },
    'states': {for (final state in ReaderCaseState.values) state.wireName},
    'racePhases': {'early', 'middle', 'late'},
  };
  final ruleDimensions = <String, String>{
    'operations': 'operation',
    'positions': 'position',
    'states': 'state',
    'racePhases': 'phase',
  };

  final ruleCoverage = <String, List<String>>{
    'hostFailures': [...requestedFailures],
  };
  for (final entry in ruleRequirements.entries) {
    final uncovered = {...entry.value};
    final dimension = ruleDimensions[entry.key]!;
    for (final candidate in selected) {
      if (!selectedIds.contains(candidate.id)) continue;
      uncovered.removeAll(coverWith(candidate, dimension));
    }
    while (uncovered.isNotEmpty) {
      ReaderCorrectnessCase? best;
      var bestCoverage = -1;
      for (final candidate in selected) {
        if (selectedIds.contains(candidate.id)) continue;
        final coverage = coverWith(
          candidate,
          dimension,
        ).intersection(uncovered).length;
        if (coverage > bestCoverage) {
          best = candidate;
          bestCoverage = coverage;
        }
      }
      if (best == null || bestCoverage <= 0) {
        throw StateError(
          'Unable to cover $entry.key for seed ${manifest.seed}; '
          'remaining=${uncovered.join(', ')}',
        );
      }
      select(best);
      final covered = coverWith(best, dimension).intersection(uncovered);
      uncovered.removeAll(covered);
      ruleCoverage.putIfAbsent(entry.key, () => <String>[]).add(best.id);
    }
  }

  final output = [
    for (final item in selected)
      if (selectedIds.contains(item.id)) item,
  ];

  // Emit compact deterministic witnesses for every rule after all hard and
  // greedy selections have been applied.  This keeps the coverage artifact
  // auditable even when a hard inclusion (for example mixed journeys) already
  // satisfies a dimension before the greedy loop runs.
  final witnesses = <String, List<String>>{};
  for (final entry in ruleRequirements.entries) {
    final remaining = {...entry.value};
    final dimension = ruleDimensions[entry.key]!;
    final ids = <String>[];
    for (final item in output) {
      final covered = coverWith(item, dimension).intersection(remaining);
      if (covered.isEmpty) continue;
      ids.add(item.id);
      remaining.removeAll(covered);
      if (remaining.isEmpty) break;
    }
    if (remaining.isNotEmpty) {
      throw StateError(
        'Unable to emit witnesses for ${entry.key}: '
        'missing=${remaining.join(', ')}',
      );
    }
    witnesses[entry.key] = ids;
  }
  witnesses['mixedJourneys'] = [
    for (final item in output)
      if (item.layer == ReaderCaseLayer.mixedJourney) item.id,
  ];
  witnesses['hostFailures'] = [...requestedFailures];
  final allCovered = <String, Set<String>>{
    'operations': {for (final item in output) ...coverWith(item, 'operation')},
    'positions': {for (final item in output) ...coverWith(item, 'position')},
    'states': {for (final item in output) ...coverWith(item, 'state')},
    'racePhases': {for (final item in output) ...coverWith(item, 'phase')},
  };
  for (final entry in ruleRequirements.entries) {
    if (!allCovered[entry.key]!.containsAll(entry.value)) {
      throw StateError(
        'Subset coverage failed for ${entry.key}: '
        'missing=${entry.value.difference(allCovered[entry.key]!).join(', ')}',
      );
    }
  }

  return ReaderCorrectnessAndroidSubsetSelection(
    seed: manifest.seed,
    cases: List<ReaderCorrectnessCase>.unmodifiable(output),
    hostFailureCaseIds: List<String>.unmodifiable(
      requestedFailures.toList()..sort(),
    ),
    ruleCoverage: Map<String, List<String>>.unmodifiable({
      for (final entry in {...ruleCoverage, ...witnesses}.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    }),
  );
}

int _requiredInt(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! num) throw FormatException('Missing integer field: $name');
  return value.toInt();
}

String _requiredString(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing string field: $name');
  }
  return value;
}

ReaderCaseLayer _readerCaseLayerFromWireName(String value) =>
    ReaderCaseLayer.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => throw FormatException('Unknown Reader case layer: $value'),
    );

ReaderCaseState _readerCaseStateFromWireName(String value) =>
    ReaderCaseState.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => throw FormatException('Unknown Reader case state: $value'),
    );

ReaderTopologyAnchor _readerTopologyAnchorFromName(String value) =>
    ReaderTopologyAnchor.values.firstWhere(
      (item) => item.name == value,
      orElse: () =>
          throw FormatException('Unknown Reader topology anchor: $value'),
    );

ReaderOperationDirection _readerOperationDirectionFromWireName(String value) =>
    ReaderOperationDirection.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () =>
          throw FormatException('Unknown Reader operation direction: $value'),
    );

String sha256Digest(String value) =>
    sha256.convert(utf8.encode(value)).toString();

ReaderCorrectnessManifest generateReaderCorrectnessManifest({
  int seed = readerCorrectnessFixtureSeed,
}) {
  final cases = <ReaderCorrectnessCase>[];
  var ordinal = 0;

  void add({
    required ReaderCaseLayer layer,
    required List<String> operations,
    required ReaderTopologyAnchor position,
    required String positionLabel,
    required ReaderCaseState state,
    required ReaderOperationDirection direction,
    String? timingPhase,
    bool resetBetweenOperations = true,
  }) {
    cases.add(
      ReaderCorrectnessCase(
        ordinal: ordinal++,
        layer: layer,
        operationIds: List<String>.unmodifiable(operations),
        positionAnchor: position,
        positionLabel: positionLabel,
        state: state,
        direction: direction,
        seed: seed,
        timingPhase: timingPhase,
        resetBetweenOperations: resetBetweenOperations,
      ),
    );
  }

  // S2 policy: single-operation coverage uses six semantically distinct
  // anchors per operation.  Boundary-focused anchors are fully expanded only
  // in the dedicated boundary layer below; there is no blind 36×10 product
  // in this layer.
  for (final operation in readerCorrectnessOperationCatalog) {
    for (final position in _singleOperationPositions(operation)) {
      add(
        layer: ReaderCaseLayer.singleOperation,
        operations: [operation.id],
        position: position,
        positionLabel: position.name,
        state: ReaderCaseState.ready,
        direction: operation.direction,
      );
    }
  }

  // S4 ordered pairs are a complete ordered product, including A→B and B→A.
  // The false reset flag is consumed by the host runner and is part of the
  // manifest contract used by C6.
  for (var a = 0; a < readerCorrectnessOperationCatalog.length; a += 1) {
    for (var b = 0; b < readerCorrectnessOperationCatalog.length; b += 1) {
      final first = readerCorrectnessOperationCatalog[a];
      final second = readerCorrectnessOperationCatalog[b];
      final position = _singleOperationPositions(
        first,
      )[(a + b + seed) % _singleOperationPositions(first).length];
      add(
        layer: ReaderCaseLayer.orderedPair,
        operations: [first.id, second.id],
        position: position,
        positionLabel: '${position.name}-pair-$a-$b',
        state: ReaderCaseState.ready,
        direction: _sequenceDirection([first, second]),
        resetBetweenOperations: false,
      );
    }
  }

  // The boundary layer intentionally expands every operation over each
  // topology anchor.  Its purpose is different from S2's normal-position
  // policy: it proves every transition at the short/long/boundary topology.
  for (final operation in readerCorrectnessOperationCatalog) {
    for (final position in ReaderTopologyAnchor.values) {
      add(
        layer: ReaderCaseLayer.boundaryTopology,
        operations: [operation.id],
        position: position,
        positionLabel: '${position.name}-boundary',
        state: ReaderCaseState.ready,
        direction: operation.direction,
      );
    }
  }

  for (final operation in readerCorrectnessOperationCatalog) {
    for (final state in ReaderCaseState.values) {
      final position = _singleOperationPositions(
        operation,
      )[(state.index + seed) % _singleOperationPositions(operation).length];
      add(
        layer: ReaderCaseLayer.stateInterruption,
        operations: [operation.id],
        position: position,
        positionLabel: '${position.name}-state-${state.wireName}',
        state: state,
        direction: operation.direction,
      );
    }
  }

  const racePhases = <String>['early', 'middle', 'tail'];
  const raceStates = <ReaderCaseState>[
    ReaderCaseState.ballisticEarly,
    ReaderCaseState.ballisticMiddle,
    ReaderCaseState.ballisticLate,
  ];
  for (final operation in readerCorrectnessOperationCatalog) {
    for (var phaseIndex = 0; phaseIndex < racePhases.length; phaseIndex += 1) {
      for (var scenario = 0; scenario < 6; scenario += 1) {
        final positions = _singleOperationPositions(operation);
        final position = positions[(scenario + seed) % positions.length];
        final phase = racePhases[phaseIndex];
        add(
          layer: ReaderCaseLayer.raceTiming,
          operations: [operation.id],
          position: position,
          positionLabel: '${position.name}-race-$phase-$scenario',
          state: raceStates[phaseIndex],
          direction: operation.direction,
          timingPhase: phase,
        );
      }
    }
  }

  // Strength-2 covering array over the three operation slots.  With N=36,
  // the Latin construction c=(a+b) mod N covers all A×B, B×C and A×C ordered
  // pairs in exactly N² cases; state×position and operation×state are covered
  // by the independent rotations below. This is the declared strength rather
  // than an impossible 36³ Cartesian product.
  final operationCount = readerCorrectnessOperationCatalog.length;
  for (var index = 0; index < operationCount * operationCount; index += 1) {
    final a = index % operationCount;
    final b = (index ~/ operationCount) % operationCount;
    final c = (a + b) % operationCount;
    final position =
        ReaderTopologyAnchor.values[((index ~/ ReaderCaseState.values.length) +
                seed) %
            ReaderTopologyAnchor.values.length];
    final state =
        ReaderCaseState.values[(index + seed) % ReaderCaseState.values.length];
    final definitions = <ReaderOperationDefinition>[
      readerCorrectnessOperationCatalog[a],
      readerCorrectnessOperationCatalog[b],
      readerCorrectnessOperationCatalog[c],
    ];
    add(
      layer: ReaderCaseLayer.threeWay,
      operations: [for (final definition in definitions) definition.id],
      position: position,
      positionLabel: '${position.name}-cover-$index',
      state: state,
      direction: _sequenceDirection(definitions),
    );
  }

  // These are intentionally hand-written journeys. The ten rotations only
  // place the same realistic route at each topology anchor; the operation
  // sequence itself is never generated by a Cartesian product.
  const journeys = <List<String>>[
    <String>[
      'navigation_jump_first',
      'drag_forward_slow',
      'fling_forward_medium',
      'natural_forward_slow_cross',
      'drag_backward_short',
      'navigation_previous',
      'navigation_far_location',
      'drag_forward_short',
      'navigation_forward_n',
      'fling_forward_high',
      'drag_release_immediate',
    ],
    <String>[
      'navigation_jump_current',
      'drag_forward_short',
      'fling_forward_high',
      'ballistic_interrupt_middle',
      'navigation_previous',
      'navigation_jump_unloaded_target',
      'drag_backward_slow',
      'navigation_forward_n',
      'fling_backward_low',
      'drag_pause_then_release',
    ],
    <String>[
      'navigation_jump_last',
      'drag_backward_slow',
      'natural_backward_fling_cross',
      'fling_backward_medium',
      'navigation_backward_n',
      'navigation_jump_loaded_target',
      'drag_forward_long',
      'fling_forward_low',
      'navigation_next',
      'drag_reverse_mid',
    ],
    <String>[
      'navigation_jump_first',
      'fling_forward_low',
      'natural_forward_fling_cross',
      'navigation_forward_n',
      'ballistic_interrupt_tail',
      'drag_backward_fast',
      'navigation_jump_current',
      'drag_forward_micro',
      'navigation_jump_unloaded_target',
    ],
    <String>[
      'navigation_jump_loaded_target',
      'drag_forward_fast',
      'drag_reverse_mid',
      'fling_backward_high',
      'navigation_previous',
      'natural_backward_slow_cross',
      'navigation_far_location',
      'drag_backward_micro',
      'navigation_next',
    ],
    <String>[
      'navigation_jump_current',
      'drag_pause_then_release',
      'fling_forward_medium',
      'ballistic_interrupt_early',
      'navigation_backward_n',
      'natural_forward_slow_cross',
      'navigation_jump_last',
      'drag_forward_short',
      'navigation_jump_first',
    ],
  ];
  for (
    var journeyIndex = 0;
    journeyIndex < journeys.length;
    journeyIndex += 1
  ) {
    final definitions = [
      for (final id in journeys[journeyIndex])
        readerCorrectnessOperationById[id]!,
    ];
    for (var repeat = 0; repeat < 10; repeat += 1) {
      final position =
          ReaderTopologyAnchor.values[(journeyIndex + repeat + seed) %
              ReaderTopologyAnchor.values.length];
      add(
        layer: ReaderCaseLayer.mixedJourney,
        operations: [for (final definition in definitions) definition.id],
        position: position,
        positionLabel: '${position.name}-journey-$journeyIndex-$repeat',
        state:
            ReaderCaseState.values[(journeyIndex + repeat + seed) %
                ReaderCaseState.values.length],
        direction: _sequenceDirection(definitions),
      );
    }
  }

  final coverage = _buildCoverageReport(cases);
  return ReaderCorrectnessManifest(
    schemaVersion: 1,
    seed: seed,
    cases: List<ReaderCorrectnessCase>.unmodifiable(cases),
    coverage: coverage,
  );
}

List<ReaderTopologyAnchor> _singleOperationPositions(
  ReaderOperationDefinition operation,
) {
  return switch (operation.category) {
    'drag' => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.bookStart,
      ReaderTopologyAnchor.firstRegularChapter,
      ReaderTopologyAnchor.veryLongChapter,
      ReaderTopologyAnchor.exactBoundaryChapter,
      ReaderTopologyAnchor.penultimateChapterTail,
      ReaderTopologyAnchor.finalChapterBottom,
    ],
    'fling' || 'ballistic_interrupt' => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.shortPreface,
      ReaderTopologyAnchor.firstRegularChapter,
      ReaderTopologyAnchor.veryLongChapter,
      ReaderTopologyAnchor.exactBoundaryChapter,
      ReaderTopologyAnchor.penultimateChapterTail,
      ReaderTopologyAnchor.finalChapterBottom,
    ],
    'natural_cross_chapter' => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.shortPreface,
      ReaderTopologyAnchor.veryShortChapterOne,
      ReaderTopologyAnchor.firstRegularChapter,
      ReaderTopologyAnchor.veryLongChapter,
      ReaderTopologyAnchor.distantChapter,
      ReaderTopologyAnchor.finalChapterBottom,
    ],
    'navigation' => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.bookStart,
      ReaderTopologyAnchor.veryShortChapterTwo,
      ReaderTopologyAnchor.firstRegularChapter,
      ReaderTopologyAnchor.distantChapter,
      ReaderTopologyAnchor.penultimateChapterTail,
      ReaderTopologyAnchor.finalChapterBottom,
    ],
    _ => ReaderTopologyAnchor.values.take(6).toList(growable: false),
  };
}

ReaderOperationDirection _sequenceDirection(
  Iterable<ReaderOperationDefinition> operations,
) {
  final directions = operations
      .map((operation) => operation.direction)
      .where((direction) => direction != ReaderOperationDirection.none)
      .toSet();
  if (directions.length == 1) return directions.single;
  return ReaderOperationDirection.none;
}

ReaderCorrectnessCoverageReport _buildCoverageReport(
  List<ReaderCorrectnessCase> cases,
) {
  final layerCounts = <String, int>{};
  for (final item in cases) {
    layerCounts.update(
      item.layer.wireName,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final pairCases = cases.where(
    (item) => item.layer == ReaderCaseLayer.orderedPair,
  );
  final pairKeys = <String>{
    for (final item in pairCases) item.operationIds.join('→'),
  };
  final threeWayCases = cases.where(
    (item) => item.layer == ReaderCaseLayer.threeWay,
  );
  final ab = <String>{};
  final bc = <String>{};
  final ac = <String>{};
  final statePosition = <String>{};
  final operationState = <String>{};
  for (final item in threeWayCases) {
    ab.add('${item.operationIds[0]}→${item.operationIds[1]}');
    bc.add('${item.operationIds[1]}→${item.operationIds[2]}');
    ac.add('${item.operationIds[0]}→${item.operationIds[2]}');
    statePosition.add('${item.state.wireName}:${item.positionAnchor.name}');
    for (final operationId in item.operationIds) {
      operationState.add('$operationId:${item.state.wireName}');
    }
  }
  final positionPolicy = <String, List<String>>{
    for (final operation in readerCorrectnessOperationCatalog)
      operation.id: [
        for (final position in _singleOperationPositions(operation))
          position.name,
      ],
  };
  final stateEntryConditions = <String, String>{
    'ready': 'phase=ready && initialRestoreCompleted=true && restoreLocked=false && pumpQueueDepth=0 && isScrolling=false',
    'dragging': 'scrollActivity=drag && dragging=true',
    'ballistic_early':
        'scrollActivity=ballistic && velocity.abs >= 0.66 * initialVelocity',
    'ballistic_middle': 'scrollActivity=ballistic && 0.33 * initialVelocity <= velocity.abs < 0.66 * initialVelocity',
    'ballistic_late': 'scrollActivity=ballistic && velocity.abs < 0.33 * initialVelocity && velocity != 0',
    'restore_ownership_acquired':
        'operationTokenId != null && pendingChapterJumpTarget != null',
    'restoring': 'phase=restoring || restoreLocked=true',
    'layout_pending': 'pumpQueueDepth > 0 || phase=layingOut',
    'rebuilding': 'phase=loading && epoch changed from previous record OR layoutGeneration changed',
    'anchor_pending':
        'pendingChapterJumpTarget != null && operationTokenId != null',
    'settling': 'previous scrollActivity=ballistic and current scrollActivity=idle, then waitUntil pumpQueueDepth=0',
    'just_became_ready': 'previous phase != ready and current phase=ready && initialRestoreCompleted=true',
  };
  final reverseEvidence = <Map<String, String>>[];
  if (readerCorrectnessOperationCatalog.length >= 2) {
    final first = readerCorrectnessOperationCatalog[0].id;
    final second = readerCorrectnessOperationCatalog[1].id;
    reverseEvidence.add(<String, String>{
      'forward': '$first→$second',
      'reverse': '$second→$first',
      'forwardPresent': pairKeys.contains('$first→$second').toString(),
      'reversePresent': pairKeys.contains('$second→$first').toString(),
    });
  }
  return ReaderCorrectnessCoverageReport(
    layerCounts: Map<String, int>.unmodifiable(layerCounts),
    operationCount: readerCorrectnessOperationCatalog.length,
    orderedPairCount: pairKeys.length,
    orderedPairReverseEvidence: List<Map<String, String>>.unmodifiable(
      reverseEvidence,
    ),
    threeWayStrength: 'strength-2 over ordered operation slots A/B/C; complete A×B, B×C, A×C projections plus rotated state×position and operation×state projections',
    threeWayOperationPairs: <String, int>{
      'A_B': ab.length,
      'B_C': bc.length,
      'A_C': ac.length,
      'required':
          readerCorrectnessOperationCatalog.length *
          readerCorrectnessOperationCatalog.length,
    },
    threeWayStatePositionPairs: statePosition.length,
    threeWayOperationStatePairs: operationState.length,
    positionPolicy: Map<String, List<String>>.unmodifiable(positionPolicy),
    stateEntryConditions: Map<String, String>.unmodifiable(
      stateEntryConditions,
    ),
  );
}
