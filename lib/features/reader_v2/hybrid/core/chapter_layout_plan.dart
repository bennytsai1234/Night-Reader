import 'hybrid_types.dart';

/// Text-free segmentation owned by the active document, not the raw cache.
/// Reloading evicted text must reuse these exact boundaries: a newer cost-model
/// estimate is not permission to reinterpret an already admitted BlockKey.
final class ChapterLayoutPlan {
  ChapterLayoutPlan(ChapterBlocks source)
    : chapterIndex = source.chapterIndex,
      contentHash = source.contentHash,
      textLength = source.displayText.length,
      layoutIdentity = source.layoutIdentity,
      _spans = [
        for (final block in source.blocks)
          (
            range: block.charRange,
            sourceParagraph: block.sourceParagraphIndex,
            isTitle: block.isTitle,
            isContinuation: block.isContinuation,
            layoutBreakBefore: block.layoutBreakBefore,
          ),
      ];

  final int chapterIndex;
  final String contentHash;
  final int textLength;
  final String layoutIdentity;
  final List<
    ({
      HybridTextRange range,
      int sourceParagraph,
      bool isTitle,
      bool isContinuation,
      bool layoutBreakBefore,
    })
  >
  _spans;

  ChapterBlocks materialize(ChapterText text) {
    if (text.id != chapterIndex ||
        text.contentHash != contentHash ||
        text.displayText.length != textLength) {
      throw StateError(
        'ChapterLayoutPlan content identity changed inside one document '
        'generation: expected chapter=$chapterIndex hash=$contentHash '
        'length=$textLength, actual chapter=${text.id} '
        'hash=${text.contentHash} length=${text.displayText.length}.',
      );
    }
    return ChapterBlocks(
      chapterIndex: chapterIndex,
      title: text.title,
      displayText: text.displayText,
      contentHash: contentHash,
      blocks: [
        for (var i = 0; i < _spans.length; i += 1)
          ChapterBlock(
            key: BlockKey(chapterIndex: chapterIndex, blockIndex: i),
            text: _spans[i].isTitle
                ? text.title
                : text.displayText.substring(
                    _spans[i].range.start,
                    _spans[i].range.end,
                  ),
            charRange: _spans[i].range,
            sourceParagraphIndex: _spans[i].sourceParagraph,
            isTitle: _spans[i].isTitle,
            isContinuation: _spans[i].isContinuation,
            layoutBreakBefore: _spans[i].layoutBreakBefore,
          ),
      ],
    );
  }
}
