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

/// 一章的語義段落：標題（`paragraph == -1`，範圍在標題內）與各正文段落
/// （範圍在 displayText 內）。沒有標題也沒有正文時是一個空段落。
typedef ChapterSegment = ({int start, int end, int paragraph, bool isTitle});

List<ChapterSegment> chapterSegmentsOf(ChapterText chapter) {
  final segments = <ChapterSegment>[
    if (chapter.title.isNotEmpty)
      (start: 0, end: chapter.title.length, paragraph: -1, isTitle: true),
  ];
  final bodyStartOffset = chapter.title.isEmpty
      ? 0
      : chapter.paragraphs.isEmpty
      ? chapter.title.length
      : chapter.title.length + 2;
  var paragraphOffset = bodyStartOffset;
  for (var i = 0; i < chapter.paragraphs.length; i += 1) {
    final length = chapter.paragraphs[i].length;
    segments.add((
      start: paragraphOffset,
      end: paragraphOffset + length,
      paragraph: i,
      isTitle: false,
    ));
    paragraphOffset += length + 2;
  }
  if (segments.isEmpty) {
    segments.add((start: 0, end: 0, paragraph: 0, isTitle: false));
  }
  return segments;
}

ChapterBlocks _processSync(_PreprocessRequest request) {
  final chapter = request.chapter;
  final maxBlockChars = request.maxBlockChars <= 0
      ? 1 << 30
      : request.maxBlockChars;
  final blocks = <ChapterBlock>[];
  for (final segment in chapterSegmentsOf(chapter)) {
    final source = segment.isTitle
        ? chapter.title
        : chapter.paragraphs.isEmpty
        ? ''
        : chapter.paragraphs[segment.paragraph];
    // 標題不切塊；正文段落依預算切成首尾相接的 continuation。
    final chunks = segment.isTitle || source.isEmpty
        ? <String>[source]
        : _splitParagraph(source, maxBlockChars);
    var start = segment.start;
    for (var i = 0; i < chunks.length; i += 1) {
      final end = start + chunks[i].length;
      blocks.add(
        ChapterBlock(
          key: BlockKey(chapterIndex: chapter.id, blockIndex: blocks.length),
          text: chunks[i],
          charRange: HybridTextRange(start, end),
          sourceParagraphIndex: segment.paragraph,
          isTitle: segment.isTitle,
          isContinuation: i > 0,
        ),
      );
      start = end;
    }
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
    var end = (start + maxBlockChars)
        .clamp(start + 1, paragraph.length)
        .toInt();
    if (end < paragraph.length) {
      end =
          _findSentenceBoundary(paragraph, start, end) ??
          _safeUtf16Boundary(paragraph, end);
    }
    chunks.add(paragraph.substring(start, end));
    start = end;
  }
  return chunks;
}

int _safeUtf16Boundary(String text, int boundary) {
  if (boundary <= 0 || boundary >= text.length) return boundary;
  final previous = text.codeUnitAt(boundary - 1);
  final next = text.codeUnitAt(boundary);
  final splitsSurrogatePair =
      previous >= 0xD800 &&
      previous <= 0xDBFF &&
      next >= 0xDC00 &&
      next <= 0xDFFF;
  return splitsSurrogatePair ? boundary + 1 : boundary;
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
