import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class LayoutCostModel {
  LayoutCostModel({double initialMsPerChar = 0.002})
    : _msPerChar = initialMsPerChar;

  double _msPerChar;

  double get msPerChar => _msPerChar;

  double layoutPassesFor(LayoutTask task) {
    return task.fingerprint.lastLineSpacingCompensation &&
            !task.block.isTitle &&
            !task.block.isContinuation &&
            task.textStyle.textAlign == ui.TextAlign.justify
        ? 2.0
        : 1.0;
  }

  Duration predict(LayoutTask task) {
    final millis = task.block.text.length * _msPerChar * layoutPassesFor(task);
    return Duration(microseconds: (millis * 1000).round());
  }

  int maxCharsFor(Duration budget, {int min = 64, int max = 1800}) {
    final budgetMs = budget.inMicroseconds / 1000;
    if (budgetMs <= 0 || _msPerChar <= 0) return min;
    return (budgetMs / _msPerChar).floor().clamp(min, max).toInt();
  }

  void record({
    required int charCount,
    required Duration elapsed,
    double layoutPasses = 1.0,
  }) {
    if (charCount <= 0) return;
    final safePasses =
        layoutPasses.isFinite && layoutPasses > 0 ? layoutPasses : 1.0;
    final observed = elapsed.inMicroseconds / 1000 / charCount / safePasses;
    _msPerChar = _msPerChar * 0.85 + observed * 0.15;
  }
}
