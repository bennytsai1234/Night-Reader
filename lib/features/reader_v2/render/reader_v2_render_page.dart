import 'reader_v2_line_box.dart';

/// Render-facing line model produced from the v2 layout pipeline.
class ReaderV2RenderLine extends ReaderV2LineBox {
  ReaderV2RenderLine({
    required super.text,
    this.chapterIndex = 0,
    this.lineIndex = 0,
    double width = 0,
    double? height,
    super.isTitle = false,
    super.isParagraphStart = false,
    super.isParagraphEnd = false,
    int chapterPosition = 0,
    double lineTop = 0,
    double? lineBottom,
    this.paragraphNum = 0,
    int? startCharOffset,
    int? endCharOffset,
    double? baseline,
  }) : width = _normalizeNonNegative(width),
       chapterPosition = _normalizeStartOffset(
         startCharOffset,
         chapterPosition,
       ),
       lineTop = _normalizeFinite(lineTop),
       lineBottom = _normalizeLineBottom(
         lineTop: lineTop,
         lineBottom: lineBottom,
         height: height,
       ),
       super(
         startCharOffset: _normalizeStartOffset(
           startCharOffset,
           chapterPosition,
         ),
         endCharOffset: _normalizeEndOffset(
           text: text,
           startCharOffset: _normalizeStartOffset(
             startCharOffset,
             chapterPosition,
           ),
           endCharOffset: endCharOffset,
         ),
         top: _normalizeFinite(lineTop),
         bottom: _normalizeLineBottom(
           lineTop: lineTop,
           lineBottom: lineBottom,
           height: height,
         ),
         baseline: _normalizeBaseline(
           lineTop: lineTop,
           lineBottom: lineBottom,
           height: height,
           baseline: baseline,
         ),
       );

  final int chapterIndex;
  final int lineIndex;
  final double width;
  @override
  double get height => lineBottom - lineTop;
  final int chapterPosition;
  final double lineTop;
  final double lineBottom;
  final int paragraphNum;

  ReaderV2RenderLine copyWith({
    String? text,
    int? chapterIndex,
    int? lineIndex,
    double? width,
    double? height,
    bool? isTitle,
    bool? isParagraphStart,
    bool? isParagraphEnd,
    int? chapterPosition,
    double? lineTop,
    double? lineBottom,
    int? paragraphNum,
    int? startCharOffset,
    int? endCharOffset,
    double? baseline,
  }) {
    return ReaderV2RenderLine(
      text: text ?? this.text,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      lineIndex: lineIndex ?? this.lineIndex,
      width: width ?? this.width,
      height: height ?? this.height,
      isTitle: isTitle ?? this.isTitle,
      isParagraphStart: isParagraphStart ?? this.isParagraphStart,
      isParagraphEnd: isParagraphEnd ?? this.isParagraphEnd,
      chapterPosition: chapterPosition ?? this.chapterPosition,
      lineTop: lineTop ?? this.lineTop,
      lineBottom: lineBottom ?? this.lineBottom,
      paragraphNum: paragraphNum ?? this.paragraphNum,
      startCharOffset: startCharOffset ?? this.startCharOffset,
      endCharOffset: endCharOffset ?? this.endCharOffset,
      baseline: baseline ?? this.baseline,
    );
  }

  ReaderV2RenderLine shiftedBy(double dy) {
    return copyWith(
      lineTop: lineTop + dy,
      lineBottom: lineBottom + dy,
      baseline: baseline + dy,
    );
  }

  ReaderV2RenderLine toPageLocal(double pageTop) {
    return copyWith(
      lineTop: top - pageTop,
      lineBottom: bottom - pageTop,
      baseline: baseline - pageTop,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderV2RenderLine &&
        other.text == text &&
        other.chapterIndex == chapterIndex &&
        other.lineIndex == lineIndex &&
        other.width == width &&
        other.isTitle == isTitle &&
        other.isParagraphStart == isParagraphStart &&
        other.isParagraphEnd == isParagraphEnd &&
        other.chapterPosition == chapterPosition &&
        other.lineTop == lineTop &&
        other.lineBottom == lineBottom &&
        other.paragraphNum == paragraphNum &&
        other.startCharOffset == startCharOffset &&
        other.endCharOffset == endCharOffset &&
        other.baseline == baseline;
  }

  @override
  int get hashCode => Object.hash(
    text,
    chapterIndex,
    lineIndex,
    width,
    isTitle,
    isParagraphStart,
    isParagraphEnd,
    chapterPosition,
    lineTop,
    lineBottom,
    paragraphNum,
    startCharOffset,
    endCharOffset,
    baseline,
  );

  static int _normalizeStartOffset(int? startCharOffset, int chapterPosition) {
    final start = startCharOffset ?? chapterPosition;
    return start < 0 ? 0 : start;
  }

  static int _normalizeEndOffset({
    required String text,
    required int startCharOffset,
    int? endCharOffset,
  }) {
    final end = endCharOffset ?? startCharOffset + text.length;
    return end < startCharOffset ? startCharOffset : end;
  }

  static double _normalizeFinite(double value) {
    return value.isFinite ? value : 0.0;
  }

  static double _normalizeNonNegative(double value) {
    final normalized = _normalizeFinite(value);
    return normalized < 0 ? 0.0 : normalized;
  }

  static double _normalizeLineBottom({
    required double lineTop,
    required double? lineBottom,
    required double? height,
  }) {
    final top = _normalizeFinite(lineTop);
    final fallbackHeight = height != null && height.isFinite ? height : 0.0;
    final bottom = lineBottom ?? top + fallbackHeight;
    final finiteBottom = bottom.isFinite ? bottom : top;
    return finiteBottom < top ? top : finiteBottom;
  }

  static double _normalizeBaseline({
    required double lineTop,
    required double? lineBottom,
    required double? height,
    required double? baseline,
  }) {
    final top = _normalizeFinite(lineTop);
    final bottom = _normalizeLineBottom(
      lineTop: lineTop,
      lineBottom: lineBottom,
      height: height,
    );
    final value = baseline ?? top + (bottom - top) * 0.82;
    final finiteValue = value.isFinite ? value : top;
    return finiteValue.clamp(top, bottom).toDouble();
  }
}

class ReaderV2RenderPage {
  ReaderV2RenderPage({
    int? index,
    int? pageIndex,
    required List<ReaderV2RenderLine> lines,
    this.title = '',
    required int chapterIndex,
    int chapterSize = 0,
    int pageSize = 0,
    int? startCharOffset,
    int? endCharOffset,
    double? width,
    double? localStartY,
    double? localEndY,
    double? height,
    double? contentHeight,
    double? viewportHeight,
    bool? hasExplicitLocalRange,
    bool? isChapterStart,
    bool? isChapterEnd,
    this.isLoading = false,
    this.errorMessage,
  }) : pageIndex = _normalizeIndex(pageIndex ?? index ?? 0),
       lines = List<ReaderV2RenderLine>.unmodifiable(lines),
       chapterIndex = _normalizeIndex(chapterIndex),
       chapterSize = _normalizeCount(chapterSize),
       pageSize = _normalizeCount(pageSize),
       startCharOffset = _pageStartOffset(lines, startCharOffset),
       endCharOffset = _pageEndOffset(lines, startCharOffset, endCharOffset),
       width = _normalizeNonNegative(width ?? _pageWidth(lines)),
       contentHeight = _pageContentHeight(
         lines: lines,
         contentHeight: contentHeight,
         height: height,
       ),
       viewportHeight = _pageViewportHeight(
         lines: lines,
         viewportHeight: viewportHeight,
         contentHeight: contentHeight,
         height: height,
       ),
       localStartY = _pageLocalStart(localStartY),
       localEndY = _pageLocalEnd(
         lines: lines,
         localStartY: localStartY,
         localEndY: localEndY,
         contentHeight: contentHeight,
         height: height,
       ),
       _hasExplicitLocalRange =
           hasExplicitLocalRange ?? (localStartY != null || localEndY != null),
       isChapterStart =
           isChapterStart ?? (_normalizeIndex(pageIndex ?? index ?? 0) == 0),
       isChapterEnd =
           isChapterEnd ??
           (_normalizeCount(pageSize) > 0 &&
               _normalizeIndex(pageIndex ?? index ?? 0) >=
                   _normalizeCount(pageSize) - 1);

  /// UI callers may still use [index]; the v2 pipeline names it [pageIndex].
  int get index => pageIndex;
  final int pageIndex;
  final List<ReaderV2RenderLine> lines;
  final String title;
  final int chapterIndex;
  final int chapterSize;
  final int pageSize;
  final int startCharOffset;
  final int endCharOffset;
  final double width;
  final double localStartY;
  final double localEndY;
  final double contentHeight;
  final double viewportHeight;
  final bool _hasExplicitLocalRange;
  final bool isChapterStart;
  final bool isChapterEnd;
  final bool isLoading;
  final String? errorMessage;
  double get height => contentHeight;
  bool get hasExplicitLocalRange => _hasExplicitLocalRange;
  bool get isPlaceholder => isLoading || errorMessage != null;
  bool get hasBodyContent =>
      lines.any((line) => !line.isTitle && line.text.isNotEmpty);

  int get lineSize => lines.length;

  String get readProgress {
    if (chapterSize == 0 || (pageSize == 0 && chapterIndex == 0)) {
      return '0.0%';
    } else if (pageSize == 0) {
      return '${((chapterIndex + 1.0) / chapterSize * 100).toStringAsFixed(1)}%';
    }
    final percent =
        (chapterIndex / chapterSize) +
        (1.0 / chapterSize) * (index + 1) / pageSize;
    var formatted = '${(percent * 100).toStringAsFixed(1)}%';
    if (formatted == '100.0%' &&
        (chapterIndex + 1 != chapterSize || index + 1 != pageSize)) {
      formatted = '99.9%';
    }
    return formatted;
  }

  bool containsCharOffset(int charOffset) {
    if (lines.isEmpty) return charOffset == startCharOffset;
    if (charOffset < startCharOffset || charOffset > endCharOffset) {
      return false;
    }
    return charOffset < endCharOffset || isChapterEnd;
  }

  ReaderV2RenderPage copyWith({
    int? index,
    int? pageIndex,
    List<ReaderV2RenderLine>? lines,
    String? title,
    int? chapterIndex,
    int? chapterSize,
    int? pageSize,
    int? startCharOffset,
    int? endCharOffset,
    double? width,
    double? localStartY,
    double? localEndY,
    double? height,
    double? contentHeight,
    double? viewportHeight,
    bool? hasExplicitLocalRange,
    bool? isChapterStart,
    bool? isChapterEnd,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    final nextPageIndex = pageIndex ?? index ?? this.pageIndex;
    final nextLines = lines ?? this.lines;
    final nextHasExplicitRange =
        hasExplicitLocalRange ??
        (_hasExplicitLocalRange || localStartY != null || localEndY != null);
    return ReaderV2RenderPage(
      pageIndex: nextPageIndex,
      lines: nextLines,
      title: title ?? this.title,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterSize: chapterSize ?? this.chapterSize,
      pageSize: pageSize ?? this.pageSize,
      startCharOffset: startCharOffset ?? this.startCharOffset,
      endCharOffset: endCharOffset ?? this.endCharOffset,
      width: width ?? this.width,
      localStartY:
          nextHasExplicitRange ? (localStartY ?? this.localStartY) : null,
      localEndY: nextHasExplicitRange ? (localEndY ?? this.localEndY) : null,
      contentHeight: contentHeight ?? height ?? this.contentHeight,
      viewportHeight: viewportHeight ?? this.viewportHeight,
      hasExplicitLocalRange: nextHasExplicitRange,
      isChapterStart: isChapterStart ?? this.isChapterStart,
      isChapterEnd: isChapterEnd ?? this.isChapterEnd,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderV2RenderPage &&
        other.pageIndex == pageIndex &&
        other.title == title &&
        other.chapterIndex == chapterIndex &&
        other.chapterSize == chapterSize &&
        other.pageSize == pageSize &&
        other.startCharOffset == startCharOffset &&
        other.endCharOffset == endCharOffset &&
        other.width == width &&
        other.localStartY == localStartY &&
        other.localEndY == localEndY &&
        other.contentHeight == contentHeight &&
        other.viewportHeight == viewportHeight &&
        other.hasExplicitLocalRange == hasExplicitLocalRange &&
        other.isChapterStart == isChapterStart &&
        other.isChapterEnd == isChapterEnd &&
        other.isLoading == isLoading &&
        other.errorMessage == errorMessage &&
        _sameLines(other.lines, lines);
  }

  @override
  int get hashCode => Object.hash(
    pageIndex,
    title,
    chapterIndex,
    chapterSize,
    pageSize,
    startCharOffset,
    endCharOffset,
    width,
    localStartY,
    localEndY,
    contentHeight,
    viewportHeight,
    hasExplicitLocalRange,
    isChapterStart,
    isChapterEnd,
    isLoading,
    errorMessage,
    Object.hashAll(lines),
  );

  static int _firstOffset(List<ReaderV2RenderLine> lines) {
    for (final line in lines) {
      if (line.text.isNotEmpty) return line.startCharOffset;
    }
    return 0;
  }

  static int _lastOffset(List<ReaderV2RenderLine> lines) {
    for (final line in lines.reversed) {
      if (line.text.isNotEmpty) return line.endCharOffset;
    }
    return _firstOffset(lines);
  }

  static double _pageWidth(List<ReaderV2RenderLine> lines) {
    if (lines.isEmpty) return 0;
    return lines
        .map((line) => line.width)
        .fold<double>(0, (max, width) => width > max ? width : max);
  }

  static double _pageHeight(List<ReaderV2RenderLine> lines) {
    if (lines.isEmpty) return 0;
    return lines
        .map((line) => line.lineBottom)
        .fold<double>(0, (max, bottom) => bottom > max ? bottom : max);
  }

  static bool _sameLines(
    List<ReaderV2RenderLine> a,
    List<ReaderV2RenderLine> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!identical(a[index], b[index]) && a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

  static int _normalizeIndex(int value) {
    return value < 0 ? 0 : value;
  }

  static int _normalizeCount(int value) {
    return value < 0 ? 0 : value;
  }

  static int _pageStartOffset(
    List<ReaderV2RenderLine> lines,
    int? startCharOffset,
  ) {
    final start = startCharOffset ?? _firstOffset(lines);
    return start < 0 ? 0 : start;
  }

  static int _pageEndOffset(
    List<ReaderV2RenderLine> lines,
    int? startCharOffset,
    int? endCharOffset,
  ) {
    final start = _pageStartOffset(lines, startCharOffset);
    final end = endCharOffset ?? _lastOffset(lines);
    return end < start ? start : end;
  }

  static double _normalizeFinite(double value) {
    return value.isFinite ? value : 0.0;
  }

  static double _normalizeNonNegative(double value) {
    final normalized = _normalizeFinite(value);
    return normalized < 0 ? 0.0 : normalized;
  }

  static double _pageContentHeight({
    required List<ReaderV2RenderLine> lines,
    required double? contentHeight,
    required double? height,
  }) {
    return _normalizeNonNegative(contentHeight ?? height ?? _pageHeight(lines));
  }

  static double _pageViewportHeight({
    required List<ReaderV2RenderLine> lines,
    required double? viewportHeight,
    required double? contentHeight,
    required double? height,
  }) {
    return _normalizeNonNegative(
      viewportHeight ?? contentHeight ?? height ?? _pageHeight(lines),
    );
  }

  static double _pageLocalStart(double? localStartY) {
    return _normalizeFinite(localStartY ?? 0.0);
  }

  static double _pageLocalEnd({
    required List<ReaderV2RenderLine> lines,
    required double? localStartY,
    required double? localEndY,
    required double? contentHeight,
    required double? height,
  }) {
    final start = _pageLocalStart(localStartY);
    final content = _pageContentHeight(
      lines: lines,
      contentHeight: contentHeight,
      height: height,
    );
    final end = _normalizeFinite(localEndY ?? start + content);
    return end < start ? start : end;
  }
}
