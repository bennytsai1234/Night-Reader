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

class ReaderV2LayoutSpec {
  ReaderV2LayoutSpec({
    required this.viewportSize,
    required this.contentWidth,
    required this.contentHeight,
    required this.style,
    this.cellWidth,
  }) : layoutSignature = _buildSignature(
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

  /// em-grid 鎖寬用的實測全形字 advance（含 letterSpacing）；null = 未鎖寬。
  /// 鎖寬時 [contentWidth] 為 cell 整數倍（外加 [_cellWidthSlack]），
  /// 縮排 placeholder 也以此為寬。
  final double? cellWidth;
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

  /// 格數判定容差：raw 因浮點誤差略小於整數倍時不誤丟一整格。
  static const double _cellCountEpsilon = 0.35;

  /// 排版約束的鬆量：引擎逐字 advance 以 float 累加，恰好整數倍的
  /// 約束可能因累加誤差把滿列末字擠到下一列；遠小於一格，無視覺影響。
  static const double _cellWidthSlack = 0.05;

  static ReaderV2LayoutSpec fromViewport({
    required Size viewportSize,
    required ReaderV2LayoutStyle style,
    double? cellWidth,
  }) {
    final rawContentWidth =
        (viewportSize.width - style.paddingLeft - style.paddingRight)
            .clamp(1.0, double.infinity)
            .toDouble();
    final contentHeight =
        (viewportSize.height - style.paddingTop - style.paddingBottom)
            .clamp(1.0, double.infinity)
            .toDouble();
    var contentWidth = rawContentWidth;
    var effectiveStyle = style;
    double? effectiveCell;
    if (cellWidth != null && cellWidth.isFinite && cellWidth > 0) {
      final cells = ((rawContentWidth + _cellCountEpsilon) / cellWidth).floor();
      if (cells >= 1) {
        // em-grid 鎖寬：寬度取 cell 乘積而非減法回推，每列殘差歸零，
        // justify／斷行都沒有零頭可攤；殘差平分回左右 padding 維持置中。
        contentWidth = cells * cellWidth + _cellWidthSlack;
        final sidePadding =
            ((rawContentWidth - contentWidth) / 2)
                .clamp(0.0, double.infinity)
                .toDouble();
        effectiveStyle = ReaderV2LayoutStyle(
          fontSize: style.fontSize,
          lineHeight: style.lineHeight,
          letterSpacing: style.letterSpacing,
          paragraphSpacing: style.paragraphSpacing,
          paddingTop: style.paddingTop,
          paddingBottom: style.paddingBottom,
          paddingLeft: style.paddingLeft + sidePadding,
          paddingRight: style.paddingRight + sidePadding,
          bold: style.bold,
          textIndent: style.textIndent,
          lastLineSpacingCompensation: style.lastLineSpacingCompensation,
        );
        effectiveCell = cellWidth;
      }
    }
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
