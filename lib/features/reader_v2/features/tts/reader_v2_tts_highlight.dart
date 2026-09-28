/// 朗讀高亮：目前朗讀的句段，以及引擎回報的正在朗讀字詞。
///
/// 句段範圍一定存在；字詞範圍只在 TTS 引擎支援進度回報
/// （Android onRangeStart）時才有，不支援的引擎只顯示句段。
/// 所有 offset 都是章節 displayText 的 UTF-16 座標。
class ReaderV2TtsHighlight {
  const ReaderV2TtsHighlight({
    required this.chapterIndex,
    required this.sentenceStart,
    required this.sentenceEnd,
    this.wordStart,
    this.wordEnd,
  }) : assert((wordStart == null) == (wordEnd == null));

  final int chapterIndex;
  final int sentenceStart;
  final int sentenceEnd;
  final int? wordStart;
  final int? wordEnd;

  bool get isValid => sentenceEnd > sentenceStart;

  bool get hasWord {
    final start = wordStart;
    final end = wordEnd;
    return start != null && end != null && end > start;
  }

  /// 視窗跟隨只看句段：句段內逐字前進不需要重新捲動。
  ReaderV2TtsHighlight get sentence => hasWord || wordStart != null
      ? ReaderV2TtsHighlight(
          chapterIndex: chapterIndex,
          sentenceStart: sentenceStart,
          sentenceEnd: sentenceEnd,
        )
      : this;

  @override
  bool operator ==(Object other) {
    return other is ReaderV2TtsHighlight &&
        other.chapterIndex == chapterIndex &&
        other.sentenceStart == sentenceStart &&
        other.sentenceEnd == sentenceEnd &&
        other.wordStart == wordStart &&
        other.wordEnd == wordEnd;
  }

  @override
  int get hashCode =>
      Object.hash(chapterIndex, sentenceStart, sentenceEnd, wordStart, wordEnd);
}
