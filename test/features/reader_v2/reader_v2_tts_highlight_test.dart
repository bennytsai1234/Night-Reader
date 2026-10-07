import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_segmenter.dart';

/// 朗讀高亮的契約：句段邊界不切開收引號，頭尾不漏字。
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

  test('句段頭尾不漏字：每個非空白字元都落在某個句段內', () {
    const text =
        '第一章\n\n　　「我們現在就出發，天亮之前一定要趕到城裡，否則城門一關就來不及了。」'
        '他說完便轉身離開了院子，留下她一個人站在門口望著遠方。\n\n'
        '天色漸暗，城門即將關閉，守衛開始驅趕還在城外徘徊的商販與旅人！';
    final segments = segmenter.segment(
      text: text,
      chapterIndex: 0,
      startOffset: 0,
    );
    final covered = List<bool>.filled(text.length, false);
    for (final segment in segments) {
      for (var i = segment.startCharOffset; i < segment.endCharOffset; i += 1) {
        covered[i] = true;
      }
    }
    for (var i = 0; i < text.length; i += 1) {
      if (text[i].trim().isEmpty) continue;
      expect(covered[i], isTrue, reason: '第 $i 個字「${text[i]}」沒有被任何句段涵蓋');
    }
  });
}
