import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_chapter_view.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_infinite_segment_strip.dart';

class ReaderV2VisiblePage {
  const ReaderV2VisiblePage({
    required this.layout,
    required this.page,
    required this.worldTop,
    required this.extent,
  });

  final ReaderV2ChapterView layout;
  final ReaderV2PageCache page;
  final double worldTop;
  final double extent;

  double get worldBottom => worldTop + extent;

  double screenY(double readingY) => worldTop - readingY;
}

class ReaderV2VisiblePageCalculator {
  ReaderV2VisiblePageCalculator({
    required ReaderV2ChapterPageCacheManager cacheManager,
    required ReaderV2InfiniteSegmentStrip strip,
  }) : _cacheManager = cacheManager,
       _strip = strip;

  final ReaderV2ChapterPageCacheManager _cacheManager;
  final ReaderV2InfiniteSegmentStrip _strip;
  List<ReaderV2VisiblePage>? _cachedAllPages;
  int? _cachedCacheRevision;
  int? _cachedStripRevision;

  bool get hasPages => allPages().isNotEmpty;

  List<ReaderV2VisiblePage> allPages() {
    final cacheRevision = _cacheManager.revision;
    final stripRevision = _strip.revision;
    final cached = _cachedAllPages;
    if (cached != null &&
        _cachedCacheRevision == cacheRevision &&
        _cachedStripRevision == stripRevision) {
      return cached;
    }

    final placements = <ReaderV2VisiblePage>[];
    for (final chapterIndex in _cacheManager.chapterIndexes()) {
      final chapter = _cacheManager.chapterAt(chapterIndex);
      final chapterTop = _strip.chapterTop(chapterIndex);
      if (chapter == null || chapterTop == null) continue;
      for (var pageIndex = 0; pageIndex < chapter.pages.length; pageIndex++) {
        final page = chapter.pages[pageIndex];
        final extent = chapter.pageExtentAt(pageIndex);
        final pageOffset = chapter.pageOffsetTop(pageIndex);
        if (pageOffset == null) continue;
        placements.add(
          ReaderV2VisiblePage(
            layout: chapter.layout,
            page: page,
            worldTop: chapterTop + pageOffset,
            extent: extent,
          ),
        );
      }
    }
    placements.sort((a, b) => a.worldTop.compareTo(b.worldTop));
    final result = List<ReaderV2VisiblePage>.unmodifiable(placements);
    _cachedAllPages = result;
    _cachedCacheRevision = cacheRevision;
    _cachedStripRevision = stripRevision;
    return result;
  }

  List<ReaderV2VisiblePage> visiblePages({
    required double readingY,
    required double viewportHeight,
  }) {
    final pages = allPages();
    if (pages.isEmpty) return const <ReaderV2VisiblePage>[];
    final visibleTop = readingY;
    final visibleBottom = readingY + viewportHeight;
    final start = _firstPageEndingAfter(pages, visibleTop);
    if (start >= pages.length) return const <ReaderV2VisiblePage>[];

    final visible = <ReaderV2VisiblePage>[];
    for (var index = start; index < pages.length; index++) {
      final placement = pages[index];
      if (placement.worldTop >= visibleBottom) break;
      if (placement.worldBottom > visibleTop) {
        visible.add(placement);
      }
    }
    return visible;
  }

  ReaderV2VisiblePage? placementAtWorldY(double worldY) {
    final pages = allPages();
    if (pages.isEmpty) return null;
    final candidateIndex = _lastPageStartingAtOrBefore(pages, worldY);
    if (candidateIndex >= 0) {
      final candidate = pages[candidateIndex];
      if (worldY < candidate.worldBottom) return candidate;
    }
    if (candidateIndex < 0) return pages.first;
    if (candidateIndex >= pages.length - 1) return pages.last;

    final before = pages[candidateIndex];
    final after = pages[candidateIndex + 1];
    final distanceToBefore = (worldY - before.worldBottom).abs();
    final distanceToAfter = (after.worldTop - worldY).abs();
    return distanceToBefore <= distanceToAfter ? before : after;
  }

  int _firstPageEndingAfter(List<ReaderV2VisiblePage> pages, double worldY) {
    var low = 0;
    var high = pages.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (pages[mid].worldBottom > worldY) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  int _lastPageStartingAtOrBefore(
    List<ReaderV2VisiblePage> pages,
    double worldY,
  ) {
    var low = 0;
    var high = pages.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (pages[mid].worldTop <= worldY) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }
}
