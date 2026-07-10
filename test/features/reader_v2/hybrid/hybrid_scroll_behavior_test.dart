import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/budget_governor.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/admission_controller.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';

/// 撞牆修復的兩個守門員：
/// 1. BudgetGovernor 的 ballistic gate 必須以「UI+raster 工作時間」判斷
///    （totalSpan 在 60Hz 健康幀就 >8.33ms，會把 gate 永久關死），且領先量
///    不足時絕不歸零。
/// 2. HybridScrollPhysics 必須從同一顆實例即時讀取領先量狀態
///    （Scrollable 只認 physics 的 runtimeType 鏈，position 永遠抱第一顆），
///    赤字方向的 fling 以高摩擦自然收斂。
void main() {
  ui.FrameTiming timing({
    required int buildMicros,
    required int rasterMicros,
    required int spanMicros,
  }) {
    return ui.FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: buildMicros,
      rasterStart: spanMicros - rasterMicros,
      rasterFinish: spanMicros,
      rasterFinishWallTime: spanMicros,
    );
  }

  group('BudgetGovernor', () {
    test('ballistic gate 以工作時間為準：60Hz 健康幀不關 gate', () {
      final governor = BudgetGovernor();
      // 幀跨度 16.6ms（60Hz 常態），但 UI+raster 實際工作僅 4ms。
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 2000, rasterMicros: 2000, spanMicros: 16600),
      ]);
      expect(governor.allowedSlices(PumpState.ballistic), 1);
    });

    test('工作時間確實超標且無赤字時才停排版', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      expect(governor.allowedSlices(PumpState.ballistic), 0);
    });

    test('領先量不足時 ballistic 配額絕不歸零（撞牆比掉幀更糟）', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      governor.updateLeadDeficit(true);
      expect(governor.allowedSlices(PumpState.ballistic), 2);
      // I4 硬底線不受影響：拖曳中永遠零排版。
      expect(governor.allowedSlices(PumpState.dragging), 0);
    });
  });

  group('HybridScrollPhysics', () {
    /// 造出「前向領先量不足」：只放行一個 150px block，視窗底 100px，
    /// 前向 lead 50px < guaranteedWindow；書尾未知（非邊界）。
    (AdmissionController, DocumentIndex) deficitForward() {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
      );
      index.admit(
        const BlockKey(chapterIndex: 0, blockIndex: 0),
        const BlockMetrics(height: 150, lineCount: 1),
      );
      final admission = AdmissionController(documentIndex: index);
      admission.updateLead(viewportTop: 0, viewportBottom: 100);
      return (admission, index);
    }

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

    test('拖曳摩擦由同一顆實例即時讀取領先量狀態', () {
      final (admission, index) = deficitForward();
      final physics = HybridScrollPhysics(admission: admission);
      // 前進方向（offset<0）赤字 → 衰減。
      expect(
        physics.applyPhysicsToUserOffset(metricsAt(), -10),
        closeTo(-4.5, 1e-9),
      );
      // 反方向在書首邊界 → 不衰減。
      expect(physics.applyPhysicsToUserOffset(metricsAt(pixels: 50), 10), 10);
      // 補足領先量後，同一顆實例即時解除摩擦（不靠 rebuild 換 physics）。
      index.admit(
        const BlockKey(chapterIndex: 0, blockIndex: 1),
        const BlockMetrics(height: 9000, lineCount: 1),
      );
      admission.updateLead(viewportTop: 0, viewportBottom: 100);
      expect(physics.applyPhysicsToUserOffset(metricsAt(), -10), -10);
    });

    test('赤字方向的 fling 高摩擦自然收斂而非等速撞牆', () {
      final (admission, _) = deficitForward();
      final deficitPhysics = HybridScrollPhysics(admission: admission);
      const freePhysics = HybridScrollPhysics();
      final deficitSim = deficitPhysics.createBallisticSimulation(
        metricsAt(),
        3000,
      );
      final freeSim = freePhysics.createBallisticSimulation(metricsAt(), 3000);
      expect(deficitSim, isNotNull);
      expect(freeSim, isNotNull);
      // 高摩擦：滑行距離明顯縮短，但仍是連續自然滑行（>0）。
      expect(deficitSim!.x(10.0), lessThan(freeSim!.x(10.0)));
      expect(deficitSim.x(10.0), greaterThan(0));
      // 無赤字方向維持框架行為（同款模擬、同距離量級不在此比對）。
    });

    test('applyTo 保留 admission 參考（position 建立時的鏈仍能即時查詢）', () {
      final (admission, _) = deficitForward();
      final physics = HybridScrollPhysics(admission: admission);
      final applied = physics.applyTo(const ClampingScrollPhysics());
      expect(applied.admission, same(admission));
    });
  });
}
