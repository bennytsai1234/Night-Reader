import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/pipeline/layout_pipeline.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/shared/widgets/skeleton_text.dart';

/// 一頁上每一行字的位置（viewport 座標，由上而下）、其中章名那幾行與
/// 插圖方塊的索引，與量這些行時的版面。紙上的骨架照它畫（ADR 0016、
/// 0024、0050）。
typedef PageLines = ({
  List<Rect> lines,
  Set<int> titleLines,
  Set<int> blockLines,
  ReaderV2LayoutSpec spec,
});

/// 捲動位置在 [offset]、正文區高 [height] 時，畫面上每一行字的位置與其中
/// 章名那幾行。
PageLines pageLinesAt({
  required HybridLayoutPipeline pipeline,
  required DocumentIndex documentIndex,
  required double offset,
  required double height,
}) {
  final lines = <Rect>[];
  final titleLines = <int>{};
  final blockLines = <int>{};
  final illustrations = <Rect>[];
  final ranges = <int, (int, int)>{};
  final spec = pipeline.layoutSpec;
  for (final key in documentIndex.keysInRange(offset, offset + height)) {
    final blocks = pipeline.blocksOf(key.chapterIndex);
    if (blocks == null) continue;
    final index = key.blockIndex;
    if (index < blocks.blocks.length && blocks.blocks[index].isIllustration) {
      // 插圖的骨架是和圖一樣大的方塊（docs/design/loading.md）。
      final top = documentIndex.topOf(key);
      final paint = pipeline.paragraphCache
          .acquireEntry(key, pipeline.epoch)
          ?.illustration;
      if (top != null && paint != null) {
        illustrations.add(
          paint.box.rect.shift(Offset(spec.textPaddingLeft, top - offset)),
        );
      }
      continue;
    }
    final range = blocks
        .blockForCharOffset(blocks.blockStartOffset(key))
        .charRange;
    final previous = ranges[key.chapterIndex];
    ranges[key.chapterIndex] = previous == null
        ? (range.start, range.end)
        : (
            math.min(previous.$1, range.start),
            math.max(previous.$2, range.end),
          );
  }
  final bodyStyle = readerSkeletonInkStyle(spec);
  void addLines(int chapter, int start, int end, {required bool title}) {
    if (end <= start) return;
    for (final box in pipeline.geometry.lineBoxes(chapter, start, end)) {
      if (box.bottom - offset <= 0 || box.top - offset >= height) continue;
      var line = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
      // 章名的字級與粗細不同，又很少以標點開頭結尾，照字框畫。
      if (!title) line = _inkLine(pipeline, chapter, line, bodyStyle, spec);
      if (title) titleLines.add(lines.length);
      lines.add(line.shift(Offset(0, -offset)));
    }
  }

  for (final MapEntry(key: chapter, value: (start, end)) in ranges.entries) {
    // 章名在一章的最前面，和正文不會在同一行。
    var titleEnd = 0;
    for (final block in pipeline.blocksOf(chapter)!.blocks) {
      if (!block.isTitle) break;
      titleEnd = block.charRange.end;
    }
    addLines(chapter, start, math.min(end, titleEnd), title: true);
    addLines(chapter, math.max(start, titleEnd), end, title: false);
  }
  for (final rect in illustrations) {
    if (rect.bottom <= 0 || rect.top >= height) continue;
    blockLines.add(lines.length);
    lines.add(rect);
  }
  return (
    lines: lines,
    titleLines: titleLines,
    blockLines: blockLines,
    // 行是這份排版管線排的；改排版的紙還在淡入時，它還是舊的那一代。
    spec: spec,
  );
}

/// 正文的字樣（標點字型在前，與段落排版相同），用來查標點的筆畫位置
/// （[PunctuationInk]）。
TextStyle readerSkeletonInkStyle(ReaderV2LayoutSpec spec) => TextStyle(
  fontFamily: kReaderV2PunctFontFamily,
  fontFamilyFallback: readerV2FontFallback(spec.style.fontFamily),
  fontWeight: spec.style.bold ? FontWeight.bold : FontWeight.normal,
  fontFeatures: kReaderV2CjkFontFeatures,
  locale: kReaderV2TextLocale,
);

/// 正文一行（正文座標）縮到行首、行尾標點的筆畫上（[skeletonInkLine]）：
/// 對話段落以「開頭、」結尾，句子停在行尾的「。」「，」。
Rect _inkLine(
  HybridLayoutPipeline pipeline,
  int chapter,
  Rect line,
  TextStyle style,
  ReaderV2LayoutSpec spec,
) {
  SkeletonGlyph? glyphAt(double x) {
    final hit = pipeline.geometry.glyphAt(Offset(x, line.center.dy));
    if (hit == null) return null;
    final text = hit.blocks.displayText;
    if (hit.offset < 0 || hit.offset >= text.length) return null;
    final mark = text[hit.offset];
    if (!PunctuationInk.marks.contains(mark)) return null;
    final boxes = pipeline.geometry.lineBoxes(
      chapter,
      hit.offset,
      hit.offset + 1,
    );
    if (boxes.isEmpty) return null;
    final box = boxes.first;
    return SkeletonGlyph(
      mark,
      Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      style: style,
      fontSize: spec.style.fontSize,
    );
  }

  return skeletonInkLine(
    line,
    first: glyphAt(line.left + 0.5),
    last: glyphAt(line.right - 0.5),
  );
}
