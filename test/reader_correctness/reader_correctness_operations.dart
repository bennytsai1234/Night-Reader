import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';

import 'reader_correctness_case_generation.dart';

export 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';

const Duration readerVsyncStep = Duration(milliseconds: 8);
const Size readerCorrectnessViewportSize = Size(
  readerCorrectnessViewportWidth,
  readerCorrectnessViewportHeight,
);

/// Shared pacing implementation.  Both host and integration tests import
/// this exact function; there is intentionally no second copy in either tier.
Future<void> pumpVsyncPaced(WidgetTester tester, Duration duration) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    final remaining = duration - elapsed;
    final step = remaining < readerVsyncStep ? remaining : readerVsyncStep;
    await tester.pump(step);
    elapsed += step;
  }
}

Future<void> moveVsyncPaced(
  WidgetTester tester,
  TestGesture gesture,
  Offset delta, {
  Duration duration = const Duration(milliseconds: 65),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    final remaining = duration - elapsed;
    final step = remaining < readerVsyncStep ? remaining : readerVsyncStep;
    final fraction = step.inMicroseconds / duration.inMicroseconds;
    await gesture.moveBy(delta * fraction);
    await tester.pump(step);
    elapsed += step;
  }
}

abstract interface class ReaderCorrectnessHarness {
  Future<void> drag(Offset delta, {Duration duration});

  Future<void> fling(Offset delta, {Duration duration});
}

/// Optional extension implemented by the real host harness.  Keeping the
/// basic C1 interface intact means older smoke tests remain source-compatible,
/// while C5 can apply the complete data-only operation catalog through one
/// shared dispatch point.
abstract interface class ReaderCorrectnessOperationHarness
    extends ReaderCorrectnessHarness {
  Future<void> applyReaderOperation(ReaderOperationDefinition operation);
}

abstract interface class ReaderOp {
  String get id;

  ReaderOpDirection get direction;

  Future<void> apply(ReaderCorrectnessHarness harness);
}

final class DragDownShortOp implements ReaderOp {
  const DragDownShortOp();

  @override
  String get id => 'drag_down_short';

  @override
  ReaderOpDirection get direction => ReaderOpDirection.forward;

  @override
  Future<void> apply(ReaderCorrectnessHarness harness) {
    return harness.drag(
      const Offset(0, -180),
      duration: const Duration(milliseconds: 240),
    );
  }
}

final class FlingForwardOp implements ReaderOp {
  const FlingForwardOp();

  @override
  String get id => 'fling_forward';

  @override
  ReaderOpDirection get direction => ReaderOpDirection.forward;

  @override
  Future<void> apply(ReaderCorrectnessHarness harness) {
    return harness.fling(
      const Offset(0, -620),
      duration: const Duration(milliseconds: 180),
    );
  }
}

/// Adapter from the shared deterministic operation definition to a concrete
/// host/integration harness.  Android C6 can use the same definitions without
/// copying the catalog; only the harness-specific gesture bridge differs.
final class ReaderCatalogOp implements ReaderOp {
  const ReaderCatalogOp(this.definition);

  final ReaderOperationDefinition definition;

  @override
  String get id => definition.id;

  @override
  ReaderOpDirection get direction => switch (definition.direction) {
    ReaderOperationDirection.forward => ReaderOpDirection.forward,
    ReaderOperationDirection.backward => ReaderOpDirection.backward,
    ReaderOperationDirection.none => ReaderOpDirection.none,
  };

  @override
  Future<void> apply(ReaderCorrectnessHarness harness) {
    if (harness is ReaderCorrectnessOperationHarness) {
      return harness.applyReaderOperation(definition);
    }
    // The fallback is deliberately conservative for a legacy harness that
    // only knows C1's two gesture methods. C5's full lane always uses the
    // extended host harness, so no operation silently becomes a logical pass.
    if (definition.category == 'drag' ||
        definition.category == 'natural_cross_chapter') {
      final sign = definition.direction == ReaderOperationDirection.backward
          ? 1.0
          : -1.0;
      return harness.drag(
        Offset(0, sign * definition.distancePx),
        duration: Duration(milliseconds: definition.durationMillis),
      );
    }
    return harness.fling(
      Offset(
        0,
        definition.direction == ReaderOperationDirection.backward
            ? definition.distancePx
            : -definition.distancePx,
      ),
      duration: Duration(
        milliseconds: definition.durationMillis == 0
            ? 180
            : definition.durationMillis,
      ),
    );
  }
}

final List<ReaderOp> readerCorrectnessCatalogOperations = [
  for (final operation in readerCorrectnessOperationCatalog)
    ReaderCatalogOp(operation),
];

const List<ReaderOp> readerCorrectnessTemplateOperations = <ReaderOp>[
  DragDownShortOp(),
  FlingForwardOp(),
];
