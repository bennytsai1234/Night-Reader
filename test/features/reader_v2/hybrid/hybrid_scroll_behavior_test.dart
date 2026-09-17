import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/budget_governor.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';

void main() {
  ui.FrameTiming timing({
    required int buildMicros,
    required int rasterMicros,
    required int spanMicros,
    int vsyncStart = 0,
  }) {
    return ui.FrameTiming(
      vsyncStart: vsyncStart,
      buildStart: vsyncStart,
      buildFinish: vsyncStart + buildMicros,
      rasterStart: vsyncStart + spanMicros - rasterMicros,
      rasterFinish: vsyncStart + spanMicros,
      rasterFinishWallTime: vsyncStart + spanMicros,
    );
  }

  group('BudgetGovernor direct-flow contract', () {
    test('dragging and ballistic never disable layout', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.dragging), greaterThan(0));
      expect(governor.frameBudgetMicros(PumpState.ballistic), greaterThan(0));
    });

    test('idle and rebuilding also remain live', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 20000, rasterMicros: 20000, spanMicros: 45000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.idle), greaterThan(0));
      expect(governor.frameBudgetMicros(PumpState.rebuilding), greaterThan(0));
    });

    test('pump work is excluded from non-pump headroom estimate', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 3000, rasterMicros: 3000, spanMicros: 8000),
      ]);
      final before = governor.frameBudgetMicros(PumpState.ballistic);
      for (var i = 0; i < 40; i += 1) {
        governor.recordPumpWork(const Duration(microseconds: 3000));
      }
      final after = governor.frameBudgetMicros(PumpState.ballistic);
      expect(after, greaterThanOrEqualTo(before));
    });
  });

  group('HybridScrollPhysics direct-flow contract', () {
    ScrollMetrics metricsAt({double pixels = 0}) {
      return FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 100000,
        pixels: pixels,
        viewportDimension: 600,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3.0,
      );
    }

    test('user drag is never attenuated by layout readiness', () {
      const physics = HybridScrollPhysics();
      expect(physics.applyPhysicsToUserOffset(metricsAt(), -10), -10);
      expect(physics.applyPhysicsToUserOffset(metricsAt(), 10), 10);
    });

    test('applyTo preserves the direct clamping physics type', () {
      const physics = HybridScrollPhysics();
      final applied = physics.applyTo(const ClampingScrollPhysics());
      expect(applied, isA<HybridScrollPhysics>());
    });
  });
}
