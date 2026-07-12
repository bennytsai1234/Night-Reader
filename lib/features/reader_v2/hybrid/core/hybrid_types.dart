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
  const LayoutEpoch(this.value) : assert(value >= 0);

  static const LayoutEpoch initial = LayoutEpoch(0);

  final int value;

  LayoutEpoch next() => LayoutEpoch(value + 1);

  bool isCurrent(LayoutEpoch current) => this == current;

  @override
  bool operator ==(Object other) {
    return other is LayoutEpoch && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LayoutEpoch($value)';
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

  /// 跨程序穩定的磁碟 key 材料。`Object.hash` 只適合記憶體 hashCode，
  /// 不保證不同 Dart process 仍產生相同值。
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
  });

  final BlockKey key;
  final String text;
  final HybridTextRange charRange;
  final int sourceParagraphIndex;
  final bool isTitle;
  final bool isContinuation;

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
  const LayoutTask({
    required this.block,
    required this.epoch,
    required this.fingerprint,
    required this.textStyle,
    required this.contentWidth,
    this.textColor = const ui.Color(0xFF000000),
    this.priority = LayoutTaskPriority.prefetch,
    this.direction = HybridScrollDirection.forward,
    this.indentChars = 0,
    this.trailingSpacing = 0.0,
  }) : assert(indentChars >= 0),
       assert(trailingSpacing >= 0);

  final ChapterBlock block;
  final LayoutEpoch epoch;
  final StyleFingerprint fingerprint;
  final HybridBlockTextStyle textStyle;
  final double contentWidth;

  /// 烘進 ui.Paragraph 的文字色。不影響幾何，因此不屬於
  /// StyleFingerprint——換色只重建 Paragraph，metrics 全部保留。
  final ui.Color textColor;
  final LayoutTaskPriority priority;
  final HybridScrollDirection direction;

  /// 段首縮排的全形空白字元數（沿用舊引擎「排版時動態前綴」規則；
  /// 續塊與標題恆為 0）。前綴不屬於章節 displayText，
  /// charOffset 換算時必須扣除。
  final int indentChars;

  /// 排在本 block 之後的垂直間距（px），計入 BlockMetrics.height。
  /// 標題塊 = paragraphSpacing*8；段落末塊 = fontSize*行高*paragraphSpacing。
  final double trailingSpacing;

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
