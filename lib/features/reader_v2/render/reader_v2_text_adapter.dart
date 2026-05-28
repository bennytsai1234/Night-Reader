import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout.dart';

ReaderV2RenderLine readerV2TextLineToRenderLine(ReaderV2TextLine line) {
  return ReaderV2RenderLine(
    text: line.text,
    chapterIndex: line.chapterIndex,
    lineIndex: line.lineIndex,
    width: line.width,
    isTitle: line.isTitle,
    isParagraphStart: line.isParagraphStart,
    isParagraphEnd: line.isParagraphEnd,
    chapterPosition: line.startCharOffset,
    lineTop: line.top,
    lineBottom: line.bottom,
    paragraphNum: line.paragraphIndex,
    startCharOffset: line.startCharOffset,
    endCharOffset: line.endCharOffset,
    baseline: line.baseline,
  );
}

ReaderV2RenderPage readerV2PageSliceToRenderPage({
  required ReaderV2ChapterLayout layout,
  required ReaderV2PageSlice slice,
  required int chapterSize,
  required String title,
}) {
  final lines = layout
      .linesForPage(slice.pageIndex)
      .map(
        (line) => readerV2TextLineToRenderLine(
          line.copyWithPageLocalTop(slice.localStartY),
        ),
      )
      .toList(growable: false);
  return ReaderV2RenderPage(
    pageIndex: slice.pageIndex,
    chapterIndex: slice.chapterIndex,
    chapterSize: chapterSize,
    pageSize: slice.pageCount,
    title: title,
    startCharOffset: slice.startCharOffset,
    endCharOffset: slice.endCharOffset,
    width: slice.contentWidth,
    localStartY: slice.localStartY,
    localEndY: slice.localEndY,
    contentHeight: slice.contentHeight,
    viewportHeight: slice.viewportHeight,
    hasExplicitLocalRange: true,
    isChapterStart: slice.isChapterStart,
    isChapterEnd: slice.isChapterEnd,
    lines: lines,
  );
}

extension ReaderV2TextLinePageLocalCopy on ReaderV2TextLine {
  ReaderV2TextLine copyWithPageLocalTop(double pageTop) {
    return ReaderV2TextLine(
      text: text,
      chapterIndex: chapterIndex,
      lineIndex: lineIndex,
      startCharOffset: startCharOffset,
      endCharOffset: endCharOffset,
      top: top - pageTop,
      bottom: bottom - pageTop,
      baseline: baseline - pageTop,
      width: width,
      isTitle: isTitle,
      paragraphIndex: paragraphIndex,
      isParagraphStart: isParagraphStart,
      isParagraphEnd: isParagraphEnd,
    );
  }
}
