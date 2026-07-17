import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class LayoutCostModel {
  LayoutCostModel({double initialMsPerChar = 0.002})
    : _msPerChar = initialMsPerChar;

  double _msPerChar;

  double get msPerChar => _msPerChar;

  double layoutPassesFor(LayoutTask task) {
    return mayCompensateLastLine(task) ? 2.0 : 1.0;
  }

  /// B2 末行補償是否可能對此 task 生效（= 需要 Pass 1 量測自然寬度）。
  ///
  /// 除既有的開關/標題/續塊/justify 條件外，再以單行寬度上界剔除
  /// 「必為單行」的 block：每字元 advance 以 fontSize + max(0, letterSpacing)
  /// 為上界（CJK 恰為 1em、西文更窄；text.length 以 UTF-16 計會高估
  /// 增補平面字元，方向一致偏保守），總寬不超過 contentWidth 就不可能
  /// soft-wrap，直接單次 layout。估算極罕見失準（特寬字形）時的代價
  /// 只是該 block 略過補償，屬外觀差異，不影響斷行與座標契約。
  static bool mayCompensateLastLine(LayoutTask task) {
    if (!task.fingerprint.lastLineSpacingCompensation ||
        task.block.isTitle ||
        task.block.isContinuation ||
        task.textStyle.textAlign != ui.TextAlign.justify) {
      return false;
    }
    final text = task.block.text;
    if (text.contains('\n')) return true;
    final indentLength = task.indentChars <= 0 ? 0 : task.indentChars.clamp(0, 8);
    final spacing =
        task.textStyle.letterSpacing > 0 ? task.textStyle.letterSpacing : 0.0;
    final upperBoundWidth =
        (indentLength + text.length) * (task.textStyle.fontSize + spacing);
    return upperBoundWidth > task.contentWidth;
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
