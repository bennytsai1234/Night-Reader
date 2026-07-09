import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

void main() {
  group('hybrid core types', () {
    test('orders BlockKey by chapter then block', () {
      final keys = <BlockKey>[
        const BlockKey(chapterIndex: 1, blockIndex: 2),
        const BlockKey(chapterIndex: 0, blockIndex: 8),
        const BlockKey(chapterIndex: 1, blockIndex: 0),
      ]..sort();

      expect(keys, const <BlockKey>[
        BlockKey(chapterIndex: 0, blockIndex: 8),
        BlockKey(chapterIndex: 1, blockIndex: 0),
        BlockKey(chapterIndex: 1, blockIndex: 2),
      ]);
    });

    test('maps separator offsets to the next content block', () {
      final blocks = ChapterBlocks(
        chapterIndex: 0,
        title: '章名',
        displayText: '章名\n\n第一段\n\n第二段',
        contentHash: 'h',
        blocks: const <ChapterBlock>[
          ChapterBlock(
            key: BlockKey(chapterIndex: 0, blockIndex: 0),
            text: '章名',
            charRange: HybridTextRange(0, 2),
            sourceParagraphIndex: -1,
            isTitle: true,
          ),
          ChapterBlock(
            key: BlockKey(chapterIndex: 0, blockIndex: 1),
            text: '第一段',
            charRange: HybridTextRange(4, 7),
            sourceParagraphIndex: 0,
          ),
          ChapterBlock(
            key: BlockKey(chapterIndex: 0, blockIndex: 2),
            text: '第二段',
            charRange: HybridTextRange(9, 12),
            sourceParagraphIndex: 1,
          ),
        ],
      );

      expect(blocks.blockForCharOffset(0).blockIndex, 0);
      expect(blocks.blockForCharOffset(2).blockIndex, 1);
      expect(blocks.blockForCharOffset(8).blockIndex, 2);
      expect(blocks.anchorForCharOffset(6).blockIndex, 1);
    });
  });
}
