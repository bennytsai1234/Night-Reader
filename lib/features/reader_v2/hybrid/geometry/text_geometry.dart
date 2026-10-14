import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import '../core/hybrid_types.dart';
import '../measure/document_index.dart';
import '../overlay/selection_service.dart';
import '../paragraph/paragraph_cache.dart';

/// 段首縮排的字數；標題與接續上一個 block 的段落不縮排。
int hybridIndentCharsFor(ChapterBlock block, ReaderV2LayoutSpec spec) {
  if (block.isTitle || block.isContinuation) return 0;
  return spec.style.textIndent.clamp(0, 8).toInt();
}

typedef _LineBoxMemo = ({
  ChapterBlocks blocks,
  HybridTextRange range,
  int revision,
  List<HybridLineBox> boxes,
});

/// 章內文字 offset 與正文座標之間的換算：朗讀高亮與選字反白的框、長按
/// 點到的字、拖把手的游標、閱讀位置與還原的捲動位置。
///
/// 座標都是正文座標（文件索引的 y，x 從 viewport 左緣起算）；換成
/// viewport 座標時由呼叫端扣掉捲動位置。一份只對應一個排版世代：
/// [epoch] 與 [paragraphCache] 換代時重建。段落還沒排好時查不到，回傳
/// null 或空清單。
final class HybridTextGeometry {
  HybridTextGeometry({
    required this._paragraphCache,
    required this._epoch,
    required this._documentIndex,
    required this._blocksOf,
    required this._layoutSpec,
  });

  final ParagraphCache _paragraphCache;
  final LayoutEpoch _epoch;
  final DocumentIndex _documentIndex;
  final ChapterBlocks? Function(int chapterIndex) _blocksOf;
  final ReaderV2LayoutSpec Function() _layoutSpec;
  _LineBoxMemo? _lineBoxMemo;

  /// 選取是否還對得上畫面：章節重新切分、換內容或樣式換代後，舊 offset
  /// 不再對應畫面。
  bool isSelectionCurrent(ReaderTextSelection selection) =>
      selection.epoch == _epoch &&
      identical(_blocksOf(selection.chapterIndex), selection.blocks);

  /// [start, end) 在正文上的字形範圍，每條視覺行一個框。
  ///
  /// 框的左右取自 Paragraph 的 glyph boxes，而不是整行寬：句段從行中間
  /// 開始或結束時，只標出屬於它的字，不波及同一行的其他句子。朗讀高亮
  /// 與選字反白在捲動時每幀都要畫，所以文件索引與這段文字都沒變時沿用
  /// 上次的結果；有 block 還沒排好時不記，下次再算。
  List<HybridLineBox> lineBoxes(int chapterIndex, int start, int end) {
    final blocks = _blocksOf(chapterIndex);
    if (blocks == null) return const <HybridLineBox>[];
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    if (range.isEmpty) return const <HybridLineBox>[];
    final memo = _lineBoxMemo;
    if (memo != null &&
        identical(memo.blocks, blocks) &&
        memo.range == range &&
        memo.revision == _documentIndex.revisionNumber) {
      return memo.boxes;
    }
    final paintLeft = _layoutSpec().textPaddingLeft;
    final result = <HybridLineBox>[];
    var complete = true;
    final blockList = blocks.blocks;
    var low = 0;
    var high = blockList.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (blockList[middle].charRange.end <= range.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < blockList.length; index += 1) {
      final block = blockList[index];
      if (block.charRange.start >= range.end) break;
      if (!block.charRange.intersects(range)) continue;
      final top = _documentIndex.topOf(block.key);
      final boxes = top == null
          ? null
          : _blockLocalBoxesForRange(blocks, block, range);
      if (top == null || boxes == null) {
        complete = false;
        continue;
      }
      for (final box in boxes) {
        final lineBox = HybridLineBox(
          left: paintLeft + box.left,
          top: top + box.top,
          right: paintLeft + box.right,
          bottom: top + box.bottom,
        );
        // block 可以切在行中，同一條視覺行會由前後兩個 block 各給一段；
        // 框已夾在各自的行格內、不同行不會重疊，所以垂直有交集就是同
        // 一行；併成一個框，避免半透明色在接縫處疊深。
        final previous = result.isEmpty ? null : result.last;
        if (previous != null &&
            math.min(previous.bottom, lineBox.bottom) -
                    math.max(previous.top, lineBox.top) >
                0.5) {
          result[result.length - 1] = HybridLineBox(
            left: math.min(previous.left, lineBox.left),
            top: math.min(previous.top, lineBox.top),
            right: math.max(previous.right, lineBox.right),
            bottom: math.max(previous.bottom, lineBox.bottom),
          );
        } else {
          result.add(lineBox);
        }
      }
    }
    _lineBoxMemo = complete
        ? (
            blocks: blocks,
            range: range,
            revision: _documentIndex.revisionNumber,
            boxes: result,
          )
        : null;
    return result;
  }

  /// [start, end) 在正文上佔的上下範圍；左右不用，固定為 0。範圍內的
  /// block 都還沒進文件索引時回傳 null。
  Rect? rangeRect(ChapterBlocks blocks, int start, int end) {
    double? top;
    double? bottom;
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    for (final block in blocks.blocks) {
      if (!block.charRange.intersects(range) &&
          !(range.isEmpty && block.charRange.containsOffset(range.start))) {
        continue;
      }
      final blockTop = _documentIndex.topOf(block.key);
      if (blockTop == null) continue;
      double localTop = 0;
      double localBottom = _documentIndex.metricsFor(block.key)?.height ?? 0;
      final boxes = _blockLocalBoxesForRange(blocks, block, range);
      if (boxes != null && boxes.isNotEmpty) {
        localTop = boxes.first.top;
        localBottom = boxes
            .map((box) => box.bottom)
            .reduce(math.max)
            .toDouble();
      }
      final rangeTop = blockTop + localTop;
      final rangeBottom = blockTop + localBottom;
      top = top == null ? rangeTop : math.min(top, rangeTop);
      bottom = bottom == null ? rangeBottom : math.max(bottom, rangeBottom);
    }
    if (top == null || bottom == null) return null;
    return Rect.fromLTRB(0, top, 0, bottom);
  }

  /// 讓 [anchor] 那個字所在的行落在 viewport 的 [anchorLine] 時的捲動位置。
  /// 段落還沒排好時以 block 頂端代替那一行；block 還沒進文件索引時回傳
  /// null。
  double? scrollOffsetForAnchor(
    HybridAnchor anchor,
    ChapterBlocks blocks, {
    required double anchorLine,
  }) {
    final resolved = _visualPositionForChar(blocks, anchor.charOffsetInChapter);
    final key = resolved?.key ?? anchor.blockKey;
    final top = _documentIndex.topOf(key);
    if (top == null) return null;
    final lineTop = resolved?.localTop ?? 0.0;
    return top + lineTop - anchorLine + anchor.visualOffsetPx;
  }

  /// [hit] 那一行的閱讀位置：行首的字，加上 [worldY] 與行頂的距離。
  /// 段落還沒排好時取 block 的第一個字。
  ReaderV2Location? locationAt(
    DocumentOffsetHit hit, {
    required double worldY,
    required int chapterCount,
  }) {
    final blocks = _blocksOf(hit.key.chapterIndex);
    if (blocks == null || hit.key.blockIndex >= blocks.blocks.length) {
      return null;
    }
    final block = blocks.blocks[hit.key.blockIndex];
    var lineTop = 0.0;
    var charOffset = block.charRange.start;
    final entry = _paragraphCache.acquireEntry(hit.key, _epoch);
    if (entry != null) {
      final paragraph = entry.paragraph;
      final line = _lineAt(paragraph, hit.offsetInBlock + entry.localTop);
      if (line != null) {
        final group = blocks.groupContaining(hit.key);
        final textMap = ParagraphTextMap.forBlocks(
          group,
          indentLength: hybridIndentCharsFor(group.first, _layoutSpec()),
        );
        final position = paragraph.getPositionForOffset(
          Offset(0, line.top + 0.1),
        );
        final boxTop = _textBoxTopForOffset(
          paragraph,
          position.offset,
          textMap.paragraphLength,
        );
        lineTop = (boxTop ?? line.top) - entry.localTop;
        final groupStart = group.first.charRange.start;
        final groupEnd = group.last.charRange.end;
        charOffset =
            (groupStart +
                    textMap.sourceOffsetForParagraphOffset(position.offset))
                .clamp(groupStart, groupEnd)
                .toInt();
      }
    }
    final visual = (worldY - (hit.blockTop + lineTop))
        .clamp(
          ReaderV2Location.minVisualOffsetPx,
          ReaderV2Location.maxVisualOffsetPx,
        )
        .toDouble();
    return ReaderV2Location(
          chapterIndex: hit.key.chapterIndex,
          charOffset: charOffset,
          visualOffsetPx: visual,
        )
        .normalized(
          chapterCount: chapterCount,
          chapterLength: blocks.displayText.length,
        )
        .withContentIdentity(
          contentHash: blocks.contentHash,
          displayText: blocks.displayText,
        );
  }

  /// 長按點到的字：只接受真的落在字形上的點，縮排、段距、行尾空白與
  /// 標題都不算。回傳章內 offset 與它所屬的來源段落。
  ({ChapterBlocks blocks, HybridTextRange paragraph, int offset})? glyphAt(
    Offset point,
  ) {
    final hit = _documentIndex.hitTest(point.dy);
    if (hit == null) return null;
    final blocks = _blocksOf(hit.key.chapterIndex);
    if (blocks == null) return null;
    final paragraphRange = blocks.sourceParagraphRange(hit.key);
    if (paragraphRange == null) return null;
    final at = _paragraphPointAt(blocks, hit, point.dx);
    if (at == null) return null;
    final position = at.paragraph.getPositionForOffset(at.local);
    final candidate = position.affinity == TextAffinity.downstream
        ? position.offset
        : position.offset - 1;
    // 縮排、插入的換行與補白都不是字。
    if (candidate >= at.textMap.paragraphLength ||
        at.textMap.isInsertedParagraphOffset(candidate)) {
      return null;
    }
    final onGlyph = at.paragraph
        .getBoxesForRange(candidate, candidate + 1)
        .any((box) => box.toRect().inflate(4).contains(at.local));
    if (!onGlyph) return null;
    final offset =
        at.groupStart + at.textMap.sourceOffsetForParagraphOffset(candidate);
    if (!paragraphRange.containsOffset(offset)) return null;
    return (blocks: blocks, paragraph: paragraphRange, offset: offset);
  }

  /// 拖把手時 [point] 在選取段落內最近的游標位置；點超出段落上下緣時
  /// 夾回段落內，所以不會換到別段。
  int? caretAt(ReaderTextSelection selection, Offset point) {
    if (!isSelectionCurrent(selection)) return null;
    final blocks = selection.blocks;
    final first = blocks.blockForCharOffset(selection.paragraph.start);
    final last = blocks.blockForCharOffset(selection.paragraph.end - 1);
    final top = _documentIndex.topOf(first.key);
    final lastTop = _documentIndex.topOf(last.key);
    final lastHeight = _documentIndex.metricsFor(last.key)?.height;
    if (top == null || lastTop == null || lastHeight == null) return null;
    final bottom = math.max(top, lastTop + lastHeight - 0.5);
    final worldY = point.dy.clamp(top, bottom).toDouble();
    final hit = _documentIndex.hitTest(worldY);
    if (hit == null) return null;
    final at = _paragraphPointAt(blocks, hit, point.dx);
    if (at == null) return null;
    final position = at.paragraph.getPositionForOffset(at.local);
    return at.groupStart +
        at.textMap.sourceOffsetForParagraphOffset(position.offset);
  }

  ({BlockKey key, double localTop})? _visualPositionForChar(
    ChapterBlocks blocks,
    int charOffsetInChapter,
  ) {
    final rawBlock = blocks.blockForCharOffset(charOffsetInChapter);
    final group = blocks.groupContaining(rawBlock.key);
    if (group.isEmpty) return null;
    final head = group.first;
    final rawEntry = _paragraphCache.acquireEntry(rawBlock.key, _epoch);
    if (rawEntry == null) return null;
    final textMap = ParagraphTextMap.forBlocks(
      group,
      indentLength: hybridIndentCharsFor(head, _layoutSpec()),
    );
    final sourceLocalOffset = (charOffsetInChapter - head.charRange.start)
        .clamp(0, textMap.sourceLength)
        .toInt();
    final groupLocalOffset = textMap.paragraphOffsetForSourceOffset(
      sourceLocalOffset,
    );
    final paragraphY =
        _textBoxTopForOffset(
          rawEntry.paragraph,
          groupLocalOffset,
          textMap.paragraphLength,
        ) ??
        0.0;
    var owningKey = rawBlock.key;
    var owningLocalTop = rawEntry.localTop;
    for (final member in group) {
      final memberEntry = _paragraphCache.acquireEntry(member.key, _epoch);
      if (memberEntry == null) continue;
      if (memberEntry.localTop <= paragraphY + 0.001) {
        owningKey = member.key;
        owningLocalTop = memberEntry.localTop;
      } else {
        break;
      }
    }
    return (key: owningKey, localTop: paragraphY - owningLocalTop);
  }

  List<ui.TextBox>? _blockLocalBoxesForRange(
    ChapterBlocks blocks,
    ChapterBlock block,
    HybridTextRange range,
  ) {
    final entry = _paragraphCache.acquireEntry(block.key, _epoch);
    if (entry == null) return null;
    final group = blocks.groupContaining(block.key);
    if (group.isEmpty) return null;
    final groupStart = group.first.charRange.start;
    final sourceStart = math.max(range.start, block.charRange.start);
    final sourceEnd = math.min(range.end, block.charRange.end);
    if (sourceEnd <= sourceStart) return const <ui.TextBox>[];
    // Paragraph 內除了縮排 placeholder，還有排版插入的換行；兩者都要
    // 經 ParagraphTextMap 換算，否則框會在每個插入換行之後偏一個字。
    final local =
        ParagraphTextMap.forBlocks(
          group,
          indentLength: hybridIndentCharsFor(group.first, _layoutSpec()),
        ).paragraphRangeForSourceRange(
          sourceStart - groupStart,
          sourceEnd - groupStart,
        );
    final boxes = _boxesPerLine(
      entry.paragraph,
      entry.paragraph.getBoxesForRange(local.start, local.end),
    );
    if (boxes.isEmpty) return boxes;
    return <ui.TextBox>[
      for (final box in boxes)
        ui.TextBox.fromLTRBD(
          box.left,
          box.top - entry.localTop,
          box.right,
          box.bottom - entry.localTop,
          box.direction,
        ),
    ];
  }

  /// [point] 在 [hit] 所屬 group Paragraph 上的位置；同時回傳 Paragraph
  /// 內座標與 offset 換算表。
  ({
    ui.Paragraph paragraph,
    Offset local,
    ParagraphTextMap textMap,
    int groupStart,
  })?
  _paragraphPointAt(ChapterBlocks blocks, DocumentOffsetHit hit, double x) {
    final entry = _paragraphCache.acquireEntry(hit.key, _epoch);
    if (entry == null) return null;
    final group = blocks.groupContaining(hit.key);
    if (group.isEmpty) return null;
    final spec = _layoutSpec();
    return (
      paragraph: entry.paragraph,
      local: Offset(
        x - spec.textPaddingLeft,
        hit.offsetInBlock + entry.localTop,
      ),
      textMap: ParagraphTextMap.forBlocks(
        group,
        indentLength: hybridIndentCharsFor(group.first, spec),
      ),
      groupStart: group.first.charRange.start,
    );
  }

  /// 每條視覺行併成一個框，垂直方向夾在該行的行格內。
  ///
  /// Paragraph 回傳的 glyph box 高度是字型自身的 ascent + descent
  /// （Noto Sans CJK 約 1.45 em），不隨行高倍率縮放：行高設得比這小時，
  /// 相鄰兩行的框會疊進對方；同一行裡不同字型的 run（中文、拉丁字、
  /// 數字）高度也各不相同。以行格為界，上下兩行的框恰好相接。
  static List<ui.TextBox> _boxesPerLine(
    ui.Paragraph paragraph,
    List<ui.TextBox> boxes,
  ) {
    if (boxes.isEmpty) return boxes;
    final lines = <int, ui.TextBox>{};
    for (final box in boxes) {
      final glyph = paragraph.getClosestGlyphInfoForOffset(
        Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
      );
      final lineNumber = glyph == null
          ? null
          : paragraph.getLineNumberAt(glyph.graphemeClusterCodeUnitRange.start);
      if (lineNumber == null) continue;
      final existing = lines[lineNumber];
      lines[lineNumber] = existing == null
          ? box
          : ui.TextBox.fromLTRBD(
              math.min(existing.left, box.left),
              math.min(existing.top, box.top),
              math.max(existing.right, box.right),
              math.max(existing.bottom, box.bottom),
              box.direction,
            );
    }
    final result = <ui.TextBox>[];
    for (final MapEntry(key: lineNumber, value: box) in lines.entries) {
      final line = paragraph.getLineMetricsAt(lineNumber);
      if (line == null) {
        result.add(box);
        continue;
      }
      final slotTop = line.baseline - line.ascent;
      var slotBottom = slotTop + line.height;
      final next = paragraph.getLineMetricsAt(lineNumber + 1);
      if (next != null) {
        slotBottom = math.min(slotBottom, next.baseline - next.ascent);
      }
      result.add(
        ui.TextBox.fromLTRBD(
          box.left,
          math.max(box.top, slotTop),
          box.right,
          math.min(box.bottom, slotBottom),
          box.direction,
        ),
      );
    }
    return result;
  }

  static ({double top, double bottom})? _lineAt(
    ui.Paragraph paragraph,
    double dy,
  ) {
    final lineCount = paragraph.numberOfLines;
    if (lineCount <= 0) return null;
    final position = paragraph.getPositionForOffset(Offset(0, dy));
    final lineNumber =
        (paragraph.getLineNumberAt(math.max(0, position.offset)) ??
                lineCount - 1)
            .clamp(0, lineCount - 1)
            .toInt();
    final line = paragraph.getLineMetricsAt(lineNumber);
    if (line == null) return null;
    final lineTop = line.baseline - line.ascent;
    return (top: lineTop, bottom: lineTop + line.height);
  }

  static double? _textBoxTopForOffset(
    ui.Paragraph paragraph,
    int textOffset,
    int textLength,
  ) {
    if (textLength <= 0) return 0.0;
    final safeOffset = textOffset.clamp(0, textLength).toInt();
    final start = safeOffset >= textLength ? textLength - 1 : safeOffset;
    final boxes = paragraph.getBoxesForRange(start, start + 1);
    if (boxes.isEmpty) return null;
    return boxes.first.top;
  }
}
