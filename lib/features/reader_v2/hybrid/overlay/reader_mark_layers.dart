import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/pipeline/layout_pipeline.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import 'bookmark_marks.dart';
import 'highlight_marks.dart';
import 'tts_highlight_overlay.dart';

/// 書籤記號、標註與朗讀高亮在 viewport 上的行框。
///
/// 書籤與標註的行框記在文件座標上（還沒扣捲動位置）：位置、那一章的正文
/// 與文件索引都沒變就沿用，捲動時每一幀只扣掉捲動位置，不重新照錨點找字、
/// 不查字形（幾何的行框只記最近一次，幾個書籤與朗讀高亮輪流查會互相擠掉）。
final class ReaderMarkGeometry {
  ReaderMarkGeometry({
    required this._pipeline,
    required this._documentIndex,
    required this._scrollOffset,
  });

  /// 目前排版世代的排版管線；換代時整份換新，所以每次都重新取。
  final HybridLayoutPipeline Function() _pipeline;
  final DocumentIndex _documentIndex;
  final double? Function() _scrollOffset;

  final Map<
    int,
    ({
      ReaderV2Location location,
      ChapterBlocks blocks,
      int revision,
      HybridLineBox box,
    })
  >
  _markBoxes = {};

  final Map<
    int,
    ({
      ReaderHighlightMark mark,
      ChapterBlocks blocks,
      int revision,
      HybridTextRange range,
      List<HybridLineBox> boxes,
    })
  >
  _highlightBoxes = {};

  /// 書籤那一行在 viewport 上的行框；那一章還沒排好的不畫。
  List<HybridLineBox> bookmarkLines(List<ReaderMark> marks) {
    final scroll = _scrollOffset();
    if (marks.isEmpty || scroll == null) return const <HybridLineBox>[];
    final pipeline = _pipeline();
    final revision = _documentIndex.revisionNumber;
    final lines = <HybridLineBox>[];
    final seen = <int>{};
    for (final (:id, :location) in marks) {
      seen.add(id);
      final blocks = pipeline.blocksOf(location.chapterIndex);
      if (blocks == null || blocks.displayText.isEmpty) continue;
      var cached = _markBoxes[id];
      if (cached == null ||
          !identical(cached.location, location) ||
          !identical(cached.blocks, blocks) ||
          cached.revision != revision) {
        final text = blocks.displayText;
        final offset = ReaderV2ContentLocationMapper.offsetIn(
          location: location,
          displayText: text,
          contentHash: blocks.contentHash,
        ).clamp(0, text.length - 1).toInt();
        final world = pipeline.geometry.lineBoxes(
          location.chapterIndex,
          offset,
          offset + 1,
        );
        // 那一段還沒排好：這次不畫、不記，排好後文件索引換版再算。
        if (world.isEmpty) continue;
        cached = (
          location: location,
          blocks: blocks,
          revision: revision,
          box: world.first,
        );
        _markBoxes[id] = cached;
      }
      lines.add(_scrolled(cached.box, scroll));
    }
    _markBoxes.removeWhere((id, _) => !seen.contains(id));
    return lines;
  }

  /// 標註在 viewport 上的字形範圍；那一章還沒排好的不畫。
  List<HighlightPaint> highlightPaints(List<ReaderHighlightMark> marks) {
    final scroll = _scrollOffset();
    if (marks.isEmpty || scroll == null) return const <HighlightPaint>[];
    final pipeline = _pipeline();
    final revision = _documentIndex.revisionNumber;
    final paints = <HighlightPaint>[];
    final seen = <int>{};
    for (final mark in marks) {
      seen.add(mark.id);
      final blocks = pipeline.blocksOf(mark.location.chapterIndex);
      if (blocks == null || blocks.displayText.isEmpty) continue;
      var cached = _highlightBoxes[mark.id];
      if (cached == null ||
          !identical(cached.mark.location, mark.location) ||
          cached.mark.length != mark.length ||
          !identical(cached.blocks, blocks) ||
          cached.revision != revision) {
        final range = _highlightRangeIn(mark, blocks);
        final world = pipeline.geometry.lineBoxes(
          mark.location.chapterIndex,
          range.start,
          range.end,
        );
        // 那一段還沒排好：這次不畫、不記，排好後文件索引換版再算。
        if (world.isEmpty) continue;
        cached = (
          mark: mark,
          blocks: blocks,
          revision: revision,
          range: range,
          boxes: world,
        );
        _highlightBoxes[mark.id] = cached;
      }
      paints.add((
        boxes: [for (final box in cached.boxes) _scrolled(box, scroll)],
        color: mark.color,
        style: mark.style,
      ));
    }
    _highlightBoxes.removeWhere((id, _) => !seen.contains(id));
    return paints;
  }

  /// viewport 上 [point] 點到的標註；同一個字有好幾個標註時取最後畫的。
  int? highlightAt(List<ReaderHighlightMark>? marks, Offset point) {
    final scroll = _scrollOffset();
    if (marks == null || marks.isEmpty || scroll == null) return null;
    final hit = _pipeline().geometry.glyphAt(point.translate(0, scroll));
    if (hit == null) return null;
    int? found;
    for (final mark in marks) {
      if (mark.location.chapterIndex != hit.blocks.chapterIndex) continue;
      final cached = _highlightBoxes[mark.id];
      final range =
          cached != null &&
              identical(cached.mark.location, mark.location) &&
              identical(cached.blocks, hit.blocks)
          ? cached.range
          : _highlightRangeIn(mark, hit.blocks);
      if (hit.offset >= range.start && hit.offset < range.end) {
        if (found == null || mark.id > found) found = mark.id;
      }
    }
    return found;
  }

  /// [start, end) 在 viewport 上的字形範圍，每條視覺行一個框（見
  /// [HybridTextGeometry.lineBoxes]）；每幀只扣掉捲動位置。
  List<HybridLineBox> lineBoxes(int chapterIndex, int start, int end) {
    final scroll = _scrollOffset();
    if (scroll == null) return const <HybridLineBox>[];
    return <HybridLineBox>[
      for (final box in _pipeline().geometry.lineBoxes(
        chapterIndex,
        start,
        end,
      ))
        _scrolled(box, scroll),
    ];
  }

  /// 標註在那一章正文裡的範圍：開頭照錨點找回（正文變了照前後原文），往
  /// 後畫記下的那麼長，不超出那一章。
  static HybridTextRange _highlightRangeIn(
    ReaderHighlightMark mark,
    ChapterBlocks blocks,
  ) {
    final text = blocks.displayText;
    final start = ReaderV2ContentLocationMapper.offsetIn(
      location: mark.location,
      displayText: text,
      contentHash: blocks.contentHash,
    ).clamp(0, text.length - 1).toInt();
    return HybridTextRange(
      start,
      math.min(text.length, start + math.max(1, mark.length)),
    );
  }

  static HybridLineBox _scrolled(HybridLineBox box, double scroll) =>
      HybridLineBox(
        left: box.left,
        top: box.top - scroll,
        right: box.right,
        bottom: box.bottom - scroll,
      );
}

/// 疊在正文上、跟著捲動的三層：標註、書籤記號、朗讀高亮（由下而上）。
/// 每一層只在有東西要畫時才跟著捲動每一幀重建。
final class ReaderMarkLayers extends StatelessWidget {
  const ReaderMarkLayers({
    super.key,
    required this.geometry,
    required this.scroll,
    required this.textLeft,
    required this.highlightColor,
    required this.highlightStrength,
    this.highlights,
    this.marks,
    this.ttsHighlight,
  });

  final ReaderMarkGeometry geometry;

  /// 正文的捲動；捲動時有東西要畫的層跟著重建。
  final Listenable scroll;

  /// 正文欄的左緣（viewport 座標），書籤記號畫在它左邊的邊距裡。
  final double textLeft;

  /// 書籤記號與朗讀高亮的顏色；[highlightStrength] 只套在朗讀高亮。
  final Color highlightColor;
  final double highlightStrength;
  final ValueListenable<List<ReaderHighlightMark>>? highlights;
  final ValueListenable<List<ReaderMark>>? marks;
  final ReaderV2TtsHighlight? ttsHighlight;

  @override
  Widget build(BuildContext context) {
    final tts = ttsHighlight;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (highlights case final highlights?)
          Positioned.fill(
            // 標註只畫在正文可視區內（同朗讀高亮）。
            child: ClipRect(
              child: ValueListenableBuilder(
                valueListenable: highlights,
                builder: (context, items, _) => items.isEmpty
                    ? const SizedBox.shrink()
                    : ListenableBuilder(
                        listenable: scroll,
                        builder: (context, _) {
                          final paints = geometry.highlightPaints(items);
                          if (paints.isEmpty) return const SizedBox.shrink();
                          return HighlightMarksOverlay(items: paints);
                        },
                      ),
              ),
            ),
          ),
        if (marks case final marks?)
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: marks,
              builder: (context, items, _) => items.isEmpty
                  ? const SizedBox.shrink()
                  : ListenableBuilder(
                      listenable: scroll,
                      builder: (context, _) {
                        final lines = geometry.bookmarkLines(items);
                        if (lines.isEmpty) return const SizedBox.shrink();
                        return BookmarkMarksOverlay(
                          lines: lines,
                          textLeft: textLeft,
                          color: highlightColor,
                        );
                      },
                    ),
            ),
          ),
        if (tts != null && tts.isValid)
          Positioned.fill(
            // 朗讀高亮只畫在正文可視區內，捲到邊緣的句子不會在邊距與頁尾區
            // 留下沒有字的色帶。
            child: ClipRect(
              child: ListenableBuilder(
                listenable: scroll,
                builder: (context, _) => HybridTtsHighlightOverlay(
                  sentence: geometry.lineBoxes(
                    tts.chapterIndex,
                    tts.sentenceStart,
                    tts.sentenceEnd,
                  ),
                  color: highlightColor.withValues(alpha: highlightStrength),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
