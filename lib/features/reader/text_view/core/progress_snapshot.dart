import '../progress/reader_chapter_shares.dart';

final class ProgressSnapshot {
  /// [chapterStart]、[chapterShare] 是這一章開頭在全書的位置與佔全書多少
  /// （[ReaderChapterShares]）；沒給時當每章一樣長。
  const ProgressSnapshot({
    required this.chapterIndex,
    required this.chapterCount,
    required this.chapterPercent,
    double? chapterStart,
    double? chapterShare,
  }) : _givenStart = chapterStart,
       _givenShare = chapterShare,
       assert(chapterCount >= 0),
       assert(chapterPercent >= 0),
       assert(chapterPercent <= 100);

  final int chapterIndex;
  final int chapterCount;
  final double chapterPercent;
  final double? _givenStart;
  final double? _givenShare;

  double get chapterStart =>
      _givenStart ??
      ReaderChapterShares.even(chapterCount).startOf(chapterIndex);
  double get chapterShare =>
      _givenShare ??
      ReaderChapterShares.even(chapterCount).shareOf(chapterIndex);

  String get chapterLabel {
    if (chapterCount <= 0) return '第 0/0 章 · 本章 0/10';
    final safeChapterIndex = chapterIndex.clamp(0, chapterCount - 1);
    return '第 ${safeChapterIndex + 1}/$chapterCount 章 · 本章 $chapterSegment/10';
  }

  /// 讀到的位置在整本書中的進度：這一章開頭的位置，加上這一章讀過的部分
  /// 佔全書多少。
  double get bookPercent {
    if (chapterCount <= 0) return 0.0;
    final safeChapterPercent = chapterPercent.clamp(0.0, 100.0);
    return ((chapterStart + chapterShare * safeChapterPercent / 100) * 100)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  String get percentLabel => '全書 ${bookPercent.toStringAsFixed(1)}%';

  /// 資訊列單欄用的精簡標籤。
  String get chapterIndexLabel {
    if (chapterCount <= 0) return '0/0';
    final safeChapterIndex = chapterIndex.clamp(0, chapterCount - 1);
    return '${safeChapterIndex + 1}/$chapterCount';
  }

  String get chapterProgressLabel => '本章 $chapterSegment/10';

  /// 全書進度顯示到小數第 [fractionDigits] 位；比較只看到第一位，再多
  /// 一位不會跟著更新。
  String bookPercentLabel(int fractionDigits) =>
      '${bookPercent.toStringAsFixed(fractionDigits)}%';

  /// 目前章節已完成的十分段數；章節開始為 0/10，章節結束為 10/10。
  int get chapterSegment {
    if (chapterPercent >= 100) return 10;
    return (chapterPercent / 10).floor().clamp(0, 9);
  }

  /// 這是資訊列的顯示模型；小於 0.1% 的 raw progress 變化不應觸發
  /// widget rebuild。
  @override
  bool operator ==(Object other) {
    return other is ProgressSnapshot &&
        other.chapterIndex == chapterIndex &&
        other.chapterCount == chapterCount &&
        other.chapterLabel == chapterLabel &&
        other.percentLabel == percentLabel;
  }

  @override
  int get hashCode =>
      Object.hash(chapterIndex, chapterCount, chapterLabel, percentLabel);
}
