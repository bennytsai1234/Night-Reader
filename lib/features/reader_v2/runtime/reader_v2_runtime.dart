import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_painter.dart';

import 'reader_v2_location.dart';
import 'reader_v2_performance_metrics.dart';
import 'reader_v2_preload_scheduler.dart';
import 'reader_v2_progress_controller.dart';
import 'reader_v2_resolver.dart';
import 'reader_v2_state.dart';

import 'reader_v2_navigation_controller.dart';
import 'reader_v2_viewport_bridge.dart';

typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore =
    Future<bool> Function(ReaderV2Location location);

class ReaderV2Runtime extends ChangeNotifier {
  ReaderV2Runtime({
    required Book book,
    required ReaderV2ChapterRepository repository,
    required ReaderV2LayoutEngine layoutEngine,
    required ReaderV2ProgressController progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    ReaderV2Location? initialLocation,
  }) : repository = repository,
       progressController = progressController,
       _initialLocation =
           (initialLocation ??
                   ReaderV2Location(
                     chapterIndex: book.chapterIndex,
                     charOffset: book.charOffset,
                     visualOffsetPx: book.visualOffsetPx,
                   ))
               .normalized(),
       resolver = ReaderV2Resolver(
         repository: repository,
         layoutEngine: layoutEngine,
         layoutSpec: initialLayoutSpec,
       ),
       state = ReaderV2State(
         phase: ReaderV2Phase.cold,
         committedLocation:
             (initialLocation ??
                     ReaderV2Location(
                       chapterIndex: book.chapterIndex,
                       charOffset: book.charOffset,
                       visualOffsetPx: book.visualOffsetPx,
                     ))
                 .normalized(),
         visibleLocation:
             (initialLocation ??
                     ReaderV2Location(
                       chapterIndex: book.chapterIndex,
                       charOffset: book.charOffset,
                       visualOffsetPx: book.visualOffsetPx,
                     ))
                 .normalized(),
         layoutSpec: initialLayoutSpec,
         layoutGeneration: 0,
       ) {
    preloadScheduler = ReaderV2PreloadScheduler(resolver: resolver);
    viewportBridge = ReaderV2ViewportBridge(this);
    navigation = ReaderV2NavigationController(this);
    _attachPerformanceLayoutObserver();
  }

  final ReaderV2ChapterRepository repository;
  final ReaderV2ProgressController progressController;
  final ReaderV2Location _initialLocation;
  final ReaderV2Resolver resolver;
  late final ReaderV2PreloadScheduler preloadScheduler;
  final ReaderV2PerformanceMetricsRecorder _performanceMetrics =
      ReaderV2PerformanceMetricsRecorder();
  ReaderV2State state;

  late final ReaderV2NavigationController navigation;
  late final ReaderV2ViewportBridge viewportBridge;

  bool disposed = false;
  bool restoreInProgress = false;
  int jumpRequestId = 0;
  int presentationRequestId = 0;
  ReaderV2Location? pendingChapterJumpTarget;

  ReaderV2LayoutStatsObserver? _previousLayoutStatsObserver;
  ReaderV2LayoutStatsObserver? _performanceLayoutStatsObserver;

  @deprecated
  ReaderV2Resolver get debugResolver => resolver;
  ReaderV2PerformanceSnapshot get performanceSnapshot =>
      _performanceMetrics.snapshot();
  String get performanceProfilingSignal =>
      performanceSnapshot.toProfilingSignal();
  int get chapterCount => repository.chapterCount;
  List<BookChapter> get chapters => repository.chapters;

  BookChapter? chapterAt(int index) => repository.chapterAt(index);
  String titleFor(int index) => repository.titleFor(index);
  String chapterUrlAt(int index) => chapterAt(index)?.url ?? '';

  void clearPerformanceMetrics() {
    if (disposed) return;
    _performanceMetrics.clear();
  }

  void recordFrameTimings(List<FrameTiming> timings) {
    if (disposed || timings.isEmpty) return;
    _performanceMetrics.recordFrameTimings(timings);
  }

  void debugRecordFrameSample({
    required double totalMs,
    required double buildMs,
    required double rasterMs,
  }) {
    if (disposed) return;
    _performanceMetrics.recordFrameSample(
      totalMs: totalMs,
      buildMs: buildMs,
      rasterMs: rasterMs,
    );
  }

  void recordFullScreenLoadingSample() {
    if (disposed) return;
    _performanceMetrics.recordFullScreenLoadingSample();
  }

  void recordOverlayLoadingSample() {
    if (disposed) return;
    _performanceMetrics.recordOverlayLoadingSample();
  }

  // -- Viewport bridge delegation --

  void registerVisibleLocationCapture(
    Object owner,
    ReaderV2VisibleLocationCapture capture,
  ) {
    viewportBridge.registerVisibleLocationCapture(owner, capture);
  }

  void unregisterVisibleLocationCapture(Object owner) {
    viewportBridge.unregisterVisibleLocationCapture(owner);
  }

  void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore) {
    viewportBridge.registerViewportRestore(owner, restore);
  }

  void unregisterViewportRestore(Object owner) {
    viewportBridge.unregisterViewportRestore(owner);
  }

  ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true}) =>
      viewportBridge.captureVisibleLocation(
        notifyIfChanged: notifyIfChanged,
      );

  Future<ReaderV2Location?> saveProgress({
    ReaderV2Location? location,
    bool immediate = true,
  }) async {
    return viewportBridge.saveProgress(
      location: location,
      immediate: immediate,
    );
  }

  Future<ReaderV2Location?> flushProgress() {
    return viewportBridge.flushProgress();
  }

  // -- Navigation delegation --

  bool moveToNextPage({bool saveSettledProgress = true}) {
    return navigation.moveToNextPage(saveSettledProgress: saveSettledProgress);
  }

  bool moveToPrevPage({bool saveSettledProgress = true}) {
    return navigation.moveToPrevPage(saveSettledProgress: saveSettledProgress);
  }

  bool moveToNextTile({bool saveSettledProgress = true}) {
    return navigation.moveToNextTile(saveSettledProgress: saveSettledProgress);
  }

  bool moveToPrevTile({bool saveSettledProgress = true}) {
    return navigation.moveToPrevTile(saveSettledProgress: saveSettledProgress);
  }

  void beginInteractivePreloadPause() {
    navigation.beginInteractivePreloadPause();
  }

  void endInteractivePreloadPause() {
    navigation.endInteractivePreloadPause();
  }

  bool get debugIsPreloadLayoutPaused => navigation.debugIsPreloadLayoutPaused;

  Future<void> preloadDirectionalForVelocity({
    required int chapterIndex,
    required bool forward,
    required double velocity,
  }) {
    return navigation.preloadDirectionalForVelocity(
      chapterIndex: chapterIndex,
      forward: forward,
      velocity: velocity,
    );
  }

  Future<void> jumpToChapter(int chapterIndex) {
    return navigation.jumpToChapter(chapterIndex);
  }

  Future<void> jumpToLocation(
    ReaderV2Location location, {
    bool immediateSave = true,
  }) {
    return navigation.jumpToLocation(location, immediateSave: immediateSave);
  }

  Future<bool> restoreFromLocation(ReaderV2Location location) {
    return navigation.restoreFromLocation(location);
  }

  Future<void> refreshNeighbors() {
    return navigation.refreshNeighbors();
  }

  // -- Runtime-owned methods --

  String? takeUserNotice() => navigation.takeUserNotice();

  Future<void> openBook() async {
    setState(state.copyWith(phase: ReaderV2Phase.loading, clearError: true));
    try {
      await repository.ensureChapters();
      final location = _initialLocation.normalized(
        chapterCount: repository.chapterCount,
      );
      if (viewportBridge.viewportRestore != null) {
        final restored = await navigation.restoreFromLocation(location);
        if (restored || state.phase == ReaderV2Phase.error) return;
      }
      await navigation.jumpToLocation(location, immediateSave: false);
      unawaited(preloadScheduler.scheduleOpen(location.chapterIndex));
    } catch (e) {
      setState(
        state.copyWith(phase: ReaderV2Phase.error, errorMessage: e.toString()),
      );
    }
  }

  Future<void> applyPresentation({
    required ReaderV2LayoutSpec spec,
  }) async {
    final needLayout = state.layoutSpec.layoutSignature != spec.layoutSignature;
    if (!needLayout) return;

    final requestId = ++presentationRequestId;
    navigation.clearPendingNeighborAdvance();
    final location =
        pendingChapterJumpTarget ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;

    final generation = preloadScheduler.bumpGeneration();
    resolver.updateLayoutSpec(spec);
    setState(
      state.copyWith(
        phase: ReaderV2Phase.switchingMode,
        layoutSpec: spec,
        layoutGeneration: generation,
        clearError: true,
        clearPageWindow: true,
      ),
    );
    await navigation.jumpToLocation(location, immediateSave: false);

    bool stillCurrentPresentation() {
      return !disposed &&
          requestId == presentationRequestId &&
          state.layoutGeneration == generation &&
          state.layoutSpec.layoutSignature == spec.layoutSignature;
    }

    if (!stillCurrentPresentation()) return;

    if (!disposed &&
        requestId == presentationRequestId &&
        state.layoutGeneration == generation &&
        state.layoutSpec.layoutSignature == spec.layoutSignature &&
        state.phase != ReaderV2Phase.error &&
        state.phase != ReaderV2Phase.ready) {
      setState(state.copyWith(phase: ReaderV2Phase.ready));
    }
  }

  Future<void> reloadContentPreservingLocation() async {
    presentationRequestId += 1;
    final location =
        pendingChapterJumpTarget ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;
    final generation = preloadScheduler.bumpGeneration();
    repository.clearContentCache();
    resolver.clearCachedLayouts();
    setState(
      state.copyWith(
        phase: ReaderV2Phase.layingOut,
        layoutGeneration: generation,
        clearError: true,
        clearPageWindow: true,
      ),
    );
    await navigation.jumpToLocation(location, immediateSave: false);
  }

  Future<void> ensureChapters() {
    return repository.ensureChapters();
  }

  Future<String> textFromVisibleLocation() async {
    final location = state.visibleLocation.normalized(
      chapterCount: repository.chapterCount,
    );
    final content = await loadContentForTts(location);
    final safeOffset =
        location.charOffset.clamp(0, content.displayText.length).toInt();
    return content.displayText.substring(safeOffset).trim();
  }

  Future<ReaderV2Content> loadContentForTts(ReaderV2Location location) {
    final normalized = location.normalized(
      chapterCount: repository.chapterCount,
    );
    return repository.loadContent(normalized.chapterIndex);
  }

  Future<ReaderV2Content> loadContentAt(int chapterIndex) {
    return repository.loadContent(chapterIndex);
  }

  void setState(ReaderV2State next) {
    if (disposed) return;
    state = next;
    notifyListeners();
  }

  void _attachPerformanceLayoutObserver() {
    _previousLayoutStatsObserver = ReaderV2LayoutEngine.debugOnStats;
    _performanceLayoutStatsObserver = (stats) {
      _performanceMetrics.recordLayoutStats(stats);
      _previousLayoutStatsObserver?.call(stats);
    };
    ReaderV2LayoutEngine.debugOnStats = _performanceLayoutStatsObserver;
  }

  void _detachPerformanceLayoutObserver() {
    if (identical(
      ReaderV2LayoutEngine.debugOnStats,
      _performanceLayoutStatsObserver,
    )) {
      ReaderV2LayoutEngine.debugOnStats = _previousLayoutStatsObserver;
    }
    _performanceLayoutStatsObserver = null;
    _previousLayoutStatsObserver = null;
  }

  @override
  void dispose() {
    disposed = true;
    _detachPerformanceLayoutObserver();
    preloadScheduler.dispose();
    progressController.dispose();
    ReaderV2TilePainter.invalidateCache();
    super.dispose();
  }
}
