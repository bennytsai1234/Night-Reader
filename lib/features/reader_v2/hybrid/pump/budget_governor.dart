import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

/// 以實測幀餘裕分配排版時間片的排程器。
///
/// 取代二元 gate（EWMA 超過固定門檻即全關）：gate 震盪會與 deficit 摩擦
/// 形成正反饋（gate 關→領先量流失→強制補片＋高摩擦→幀更重→gate 續關），
/// 是 fling「一頓一頓」的來源之一。這裡改為：
/// `本幀預算 = 幀週期 − 安全邊際 − 非 pump 工作量`，連續縮放、永不長期
/// 歸零；幀週期由 FrameTiming 的 vsync 間隔實測（120Hz 裝置自動得到
/// ~8.3ms，不依賴平台 refreshRate API 的正確性）。
final class BudgetGovernor {
  BudgetGovernor({
    this.ballisticSliceBudget = const Duration(milliseconds: 2),
    this.safetyMarginMicros = 1200,
    this.defaultFramePeriodMicros = 8333,
  });

  /// 單一 LayoutTask 的目標尺寸（TextPreprocessor 依此切塊），同時是
  /// 赤字保底預算——撞牆急停比偶發掉幀更糟。
  final Duration ballisticSliceBudget;

  /// 每幀留給輸入處理／合成的固定安全邊際。
  final int safetyMarginMicros;

  /// 尚無 vsync 實測值時的幀週期假設（120Hz）。
  final int defaultFramePeriodMicros;

  static const int _ballisticCapMicros = 4000;
  static const int _rebuildingCapMicros = 6000;
  static const double _periodTolerance = 0.15;

  double _framePeriodMicros = 0;
  double _averageWorkMicros = 0;
  double _averagePumpMicros = 0;
  int? _lastVsyncStartMicros;
  bool _leadDeficit = false;

  double get averageWorkMicros => _averageWorkMicros;
  double get framePeriodMicros =>
      _framePeriodMicros > 0
          ? _framePeriodMicros
          : defaultFramePeriodMicros.toDouble();

  void updateLeadDeficit(bool value) {
    _leadDeficit = value;
  }

  void recordFrameTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      // 用 UI+raster 工作時間，不用 totalSpan：totalSpan 含 vsync 對齊
      // 等待，健康幀也會被灌成整個幀週期。
      final micros =
          (timing.buildDuration + timing.rasterDuration).inMicroseconds
              .toDouble();
      _averageWorkMicros =
          _averageWorkMicros == 0
              ? micros
              : _averageWorkMicros * 0.9 + micros * 0.1;
      // 幀週期取相鄰 vsyncStart 差值。漏掉一個或多個 vsync 時，delta 會
      // 變成實際週期的整數倍；這種間隔不能拿來放大後續排版預算。
      final vsyncStart = timing.timestampInMicroseconds(
        ui.FramePhase.vsyncStart,
      );
      final last = _lastVsyncStartMicros;
      _lastVsyncStartMicros = vsyncStart;
      if (last != null) {
        final delta = (vsyncStart - last).toDouble();
        if (delta >= 4000 && delta <= 40000 && _isSingleFramePeriod(delta)) {
          _framePeriodMicros =
              _framePeriodMicros == 0
                  ? delta
                  : _framePeriodMicros * 0.9 + delta * 0.1;
        }
      }
    }
  }

  bool _isSingleFramePeriod(double delta) {
    final period = framePeriodMicros;
    final multiple = (delta / period).round();
    if (multiple < 1) return false;
    final expected = period * multiple;
    final tolerance = math.max(500.0, period * _periodTolerance);
    // 只接受接近一個目前週期的間隔；2x、3x… 都是漏幀，不更新 EWMA。
    return multiple == 1 && (delta - expected).abs() <= tolerance;
  }

  /// pump 每次執行後自報耗時（含空轉 0），供預算扣除「非 pump 工作量」
  /// ——pump 自己造成的幀成本不應反過來擠壓自己的預算。
  void recordPumpWork(Duration elapsed) {
    _averagePumpMicros =
        _averagePumpMicros * 0.8 + elapsed.inMicroseconds * 0.2;
  }

  /// 本幀可用的排版預算（µs）。dragging 恆為 0（I4）；idle/rebuilding
  /// 保底一個標準切片（餓死會讓 restore 與領先量鋪設停擺）；ballistic
  /// 無赤字時允許歸零（該幀已滿載），有赤字時保底（撞牆防護）。
  int frameBudgetMicros(PumpState state) {
    final slice = ballisticSliceBudget.inMicroseconds;
    switch (state) {
      case PumpState.dragging:
        return 0;
      case PumpState.ballistic:
        final budget = _headroomMicros(capMicros: _ballisticCapMicros);
        return _leadDeficit ? math.max(budget, slice) : budget;
      case PumpState.rebuilding:
        return math.max(
          _headroomMicros(capMicros: _rebuildingCapMicros),
          slice,
        );
      case PumpState.idle:
        // 非滾動幀：允許用到約兩個幀週期快速鋪領先量，但保底 4 個標準
        // 切片維持與舊行為相當的暖機速度。
        final cap = (2 * framePeriodMicros).round();
        return math.max(_headroomMicros(capMicros: cap), 4 * slice);
    }
  }

  int _headroomMicros({required int capMicros}) {
    final nonPumpWork = math.max(0.0, _averageWorkMicros - _averagePumpMicros);
    final headroom = framePeriodMicros - safetyMarginMicros - nonPumpWork;
    if (!headroom.isFinite || headroom <= 0) return 0;
    return math.min(headroom, capMicros.toDouble()).round();
  }
}
