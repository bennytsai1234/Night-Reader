import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_infinite_segment_strip.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_position_tracker.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_visible_page_calculator.dart';

class ScrollReaderV2ViewportModel {
  static const double maxForwardWindowExtent = 6000.0;
  static const double maxBackwardWindowExtent = 2400.0;
  static const double maxFlingWindowBoost = 4000.0;
  static const double flingWindowBoostSeconds = 0.6;

  ScrollReaderV2ViewportModel({
    required ReaderV2Runtime runtime,
    required ReaderV2Style style,
  }) : runtime = runtime,
       style = style {
    _configure();
  }

  ReaderV2Runtime runtime;
  ReaderV2Style style;

  late ReaderV2ChapterPageCacheManager cacheManager;
  late ReaderV2VisiblePageCalculator visiblePages;
  final ReaderV2InfiniteSegmentStrip strip = ReaderV2InfiniteSegmentStrip();
  final ReaderV2PositionTracker positionTracker =
      const ReaderV2PositionTracker();

  int? currentChapterIndex;
  int _windowRequestId = 0;
  double _activeForwardWindowBoost = 0.0;
  double _activeBackwardWindowBoost = 0.0;

  /// 視窗內章節因背景排版推進而更新（strip 已同步重錨）後通知，viewport
  /// State 據此觸發重繪，讓新長出來的內容不必等下一次滑動就出現。
  void Function()? onWindowContentChanged;

  /// 被往上鎖定的上一章排完後通知（已通過相關性守衛：該章不在 strip、
  /// 其下一章在 strip），viewport State 據此排程視窗重建把它接上，讓停在
  /// 章界等待的使用者不必再滑一下才看到真章尾。
  void Function(int chapterIndex)? onBackwardChapterReady;

  void updateRuntime(ReaderV2Runtime nextRuntime) {
    cacheManager.dispose();
    runtime = nextRuntime;
    _configure();
  }

  void dispose() {
    cacheManager.dispose();
    onWindowContentChanged = null;
    onBackwardChapterReady = null;
  }

  void updateStyle(ReaderV2Style nextStyle) {
    style = nextStyle;
  }

  void resetLoadedState() {
    cacheManager.invalidateAll(reason: 'viewport reset');
    strip.clear();
    _windowRequestId += 1;
    currentChapterIndex = null;
    _activeForwardWindowBoost = 0.0;
    _activeBackwardWindowBoost = 0.0;
  }

  double viewportHeight() {
    final height = runtime.state.layoutSpec.viewportSize.height;
    return height.isFinite && height > 0 ? height : 1.0;
  }

  double anchorOffsetInViewport() {
    return runtime.state.layoutSpec.anchorOffsetInViewport;
  }

  ({double min, double max})? scrollBounds() {
    return strip.scrollBounds(
      viewportHeight: viewportHeight(),
      anchorOffset: anchorOffsetInViewport(),
    );
  }

  ReaderV2Style scrollRenderStyle() {
    return style.copyWith(paddingTop: 0, paddingBottom: 0);
  }

  /// 一律用最大提前量擴張視窗：不論拖曳中（速度來源本來就恆為 0）、甩動減速
  /// 尾聲、或靜止，都不再依當下速度縮小門檻，用記憶體/CPU 換取滑動時不再
  /// 因臨時排版而卡頓。
  double shiftThreshold({required double scrollVelocity}) {
    return viewportHeight() * 1.5;
  }

  double forwardWindowExtent() {
    final base = viewportHeight() * 8.0 + anchorOffsetInViewport();
    return math.min(base, maxForwardWindowExtent) + _activeForwardWindowBoost;
  }

  double backwardWindowExtent() {
    final base = viewportHeight() * 3.0;
    return math.min(base, maxBackwardWindowExtent) + _activeBackwardWindowBoost;
  }

  void updateWindowBoostForFling(double velocity) {
    final boost = math.min(
      velocity.abs() * flingWindowBoostSeconds,
      maxFlingWindowBoost,
    );
    _activeForwardWindowBoost = velocity > 0 ? boost : 0.0;
    _activeBackwardWindowBoost = velocity < 0 ? boost : 0.0;
  }

  bool clearWindowBoost() {
    if (_activeForwardWindowBoost == 0.0 && _activeBackwardWindowBoost == 0.0) {
      return false;
    }
    _activeForwardWindowBoost = 0.0;
    _activeBackwardWindowBoost = 0.0;
    return true;
  }

  int safeChapterIndex(int chapterIndex) {
    final chapterCount = runtime.chapterCount;
    if (chapterCount <= 0) return 0;
    return chapterIndex.clamp(0, chapterCount - 1).toInt();
  }

  Future<bool> tryEnsureChapterLoaded(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    if (runtime.chapterCount <= 0) return false;
    final safeIndex = safeChapterIndex(chapterIndex);
    return cacheManager.ensureChapterLoaded(safeIndex, isCurrent: isCurrent);
  }

  Future<bool> ensureWindowAround(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    if (runtime.chapterCount <= 0) return false;
    final requestId = ++_windowRequestId;
    bool stillCurrent() {
      return requestId == _windowRequestId && (isCurrent?.call() ?? true);
    }

    final center = safeChapterIndex(chapterIndex);
    final window = await cacheManager.ensureWindowAround(
      centerChapterIndex: center,
      backwardExtent: backwardWindowExtent(),
      forwardExtent: forwardWindowExtent(),
      isCurrent: stillCurrent,
    );
    if (!stillCurrent() || window == null) return false;

    placeWindowInStrip(window);
    currentChapterIndex = window.center.chapterIndex;
    return true;
  }

  void placeWindowInStrip(ReaderV2ChapterPageCacheWindow window) {
    // 快照只提供章節清單與順序；高度一律取 cacheManager 的即時 extent——
    // ensureWindowAround 的 await 期間章節可能已被背景排版重新包裝長高，
    // 用快照的舊高度重放會讓即時頁面超出段落底、疊進下一段。
    double liveExtent(ReaderV2CachedChapterPages chapter) {
      return cacheManager.chapterAt(chapter.chapterIndex)?.extent ??
          chapter.extent;
    }

    final center = window.center;
    final centerTop = strip.chapterTop(center.chapterIndex) ?? 0.0;
    final centerExtent = liveExtent(center);
    strip.placeChapter(
      chapterIndex: center.chapterIndex,
      startY: centerTop,
      height: centerExtent,
    );

    var backwardTop = centerTop;
    for (final chapter in window.previous) {
      final extent = liveExtent(chapter);
      backwardTop -= extent;
      strip.placeChapter(
        chapterIndex: chapter.chapterIndex,
        startY: backwardTop,
        height: extent,
      );
    }

    var forwardTop = centerTop + centerExtent;
    for (final chapter in window.next) {
      final extent = liveExtent(chapter);
      strip.placeChapter(
        chapterIndex: chapter.chapterIndex,
        startY: forwardTop,
        height: extent,
      );
      forwardTop += extent;
    }

    strip.retain(window.retainedChapterIndexes);
    assert(
      _debugNoSegmentBelowPartialChapter(window),
      '部分就緒章節（中心章含以後）下方不得有相鄰段落——背景長高時重錨會誤判為 '
      'bottom 對齊的上一章、往上長疊進前一章（章節跳轉文字重疊回歸）',
    );
  }

  /// Debug 不變量：位於中心章（含）之後、尚未排完的章節必須是視窗前向
  /// 邊界，下方不得緊貼任何段落。中心章之前的部分就緒章節本來就以
  /// bottom 貼齊下一章放置，屬合法情況。
  bool _debugNoSegmentBelowPartialChapter(ReaderV2ChapterPageCacheWindow window) {
    for (final chapterIndex in window.retainedChapterIndexes) {
      if (chapterIndex < window.center.chapterIndex) continue;
      final chapter = cacheManager.chapterAt(chapterIndex);
      if (chapter == null || chapter.isComplete) continue;
      final end = strip.chapterEnd(chapterIndex);
      final belowTop = strip.chapterTop(chapterIndex + 1);
      if (end != null && belowTop != null && (belowTop - end).abs() < 0.5) {
        return false;
      }
    }
    return true;
  }

  double? readingYForLocation(ReaderV2Location location) {
    final chapterIndex = safeChapterIndex(location.chapterIndex);
    if (isTopAlignedChapterStart(location)) {
      return strip.chapterTop(chapterIndex);
    }
    return positionTracker.readingYForLocation(
      location: location.copyWith(chapterIndex: chapterIndex),
      cacheManager: cacheManager,
      strip: strip,
      anchorOffset: anchorOffsetInViewport(),
      style: scrollRenderStyle(),
    );
  }

  double clampReadingY(double target) {
    final bounds = scrollBounds();
    if (bounds == null) return target;
    return target.clamp(bounds.min, bounds.max).toDouble();
  }

  ReaderV2Location? captureVisibleLocation({
    required bool initialJumpCompleted,
    required double readingY,
  }) {
    if (!initialJumpCompleted || runtime.chapterCount <= 0) {
      return null;
    }
    return positionTracker.captureVisibleLocation(
      calculator: visiblePages,
      cacheManager: cacheManager,
      strip: strip,
      readingY: readingY,
      anchorOffset: anchorOffsetInViewport(),
      style: scrollRenderStyle(),
    );
  }

  bool isTopAlignedChapterStart(ReaderV2Location location) {
    return location.charOffset == 0 &&
        (location.visualOffsetPx - anchorOffsetInViewport()).abs() < 0.01;
  }

  bool isAtBookBoundaryForDelta(double readingDelta, double readingY) {
    final bounds = scrollBounds();
    if (bounds == null || runtime.chapterCount <= 0) return false;
    const tolerance = 0.5;
    if (readingDelta < 0) {
      return strip.containsChapter(0) && readingY <= bounds.min + tolerance;
    }
    if (readingDelta > 0) {
      final lastChapterIndex = runtime.chapterCount - 1;
      return strip.containsChapter(lastChapterIndex) &&
          readingY >= bounds.max - tolerance;
    }
    return false;
  }

  bool isArtificialScrollBoundaryForTarget(double target, double readingY) {
    final bounds = scrollBounds();
    if (bounds == null || runtime.chapterCount <= 0) return false;
    const tolerance = 0.5;
    if (target > readingY && target >= bounds.max - tolerance) {
      return !strip.containsChapter(runtime.chapterCount - 1);
    }
    if (target < readingY && target <= bounds.min + tolerance) {
      return !strip.containsChapter(0);
    }
    return false;
  }

  bool isNearArtificialWindowEdge({
    required bool forward,
    required double threshold,
    required double readingY,
  }) {
    final bounds = scrollBounds();
    if (bounds == null || runtime.chapterCount <= 0) return false;
    const tolerance = 0.5;
    if (forward) {
      return !strip.containsChapter(runtime.chapterCount - 1) &&
          bounds.max - readingY <= threshold + tolerance;
    }
    return !strip.containsChapter(0) &&
        readingY - bounds.min <= threshold + tolerance;
  }

  bool shouldShiftWindow({
    required int currentChapter,
    required int targetChapter,
    required double anchorWorldY,
    required double threshold,
    required double readingY,
  }) {
    final targetTop = strip.chapterTop(targetChapter);
    final currentTop = strip.chapterTop(currentChapter);
    if (targetTop == null || currentTop == null) return false;
    if (targetChapter > currentChapter) {
      if (isNearWindowEdge(
        forward: true,
        threshold: threshold,
        readingY: readingY,
      )) {
        return true;
      }
      return anchorWorldY - targetTop >= threshold;
    }
    if (isNearWindowEdge(
      forward: false,
      threshold: threshold,
      readingY: readingY,
    )) {
      return true;
    }
    return currentTop - anchorWorldY >= threshold;
  }

  bool isNearWindowEdge({
    required bool forward,
    required double threshold,
    required double readingY,
  }) {
    return strip.isNearEdge(
      forward: forward,
      readingY: readingY,
      threshold: threshold,
      viewportHeight: viewportHeight(),
      anchorOffset: anchorOffsetInViewport(),
    );
  }

  int anchorChapterIndex(double readingY) {
    final anchorWorldY = readingY + anchorOffsetInViewport();
    final placement = visiblePages.placementAtWorldY(anchorWorldY);
    final chapterIndex =
        placement?.page.chapterIndex ??
        runtime.state.visibleLocation.chapterIndex;
    return safeChapterIndex(chapterIndex);
  }

  double scrollPageExtent(ReaderV2PageCache page) {
    final fullHeight = _fullPageHeight(page);
    if (page.lines.isEmpty) return fullHeight;

    final contentBottom = page.lines.fold<double>(
      0.0,
      (bottom, line) => math.max(bottom, line.bottom),
    );
    return math.max(1.0, contentBottom);
  }

  void _configure() {
    cacheManager = ReaderV2ChapterPageCacheManager(
      runtime: runtime,
      pageExtent: scrollPageExtent,
    );
    cacheManager.onChapterCacheUpdated = _handleChapterCacheUpdated;
    cacheManager.onBackwardChapterCompleted = _handleBackwardChapterCompleted;
    visiblePages = ReaderV2VisiblePageCalculator(
      cacheManager: cacheManager,
      strip: strip,
    );
  }

  /// 往上鎖定的章節排完了：只在它仍然是「視窗正上方的缺口」時往上通知
  /// ——視窗早已移走的過期完成訊號直接丟棄，避免無關的視窗重建。
  void _handleBackwardChapterCompleted(int chapterIndex) {
    if (strip.containsChapter(chapterIndex)) return;
    if (!strip.containsChapter(chapterIndex + 1)) return;
    onBackwardChapterReady?.call(chapterIndex);
  }

  /// 視窗內章節在背景排版推進後重新包裝完成：同步把 strip 上的佔位段落
  /// 依新高度重錨，再通知 viewport 重繪。
  ///
  /// 重錨規則——下方有相鄰段落（部分就緒的「上一章」以 bottom 貼齊中心章
  /// 頂端放置）時固定 bottom 往上長，避免新長出來的頁面往下疊進下一章的
  /// 世界座標；否則（視窗前緣的「下一章」）固定 top 往下長。
  void _handleChapterCacheUpdated(int chapterIndex) {
    _reanchorGrownChapter(chapterIndex);
    onWindowContentChanged?.call();
  }

  void _reanchorGrownChapter(int chapterIndex) {
    final segmentTop = strip.chapterTop(chapterIndex);
    final segmentEnd = strip.chapterEnd(chapterIndex);
    if (segmentTop == null || segmentEnd == null) return;
    final chapter = cacheManager.chapterAt(chapterIndex);
    if (chapter == null) return;
    final oldHeight = segmentEnd - segmentTop;
    if ((chapter.extent - oldHeight).abs() < 0.5) return;
    final belowTop = strip.chapterTop(chapterIndex + 1);
    final anchoredToBottom =
        belowTop != null && (belowTop - segmentEnd).abs() < 0.5;
    if (anchoredToBottom) {
      strip.placeChapter(
        chapterIndex: chapterIndex,
        startY: segmentEnd - chapter.extent,
        height: chapter.extent,
      );
    } else {
      strip.placeChapter(
        chapterIndex: chapterIndex,
        startY: segmentTop,
        height: chapter.extent,
      );
    }
  }

  double _fullPageHeight(ReaderV2PageCache page) {
    return page.height.isFinite && page.height > 0 ? page.height : 1.0;
  }
}
