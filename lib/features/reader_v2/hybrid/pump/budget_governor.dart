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
      final micros = timing.totalSpan.inMicroseconds.toDouble();
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
        if (_averageFrameMicros > jankFrameBudget.inMicroseconds) return 0;
        return _leadDeficit ? 2 : 1;
      case PumpState.rebuilding:
        return 1;
      case PumpState.idle:
        return _leadDeficit ? 12 : 8;
    }
  }
}
