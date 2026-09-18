import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/chapter_layout_plan.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

void main() {
  test('raw text can be released and rebound without changing admitted segmentation', () {
    final source = ChapterBlocks(
      chapterIndex: 2,
      title: '',
      displayText: 'abcdefgh',
      contentHash: 'content-v1',
      blocks: const [
        ChapterBlock(
          key: BlockKey(chapterIndex: 2, blockIndex: 0),
          text: 'abc',
          charRange: HybridTextRange(0, 3),
          sourceParagraphIndex: 0,
        ),
        ChapterBlock(
          key: BlockKey(chapterIndex: 2, blockIndex: 1),
          text: 'defgh',
          charRange: HybridTextRange(3, 8),
          sourceParagraphIndex: 0,
          isContinuation: true,
          layoutBreakBefore: true,
        ),
      ],
    );
    final plan = ChapterLayoutPlan(source);
    final restored = plan.materialize(
      ChapterText(
        id: 2,
        title: '',
        paragraphs: ['abcdefgh'],
        displayText: 'abcdefgh',
        contentHash: 'content-v1',
      ),
    )!;
    expect(restored.layoutIdentity, source.layoutIdentity);
    expect(restored.blocks.map((b) => b.text), ['abc', 'defgh']);
    expect(restored.paragraphGroups().length, 2);
    expect(
      plan.materialize(
        ChapterText(
          id: 2,
          title: '',
          paragraphs: ['changed!'],
          displayText: 'changed!',
          contentHash: 'content-v2',
        ),
      ),
      isNull,
    );
    expect(
      plan.materialize(
        ChapterText(
          id: 2,
          title: '',
          paragraphs: ['short'],
          displayText: 'short',
          contentHash: 'content-v1',
        ),
      ),
      isNull,
    );
  });
}
