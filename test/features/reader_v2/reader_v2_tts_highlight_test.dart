import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_segmenter.dart';

/// 朗讀高亮的契約：句段邊界不切開收引號；視窗跟隨只在換句時觸發。
void main() {
  const segmenter = ReaderV2TtsSegmenter();

  test('a sentence keeps its closing quote', () {
    const text = '「我們現在就出發，天亮之前一定要趕到城裡，否則城門一關就來不及了。」他說完便轉身離開了院子。';
    final segments = segmenter.segment(
      text: text,
      chapterIndex: 0,
      startOffset: 0,
    );
    expect(segments.first.text, endsWith('。」'));
    expect(segments[1].text, isNot(startsWith('」')));
    // 句段仍與章節座標一一對應。
    for (final segment in segments) {
      expect(
        text.substring(segment.startCharOffset, segment.endCharOffset),
        segment.text,
      );
    }
  });

  test('word progress inside a sentence does not change the follow target', () {
    const first = ReaderV2TtsHighlight(
      chapterIndex: 3,
      sentenceStart: 10,
      sentenceEnd: 40,
      wordStart: 10,
      wordEnd: 12,
    );
    const later = ReaderV2TtsHighlight(
      chapterIndex: 3,
      sentenceStart: 10,
      sentenceEnd: 40,
      wordStart: 20,
      wordEnd: 22,
    );
    expect(first, isNot(later), reason: '字詞前進要重畫高亮');
    expect(first.sentence, later.sentence, reason: '同一句不重新捲動');
    expect(first.sentence.hasWord, isFalse);
  });
}
