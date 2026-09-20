import 'dart:convert';
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

typedef ChapterId = int;

enum HybridScrollDirection { forward, backward }

enum PumpState { idle, dragging, ballistic, rebuilding }

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
  String toString() =>
      'LayoutEpoch(layout=$value, content=$contentGeneration)';
}

final class StyleFingerprint {
  const StyleFingerprint({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.contentWidth,
    required this.contentHeight,
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.paragraphSpacing,
    required this.paddingTop,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.paddingRight,
    required this.textIndent,
    required this.bold,
    required this.justify,
    required this.textScaleFactor,
    required this.fontFamilySignature,
    required this.platformFontSignature,
    this.typographyFeatureSignature = kReaderV2CjkTypographyFeatureSignature,
    this.lastLineSpacingCompensation = false,
  });

  factory StyleFingerprint.fromLayoutSpec(
    ReaderV2LayoutSpec spec, {
    bool justify = true,
    double textScaleFactor = 1.0,
    String fontFamilySignature = 'system',
    String platformFontSignature = 'unknown',
  }) {
    final style = spec.style;
    return StyleFingerprint(
      viewportWidth: spec.viewportSize.width,
      viewportHeight: spec.viewportSize.height,
      contentWidth: spec.contentWidth,
      contentHeight: spec.contentHeight,
      fontSize: style.fontSize,
      lineHeight: style.lineHeight,
      letterSpacing: style.letterSpacing,
      paragraphSpacing: style.paragraphSpacing,
      paddingTop: style.paddingTop,
      paddingBottom: style.paddingBottom,
      paddingLeft: style.paddingLeft,
      paddingRight: style.paddingRight,
      textIndent: style.textIndent,
      bold: style.bold,
      justify: justify,
      textScaleFactor: textScaleFactor,
      fontFamilySignature: fontFamilySignature,
      platformFontSignature: platformFontSignature,
      lastLineSpacingCompensation: style.lastLineSpacingCompensation,
    );
  }

  final double viewportWidth;
  final double viewportHeight;
  final double contentWidth;
  final double contentHeight;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double paragraphSpacing;
  final double paddingTop;
  final double paddingBottom;
  final double paddingLeft;
  final double paddingRight;
  final int textIndent;
  final bool bold;
  final bool justify;
  final double textScaleFactor;
  final String fontFamilySignature;
  final String platformFontSignature;
  final String typographyFeatureSignature;
  final bool lastLineSpacingCompensation;

  int get stableHash => Object.hash(
    viewportWidth,
    viewportHeight,
    contentWidth,
    contentHeight,
    fontSize,
    lineHeight,
    letterSpacing,
    paragraphSpacing,
    paddingTop,
    paddingBottom,
    paddingLeft,
    paddingRight,
    textIndent,
    bold,
    justify,
    textScaleFactor,
    fontFamilySignature,
    platformFontSignature,
    typographyFeatureSignature,
    lastLineSpacingCompensation,
  );

  String get stableKey => jsonEncode(<Object>[
    viewportWidth,
    viewportHeight,
    contentWidth,
    contentHeight,
    fontSize,
    lineHeight,
    letterSpacing,
    paragraphSpacing,
    paddingTop,
    paddingBottom,
    paddingLeft,
    paddingRight,
    textIndent,
    bold,
    justify,
    textScaleFactor,
    fontFamilySignature,
    platformFontSignature,
    typographyFeatureSignature,
    lastLineSpacingCompensation,
  ]);

  @override
  bool operator ==(Object other) {
    return other is StyleFingerprint &&
        other.viewportWidth == viewportWidth &&
        other.viewportHeight == viewportHeight &&
        other.contentWidth == contentWidth &&
        other.contentHeight == contentHeight &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight &&
        other.letterSpacing == letterSpacing &&
        other.paragraphSpacing == paragraphSpacing &&
        other.paddingTop == paddingTop &&
        other.paddingBottom == paddingBottom &&
        other.paddingLeft == paddingLeft &&
        other.paddingRight == paddingRight &&
        other.textIndent == textIndent &&
        other.bold == bold &&
        other.justify == justify &&
        other.textScaleFactor == textScaleFactor &&
        other.fontFamilySignature == fontFamilySignature &&
        other.platformFontSignature == platformFontSignature &&
        other.typographyFeatureSignature == typographyFeatureSignature &&
        other.lastLineSpacingCompensation == lastLineSpacingCompensation;
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

final class ChapterBlock {
  const ChapterBlock({
    required this.key,
    required this.text,
    required this.charRange,
    required this.sourceParagraphIndex,
    this.isTitle = false,
    this.isContinuation = false,
    this.layoutBreakBefore = false,
  });

  final BlockKey key;
  final String text;
  final HybridTextRange charRange;
  final int sourceParagraphIndex;
  final bool isTitle;

  /// Semantic paragraph identity. A continuation still belongs to the same
  /// source paragraph and therefore gets no paragraph spacing/indent.
  final bool isContinuation;

  /// True only when this continuation begins at a visual line boundary that
  /// was measured with the current layout style. Unlike an arbitrary
  /// preprocessing chunk, this boundary may safely start a new ui.Paragraph
  /// transaction without introducing a new visible line break.
  final bool layoutBreakBefore;

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
    final block = blocks.firstWhere((item) => item.key == key);
    return block.charRange.start;
  }

  /// Returns the blocks that still require one continuous ui.Paragraph. An
  /// arbitrary preprocessor chunk remains grouped; a measured visual-line
  /// boundary starts a new layout transaction while keeping semantic
  /// continuation metadata intact.
  List<ChapterBlock> groupContaining(BlockKey key) {
    final index = blocks.indexWhere((block) => block.key == key);
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
    this.textAlign = ui.TextAlign.start,
  });

  factory HybridBlockTextStyle.fromLayoutStyle(
    ReaderV2LayoutStyle style, {
    bool isTitle = false,
    bool justify = true,
  }) {
    return HybridBlockTextStyle(
      fontSize: isTitle ? style.fontSize + 4 : style.fontSize,
      lineHeight: style.effectiveLineHeight,
      letterSpacing: style.letterSpacing,
      bold: isTitle || style.bold,
      textAlign: justify ? ui.TextAlign.justify : ui.TextAlign.start,
    );
  }

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final bool bold;
  final ui.TextAlign textAlign;
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
  }) : assert(indentChars >= 0),
       assert(trailingSpacing >= 0),
       assert(cellWidth == null || cellWidth > 0);

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

  /// A visual-line-aligned non-final transaction lays out one following rune
  /// only as context. The render object clips that following line; it exists so
  /// justify/shaping semantics of the visible last line match the unsplit
  /// paragraph rather than treating every transaction as a paragraph end.
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

final class HybridLineBox {
  const HybridLineBox({
    required this.key,
    required this.top,
    required this.bottom,
    required this.charRange,
  }) : assert(bottom >= top);

  final BlockKey key;
  final double top;
  final double bottom;
  final HybridTextRange charRange;
}
