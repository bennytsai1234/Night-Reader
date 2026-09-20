import 'package:flutter/widgets.dart';

import 'reader_v2_typography.dart';

class ReaderV2LayoutStyle {
  static const double minReadableLineHeight = 1.2;
  static const double maxReadableLineHeight = 3.0;
  static const double defaultLineHeight = 1.5;

  const ReaderV2LayoutStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.paragraphSpacing,
    required this.paddingTop,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.paddingRight,
    this.bold = false,
    this.textIndent = 0,
    this.lastLineSpacingCompensation = false,
  });

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double paragraphSpacing;
  final double paddingTop;
  final double paddingBottom;
  final double paddingLeft;
  final double paddingRight;
  final bool bold;
  final int textIndent;
  final bool lastLineSpacingCompensation;

  double get effectiveLineHeight => normalizeLineHeight(lineHeight);

  static double normalizeLineHeight(double value) {
    if (!value.isFinite || value.isNaN) return defaultLineHeight;
    return value.clamp(minReadableLineHeight, maxReadableLineHeight).toDouble();
  }
}

final class ReaderV2TextLayoutFrame {
  const ReaderV2TextLayoutFrame({
    required this.width,
    required this.leftInset,
    required this.rightInset,
  });

  factory ReaderV2TextLayoutFrame.centered({
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
      return ReaderV2TextLayoutFrame(
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
    const cellCountEpsilon = 0.01;
    const paragraphSlack = 0.05;
    final cells = ((contentWidth + cellCountEpsilon) / cellWidth).floor();
    if (cells < 1) {
      return ReaderV2TextLayoutFrame(
        width: contentWidth,
        leftInset: 0,
        rightInset: 0,
      );
    }

    final width = (cells * cellWidth + paragraphSlack)
        .clamp(1.0, contentWidth)
        .toDouble();
    final residual = (contentWidth - width)
        .clamp(0.0, double.infinity)
        .toDouble();
    final leftInset = residual / 2;
    return ReaderV2TextLayoutFrame(
      width: width,
      leftInset: leftInset,
      rightInset: residual - leftInset,
    );
  }

  /// Drawable paragraph width inside the physical content box.
  final double width;

  /// Insets relative to the physical content box, not the viewport.
  final double leftInset;
  final double rightInset;
}

class ReaderV2LayoutSpec {
  ReaderV2LayoutSpec({
    required this.viewportSize,
    required this.contentWidth,
    required this.contentHeight,
    required this.style,
    this.cellWidth,
  }) : textLayoutFrame = ReaderV2TextLayoutFrame.centered(
         contentWidth: contentWidth,
         cellWidth: cellWidth,
       ),
       layoutSignature = _buildSignature(
         viewportSize: viewportSize,
         contentWidth: contentWidth,
         contentHeight: contentHeight,
         style: style,
         cellWidth: cellWidth,
       );

  final Size viewportSize;
  final double contentWidth;
  final double contentHeight;
  final ReaderV2LayoutStyle style;

  /// Typography-owned placement inside [contentWidth]. It never changes the
  /// viewport-owned physical content width or user padding.
  final ReaderV2TextLayoutFrame textLayoutFrame;

  /// 實測全形字 advance（含 letterSpacing），只屬於 typography metrics。
  /// 目前僅供首行縮排 placeholder 等字形幾何使用；它不得改寫
  /// [contentWidth]。正文可用寬度永遠由 viewport 與使用者 padding 決定。
  final double? cellWidth;

  /// Effective viewport paddings used by paragraph paint/highlight. They add
  /// the centered text-frame residual without mutating [style].
  double get textPaddingLeft => style.paddingLeft + textLayoutFrame.leftInset;
  double get textPaddingRight =>
      style.paddingRight + textLayoutFrame.rightInset;

  final int layoutSignature;

  /// Shared anchor offset calculation — the vertical position in the viewport
  /// used as the reference point for location capture and restore.
  ///
  /// Previously duplicated in Runtime, ScrollViewport, and SlideViewport.
  double get anchorOffsetInViewport {
    final height = viewportSize.height;
    final viewportHeight = height.isFinite && height > 0 ? height : 1.0;
    return (viewportHeight * 0.2).clamp(24.0, 120.0).toDouble();
  }

  static ReaderV2LayoutSpec fromViewport({
    required Size viewportSize,
    required ReaderV2LayoutStyle style,
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
    final normalizedLineHeight = ReaderV2LayoutStyle.normalizeLineHeight(
      style.lineHeight,
    );
    final effectiveStyle = normalizedLineHeight == style.lineHeight
        ? style
        : ReaderV2LayoutStyle(
            fontSize: style.fontSize,
            lineHeight: normalizedLineHeight,
            letterSpacing: style.letterSpacing,
            paragraphSpacing: style.paragraphSpacing,
            paddingTop: style.paddingTop,
            paddingBottom: style.paddingBottom,
            paddingLeft: style.paddingLeft,
            paddingRight: style.paddingRight,
            bold: style.bold,
            textIndent: style.textIndent,
            lastLineSpacingCompensation: style.lastLineSpacingCompensation,
          );
    final effectiveCell =
        cellWidth != null && cellWidth.isFinite && cellWidth > 0
        ? cellWidth
        : null;
    return ReaderV2LayoutSpec(
      viewportSize: viewportSize,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style: effectiveStyle,
      cellWidth: effectiveCell,
    );
  }

  static int _buildSignature({
    required Size viewportSize,
    required double contentWidth,
    required double contentHeight,
    required ReaderV2LayoutStyle style,
    required double? cellWidth,
  }) {
    return Object.hash(
      viewportSize.width,
      viewportSize.height,
      contentWidth,
      contentHeight,
      cellWidth,
      style.fontSize,
      style.lineHeight,
      style.letterSpacing,
      style.paragraphSpacing,
      style.paddingTop,
      style.paddingBottom,
      style.paddingLeft,
      style.paddingRight,
      style.textIndent,
      style.bold,
      style.lastLineSpacingCompensation,
      kReaderV2CjkTypographyFeatureSignature,
    );
  }
}
