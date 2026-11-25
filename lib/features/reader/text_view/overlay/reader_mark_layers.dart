import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/widgets.dart';

import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_highlight.dart';
import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/text_view/measure/document_index.dart';
import 'package:night_reader/features/reader/text_view/pipeline/layout_pipeline.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';

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
    required this._viewportHeight,
  });

  /// 目前排版世代的排版管線；換代時整份換新，所以每次都重新取。
  final LayoutPipeline Function() _pipeline;
  final DocumentIndex _documentIndex;
  final double? Function() _scrollOffset;
  final double Function() _viewportHeight;

  final Map<
    int,
    ({ReaderLocation location, ChapterBlocks blocks, int revision, LineBox box})
  >
  _markBoxes = {};

  final Map<
    int,
    ({
      ReaderHighlightMark mark,
      ChapterBlocks blocks,
      int revision,
      ChapterTextRange range,
      List<LineBox> boxes,
      bool complete,
    })
  >
  _highlightBoxes = {};

  /// 書籤那一行在 viewport 上的行框；那一章還沒排好的不畫。
  List<LineBox> bookmarkLines(List<ReaderMark> marks) {
    final scroll = _scrollOffset();
    if (marks.isEmpty || scroll == null) return const <LineBox>[];
    final pipeline = _pipeline();
    final revision = _documentIndex.revisionNumber;
    final lines = <LineBox>[];
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
        final offset = ReaderContentLocationMapper.offsetIn(
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
        final range = highlightRangeIn(mark, blocks);
        final world = range == null
            ? null
            : pipeline.geometry.lineBoxesChecked(
                mark.location.chapterIndex,
                range.start,
                range.end,
              );
        // 那一段還沒排好：這次不畫、不記，排好後文件索引換版再算。
        if (world != null && world.boxes.isEmpty) continue;
        // 那一章找不到原文的也記下（空的範圍），同一份正文不再每幀找一次。
        cached = (
          mark: mark,
          blocks: blocks,
          revision: revision,
          range: range ?? const ChapterTextRange(0, 0),
          boxes: world?.boxes ?? const <LineBox>[],
          complete: world?.complete ?? true,
        );
        _highlightBoxes[mark.id] = cached;
      }
      if (cached.range.isEmpty) continue;
      // 跨好幾屏的標註有幾段的排版不在手上（畫面外丟掉了）時，記下的框
      // 缺了那幾段；每幀只算畫面上看得到的那一段，捲回來的段落照樣畫到。
      // 排齊的照記下的框，只畫畫面上的那幾行。
      final bottom = scroll + _viewportHeight();
      final boxes = cached.complete
          ? cached.boxes.where((box) => box.bottom > scroll && box.top < bottom)
          : pipeline.geometry.lineBoxesWithin(
              mark.location.chapterIndex,
              cached.range.start,
              cached.range.end,
              top: scroll,
              bottom: bottom,
            );
      paints.add((
        boxes: [for (final box in boxes) _scrolled(box, scroll)],
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
          : highlightRangeIn(mark, hit.blocks);
      if (range != null && range.containsOffset(hit.offset)) {
        if (found == null || mark.id > found) found = mark.id;
      }
    }
    return found;
  }

  /// [start, end) 在 viewport 上的字形範圍，每條視覺行一個框（見
  /// [TextGeometry.lineBoxes]）；每幀只扣掉捲動位置。
  List<LineBox> lineBoxes(int chapterIndex, int start, int end) {
    final scroll = _scrollOffset();
    if (scroll == null) return const <LineBox>[];
    return <LineBox>[
      for (final box in _pipeline().geometry.lineBoxes(
        chapterIndex,
        start,
        end,
      ))
        _scrolled(box, scroll),
    ];
  }

  /// 標註在那一章正文裡的範圍：開頭照錨點找回（正文變了照前後原文），往
  /// 後數記下的那麼多個字，段落分隔不算（分段和畫的時候不同也畫到同一段
  /// 字的結尾），不超出那一章。沒有錨點的照記下的原文核對，見
  /// [_unanchoredRangeIn]；那一章找不到原文時是 null，不畫。
  @visibleForTesting
  static ChapterTextRange? highlightRangeIn(
    ReaderHighlightMark mark,
    ChapterBlocks blocks,
  ) {
    final text = blocks.displayText;
    final start = ReaderContentLocationMapper.offsetIn(
      location: mark.location,
      displayText: text,
      contentHash: blocks.contentHash,
    ).clamp(0, text.length - 1).toInt();
    if (mark.unanchoredQuote case final quote?) {
      return _unanchoredRangeIn(text, quote, near: start);
    }
    var end = start;
    var remaining = math.max(1, mark.length);
    while (end < text.length && remaining > 0) {
      if (text.codeUnitAt(end) != 0x0A) remaining--;
      end++;
    }
    return ChapterTextRange(start, end);
  }

  /// 沒有錨點的標註（從 Legado 的備份轉來的）：Legado 記的位置算進章名與
  /// 段首縮排、正文也可能和這台不同（替換規則、書源），原文更可能被讀者
  /// 在 Legado 的書籤裡改過，所以記下的位置不一定就是 [quote]。在那一章
  /// 找 [quote]，空白與換行不算（Legado 選到的字含段首縮排），取離記下的
  /// 位置 [near] 最近的一處（位置上就是原文時就是那裡）；找不到是 null。
  ///
  /// 正文照閱讀設定的繁簡轉換顯示，原文是 Legado 畫面上的寫法：[quote]
  /// 原樣、簡轉繁、繁轉簡（和正文同一套轉換）各找一次，讀者怎麼切換都
  /// 對得上。找的是畫面上的正文，轉換後字數變了也不用換算位置。
  static ChapterTextRange? _unanchoredRangeIn(
    String text,
    String quote, {
    required int near,
  }) {
    final wanted = {
      for (final convertType in const [0, 1, 2])
        String.fromCharCodes(
          _converter
              .convert(quote, convertType: convertType)
              .codeUnits
              .where((unit) => !_isBlank(unit)),
        ),
    }..remove('');
    if (wanted.isEmpty) return null;
    // 去掉空白後的正文，記下每個字在原本正文裡的位置。
    final kept = <int>[];
    final positions = <int>[];
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (_isBlank(unit)) continue;
      kept.add(unit);
      positions.add(i);
    }
    final haystack = String.fromCharCodes(kept);
    ChapterTextRange? best;
    var bestDistance = 0;
    for (final words in wanted) {
      for (
        var at = haystack.indexOf(words);
        at >= 0;
        at = haystack.indexOf(words, at + 1)
      ) {
        final start = positions[at];
        final distance = (start - near).abs();
        if (best == null || distance < bestDistance) {
          best = ChapterTextRange(start, positions[at + words.length - 1] + 1);
          bestDistance = distance;
        }
      }
    }
    return best;
  }

  static const ChineseTextConverter _converter = ChineseTextConverter();

  /// 空白與換行，含全形空白（段首縮排）。
  static bool _isBlank(int unit) =>
      unit <= 0x20 ||
      unit == 0xA0 ||
      unit == 0x3000 ||
      unit == 0xFEFF ||
      (unit >= 0x2000 && unit <= 0x200B);

  static LineBox _scrolled(LineBox box, double scroll) => LineBox(
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
  final ReaderTtsHighlight? ttsHighlight;

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
                builder: (context, _) => TtsHighlightOverlay(
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
