import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
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

  void updateRuntime(ReaderV2Runtime nextRuntime) {
    runtime = nextRuntime;
    _configure();
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

  double shiftThreshold({required double scrollVelocity}) {
    final base = math.min(120.0, viewportHeight() * 0.2);
    final dynamicLookahead = math.min(
      viewportHeight() * 1.5,
      scrollVelocity.abs() * 0.18,
    );
    return math.max(base, dynamicLookahead);
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
    final center = window.center;
    final centerTop = strip.chapterTop(center.chapterIndex) ?? 0.0;
    strip.placeChapter(
      chapterIndex: center.chapterIndex,
      startY: centerTop,
      height: center.extent,
    );

    var backwardTop = centerTop;
    for (final chapter in window.previous) {
      backwardTop -= chapter.extent;
      strip.placeChapter(
        chapterIndex: chapter.chapterIndex,
        startY: backwardTop,
        height: chapter.extent,
      );
    }

    var forwardTop = centerTop + center.extent;
    for (final chapter in window.next) {
      strip.placeChapter(
        chapterIndex: chapter.chapterIndex,
        startY: forwardTop,
        height: chapter.extent,
      );
      forwardTop += chapter.extent;
    }

    strip.retain(window.retainedChapterIndexes);
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
    visiblePages = ReaderV2VisiblePageCalculator(
      cacheManager: cacheManager,
      strip: strip,
    );
  }

  double _fullPageHeight(ReaderV2PageCache page) {
    return page.height.isFinite && page.height > 0 ? page.height : 1.0;
  }
}
