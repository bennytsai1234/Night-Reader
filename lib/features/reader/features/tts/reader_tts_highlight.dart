/// 朗讀高亮：目前朗讀的整個句段。
///
/// offset 是章節 displayText 的 UTF-16 座標。
class ReaderV2TtsHighlight {
  const ReaderV2TtsHighlight({
    required this.chapterIndex,
    required this.sentenceStart,
    required this.sentenceEnd,
  });

  final int chapterIndex;
  final int sentenceStart;
  final int sentenceEnd;

  bool get isValid => sentenceEnd > sentenceStart;

  @override
  bool operator ==(Object other) {
    return other is ReaderV2TtsHighlight &&
        other.chapterIndex == chapterIndex &&
        other.sentenceStart == sentenceStart &&
        other.sentenceEnd == sentenceEnd;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, sentenceStart, sentenceEnd);
}
