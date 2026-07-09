import 'dart:isolate';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class TextPreprocessor implements HybridTextPreprocessor {
  const TextPreprocessor({this.useIsolate = true});

  final bool useIsolate;

  @override
  Future<ChapterBlocks> process(
    ChapterText chapter, {
    int maxBlockChars = 1800,
  }) {
    final request = _PreprocessRequest(chapter, maxBlockChars);
    if (!useIsolate) {
      return Future<ChapterBlocks>.value(_processSync(request));
    }
    return Isolate.run(() => _processSync(request));
  }
}

final class _PreprocessRequest {
  const _PreprocessRequest(this.chapter, this.maxBlockChars);

  final ChapterText chapter;
  final int maxBlockChars;
}

ChapterBlocks _processSync(_PreprocessRequest request) {
  final chapter = request.chapter;
  final maxBlockChars =
      request.maxBlockChars <= 0 ? 1 << 30 : request.maxBlockChars;
  final blocks = <ChapterBlock>[];
  var blockIndex = 0;
  if (chapter.title.isNotEmpty) {
    blocks.add(
      ChapterBlock(
        key: BlockKey(chapterIndex: chapter.id, blockIndex: blockIndex),
        text: chapter.title,
        charRange: HybridTextRange(0, chapter.title.length),
        sourceParagraphIndex: -1,
        isTitle: true,
      ),
    );
    blockIndex += 1;
  }

  final bodyStartOffset =
      chapter.title.isEmpty
          ? 0
          : chapter.paragraphs.isEmpty
          ? chapter.title.length
          : chapter.title.length + 2;
  var paragraphOffset = bodyStartOffset;
  for (
    var paragraphIndex = 0;
    paragraphIndex < chapter.paragraphs.length;
    paragraphIndex += 1
  ) {
    final paragraph = chapter.paragraphs[paragraphIndex];
    final chunks = _splitParagraph(paragraph, maxBlockChars);
    var localOffset = 0;
    for (var i = 0; i < chunks.length; i += 1) {
      final chunk = chunks[i];
      final start = paragraphOffset + localOffset;
      final end = start + chunk.length;
      blocks.add(
        ChapterBlock(
          key: BlockKey(chapterIndex: chapter.id, blockIndex: blockIndex),
          text: chunk,
          charRange: HybridTextRange(start, end),
          sourceParagraphIndex: paragraphIndex,
          isContinuation: i > 0,
        ),
      );
      blockIndex += 1;
      localOffset += chunk.length;
    }
    paragraphOffset += paragraph.length + 2;
  }

  if (blocks.isEmpty) {
    blocks.add(
      ChapterBlock(
        key: BlockKey(chapterIndex: chapter.id, blockIndex: 0),
        text: '',
        charRange: const HybridTextRange(0, 0),
        sourceParagraphIndex: 0,
      ),
    );
  }

  return ChapterBlocks(
    chapterIndex: chapter.id,
    title: chapter.title,
    displayText: chapter.displayText,
    contentHash: chapter.contentHash,
    blocks: blocks,
  );
}

List<String> _splitParagraph(String paragraph, int maxBlockChars) {
  if (paragraph.length <= maxBlockChars) return <String>[paragraph];
  final chunks = <String>[];
  var start = 0;
  while (start < paragraph.length) {
    var end =
        (start + maxBlockChars).clamp(start + 1, paragraph.length).toInt();
    if (end < paragraph.length) {
      end = _findSentenceBoundary(paragraph, start, end) ?? end;
    }
    chunks.add(paragraph.substring(start, end));
    start = end;
  }
  return chunks;
}

int? _findSentenceBoundary(String text, int start, int preferredEnd) {
  const sentenceEndChars = '。！？!?；;';
  const sentenceCloseChars = '」』"\'）)》〉】]';
  for (var i = preferredEnd - 1; i > start; i -= 1) {
    if (!sentenceEndChars.contains(text[i])) continue;
    var end = i + 1;
    while (end < text.length && sentenceCloseChars.contains(text[end])) {
      end += 1;
    }
    return end;
  }
  return null;
}
