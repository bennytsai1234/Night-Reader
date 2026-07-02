import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_chapter_view.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';

typedef ReaderV2ScrollPageExtentResolver =
    double Function(ReaderV2PageCache page);

class ReaderV2CachedChapterPages {
  factory ReaderV2CachedChapterPages({
    required ReaderV2ChapterView layout,
    required List<ReaderV2PageCache> pages,
    required List<double> pageExtents,
  }) {
    final continuousExtents = _continuousPageExtents(pages, pageExtents);
    return ReaderV2CachedChapterPages._(
      layout: layout,
      pages: pages,
      pageExtents: continuousExtents,
    );
  }

  ReaderV2CachedChapterPages._({
    required this.layout,
    required List<ReaderV2PageCache> pages,
    required List<double> pageExtents,
  }) : pages = List<ReaderV2PageCache>.unmodifiable(pages),
       pageExtents = List<double>.unmodifiable(pageExtents),
       pagePrefixOffsets = List<double>.unmodifiable(
         _prefixOffsets(pageExtents),
       ),
       extent = _visualExtent(pageExtents);

  final ReaderV2ChapterView layout;
  final List<ReaderV2PageCache> pages;
  final List<double> pageExtents;
  final List<double> pagePrefixOffsets;
  final double extent;

  int get chapterIndex => layout.chapterIndex;

  /// false 代表這一章排版還沒排完，[extent] 只是目前為止已經排出來的高度，
  /// 之後背景排版繼續推進時還會再變大。
  bool get isComplete => layout.isComplete;

  double pageExtentAt(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pageExtents.length) return 1.0;
    final extent = pageExtents[pageIndex];
    return extent.isFinite && extent > 0 ? extent : 1.0;
  }

  double? pageOffsetTop(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) return null;
    return pagePrefixOffsets[pageIndex];
  }

  static List<double> _prefixOffsets(List<double> pageExtents) {
    final offsets = <double>[];
    var top = 0.0;
    for (final extent in pageExtents) {
      offsets.add(top);
      top += _normalPageExtent(extent);
    }
    return offsets;
  }

  static List<double> _continuousPageExtents(
    List<ReaderV2PageCache> pages,
    List<double> fallbackExtents,
  ) {
    if (pages.isEmpty) return const <double>[];
    // Scroll mode stacks paginated tiles as one continuous chapter, so internal
    // page boundaries follow the next page's layout-local start instead of
    // reusing full viewport-sized page boxes.
    return <double>[
      for (var index = 0; index < pages.length; index++)
        if (index + 1 < pages.length)
          _continuousGap(
            pages[index].localStartY,
            pages[index + 1].localStartY,
            _extentAt(fallbackExtents, index),
          )
        else
          _normalPageExtent(_extentAt(fallbackExtents, index)),
    ];
  }

  static double _continuousGap(
    double currentLocalStart,
    double nextLocalStart,
    double fallback,
  ) {
    final current = currentLocalStart.isFinite ? currentLocalStart : 0.0;
    final next = nextLocalStart.isFinite ? nextLocalStart : current;
    final gap = next - current;
    return gap > 0 ? gap : _normalPageExtent(fallback);
  }

  static double _extentAt(List<double> extents, int index) {
    if (index < 0 || index >= extents.length) return 1.0;
    return extents[index];
  }

  static double _visualExtent(List<double> pageExtents) {
    final extent = pageExtents.fold<double>(
      0.0,
      (total, pageExtent) => total + _normalPageExtent(pageExtent),
    );
    return extent <= 0 ? 1.0 : extent;
  }

  static double _normalPageExtent(double extent) {
    return extent.isFinite && extent > 0 ? extent : 1.0;
  }
}

class ReaderV2ChapterPageCacheWindow {
  const ReaderV2ChapterPageCacheWindow({
    required this.center,
    required this.previous,
    required this.next,
  });

  final ReaderV2CachedChapterPages center;
  final List<ReaderV2CachedChapterPages> previous;
  final List<ReaderV2CachedChapterPages> next;

  Set<int> get retainedChapterIndexes => <int>{
    center.chapterIndex,
    for (final chapter in previous) chapter.chapterIndex,
    for (final chapter in next) chapter.chapterIndex,
  };
}

class ReaderV2ChapterPageCacheManager {
  static const int softRetainRecentChapterCount = 2;

  ReaderV2ChapterPageCacheManager({
    required this.runtime,
    required ReaderV2ScrollPageExtentResolver pageExtent,
  }) : _pageExtent = pageExtent {
    // 已經放進視窗、但排版還沒排完的章節，背景排版繼續推進時要能反映到
    // 畫面上，不必等使用者再滑動才補上新長出來的內容。
    runtime.resolver.onChapterProgressed = _handleChapterProgressed;
  }

  final ReaderV2Runtime runtime;
  final ReaderV2ScrollPageExtentResolver _pageExtent;

  final Map<int, ReaderV2CachedChapterPages> _chapters =
      <int, ReaderV2CachedChapterPages>{};
  final Map<int, Future<ReaderV2CachedChapterPages>> _inFlightLoads =
      <int, Future<ReaderV2CachedChapterPages>>{};
  final Set<int> _evictedChapters = <int>{};
  final Map<int, int> _chapterTouchTicks = <int, int>{};
  int _touchTick = 0;
  int _cacheGeneration = 0;
  int _revision = 0;
  String? _lastInvalidationReason;

  bool get hasChapters => _chapters.isNotEmpty;
  int get cacheGeneration => _cacheGeneration;
  int get revision => _revision;
  String? get lastInvalidationReason => _lastInvalidationReason;

  bool containsChapter(int chapterIndex) => _chapters.containsKey(chapterIndex);

  ReaderV2CachedChapterPages? chapterAt(int chapterIndex) {
    return _chapters[chapterIndex];
  }

  List<int> chapterIndexes() {
    return _chapters.keys.toList(growable: false)..sort();
  }

  Future<ReaderV2CachedChapterPages?> ensureChapter(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    if (runtime.chapterCount <= 0) return null;
    final safeIndex = _safeChapterIndex(chapterIndex);
    final cached = _chapters[safeIndex];
    if (cached != null) {
      _touchChapter(safeIndex);
      return cached;
    }
    _evictedChapters.remove(safeIndex);
    final generation = _cacheGeneration;
    try {
      final loaded = await _loadChapter(safeIndex);
      if (generation != _cacheGeneration ||
          _evictedChapters.contains(safeIndex) ||
          !(isCurrent?.call() ?? true)) {
        return null;
      }
      _chapters[safeIndex] = loaded;
      _touchChapter(safeIndex);
      _bumpRevision();
      return loaded;
    } catch (_) {
      return null;
    }
  }

  /// 排到「已完成」或「這一章自己的 [ReaderV2CachedChapterPages.extent] ≥
  /// minExtentPx」其中之一先滿足就回傳，不必排完整章——等待時間的上界只跟
  /// minExtentPx 成正比，不跟章節總長度成正比。用於 [ensureWindowAround]
  /// 視窗邊界的章節，避免撞上一整章超長的未排版內容時卡住。
  Future<ReaderV2CachedChapterPages?> ensureChapterAtLeast(
    int chapterIndex, {
    required double minExtentPx,
    bool Function()? isCurrent,
  }) async {
    if (runtime.chapterCount <= 0) return null;
    final safeIndex = _safeChapterIndex(chapterIndex);
    final cached = _chapters[safeIndex];
    if (cached != null && (cached.isComplete || cached.extent >= minExtentPx)) {
      _touchChapter(safeIndex);
      return cached;
    }
    _evictedChapters.remove(safeIndex);
    final generation = _cacheGeneration;
    try {
      // 這裡刻意不走 _loadChapter 的 in-flight 去重——resolver 自己那層已經
      // 用更細的粒度（每個 layoutStep）去重，這裡不必再疊一層以章節為單位
      // 的去重，否則不同呼叫端要求的 minExtentPx 不同時，晚到的呼叫可能被
      // 早到、需求量較小的那次呼叫「頂替」，拿到不夠用的結果。
      final layout = await runtime.resolver.ensureLayoutAtLeast(
        safeIndex,
        minExtentPx: minExtentPx,
      );
      if (generation != _cacheGeneration ||
          _evictedChapters.contains(safeIndex) ||
          !(isCurrent?.call() ?? true)) {
        return null;
      }
      final loaded = _wrapChapterView(layout);
      _chapters[safeIndex] = loaded;
      _touchChapter(safeIndex);
      _bumpRevision();
      return loaded;
    } catch (_) {
      return null;
    }
  }

  Future<bool> ensureChapterLoaded(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    final chapter = await ensureChapter(chapterIndex, isCurrent: isCurrent);
    return chapter != null;
  }

  Future<ReaderV2ChapterPageCacheWindow?> ensureWindowAround({
    required int centerChapterIndex,
    required double backwardExtent,
    required double forwardExtent,
    bool Function()? isCurrent,
  }) async {
    if (runtime.chapterCount <= 0) return null;
    final generation = _cacheGeneration;
    bool stillCurrent() {
      return generation == _cacheGeneration && (isCurrent?.call() ?? true);
    }

    final center = await ensureChapter(
      centerChapterIndex,
      isCurrent: stillCurrent,
    );
    if (center == null || !stillCurrent()) return null;

    final previous = <ReaderV2CachedChapterPages>[];
    var previousIndex = center.chapterIndex - 1;
    var loadedPreviousCount = 0;
    var backwardCoveredExtent = 0.0;
    while (previousIndex >= 0 &&
        (loadedPreviousCount == 0 ||
            backwardCoveredExtent < _normalExtent(backwardExtent))) {
      final remaining = _normalExtent(backwardExtent) - backwardCoveredExtent;
      final chapter = await ensureChapterAtLeast(
        previousIndex,
        minExtentPx: remaining,
        isCurrent: stillCurrent,
      );
      if (!stillCurrent()) return null;
      loadedPreviousCount += 1;
      previousIndex -= 1;
      if (chapter == null) continue;
      previous.add(chapter);
      backwardCoveredExtent += chapter.extent;
      if (!chapter.isComplete) {
        // 這一章排版還沒完成：把它當成目前視窗的邊界，不再往更遠處抓下一
        // 章。它之後在背景繼續長大時只會影響捲動範圍的上限，不會讓已經
        // 放進 strip 的其他章節跟著移動——但前提是後面不能再插入新章節。
        break;
      }
    }

    final next = <ReaderV2CachedChapterPages>[];
    var nextIndex = center.chapterIndex + 1;
    var loadedNextCount = 0;
    var forwardCoveredExtent = 0.0;
    while (nextIndex < runtime.chapterCount &&
        (loadedNextCount == 0 ||
            forwardCoveredExtent < _normalExtent(forwardExtent))) {
      final remaining = _normalExtent(forwardExtent) - forwardCoveredExtent;
      final chapter = await ensureChapterAtLeast(
        nextIndex,
        minExtentPx: remaining,
        isCurrent: stillCurrent,
      );
      if (!stillCurrent()) return null;
      loadedNextCount += 1;
      nextIndex += 1;
      if (chapter == null) continue;
      next.add(chapter);
      forwardCoveredExtent += chapter.extent;
      if (!chapter.isComplete) break;
    }

    if (!stillCurrent()) return null;
    final window = ReaderV2ChapterPageCacheWindow(
      center: center,
      previous: List<ReaderV2CachedChapterPages>.unmodifiable(previous),
      next: List<ReaderV2CachedChapterPages>.unmodifiable(next),
    );
    evictOutsideWindow(window.retainedChapterIndexes);
    return window;
  }

  Future<ReaderV2ChapterPageCacheWindow?> preloadAround({
    required int centerChapterIndex,
    required double backwardExtent,
    required double forwardExtent,
    bool Function()? isCurrent,
  }) {
    return ensureWindowAround(
      centerChapterIndex: centerChapterIndex,
      backwardExtent: backwardExtent,
      forwardExtent: forwardExtent,
      isCurrent: isCurrent,
    );
  }

  void evictOutsideWindow(Set<int> retained) {
    final retainedSafeIndexes = retained.map(_safeChapterIndex).toSet();
    final softRetained = _recentlyTouchedChapters(
      retained: retainedSafeIndexes,
      limit: softRetainRecentChapterCount,
    );
    final effectiveRetained = <int>{...retainedSafeIndexes, ...softRetained};
    final evicted = <int>{};
    for (final chapterIndex in _chapters.keys) {
      if (!effectiveRetained.contains(chapterIndex)) {
        evicted.add(chapterIndex);
      }
    }
    for (final chapterIndex in _inFlightLoads.keys) {
      if (!effectiveRetained.contains(chapterIndex)) {
        evicted.add(chapterIndex);
      }
    }
    final hadEvictions = evicted.isNotEmpty;
    _evictedChapters
      ..addAll(evicted)
      ..removeWhere(effectiveRetained.contains);
    _chapterTouchTicks.removeWhere(
      (chapterIndex, _) => !effectiveRetained.contains(chapterIndex),
    );
    _chapters.removeWhere(
      (chapterIndex, _) => !effectiveRetained.contains(chapterIndex),
    );
    _inFlightLoads.removeWhere(
      (chapterIndex, _) => !effectiveRetained.contains(chapterIndex),
    );
    if (hadEvictions) _bumpRevision();
    // 刻意不砍 resolver 的排版快取——讓它用自己的 50 章 LRU，不跟著窗口窄範圍驅逐。
  }

  void retainChapters(Set<int> retained) {
    evictOutsideWindow(retained);
  }

  void evictFarFrom({
    required int centerChapterIndex,
    required int chapterRadius,
  }) {
    final center = _safeChapterIndex(centerChapterIndex);
    final radius = chapterRadius < 0 ? 0 : chapterRadius;
    evictOutsideWindow(<int>{
      for (
        var chapterIndex = center - radius;
        chapterIndex <= center + radius;
        chapterIndex++
      )
        if (_isValidChapterIndex(chapterIndex)) chapterIndex,
    });
  }

  void invalidateAll({String? reason}) {
    _cacheGeneration += 1;
    _bumpRevision();
    _lastInvalidationReason = reason;
    _chapters.clear();
    _inFlightLoads.clear();
    _evictedChapters.clear();
    _chapterTouchTicks.clear();
    _touchTick = 0;
  }

  void clear() {
    invalidateAll(reason: 'clear');
  }

  int _safeChapterIndex(int chapterIndex) {
    final chapterCount = runtime.chapterCount;
    if (chapterCount <= 0) return 0;
    return chapterIndex.clamp(0, chapterCount - 1).toInt();
  }

  bool _isValidChapterIndex(int chapterIndex) {
    return chapterIndex >= 0 && chapterIndex < runtime.chapterCount;
  }

  double _normalExtent(double extent) {
    if (!extent.isFinite || extent <= 0) return 1.0;
    return extent;
  }

  void _bumpRevision() {
    _revision += 1;
  }

  void _touchChapter(int chapterIndex) {
    _touchTick += 1;
    _chapterTouchTicks[chapterIndex] = _touchTick;
  }

  Set<int> _recentlyTouchedChapters({
    required Set<int> retained,
    required int limit,
  }) {
    if (limit <= 0 || _chapterTouchTicks.isEmpty) return const <int>{};
    final ranked = _chapterTouchTicks.entries
      .where((entry) {
        final chapterIndex = entry.key;
        if (retained.contains(chapterIndex)) return false;
        return _chapters.containsKey(chapterIndex) ||
            _inFlightLoads.containsKey(chapterIndex);
      })
      .toList(growable: false)..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty) return const <int>{};
    return ranked.take(limit).map((entry) => entry.key).toSet();
  }

  Future<ReaderV2CachedChapterPages> _loadChapter(int chapterIndex) {
    final safeIndex = _safeChapterIndex(chapterIndex);
    final existing = _inFlightLoads[safeIndex];
    if (existing != null) return existing;

    late final Future<ReaderV2CachedChapterPages> task;
    task = () async {
      try {
        final layout = await runtime.resolver.ensureLayout(
          safeIndex,
          retryOnStale: false,
        );
        return _wrapChapterView(layout);
      } finally {
        if (identical(_inFlightLoads[safeIndex], task)) {
          _inFlightLoads.remove(safeIndex);
        }
      }
    }();
    _inFlightLoads[safeIndex] = task;
    return task;
  }

  ReaderV2CachedChapterPages _wrapChapterView(ReaderV2ChapterView layout) {
    final pages = ReaderV2PageCacheFactory.fromRenderPages(layout.pages);
    final pageExtents = pages.map(_pageExtent).toList(growable: false);
    return ReaderV2CachedChapterPages(
      layout: layout,
      pages: pages,
      pageExtents: pageExtents,
    );
  }

  /// [ReaderV2Resolver.onChapterProgressed] 的訂閱回呼：只處理目前已經放進
  /// 視窗（在 [_chapters] 裡）的章節——背景排版還在推進的其他章節跟目前
  /// 畫面無關，不用理會。純粹重新包裝 resolver 目前最新的快照並 bump
  /// revision，不觸發任何新的排版工作。
  void _handleChapterProgressed(int chapterIndex) {
    if (!_chapters.containsKey(chapterIndex)) return;
    final layout = runtime.resolver.cachedLayout(chapterIndex);
    if (layout == null) return;
    _chapters[chapterIndex] = _wrapChapterView(layout);
    _bumpRevision();
  }
}
