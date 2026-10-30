import 'dart:convert';
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

typedef ChapterId = int;

enum HybridScrollDirection { forward, backward }

/// [loading]：視口只顯示載入畫面、沒有正文可掉幀，排版可用滿整幀。
enum PumpState { idle, dragging, ballistic, rebuilding, loading }

enum ChapterEventKind { loaded, evicted, invalidated }

enum LayoutTaskPriority { anchor, visible, prefetch }

final class BlockKey implements Comparable<BlockKey> {
  const BlockKey({required this.chapterIndex, required this.blockIndex})
    : assert(chapterIndex >= 0),
      assert(blockIndex >= 0);

  final int chapterIndex;
  final int blockIndex;

  @override
  int compareTo(BlockKey other) {
    final chapterOrder = chapterIndex.compareTo(other.chapterIndex);
    if (chapterOrder != 0) return chapterOrder;
    return blockIndex.compareTo(other.blockIndex);
  }

  bool operator <(BlockKey other) => compareTo(other) < 0;
  bool operator <=(BlockKey other) => compareTo(other) <= 0;
  bool operator >(BlockKey other) => compareTo(other) > 0;
  bool operator >=(BlockKey other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    return other is BlockKey &&
        other.chapterIndex == chapterIndex &&
        other.blockIndex == blockIndex;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, blockIndex);

  @override
  String toString() {
    return 'BlockKey(chapterIndex: $chapterIndex, blockIndex: $blockIndex)';
  }
}

final class LayoutEpoch {
  const LayoutEpoch(this.value, {this.contentGeneration = 0})
    : assert(value >= 0),
      assert(contentGeneration >= 0);

  static const LayoutEpoch initial = LayoutEpoch(0);

  /// Layout-spec generation published by Runtime.
  final int value;

  /// Semantic content generation published by Runtime.
  ///
  /// Paragraphs and measurements belong to the pair, not to layout style
  /// alone: equal geometry with different text is still a different document.
  final int contentGeneration;

  LayoutEpoch next() =>
      LayoutEpoch(value + 1, contentGeneration: contentGeneration);

  bool isCurrent(LayoutEpoch current) => this == current;

  @override
  bool operator ==(Object other) {
    return other is LayoutEpoch &&
        other.value == value &&
        other.contentGeneration == contentGeneration;
  }

  @override
  int get hashCode => Object.hash(value, contentGeneration);

  @override
  String toString() => 'LayoutEpoch(layout=$value, content=$contentGeneration)';
}

final class StyleFingerprint {
  const StyleFingerprint({
    required this.contentWidth,
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.paragraphSpacing,
    this.chapterSpacing = 1.0,
    required this.textIndent,
    required this.bold,
    required this.textScaleFactor,
    required this.fontFamilySignature,
    required this.platformFontSignature,
    this.cellWidth,
    this.typographyFeatureSignature = kReaderV2CjkTypographyFeatureSignature,
    this.titleFontSize = 0,
    this.titleSpacing = 0,
  });

  factory StyleFingerprint.fromLayoutSpec(
    ReaderV2LayoutSpec spec, {
    double textScaleFactor = 1.0,
    String fontFamilySignature = 'system',
    String platformFontSignature = 'unknown',
  }) {
    final style = spec.style;
    return StyleFingerprint(
      contentWidth: spec.textLayoutFrame.width,
      cellWidth: spec.cellWidth,
      fontSize: style.fontSize,
      lineHeight: style.lineHeight,
      letterSpacing: style.letterSpacing,
      paragraphSpacing: style.paragraphSpacing,
      chapterSpacing: style.chapterSpacing,
      textIndent: style.textIndent,
      bold: style.bold,
      textScaleFactor: textScaleFactor,
      fontFamilySignature: fontFamilySignature,
      platformFontSignature: platformFontSignature,
      titleFontSize: style.titleFontSize,
      titleSpacing: style.titleSpacing,
    );
  }

  /// Only inputs that can change paragraph measurement belong here.
  ///
  /// Viewport height, top/bottom insets and paint offsets are intentionally
  /// excluded so transient system chrome cannot poison the measurement cache.
  final double contentWidth;
  final double? cellWidth;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double paragraphSpacing;

  /// 章末 block 的量測高度含章節間距，必須進入快取鍵。
  final double chapterSpacing;
  final int textIndent;
  final bool bold;
  final double textScaleFactor;
  final String fontFamilySignature;
  final String platformFontSignature;
  final String typographyFeatureSignature;

  /// 標題 block 的量測高度取決於標題字號，必須進入快取鍵。
  final double titleFontSize;

  /// 標題 block 的量測高度含標題間距，必須進入快取鍵。
  final double titleSpacing;

  int get stableHash => Object.hash(
    contentWidth,
    cellWidth,
    fontSize,
    lineHeight,
    letterSpacing,
    paragraphSpacing,
    chapterSpacing,
    textIndent,
    bold,
    textScaleFactor,
    fontFamilySignature,
    platformFontSignature,
    typographyFeatureSignature,
    titleFontSize,
    titleSpacing,
  );

  String get stableKey => jsonEncode(<Object?>[
    contentWidth,
    cellWidth,
    fontSize,
    lineHeight,
    letterSpacing,
    paragraphSpacing,
    chapterSpacing,
    textIndent,
    bold,
    textScaleFactor,
    fontFamilySignature,
    platformFontSignature,
    typographyFeatureSignature,
    titleFontSize,
    titleSpacing,
  ]);

  @override
  bool operator ==(Object other) {
    return other is StyleFingerprint &&
        other.contentWidth == contentWidth &&
        other.cellWidth == cellWidth &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight &&
        other.letterSpacing == letterSpacing &&
        other.paragraphSpacing == paragraphSpacing &&
        other.chapterSpacing == chapterSpacing &&
        other.textIndent == textIndent &&
        other.bold == bold &&
        other.textScaleFactor == textScaleFactor &&
        other.fontFamilySignature == fontFamilySignature &&
        other.platformFontSignature == platformFontSignature &&
        other.typographyFeatureSignature == typographyFeatureSignature &&
        other.titleFontSize == titleFontSize &&
        other.titleSpacing == titleSpacing;
  }

  @override
  int get hashCode => stableHash;

  @override
  String toString() => 'StyleFingerprint($stableHash)';
}

final class MeasurementNamespace {
  const MeasurementNamespace({required this.epoch, required this.fingerprint});

  final LayoutEpoch epoch;
  final StyleFingerprint fingerprint;

  @override
  bool operator ==(Object other) {
    return other is MeasurementNamespace &&
        other.epoch == epoch &&
        other.fingerprint == fingerprint;
  }

  @override
  int get hashCode => Object.hash(epoch, fingerprint);
}

final class BlockMetrics {
  const BlockMetrics({required this.height, required this.lineCount})
    : assert(height > 0),
      assert(lineCount >= 0);

  final double height;
  final int lineCount;

  @override
  bool operator ==(Object other) {
    return other is BlockMetrics &&
        other.height == height &&
        other.lineCount == lineCount;
  }

  @override
  int get hashCode => Object.hash(height, lineCount);
}

final class HybridTextRange {
  const HybridTextRange(this.start, this.end)
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool get isEmpty => start == end;

  bool containsOffset(int offset) => offset >= start && offset < end;

  bool intersects(HybridTextRange other) {
    return start < other.end && other.start < end;
  }

  @override
  bool operator ==(Object other) {
    return other is HybridTextRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

final class BlockRange {
  const BlockRange({required this.first, required this.last});

  final BlockKey first;
  final BlockKey last;

  bool contains(BlockKey key) => first <= key && key <= last;
}

/// 視覺行內的補白：英數字段補到半格時，插在 [offset] 那個字之前、寬
/// [width] 的空白。[offset] 是來源文字內的 UTF-16 位置，不會落在行首或
/// 行尾（行首不補左側、行尾不補右側）。
final class LineSpacer {
  const LineSpacer(this.offset, this.width);

  final int offset;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is LineSpacer && other.offset == offset && other.width == width;

  @override
  int get hashCode => Object.hash(offset, width);

  @override
  String toString() => 'LineSpacer($offset, $width)';
}

final class ChapterBlock {
  const ChapterBlock({
    required this.key,
    required this.text,
    required this.charRange,
    required this.sourceParagraphIndex,
    this.isTitle = false,
    this.isContinuation = false,
    this.layoutBreakBefore = false,
    this.visualLineBreakOffsets = const <int>[],
    this.visualLineSpacers = const <LineSpacer>[],
  });

  final BlockKey key;
  final String text;
  final HybridTextRange charRange;
  final int sourceParagraphIndex;
  final bool isTitle;

  /// Semantic paragraph identity. A continuation still belongs to the same
  /// source paragraph and therefore gets no paragraph spacing/indent.
  final bool isContinuation;

  /// True only when this continuation begins at a reader-owned visual line
  /// boundary. The boundary is part of the active layout plan, not a
  /// preprocessing hint.
  final bool layoutBreakBefore;

  /// Source-relative UTF-16 offsets where a new reader-owned visual line
  /// begins inside this block. These are layout metadata only; source text is
  /// never modified with synthetic newlines.
  final List<int> visualLineBreakOffsets;

  /// 視覺行內的補白（見 [LineSpacer]），offset 相對於本塊文字，遞增排列。
  final List<LineSpacer> visualLineSpacers;

  int get chapterIndex => key.chapterIndex;
  int get blockIndex => key.blockIndex;
}

final class ChapterBlocks {
  ChapterBlocks({
    required this.chapterIndex,
    required this.title,
    required this.displayText,
    required this.contentHash,
    required List<ChapterBlock> blocks,
  }) : blocks = List<ChapterBlock>.unmodifiable(blocks) {
    assert(blocks.isNotEmpty);
    assert(blocks.every((block) => block.chapterIndex == chapterIndex));
    assert(() {
      for (var i = 1; i < blocks.length; i += 1) {
        if (blocks[i - 1].key >= blocks[i].key) return false;
      }
      return true;
    }(), 'ChapterBlocks must be sorted by BlockKey');
  }

  final int chapterIndex;
  final String title;
  final String displayText;
  final String contentHash;
  final List<ChapterBlock> blocks;

  late final String layoutIdentity = jsonEncode([
    contentHash,
    title,
    for (final block in blocks)
      [
        block.blockIndex,
        block.charRange.start,
        block.charRange.end,
        block.sourceParagraphIndex,
        block.isTitle,
        block.isContinuation,
        block.layoutBreakBefore,
        block.visualLineBreakOffsets,
        [
          for (final spacer in block.visualLineSpacers)
            [spacer.offset, spacer.width],
        ],
      ],
  ]);

  ChapterBlock blockForCharOffset(int charOffset) {
    final safeOffset = charOffset.clamp(0, displayText.length).toInt();
    for (final block in blocks) {
      if (block.charRange.containsOffset(safeOffset)) return block;
      if (safeOffset < block.charRange.start) return block;
    }
    return blocks.last;
  }

  HybridAnchor anchorForCharOffset(int charOffset) {
    final block = blockForCharOffset(charOffset);
    return HybridAnchor(
      chapterIndex: chapterIndex,
      blockIndex: block.blockIndex,
      charOffsetInChapter: charOffset.clamp(0, displayText.length).toInt(),
    );
  }

  int blockStartOffset(BlockKey key) {
    return blocks[_indexOf(key)].charRange.start;
  }

  /// 區塊照 blockIndex 排在清單的同一個位置，先直接取；對不上才逐一找。
  /// 閱讀器每次要排的視窗都會對範圍內每個區塊查一次，逐一找在長章節裡
  /// 會變成平方成長（跳章時一次卡上 40 毫秒）。
  int _indexOf(BlockKey key) {
    final direct = key.blockIndex;
    if (direct < blocks.length && blocks[direct].key == key) return direct;
    return blocks.indexWhere((block) => block.key == key);
  }

  /// Returns the blocks that still require one continuous ui.Paragraph. Raw
  /// preprocessing chunks remain grouped until the reader-owned line planner
  /// produces authoritative transaction boundaries.
  List<ChapterBlock> groupContaining(BlockKey key) {
    final index = _indexOf(key);
    if (index < 0) return const <ChapterBlock>[];
    final sourceParagraphIndex = blocks[index].sourceParagraphIndex;
    var start = index;
    while (start > 0 &&
        blocks[start].isContinuation &&
        !blocks[start].layoutBreakBefore &&
        blocks[start - 1].sourceParagraphIndex == sourceParagraphIndex) {
      start -= 1;
    }
    var end = index;
    while (end + 1 < blocks.length &&
        blocks[end + 1].isContinuation &&
        !blocks[end + 1].layoutBreakBefore &&
        blocks[end + 1].sourceParagraphIndex == sourceParagraphIndex) {
      end += 1;
    }
    return blocks.sublist(start, end + 1);
  }

  /// [key] 所屬來源段落在章內的字元範圍；長段落即使被拆成多個 group 也
  /// 回傳整段。標題不屬於任何來源段落，回傳 null。
  HybridTextRange? sourceParagraphRange(BlockKey key) {
    final index = blocks.indexWhere((block) => block.key == key);
    if (index < 0) return null;
    final block = blocks[index];
    if (block.isTitle || block.sourceParagraphIndex < 0) return null;
    final sourceParagraphIndex = block.sourceParagraphIndex;
    var start = index;
    while (start > 0 &&
        blocks[start - 1].sourceParagraphIndex == sourceParagraphIndex) {
      start -= 1;
    }
    var end = index;
    while (end + 1 < blocks.length &&
        blocks[end + 1].sourceParagraphIndex == sourceParagraphIndex) {
      end += 1;
    }
    return HybridTextRange(
      blocks[start].charRange.start,
      blocks[end].charRange.end,
    );
  }

  List<List<ChapterBlock>> paragraphGroups() {
    final groups = <List<ChapterBlock>>[];
    var i = 0;
    while (i < blocks.length) {
      final sourceParagraphIndex = blocks[i].sourceParagraphIndex;
      var j = i + 1;
      while (j < blocks.length &&
          blocks[j].isContinuation &&
          !blocks[j].layoutBreakBefore &&
          blocks[j].sourceParagraphIndex == sourceParagraphIndex) {
        j += 1;
      }
      groups.add(blocks.sublist(i, j));
      i = j;
    }
    return groups;
  }
}

/// 來源文字與 Paragraph 文字之間的位置換算。
///
/// Paragraph 文字 = 縮排 placeholder + 來源文字，再在視覺行邊界插入換行、
/// 在補白處插入寬度固定的 placeholder。插入的換行與補白都屬於它後面那個
/// 字，各佔一個 UTF-16 位置。
final class ParagraphTextMap {
  ParagraphTextMap({
    required this.sourceLength,
    required this.indentLength,
    List<int> visualLineBreakOffsets = const <int>[],
    List<LineSpacer> spacers = const <LineSpacer>[],
  }) : visualLineBreakOffsets = List<int>.unmodifiable(visualLineBreakOffsets),
       spacers = List<LineSpacer>.unmodifiable(spacers) {
    var previous = 0;
    for (final offset in this.visualLineBreakOffsets) {
      if (offset <= previous || offset >= sourceLength) {
        throw StateError(
          'Visual line breaks must be strictly increasing source offsets '
          'inside the block: offset=$offset sourceLength=$sourceLength.',
        );
      }
      previous = offset;
    }
    final breaks = this.visualLineBreakOffsets.toSet();
    previous = 0;
    for (final spacer in this.spacers) {
      if (spacer.offset <= previous ||
          spacer.offset >= sourceLength ||
          breaks.contains(spacer.offset) ||
          !spacer.width.isFinite ||
          spacer.width <= 0) {
        throw StateError(
          'Line spacers must be strictly increasing, positive-width and '
          'never on a line boundary: $spacer sourceLength=$sourceLength.',
        );
      }
      previous = spacer.offset;
    }
    _inserted = <int>[
      ...this.visualLineBreakOffsets,
      for (final spacer in this.spacers) spacer.offset,
    ]..sort();
  }

  factory ParagraphTextMap.forBlocks(
    List<ChapterBlock> blocks, {
    required int indentLength,
  }) {
    var sourceLength = 0;
    final breaks = <int>[];
    final spacers = <LineSpacer>[];
    for (final block in blocks) {
      for (final offset in block.visualLineBreakOffsets) {
        breaks.add(sourceLength + offset);
      }
      for (final spacer in block.visualLineSpacers) {
        spacers.add(LineSpacer(sourceLength + spacer.offset, spacer.width));
      }
      sourceLength += block.text.length;
    }
    return ParagraphTextMap(
      sourceLength: sourceLength,
      indentLength: indentLength,
      visualLineBreakOffsets: breaks,
      spacers: spacers,
    );
  }

  final int sourceLength;
  final int indentLength;
  final List<int> visualLineBreakOffsets;
  final List<LineSpacer> spacers;

  /// 換行與補白的來源位置，遞增排列。
  late final List<int> _inserted;

  int get paragraphLength => indentLength + sourceLength + _inserted.length;

  int paragraphOffsetForSourceOffset(int sourceOffset) {
    final safe = sourceOffset.clamp(0, sourceLength).toInt();
    var inserted = 0;
    for (final offset in _inserted) {
      if (offset > safe) break;
      inserted += 1;
    }
    return indentLength + safe + inserted;
  }

  /// 來源範圍 [start, end) 在 Paragraph 內的範圍。插入的換行與補白屬於它
  /// 後面那個字；範圍恰好結束在插入處時，插入的那一格不包進來。
  ({int start, int end}) paragraphRangeForSourceRange(int start, int end) {
    final paragraphStart = paragraphOffsetForSourceOffset(start);
    if (end <= start) return (start: paragraphStart, end: paragraphStart);
    return (
      start: paragraphStart,
      end: paragraphOffsetForSourceOffset(end - 1) + 1,
    );
  }

  int sourceOffsetForParagraphOffset(int paragraphOffset) {
    final safe = paragraphOffset.clamp(0, paragraphLength).toInt();
    if (safe <= indentLength) return 0;
    final bodyOffset = safe - indentLength;
    var insertedBefore = 0;
    for (var i = 0; i < _inserted.length; i += 1) {
      final insertedOffset = _inserted[i] + i;
      if (insertedOffset >= bodyOffset) break;
      insertedBefore += 1;
    }
    return (bodyOffset - insertedBefore).clamp(0, sourceLength).toInt();
  }

  /// [paragraphOffset] 是縮排、插入的換行或補白，不是來源文字。
  bool isInsertedParagraphOffset(int paragraphOffset) {
    if (paragraphOffset < indentLength) return true;
    final bodyOffset = paragraphOffset - indentLength;
    for (var i = 0; i < _inserted.length; i += 1) {
      final insertedOffset = _inserted[i] + i;
      if (insertedOffset == bodyOffset) return true;
      if (insertedOffset > bodyOffset) break;
    }
    return false;
  }

  /// 依序列出 Paragraph 本文（縮排之後）的各段：來源文字、換行與補白
  /// （[ParagraphPiece.spacerWidth]）。
  List<ParagraphPiece> pieces(String sourceText) {
    if (sourceText.length != sourceLength) {
      throw StateError(
        'ParagraphTextMap source length mismatch: expected=$sourceLength '
        'actual=${sourceText.length}.',
      );
    }
    final spacerWidths = {
      for (final spacer in spacers) spacer.offset: spacer.width,
    };
    final result = <ParagraphPiece>[];
    var cursor = 0;
    for (final offset in _inserted) {
      if (offset > cursor) {
        result.add(ParagraphPiece.text(sourceText.substring(cursor, offset)));
      }
      final width = spacerWidths[offset];
      result.add(
        width == null
            ? const ParagraphPiece.text('\n')
            : ParagraphPiece.spacer(width),
      );
      cursor = offset;
    }
    if (cursor < sourceText.length) {
      result.add(ParagraphPiece.text(sourceText.substring(cursor)));
    }
    return result;
  }
}

/// [ParagraphTextMap.pieces] 的一段：文字或補白其中之一。
final class ParagraphPiece {
  const ParagraphPiece.text(String this.text) : spacerWidth = null;
  const ParagraphPiece.spacer(double this.spacerWidth) : text = null;

  final String? text;
  final double? spacerWidth;
}

final class HybridAnchor {
  const HybridAnchor({
    required this.chapterIndex,
    required this.blockIndex,
    required this.charOffsetInChapter,
    this.visualOffsetPx = 0.0,
  }) : assert(chapterIndex >= 0),
       assert(blockIndex >= 0),
       assert(charOffsetInChapter >= 0);

  factory HybridAnchor.fromLocation(
    ReaderV2Location location,
    ChapterBlocks blocks,
  ) {
    final normalized = location.normalized(
      chapterLength: blocks.displayText.length,
    );
    final block = blocks.blockForCharOffset(normalized.charOffset);
    return HybridAnchor(
      chapterIndex: normalized.chapterIndex,
      blockIndex: block.blockIndex,
      charOffsetInChapter: normalized.charOffset,
      visualOffsetPx: normalized.visualOffsetPx,
    );
  }

  final int chapterIndex;
  final int blockIndex;
  final int charOffsetInChapter;
  final double visualOffsetPx;

  BlockKey get blockKey {
    return BlockKey(chapterIndex: chapterIndex, blockIndex: blockIndex);
  }

  ReaderV2Location toLocation({int? chapterLength}) {
    return ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: charOffsetInChapter,
      visualOffsetPx: visualOffsetPx,
    ).normalized(chapterLength: chapterLength);
  }
}

final class ChapterText {
  ChapterText({
    required this.id,
    required this.title,
    required List<String> paragraphs,
    required this.displayText,
    required this.contentHash,
  }) : paragraphs = List<String>.unmodifiable(paragraphs);

  final ChapterId id;
  final String title;
  final List<String> paragraphs;
  final String displayText;
  final String contentHash;
}

final class ChapterEvent {
  const ChapterEvent({
    required this.kind,
    required this.chapterId,
    this.contentHash,
  });

  const ChapterEvent.loaded({
    required ChapterId chapterId,
    required String contentHash,
  }) : this(
         kind: ChapterEventKind.loaded,
         chapterId: chapterId,
         contentHash: contentHash,
       );

  const ChapterEvent.evicted({required ChapterId chapterId})
    : this(kind: ChapterEventKind.evicted, chapterId: chapterId);

  const ChapterEvent.invalidated({required ChapterId chapterId})
    : this(kind: ChapterEventKind.invalidated, chapterId: chapterId);

  final ChapterEventKind kind;
  final ChapterId chapterId;
  final String? contentHash;
}

final class HybridBlockTextStyle {
  const HybridBlockTextStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    this.bold = false,
  });

  factory HybridBlockTextStyle.fromLayoutStyle(
    ReaderV2LayoutStyle style, {
    bool isTitle = false,
  }) {
    return HybridBlockTextStyle(
      fontSize: isTitle ? style.titleFontSize : style.fontSize,
      lineHeight: style.effectiveLineHeight,
      letterSpacing: style.letterSpacing,
      bold: isTitle || style.bold,
    );
  }

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final bool bold;
}

final class LayoutTask {
  LayoutTask({
    required this.block,
    this.continuationBlocks = const <ChapterBlock>[],
    required this.epoch,
    required this.fingerprint,
    required this.textStyle,
    required this.contentWidth,
    this.textColor = const ui.Color(0xFF000000),
    this.priority = LayoutTaskPriority.prefetch,
    this.direction = HybridScrollDirection.forward,
    this.indentChars = 0,
    this.trailingSpacing = 0.0,
    this.trailingLayoutLookahead = '',
    this.cellWidth,
    this.readerOwnedLinePlan = false,
  }) : assert(indentChars >= 0),
       assert(trailingSpacing >= 0),
       assert(cellWidth == null || cellWidth > 0),
       assert(
         !readerOwnedLinePlan || trailingLayoutLookahead.isEmpty,
         'Reader-owned line plans cannot expose following-line context.',
       );

  final ChapterBlock block;
  final List<ChapterBlock> continuationBlocks;

  List<ChapterBlock> get groupBlocks => continuationBlocks.isEmpty
      ? <ChapterBlock>[block]
      : <ChapterBlock>[block, ...continuationBlocks];

  late final String combinedText = _buildCombinedText();

  String _buildCombinedText() {
    if (continuationBlocks.isEmpty) return block.text;
    final buffer = StringBuffer(block.text);
    for (final continuation in continuationBlocks) {
      buffer.write(continuation.text);
    }
    return buffer.toString();
  }

  /// Legacy cross-transaction shaping context. Reader-owned line plans keep
  /// this empty: exposing the following rune would hand soft-wrap policy back
  /// to SkParagraph.
  final String trailingLayoutLookahead;

  late final String layoutText = trailingLayoutLookahead.isEmpty
      ? combinedText
      : '$combinedText$trailingLayoutLookahead';

  final LayoutEpoch epoch;
  final StyleFingerprint fingerprint;
  final HybridBlockTextStyle textStyle;
  final double contentWidth;
  final ui.Color textColor;
  final LayoutTaskPriority priority;
  final HybridScrollDirection direction;
  final int indentChars;
  final double trailingSpacing;
  final double? cellWidth;

  /// The block already carries authoritative visual-line boundaries. Native
  /// Paragraph layout may shape and paint them but may not choose new breaks.
  final bool readerOwnedLinePlan;

  BlockKey get key => block.key;
}

final class BlockReady {
  const BlockReady({
    required this.key,
    required this.epoch,
    required this.metrics,
  });

  final BlockKey key;
  final LayoutEpoch epoch;
  final BlockMetrics metrics;
}

/// 一段文字在畫面上一條視覺行內實際佔據的範圍（viewport 座標）。
final class HybridLineBox {
  const HybridLineBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(bottom >= top),
       assert(right >= left);

  final double left;
  final double top;
  final double right;
  final double bottom;
}
