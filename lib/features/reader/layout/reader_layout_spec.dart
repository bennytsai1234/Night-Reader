import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'reader_layout_constants.dart';
import 'reader_typography.dart';

/// 一段正文（或標題）之後的留白高度，計入該 block 的量測高度。
///
/// 標題之後留 [ReaderLayoutStyle.titleSpacing] 行（標題間距），正文段落
/// 之後留段距。章末改留 [ReaderLayoutStyle.chapterSpacing] 行（使用者設定的
/// 章節間距），與段距分開計算、不疊加。空白屬於章末 block 自己的高度，捲動、
/// 定位與進度都沿用同一份幾何，不需要另外的特例。
double readerBlockTrailingSpacing(
  ReaderLayoutStyle style, {
  required bool isTitle,
  required bool isChapterEnd,
}) {
  final lineExtent = style.fontSize * style.effectiveLineHeight;
  final spacing =
      lineExtent * (isTitle ? style.titleSpacing : style.paragraphSpacing);
  if (!isChapterEnd) return spacing;
  return lineExtent * style.chapterSpacing;
}

/// 插圖上下各留的空白：半行（docs/design/reader.md「插圖」）。
double readerIllustrationGap(ReaderLayoutStyle style) =>
    style.fontSize * style.effectiveLineHeight / 2;

class ReaderLayoutStyle {
  const ReaderLayoutStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.paragraphSpacing,
    this.chapterSpacing = 1.0,
    required this.paddingTop,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.paddingRight,
    this.bold = false,
    this.titleBold = true,
    this.titleCenter = false,
    this.fontFamily,
    this.textIndent = 0,
    double? titleFontSize,
    this.titleSpacing = 0.0,
  }) : titleFontSize = titleFontSize ?? fontSize + kReaderDefaultTitleSizeDelta;

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double paragraphSpacing;

  /// 章末與下一章標題之間的空白（行），計入章末 block 的量測高度。
  final double chapterSpacing;
  final double paddingTop;
  final double paddingBottom;
  final double paddingLeft;
  final double paddingRight;
  final bool bold;
  final bool titleBold;
  final bool titleCenter;

  /// 字族（ADR 0045）；null 是系統字型。
  final String? fontFamily;
  final int textIndent;
  final double titleFontSize;

  /// 標題與正文之間的空白（行），計入標題 block 的量測高度。
  final double titleSpacing;

  double get effectiveLineHeight => normalizeReaderLineHeight(lineHeight);
}

final class ReaderTextLayoutFrame {
  const ReaderTextLayoutFrame({
    required this.width,
    required this.leftInset,
    required this.rightInset,
  });

  factory ReaderTextLayoutFrame.centered({
    required double contentWidth,
    required double? cellWidth,
  }) {
    if (!contentWidth.isFinite || contentWidth <= 0) {
      throw StateError('Text layout frame requires a positive content width.');
    }
    if (cellWidth == null ||
        !cellWidth.isFinite ||
        cellWidth <= 0 ||
        contentWidth < cellWidth) {
      return ReaderTextLayoutFrame(
        width: contentWidth,
        leftInset: 0,
        rightInset: 0,
      );
    }

    // The viewport still owns the physical content width. Typography only
    // chooses a centered inner frame that can hold an integer number of
    // measured full-width advances. A tiny paragraph slack protects native
    // layout from float accumulation without allowing the frame to escape the
    // physical content box.
    final cells = _cellCount(contentWidth, cellWidth);
    if (cells < 1) {
      return ReaderTextLayoutFrame(
        width: contentWidth,
        leftInset: 0,
        rightInset: 0,
      );
    }

    final width = (cells * cellWidth + _paragraphSlack)
        .clamp(1.0, contentWidth)
        .toDouble();
    final residual = (contentWidth - width)
        .clamp(0.0, double.infinity)
        .toDouble();
    final leftInset = residual / 2;
    return ReaderTextLayoutFrame(
      width: width,
      leftInset: leftInset,
      rightInset: residual - leftInset,
    );
  }

  static const _cellCountEpsilon = 0.01;
  static const _paragraphSlack = 0.05;

  static int _cellCount(double contentWidth, double cellWidth) =>
      ((contentWidth + _cellCountEpsilon) / cellWidth).floor();

  /// 畫面寬 [viewportWidth]、兩側至少留 [minPadding] 時，一行放得下幾個字
  /// 格（[cellWidth] 是含字距的實測字格寬）。
  static int lineCapacity({
    required double viewportWidth,
    required double minPadding,
    required double cellWidth,
  }) {
    if (!cellWidth.isFinite || cellWidth <= 0) return 0;
    final contentWidth = viewportWidth - minPadding * 2;
    if (!contentWidth.isFinite || contentWidth <= 0) return 0;
    return _cellCount(contentWidth, cellWidth);
  }

  /// 每行最多 [lineChars] 個字時正文兩側的留白：放得下更多字就把正文欄
  /// 收成剛好 [lineChars] 格、置中，多的寬度平分到兩側；放不下就撐滿，
  /// 兩側只留 [minPadding]。收窄時欄寬剛好是整數格，左右對齊沒有零頭可攤，
  /// 字距就是使用者設的字距。
  static double sidePadding({
    required double viewportWidth,
    required double minPadding,
    required double? cellWidth,
    required int lineChars,
  }) {
    if (cellWidth == null || !cellWidth.isFinite || cellWidth <= 0) {
      return minPadding;
    }
    final capacity = lineCapacity(
      viewportWidth: viewportWidth,
      minPadding: minPadding,
      cellWidth: cellWidth,
    );
    if (lineChars >= capacity) return minPadding;
    return (viewportWidth - (lineChars * cellWidth + _paragraphSlack)) / 2;
  }

  /// 左右對齊用的字距：把 [contentWidth] 湊整數個字格後剩下的空隙平均攤進
  /// 每一格（[cellWidth] 是含 [letterSpacing] 的實測字格寬），只留下
  /// paragraph slack，用新字距量出的字格排成的文字框就撐滿整個內容寬，
  /// 正文左右兩緣貼齊邊距，字格仍然等寬、直行照樣對齊。放不下一格時照舊。
  static double justifiedLetterSpacing({
    required double contentWidth,
    required double cellWidth,
    required double letterSpacing,
  }) {
    if (!contentWidth.isFinite || !cellWidth.isFinite || cellWidth <= 0) {
      return letterSpacing;
    }
    final cells = _cellCount(contentWidth, cellWidth);
    if (cells < 1) return letterSpacing;
    final spread = (contentWidth - _paragraphSlack - cells * cellWidth) / cells;
    return spread > 0 ? letterSpacing + spread : letterSpacing;
  }

  /// Drawable paragraph width inside the physical content box.
  final double width;

  /// Insets relative to the physical content box, not the viewport.
  final double leftInset;
  final double rightInset;
}

class ReaderLayoutSpec {
  ReaderLayoutSpec({
    required this.viewportSize,
    required this.contentWidth,
    required this.contentHeight,
    required this.style,
    this.cellWidth,
  }) : textLayoutFrame = ReaderTextLayoutFrame.centered(
         contentWidth: contentWidth,
         cellWidth: cellWidth,
       ),
       layoutSignature = _buildLayoutSignature(
         contentWidth: contentWidth,
         style: style,
         cellWidth: cellWidth,
       ),
       viewportSignature = _buildViewportSignature(
         viewportSize: viewportSize,
         contentHeight: contentHeight,
         style: style,
       ),
       presentationSignature = Object.hash(
         _buildLayoutSignature(
           contentWidth: contentWidth,
           style: style,
           cellWidth: cellWidth,
         ),
         _buildViewportSignature(
           viewportSize: viewportSize,
           contentHeight: contentHeight,
           style: style,
         ),
       );

  final Size viewportSize;
  final double contentWidth;
  final double contentHeight;
  final ReaderLayoutStyle style;

  /// Typography-owned placement inside [contentWidth]. It never changes the
  /// viewport-owned physical content width or user padding.
  final ReaderTextLayoutFrame textLayoutFrame;

  /// 實測全形字 advance（含 letterSpacing），只屬於 typography metrics。
  /// 用於首行縮排 placeholder 與 [textLayoutFrame] 的內部排版幾何；
  /// 它不得改寫 [contentWidth]。正文的實體可用寬度永遠由 viewport 與
  /// 使用者 padding 決定。
  final double? cellWidth;

  /// Effective viewport paddings used by paragraph paint/highlight. They add
  /// the centered text-frame residual without mutating [style].
  double get textPaddingLeft => style.paddingLeft + textLayoutFrame.leftInset;
  double get textPaddingRight =>
      style.paddingRight + textLayoutFrame.rightInset;

  /// Identity of paragraph measurement and line breaking.
  ///
  /// Viewport height and vertical chrome/insets are deliberately excluded.
  /// They change how much of the already-laid-out document is visible, not
  /// how text wraps. A change here is the only kind that may advance the
  /// Runtime layout generation and rebuild the text-view measurement epoch.
  final int layoutSignature;

  /// Identity of the physical viewport/chrome geometry.
  ///
  /// This may change when status/navigation bars or vertical padding change.
  /// Runtime keeps the latest value without invalidating paragraph layout.
  final int viewportSignature;

  /// Detects either text-layout or viewport-geometry changes.
  final int presentationSignature;

  /// Shared anchor offset calculation — the vertical position in the viewport
  /// used as the reference point for location capture and restore.
  ///
  /// Previously duplicated in Runtime, ScrollViewport, and SlideViewport.
  double get anchorOffsetInViewport {
    final height = viewportSize.height;
    final viewportHeight = height.isFinite && height > 0 ? height : 1.0;
    return (viewportHeight * 0.2).clamp(24.0, 120.0).toDouble();
  }

  static ReaderLayoutSpec fromViewport({
    required Size viewportSize,
    required ReaderLayoutStyle style,
    double? cellWidth,
  }) {
    final contentWidth =
        (viewportSize.width - style.paddingLeft - style.paddingRight)
            .clamp(1.0, double.infinity)
            .toDouble();
    final contentHeight =
        (viewportSize.height - style.paddingTop - style.paddingBottom)
            .clamp(1.0, double.infinity)
            .toDouble();
    final normalizedLineHeight = normalizeReaderLineHeight(style.lineHeight);
    final effectiveCell =
        cellWidth != null && cellWidth.isFinite && cellWidth > 0
        ? cellWidth
        : null;
    // 首行縮排至少留一格給字：每行字數很少（最少 1 字）或畫面很窄時，縮排
    // 等於或寬過一行就排不出來或第一行超出邊界，縮到一行少一格。量字、畫字
    // 與選字都照這裡的縮排。
    final cells = effectiveCell == null
        ? null
        : ReaderTextLayoutFrame._cellCount(contentWidth, effectiveCell);
    final textIndent = cells == null
        ? style.textIndent
        : math.min(style.textIndent, math.max(0, cells - 1));
    final effectiveStyle =
        normalizedLineHeight == style.lineHeight &&
            textIndent == style.textIndent
        ? style
        : ReaderLayoutStyle(
            fontSize: style.fontSize,
            lineHeight: normalizedLineHeight,
            letterSpacing: style.letterSpacing,
            paragraphSpacing: style.paragraphSpacing,
            chapterSpacing: style.chapterSpacing,
            paddingTop: style.paddingTop,
            paddingBottom: style.paddingBottom,
            paddingLeft: style.paddingLeft,
            paddingRight: style.paddingRight,
            bold: style.bold,
            titleBold: style.titleBold,
            titleCenter: style.titleCenter,
            fontFamily: style.fontFamily,
            textIndent: textIndent,
            titleFontSize: style.titleFontSize,
            titleSpacing: style.titleSpacing,
          );
    return ReaderLayoutSpec(
      viewportSize: viewportSize,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style: effectiveStyle,
      cellWidth: effectiveCell,
    );
  }

  static int _buildLayoutSignature({
    required double contentWidth,
    required ReaderLayoutStyle style,
    required double? cellWidth,
  }) {
    final paragraphWidth = ReaderTextLayoutFrame.centered(
      contentWidth: contentWidth,
      cellWidth: cellWidth,
    ).width;
    return Object.hash(
      paragraphWidth,
      cellWidth,
      style.fontSize,
      style.lineHeight,
      style.letterSpacing,
      style.paragraphSpacing,
      style.chapterSpacing,
      style.textIndent,
      style.bold,
      style.titleBold,
      style.titleCenter,
      readerFontFamilySignature(style.fontFamily),
      style.titleFontSize,
      style.titleSpacing,
      kReaderCjkTypographyFeatureSignature,
    );
  }

  static int _buildViewportSignature({
    required Size viewportSize,
    required double contentHeight,
    required ReaderLayoutStyle style,
  }) {
    return Object.hash(
      viewportSize.width,
      viewportSize.height,
      contentHeight,
      style.paddingTop,
      style.paddingBottom,
      style.paddingLeft,
      style.paddingRight,
    );
  }
}
