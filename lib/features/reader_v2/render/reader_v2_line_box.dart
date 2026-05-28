class ReaderV2LineBox {
  const ReaderV2LineBox({
    required this.startCharOffset,
    required this.endCharOffset,
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.text,
    this.isParagraphStart = false,
    this.isParagraphEnd = false,
    this.isTitle = false,
  });

  final int startCharOffset;
  final int endCharOffset;
  final double top;
  final double bottom;
  final double baseline;
  final String text;
  final bool isParagraphStart;
  final bool isParagraphEnd;
  final bool isTitle;

  double get height => bottom - top;

  bool containsCharOffset(int charOffset) {
    return charOffset >= startCharOffset && charOffset < endCharOffset;
  }
}
