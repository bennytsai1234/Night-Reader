import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/budget_governor.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/admission_controller.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';

/// 撞牆／頓挫修復的守門員：
/// 1. BudgetGovernor 以「幀週期 − 安全邊際 − 非 pump 工作量」給出連續
///    預算：健康幀有預算、滿載幀自動縮量、赤字保底不歸零，且 pump 自報
///    的工作量要從扣除項中剔除（自己不擠壓自己）。
/// 2. HybridScrollPhysics 必須從同一顆實例即時讀取領先量狀態
///    （Scrollable 只認 physics 的 runtimeType 鏈，position 永遠抱第一顆），
///    赤字摩擦為含遲滯的連續曲線，simulation 重建時不二態跳變。
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
    test('健康幀（工作量遠低於幀週期）ballistic 有預算', () {
      final governor = BudgetGovernor();
      // 幀跨度 16.6ms，但 UI+raster 實際工作僅 4ms——預算以工作時間為
      // 準，不受 vsync 對齊等待灌水。
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 2000, rasterMicros: 2000, spanMicros: 16600),
      ]);
      expect(governor.frameBudgetMicros(PumpState.ballistic), greaterThan(0));
    });

    test('工作量佔滿幀週期且無赤字時預算歸零', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.ballistic), 0);
    });

    test('領先量不足時 ballistic 預算保底一個標準切片（撞牆比掉幀更糟）', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      governor.updateLeadDeficit(true);
      expect(
        governor.frameBudgetMicros(PumpState.ballistic),
        governor.ballisticSliceBudget.inMicroseconds,
      );
      // I4 硬底線不受影響：拖曳中永遠零預算。
      expect(governor.frameBudgetMicros(PumpState.dragging), 0);
    });

    test('pump 自報的工作量不反過來擠壓自己的預算', () {
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

    test('幀週期接受單一 vsync 間隔', () {
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

    test('漏掉多個 vsync 的倍數間隔不會放大幀週期', () {
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

    test('idle 與 rebuilding 永不餓死（restore 與領先量鋪設不可停擺）', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 20000, rasterMicros: 20000, spanMicros: 45000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.idle), greaterThan(0));
      expect(governor.frameBudgetMicros(PumpState.rebuilding), greaterThan(0));
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

  group('AdmissionController friction scale', () {
    /// 單一 10000px block；viewportBottom = 10000 − lead 可精準控制前向
    /// 領先量。書尾未知（非邊界）、書首為邊界（chapterCount=0）。
    AdmissionController controllerWithLead(double lead) {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
      );
      index.admit(
        const BlockKey(chapterIndex: 0, blockIndex: 0),
        const BlockMetrics(height: 10000, lineCount: 1),
      );
      return AdmissionController(documentIndex: index)
        ..updateLead(viewportTop: 0, viewportBottom: 10000 - lead);
    }

    test('遲滯：領先量在 engage 與 release 之間時依歷史決定', () {
      // 由充足直接降到 5000（engage 4800 與 release 6000 之間）：
      // 未曾跌破 engage → 不施加摩擦。
      final fresh = controllerWithLead(5000);
      expect(fresh.frictionScaleToward(forward: true), 0.0);
      // 先跌破 engage 再回到同樣的 5000 → latch 保持 → 仍施加摩擦。
      final latched = controllerWithLead(4000);
      expect(latched.frictionScaleToward(forward: true), greaterThan(0.0));
      latched.updateLead(viewportTop: 0, viewportBottom: 5000);
      expect(latched.frictionScaleToward(forward: true), greaterThan(0.0));
      // 補回 release 以上 → 完全解除。
      latched.updateLead(viewportTop: 0, viewportBottom: 3000);
      expect(latched.frictionScaleToward(forward: true), 0.0);
    });

    test('摩擦比例對領先量單調且連續（無二態跳變）', () {
      final controller = controllerWithLead(100);
      double scaleAt(double lead) {
        controller.updateLead(viewportTop: 0, viewportBottom: 10000 - lead);
        return controller.frictionScaleToward(forward: true);
      }

      expect(scaleAt(100), 1.0); // ≤ floor（1500）滿摩擦。
      var previous = 1.0;
      for (var lead = 1500.0; lead <= 6000.0; lead += 250.0) {
        final scale = scaleAt(lead);
        expect(scale, lessThanOrEqualTo(previous));
        expect(scale, inInclusiveRange(0.0, 1.0));
        // 相鄰取樣間的跳變幅度必須小（連續曲線，非 0/1 階梯）。
        expect((previous - scale).abs(), lessThan(0.2));
        previous = scale;
      }
      expect(previous, 0.0); // release（6000）完全解除。
    });

    test('書尾邊界不施加摩擦（自然滑到底）', () {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
      );
      index.admit(
        const BlockKey(chapterIndex: 0, blockIndex: 0),
        const BlockMetrics(height: 300, lineCount: 1),
      );
      final admission =
          AdmissionController(documentIndex: index)
            ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
            ..registerChapter(
              ChapterBlocks(
                chapterIndex: 0,
                title: '第一章',
                contentHash: 'hash',
                displayText: 'x',
                blocks: const <ChapterBlock>[
                  ChapterBlock(
                    key: BlockKey(chapterIndex: 0, blockIndex: 0),
                    text: 'x',
                    charRange: HybridTextRange(0, 1),
                    sourceParagraphIndex: 0,
                  ),
                ],
              ),
            )
            ..updateLead(viewportTop: 0, viewportBottom: 200);
      expect(admission.atForwardBookBoundary, isTrue);
      expect(admission.frictionScaleToward(forward: true), 0.0);
    });
  });
}
