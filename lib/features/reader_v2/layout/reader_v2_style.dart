import 'package:night_reader/core/constant/page_anim.dart';

enum ReaderV2PageMode {
  scroll,
  slide;

  static ReaderV2PageMode fromPageAnim(int pageAnim) {
    return pageAnim == PageAnim.scroll ? ReaderV2PageMode.scroll : slide;
  }

  int get pageAnim => switch (this) {
    ReaderV2PageMode.scroll => PageAnim.scroll,
    ReaderV2PageMode.slide => PageAnim.slide,
  };
}

class ReaderV2Style {
  static const double minReadableLineHeight = 1.2;
  static const double maxReadableLineHeight = 3.0;
  static const double defaultLineHeight = 1.5;

  const ReaderV2Style({
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
    required this.pageMode,
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
  final ReaderV2PageMode pageMode;

  double get effectiveLineHeight => normalizeLineHeight(lineHeight);

  static double normalizeLineHeight(double value) {
    if (!value.isFinite || value.isNaN) return defaultLineHeight;
    return value.clamp(minReadableLineHeight, maxReadableLineHeight).toDouble();
  }

  ReaderV2Style copyWith({
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? paragraphSpacing,
    double? paddingTop,
    double? paddingBottom,
    double? paddingLeft,
    double? paddingRight,
    bool? bold,
    int? textIndent,
    ReaderV2PageMode? pageMode,
  }) {
    return ReaderV2Style(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      paddingLeft: paddingLeft ?? this.paddingLeft,
      paddingRight: paddingRight ?? this.paddingRight,
      bold: bold ?? this.bold,
      textIndent: textIndent ?? this.textIndent,
      pageMode: pageMode ?? this.pageMode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderV2Style &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight &&
        other.letterSpacing == letterSpacing &&
        other.paragraphSpacing == paragraphSpacing &&
        other.paddingTop == paddingTop &&
        other.paddingBottom == paddingBottom &&
        other.paddingLeft == paddingLeft &&
        other.paddingRight == paddingRight &&
        other.bold == bold &&
        other.textIndent == textIndent &&
        other.pageMode == pageMode;
  }

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    letterSpacing,
    paragraphSpacing,
    paddingTop,
    paddingBottom,
    paddingLeft,
    paddingRight,
    bold,
    textIndent,
    pageMode,
  );
}
