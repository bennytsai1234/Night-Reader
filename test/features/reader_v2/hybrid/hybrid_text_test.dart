import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

void main() {
  group('TextPreprocessor', () {
    test('emits title block and UTF-16 displayText ranges', () async {
      final chapter = ChapterText(
        id: 3,
        title: '標題',
        paragraphs: const <String>['第一段', '第二段'],
        displayText: '標題\n\n第一段\n\n第二段',
        contentHash: 'hash',
      );

      final blocks = await const TextPreprocessor(
        useIsolate: false,
      ).process(chapter, maxBlockChars: 20);

      expect(blocks.blocks, hasLength(3));
      expect(blocks.blocks[0].isTitle, isTrue);
      expect(blocks.blocks[0].charRange, const HybridTextRange(0, 2));
      expect(blocks.blocks[1].charRange, const HybridTextRange(4, 7));
      expect(blocks.blocks[2].charRange, const HybridTextRange(9, 12));
    });

    test('splits long paragraphs at sentence boundaries', () async {
      final chapter = ChapterText(
        id: 0,
        title: '',
        paragraphs: const <String>['abc。def。ghi。'],
        displayText: 'abc。def。ghi。',
        contentHash: 'hash',
      );

      final blocks = await const TextPreprocessor(
        useIsolate: false,
      ).process(chapter, maxBlockChars: 4);

      expect(blocks.blocks.map((block) => block.text), <String>[
        'abc。',
        'def。',
        'ghi。',
      ]);
      expect(blocks.blocks[1].isContinuation, isTrue);
      expect(blocks.blocks[1].charRange, const HybridTextRange(4, 8));
    });
  });
}
