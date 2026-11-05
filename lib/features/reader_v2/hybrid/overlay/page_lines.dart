import 'dart:math' as math;
import 'dart:ui';

import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/pipeline/layout_pipeline.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

/// 一頁上每一行字的位置（viewport 座標，由上而下）、其中章名那幾行的
/// 索引，與量這些行時的版面。紙上的骨架照它畫（ADR 0016、0024）。
typedef PageLines = ({
  List<Rect> lines,
  Set<int> titleLines,
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
  final ranges = <int, (int, int)>{};
  for (final key in documentIndex.keysInRange(offset, offset + height)) {
    final blocks = pipeline.blocksOf(key.chapterIndex);
    if (blocks == null) continue;
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
  void addLines(int chapter, int start, int end, {required bool title}) {
    if (end <= start) return;
    for (final box in pipeline.geometry.lineBoxes(chapter, start, end)) {
      final top = box.top - offset;
      final bottom = box.bottom - offset;
      if (bottom <= 0 || top >= height) continue;
      if (title) titleLines.add(lines.length);
      lines.add(Rect.fromLTRB(box.left, top, box.right, bottom));
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
  return (
    lines: lines,
    titleLines: titleLines,
    // 行是這份排版管線排的；改排版的紙還在淡入時，它還是舊的那一代。
    spec: pipeline.layoutSpec,
  );
}
