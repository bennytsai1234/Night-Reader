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

    test(
      'groupContaining/paragraphGroups 不把不同 sourceParagraphIndex 的 '
      'isContinuation 相鄰塊併成同一組',
      () {
        // 手動建構一個「錯誤標記」情境：block 1 與 block 2 相鄰、block 2
        // 的 isContinuation 為 true，但兩者 sourceParagraphIndex 不同——
        // 真正的 TextPreprocessor 不會產生這種資料（i 在每個新段落重置為
        // 0），但 group 計算不能只信任 isContinuation，必須自行核對
        // sourceParagraphIndex，否則任何上游資料異常都會把兩個獨立語意
        // 段落的縮排／間距錯誤地併成一個連續排版單位。
        final blocks = ChapterBlocks(
          chapterIndex: 0,
          title: '',
          displayText: '第一段第二段',
          contentHash: 'h',
          blocks: const <ChapterBlock>[
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 0),
              text: '第一段',
              charRange: HybridTextRange(0, 3),
              sourceParagraphIndex: 0,
            ),
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 1),
              text: '第二',
              charRange: HybridTextRange(3, 5),
              sourceParagraphIndex: 1,
              isContinuation: true,
            ),
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 2),
              text: '段',
              charRange: HybridTextRange(5, 6),
              sourceParagraphIndex: 1,
              isContinuation: true,
            ),
          ],
        );

        expect(
          blocks
              .groupContaining(const BlockKey(chapterIndex: 0, blockIndex: 0))
              .map((b) => b.blockIndex),
          <int>[0],
          reason: 'block 0 自成一組，不得因 block 1 的 isContinuation 併入',
        );
        expect(
          blocks
              .groupContaining(const BlockKey(chapterIndex: 0, blockIndex: 1))
              .map((b) => b.blockIndex),
          <int>[1, 2],
          reason: 'block 1/2 同 sourceParagraphIndex，應併成一組',
        );
        expect(
          blocks.paragraphGroups().map((g) => g.map((b) => b.blockIndex).toList()),
          <List<int>>[
            <int>[0],
            <int>[1, 2],
          ],
        );
      },
    );

    test(
      '真正不同 source paragraph 各自獨立排版：group 邊界對齊 '
      'sourceParagraphIndex 分界',
      () {
        // 三個真正獨立的來源段落，其中第二段被效能切塊（isContinuation
        // 串接），驗證 group 邊界precisely落在段落分界，不多不少。
        final blocks = ChapterBlocks(
          chapterIndex: 0,
          title: '書名',
          displayText: '書名\n\n段一\n\n段二上段二下\n\n段三',
          contentHash: 'h',
          blocks: const <ChapterBlock>[
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 0),
              text: '書名',
              charRange: HybridTextRange(0, 2),
              sourceParagraphIndex: -1,
              isTitle: true,
            ),
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 1),
              text: '段一',
              charRange: HybridTextRange(4, 6),
              sourceParagraphIndex: 0,
            ),
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 2),
              text: '段二上',
              charRange: HybridTextRange(8, 11),
              sourceParagraphIndex: 1,
            ),
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 3),
              text: '段二下',
              charRange: HybridTextRange(11, 14),
              sourceParagraphIndex: 1,
              isContinuation: true,
            ),
            ChapterBlock(
              key: BlockKey(chapterIndex: 0, blockIndex: 4),
              text: '段三',
              charRange: HybridTextRange(16, 18),
              sourceParagraphIndex: 2,
            ),
          ],
        );

        final groups = blocks.paragraphGroups();
        expect(
          groups.map((g) => g.map((b) => b.blockIndex).toList()),
          <List<int>>[
            <int>[0],
            <int>[1],
            <int>[2, 3],
            <int>[4],
          ],
          reason:
              '標題、段一、段三皆獨立成組（各自的縮排／段落間距不得被鄰組吃掉）；'
              '只有效能切塊的段二應併成一組',
        );
      },
    );
  });
}
