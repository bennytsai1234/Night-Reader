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
  }) : layoutSignature = _buildSignature(
         viewportSize: viewportSize,
         contentWidth: contentWidth,
         contentHeight: contentHeight,
         style: style,
       );

  final Size viewportSize;
  final double contentWidth;
  final double contentHeight;
  final ReaderV2LayoutStyle style;
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
  }) {
    final contentWidth =
        (viewportSize.width - style.paddingLeft - style.paddingRight)
            .clamp(1.0, double.infinity)
            .toDouble();
    final contentHeight =
        (viewportSize.height - style.paddingTop - style.paddingBottom)
            .clamp(1.0, double.infinity)
            .toDouble();
    return ReaderV2LayoutSpec(
      viewportSize: viewportSize,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style: style,
    );
  }

  static int _buildSignature({
    required Size viewportSize,
    required double contentWidth,
    required double contentHeight,
    required ReaderV2LayoutStyle style,
  }) {
    return Object.hash(
      viewportSize.width,
      viewportSize.height,
      contentWidth,
      contentHeight,
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
