import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_segmenter.dart';

void main() {
  const segmenter = ReaderV2TtsSegmenter();

  test('preserves UTF-16 offsets and never cuts a surrogate pair', () {
    for (final prefixLength in <int>[219, 220, 221]) {
      final text = '${'甲' * prefixLength}😀${'乙' * 48}';
      final segments = segmenter.segment(
        text: text,
        chapterIndex: 7,
        startOffset: 0,
      );

      expect(
        segments.map((segment) => segment.text).join(),
        text,
        reason: 'all UTF-16 code units must be preserved at $prefixLength',
      );
      for (final segment in segments) {
        expect(segment.chapterIndex, 7);
        expect(
          segment.endCharOffset - segment.startCharOffset,
          segment.text.length,
        );
        expect(
          text.substring(segment.startCharOffset, segment.endCharOffset),
          segment.text,
        );
        expect(_isSurrogateBoundary(text, segment.startCharOffset), isTrue);
        expect(_isSurrogateBoundary(text, segment.endCharOffset), isTrue);
      }
    }
  });

  test('a start offset inside a supplementary character is promoted to its pair start', () {
    const text = '甲😀乙丙丁';
    final segments = segmenter.segment(
      text: text,
      chapterIndex: 0,
      startOffset: 2,
    );

    expect(segments, isNotEmpty);
    expect(segments.first.startCharOffset, 1);
    expect(segments.map((segment) => segment.text).join(), text.substring(1));
  });
}

bool _isSurrogateBoundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return true;
  final previous = text.codeUnitAt(offset - 1);
  final current = text.codeUnitAt(offset);
  final previousIsHigh = previous >= 0xD800 && previous <= 0xDBFF;
  final currentIsLow = current >= 0xDC00 && current <= 0xDFFF;
  return !(previousIsHigh && currentIsLow);
}
