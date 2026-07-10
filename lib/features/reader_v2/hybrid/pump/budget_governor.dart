import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class BudgetGovernor {
  BudgetGovernor({
    this.ballisticSliceBudget = const Duration(milliseconds: 2),
    this.jankFrameBudget = const Duration(microseconds: 8333),
  });

  final Duration ballisticSliceBudget;
  final Duration jankFrameBudget;
  double _averageFrameMicros = 0;
  bool _leadDeficit = false;

  double get averageFrameMicros => _averageFrameMicros;

  void updateLeadDeficit(bool value) {
    _leadDeficit = value;
  }

  void recordFrameTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      // 用 UI+raster 工作時間，不用 totalSpan：totalSpan 含 vsync 對齊等
      // 待，60Hz 裝置健康幀就 >8.33ms，會把 ballistic gate 永久關死——
      // 領先量在 fling 中無法補充，慣性衝到已放行邊界被硬夾停（撞牆）。
      final micros =
          (timing.buildDuration + timing.rasterDuration).inMicroseconds
              .toDouble();
      _averageFrameMicros =
          _averageFrameMicros == 0
              ? micros
              : _averageFrameMicros * 0.9 + micros * 0.1;
    }
  }

  int allowedSlices(PumpState state) {
    switch (state) {
      case PumpState.dragging:
        return 0;
      case PumpState.ballistic:
        // 領先量不足時絕不歸零：撞牆急停比偶發掉幀更糟。
        if (_leadDeficit) return 2;
        return _averageFrameMicros > jankFrameBudget.inMicroseconds ? 0 : 1;
      case PumpState.rebuilding:
        return 1;
      case PumpState.idle:
        return _leadDeficit ? 12 : 8;
    }
  }
}
