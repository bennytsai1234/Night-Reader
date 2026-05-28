import 'package:reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_infinite_segment_strip.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_visible_page_calculator.dart';

class ReaderV2PositionTracker {
  const ReaderV2PositionTracker();

  double? readingYForLocation({
    required ReaderV2Location location,
    required ReaderV2ChapterPageCacheManager cacheManager,
    required ReaderV2InfiniteSegmentStrip strip,
    required double anchorOffset,
    required ReaderV2Style style,
  }) {
    final chapter = cacheManager.chapterAt(location.chapterIndex);
    final chapterTop = strip.chapterTop(location.chapterIndex);
    if (chapter == null || chapterTop == null) return null;

    final line = chapter.layout.lineForCharOffset(location.charOffset);
    if (line == null) return chapterTop - anchorOffset;
    final lineTop = lineWorldTop(
      chapter: chapter,
      chapterTop: chapterTop,
      line: line,
      style: style,
    );
    if (lineTop == null) return null;
    return lineTop + location.visualOffsetPx - anchorOffset;
  }

  ReaderV2Location? captureVisibleLocation({
    required ReaderV2VisiblePageCalculator calculator,
    required ReaderV2ChapterPageCacheManager cacheManager,
    required ReaderV2InfiniteSegmentStrip strip,
    required double readingY,
    required double anchorOffset,
    required ReaderV2Style style,
  }) {
    final anchorWorldY = readingY + anchorOffset;
    final placement = calculator.placementAtWorldY(anchorWorldY);
    if (placement == null) return null;

    final pageContentY =
        (anchorWorldY - placement.worldTop - style.paddingTop)
            .clamp(0.0, placement.page.contentHeight)
            .toDouble();
    final chapterLocalY = placement.page.localStartY + pageContentY;
    final line = placement.layout.lineAtOrNearLocalY(chapterLocalY);
    if (line == null) return null;

    final chapter = cacheManager.chapterAt(line.chapterIndex);
    final chapterTop = strip.chapterTop(line.chapterIndex);
    if (chapter == null || chapterTop == null) return null;
    final lineTop = lineWorldTop(
      chapter: chapter,
      chapterTop: chapterTop,
      line: line,
      style: style,
    );
    if (lineTop == null) return null;
    final lineTopOnScreen = lineTop - readingY;
    return ReaderV2Location(
      chapterIndex: line.chapterIndex,
      charOffset: line.startCharOffset,
      visualOffsetPx: anchorOffset - lineTopOnScreen,
    );
  }

  double? lineWorldTop({
    required ReaderV2CachedChapterPages chapter,
    required double chapterTop,
    required ReaderV2RenderLine line,
    required ReaderV2Style style,
  }) {
    final page = chapter.layout.pageForLine(line);
    if (page == null) return null;
    final pageOffsetTop = chapter.pageOffsetTop(page.pageIndex);
    if (pageOffsetTop == null) return null;
    return chapterTop +
        pageOffsetTop +
        style.paddingTop +
        line.top -
        page.localStartY;
  }

  double? lineWorldBottom({
    required ReaderV2CachedChapterPages chapter,
    required double chapterTop,
    required ReaderV2RenderLine line,
    required ReaderV2Style style,
  }) {
    final page = chapter.layout.pageForLine(line);
    if (page == null) return null;
    final pageOffsetTop = chapter.pageOffsetTop(page.pageIndex);
    if (pageOffsetTop == null) return null;
    return chapterTop +
        pageOffsetTop +
        style.paddingTop +
        line.bottom -
        page.localStartY;
  }
}
