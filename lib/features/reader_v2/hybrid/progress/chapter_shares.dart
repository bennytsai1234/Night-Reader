import 'package:flutter/foundation.dart';

/// 每一章佔全書多少，全書進度照它算：讀到第幾章不照章數平均，照前面
/// 各章的長度加總。長度是下載好的正文的位元組數（中文一個字固定三個
/// 位元組，比例和字數一樣）；還不知道長度的章用已知各章的平均，一章都
/// 不知道時就是平均分（[ReaderV2ChapterShares.even]）。分卷標題沒有
/// 正文，佔 0。
@immutable
final class ReaderV2ChapterShares {
  /// 每章一樣長。
  const ReaderV2ChapterShares.even(this.chapterCount) : _starts = null;

  /// [lengths] 與章節一一對應：null 是還不知道，0 是沒有正文（分卷）。
  factory ReaderV2ChapterShares.fromLengths(List<int?> lengths) {
    final known = [
      for (final length in lengths)
        if (length != null && length > 0) length,
    ];
    if (known.isEmpty) return ReaderV2ChapterShares.even(lengths.length);
    final average = known.reduce((a, b) => a + b) / known.length;
    final weights = [
      for (final length in lengths)
        length == null ? average : length.toDouble(),
    ];
    final total = weights.fold<double>(0, (sum, w) => sum + w);
    if (total <= 0) return ReaderV2ChapterShares.even(lengths.length);
    final starts = List<double>.filled(lengths.length + 1, 0);
    for (var i = 0; i < weights.length; i++) {
      starts[i + 1] = starts[i] + weights[i] / total;
    }
    starts[lengths.length] = 1;
    return ReaderV2ChapterShares._(lengths.length, starts);
  }

  const ReaderV2ChapterShares._(this.chapterCount, List<double> starts)
    : _starts = starts;

  final int chapterCount;

  /// 第 i 章開頭在全書的位置是 `_starts[i]`，最後一個是 1。
  final List<double>? _starts;

  /// 第 [chapterIndex] 章開頭在全書的位置（0 到 1）。
  double startOf(int chapterIndex) {
    if (chapterCount <= 0) return 0;
    final index = chapterIndex.clamp(0, chapterCount - 1).toInt();
    final starts = _starts;
    return starts == null ? index / chapterCount : starts[index];
  }

  /// 第 [chapterIndex] 章佔全書多少（0 到 1）。
  double shareOf(int chapterIndex) {
    if (chapterCount <= 0) return 0;
    final index = chapterIndex.clamp(0, chapterCount - 1).toInt();
    final starts = _starts;
    return starts == null
        ? 1 / chapterCount
        : starts[index + 1] - starts[index];
  }
}
