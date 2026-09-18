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

  group('BudgetGovernor', () {
    test('healthy frames receive ballistic credit', () {
      final governor = BudgetGovernor();
      // 幀跨度 16.6ms，但 UI+raster 實際工作僅 4ms——預算以工作時間為
      // 準，不受 vsync 對齊等待灌水。
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 2000, rasterMicros: 2000, spanMicros: 16600),
      ]);
      expect(governor.frameBudgetMicros(PumpState.ballistic), greaterThan(0));
    });

    test('busy frames still permit one bounded layout slice', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      expect(
        governor.frameBudgetMicros(PumpState.ballistic),
        governor.ballisticSliceBudget.inMicroseconds,
      );
    });

    test('dragging and ballistic retain bounded forward progress', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      expect(
        governor.frameBudgetMicros(PumpState.ballistic),
        governor.ballisticSliceBudget.inMicroseconds,
      );
      expect(
        governor.frameBudgetMicros(PumpState.dragging),
        governor.ballisticSliceBudget.inMicroseconds,
      );
    });

    test('pump work is excluded from non-pump budget pressure', () {
      final governor = BudgetGovernor();
      // 幀工作 6ms，其中 3ms 是 pump 自己——扣除項應只剩 3ms 非 pump。
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 3000, rasterMicros: 3000, spanMicros: 8000),
      ]);
      final starvedBudget = governor.frameBudgetMicros(PumpState.ballistic);
      for (var i = 0; i < 40; i += 1) {
        governor.recordPumpWork(const Duration(microseconds: 3000));
      }
      final informedBudget = governor.frameBudgetMicros(PumpState.ballistic);
      expect(informedBudget, greaterThan(starvedBudget));
    });

    test('one native vsync interval calibrates the frame period', () {
      final governor = BudgetGovernor();
      expect(governor.framePeriodMicros, 8333.0);
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 1000, rasterMicros: 1000, spanMicros: 4000),
        timing(
          buildMicros: 1000,
          rasterMicros: 1000,
          spanMicros: 4000,
          vsyncStart: 8333,
        ),
      ]);
      expect(governor.framePeriodMicros, closeTo(8333, 1));
    });

    test('missed-vsync multiples cannot enlarge frame credit', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 1000, rasterMicros: 1000, spanMicros: 4000),
        timing(
          buildMicros: 1000,
          rasterMicros: 1000,
          spanMicros: 4000,
          vsyncStart: 8333,
        ),
        // 120Hz 漏一幀：相鄰完成幀相隔約 2 × 8.33ms。
        timing(
          buildMicros: 1000,
          rasterMicros: 1000,
          spanMicros: 4000,
          vsyncStart: 24999,
        ),
        // 下一個正常幀仍以前一個 timing 為基準，應再次校正為單一週期。
        timing(
          buildMicros: 1000,
          rasterMicros: 1000,
          spanMicros: 4000,
          vsyncStart: 33332,
        ),
      ]);
      expect(governor.framePeriodMicros, closeTo(8333, 1));
    });

    test('idle and rebuilding retain bounded forward progress', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 20000, rasterMicros: 20000, spanMicros: 45000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.idle), greaterThan(0));
      expect(governor.frameBudgetMicros(PumpState.rebuilding), greaterThan(0));
    });
  });

  group('HybridScrollPhysics native behavior', () {
    ScrollMetrics metrics(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 10000,
      pixels: pixels,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );
    test('pointer distance is never reduced by materialization readiness', () {
      const physics = HybridScrollPhysics();
      for (final delta in [-100.0, -1.0, 1.0, 100.0]) {
        expect(physics.applyPhysicsToUserOffset(metrics(500), delta), delta);
      }
    });
    test('fling trajectories match native clamping physics', () {
      const actual = HybridScrollPhysics();
      const native = ClampingScrollPhysics();
      for (final offset in [0.0, 500.0, 10000.0]) {
        for (final velocity in [-8000.0, -400.0, 0.0, 400.0, 8000.0]) {
          final a = actual.createBallisticSimulation(metrics(offset), velocity);
          final b = native.createBallisticSimulation(metrics(offset), velocity);
          expect(a == null, b == null);
          if (a == null || b == null) continue;
          for (final t in [0.0, 0.01, 0.1, 0.5]) {
            expect(a.x(t), closeTo(b.x(t), 1e-9));
            expect(a.dx(t), closeTo(b.dx(t), 1e-9));
          }
        }
      }
    });
    test('applyTo retains the native physics parent chain', () {
      const parent = AlwaysScrollableScrollPhysics();
      final applied = const HybridScrollPhysics().applyTo(parent);
      expect(applied.parent, same(parent));
    });
  });
}
