import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';
import 'reader_v2_operation_token.dart';
import 'reader_v2_page_window.dart';
import 'reader_v2_performance_metrics.dart';
import 'reader_v2_preload_scheduler.dart';
import 'reader_v2_progress_controller.dart';
import 'reader_v2_resolver.dart';
import 'reader_v2_state.dart';
import 'reader_v2_state_machine.dart';

import 'reader_v2_navigation_controller.dart';
import 'reader_v2_viewport_bridge.dart';

typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore =
    Future<bool> Function(ReaderV2Location location);

class ReaderV2Runtime extends ChangeNotifier {
  factory ReaderV2Runtime({
    required Book book,
    required ReaderV2ChapterRepository repository,
    required ReaderV2LayoutEngine layoutEngine,
    required ReaderV2ProgressController progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    ReaderV2Location? initialLocation,
  }) {
    final location =
        (initialLocation ??
                ReaderV2Location(
                  chapterIndex: book.chapterIndex,
                  charOffset: book.charOffset,
                  visualOffsetPx: book.visualOffsetPx,
                ))
            .normalized();
    return ReaderV2Runtime._(
      repository: repository,
      layoutEngine: layoutEngine,
      progressController: progressController,
      initialLayoutSpec: initialLayoutSpec,
      initialLocation: location,
    );
  }

  ReaderV2Runtime._({
    required this.repository,
    required ReaderV2LayoutEngine layoutEngine,
    required this.progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    required ReaderV2Location initialLocation,
  }) : _initialLocation = initialLocation,
       resolver = ReaderV2Resolver(
         repository: repository,
         layoutEngine: layoutEngine,
         layoutSpec: initialLayoutSpec,
       ),
       stateMachine = ReaderV2StateMachine(
         ReaderV2State(
           phase: ReaderV2Phase.cold,
           committedLocation: initialLocation,
           visibleLocation: initialLocation,
           layoutSpec: initialLayoutSpec,
           layoutGeneration: 0,
         ),
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
  final ReaderV2StateMachine stateMachine;

  late final ReaderV2NavigationController navigation;
  late final ReaderV2ViewportBridge viewportBridge;

  bool disposed = false;
  ReaderV2Location? pendingChapterJumpTarget;
  Object? _hybridViewportOwner;

  ReaderV2LayoutStatsObserver? _previousLayoutStatsObserver;
  ReaderV2LayoutStatsObserver? _performanceLayoutStatsObserver;

  ReaderV2PerformanceSnapshot get performanceSnapshot =>
      _performanceMetrics.snapshot();
  String get performanceProfilingSignal =>
      performanceSnapshot.toProfilingSignal();
  ReaderV2State get state => stateMachine.state;

  bool get restoreInProgress => stateMachine.restoreInProgress;
  bool get hybridViewportActive => _hybridViewportOwner != null;

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

  void registerHybridViewport(Object owner) {
    _hybridViewportOwner = owner;
  }

  void unregisterHybridViewport(Object owner) {
    if (identical(_hybridViewportOwner, owner)) {
      _hybridViewportOwner = null;
    }
  }

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
      viewportBridge.captureVisibleLocation(notifyIfChanged: notifyIfChanged);

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
    if (hybridViewportActive) return false;
    return navigation.moveToNextPage(saveSettledProgress: saveSettledProgress);
  }

  bool moveToPrevPage({bool saveSettledProgress = true}) {
    if (hybridViewportActive) return false;
    return navigation.moveToPrevPage(saveSettledProgress: saveSettledProgress);
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
    if (hybridViewportActive) return _jumpHybridToChapter(chapterIndex);
    return navigation.jumpToChapter(chapterIndex);
  }

  Future<void> jumpToLocation(
    ReaderV2Location location, {
    bool immediateSave = true,
  }) {
    if (hybridViewportActive) {
      return _jumpHybridToLocation(location, immediateSave: immediateSave);
    }
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
    var token = stateMachine.beginOpen();
    notifyListeners();
    try {
      await repository.ensureChapters();
      final location = _initialLocation.normalized(
        chapterCount: repository.chapterCount,
      );
      if (hybridViewportActive) {
        final positioned = await _positionHybridViewport(
          location: location,
          token: token,
        );
        if (!positioned && stateMachine.isCurrent(token)) {
          failOperation(token, StateError('Hybrid viewport restore failed.'));
        }
        return;
      }
      if (viewportBridge.viewportRestore != null) {
        final restored = await navigation.restoreFromLocation(location);
        if (restored || state.phase == ReaderV2Phase.error) return;
        token = stateMachine.beginOpen();
        notifyListeners();
      }
      await navigation.jumpToLocation(
        location,
        immediateSave: false,
        operationToken: token,
      );
      unawaited(preloadScheduler.scheduleOpen(location.chapterIndex));
    } catch (e) {
      if (stateMachine.fail(token, e)) notifyListeners();
    }
  }

  Future<void> applyPresentation({required ReaderV2LayoutSpec spec}) async {
    final needLayout = state.layoutSpec.layoutSignature != spec.layoutSignature;
    if (!needLayout) return;

    navigation.clearPendingNeighborAdvance();
    final location =
        pendingChapterJumpTarget ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;

    if (hybridViewportActive) {
      final token = stateMachine.beginPresentation(
        spec: spec,
        layoutGeneration: state.layoutGeneration + 1,
      );
      notifyListeners();
      try {
        final positioned = await _positionHybridViewport(
          location: location,
          token: token,
        );
        if (!positioned && stateMachine.isCurrent(token)) {
          failOperation(
            token,
            StateError('Hybrid presentation restore failed.'),
          );
        }
      } catch (error) {
        failOperation(token, error);
      }
      return;
    }

    final generation = preloadScheduler.bumpGeneration();
    resolver.updateLayoutSpec(spec);
    final token = stateMachine.beginPresentation(
      spec: spec,
      layoutGeneration: generation,
    );
    notifyListeners();
    await navigation.jumpToLocation(
      location,
      immediateSave: false,
      operationToken: token,
    );

    bool stillCurrentPresentation() {
      return !disposed &&
          stateMachine.isCurrent(token) &&
          state.layoutSpec.layoutSignature == spec.layoutSignature;
    }

    if (!stillCurrentPresentation()) return;

    if (!disposed &&
        stateMachine.isCurrent(token) &&
        state.layoutSpec.layoutSignature == spec.layoutSignature &&
        state.phase != ReaderV2Phase.error &&
        state.phase != ReaderV2Phase.ready) {
      if (stateMachine.completeReady(token)) notifyListeners();
    }
  }

  Future<void> reloadContentPreservingLocation() async {
    final location =
        pendingChapterJumpTarget ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;
    if (hybridViewportActive) {
      repository.clearContentCache();
      final token = stateMachine.beginContentReload(
        layoutGeneration: state.layoutGeneration + 1,
      );
      notifyListeners();
      try {
        final positioned = await _positionHybridViewport(
          location: location,
          token: token,
        );
        if (!positioned && stateMachine.isCurrent(token)) {
          failOperation(token, StateError('Hybrid content restore failed.'));
        }
      } catch (error) {
        failOperation(token, error);
      }
      return;
    }
    final generation = preloadScheduler.bumpGeneration();
    repository.clearContentCache();
    resolver.clearCachedLayouts();
    final token = stateMachine.beginContentReload(layoutGeneration: generation);
    notifyListeners();
    await navigation.jumpToLocation(
      location,
      immediateSave: false,
      operationToken: token,
    );
  }

  bool isCurrentOperationToken(ReaderV2OperationToken token) {
    return !disposed && stateMachine.isCurrent(token);
  }

  ReaderV2OperationToken beginJumpOperation() {
    final token = stateMachine.beginJump();
    notifyListeners();
    return token;
  }

  ReaderV2OperationToken beginRestoreOperation() {
    final token = stateMachine.beginRestore();
    notifyListeners();
    return token;
  }

  void endRestoreOperation(ReaderV2OperationToken token) {
    stateMachine.endRestore(token);
  }

  bool completeReadyOperation(
    ReaderV2OperationToken token, {
    ReaderV2Location? visibleLocation,
    ReaderV2PageWindow? pageWindow,
  }) {
    final completed = stateMachine.completeReady(
      token,
      visibleLocation: visibleLocation,
      pageWindow: pageWindow,
    );
    if (completed) notifyListeners();
    return completed;
  }

  bool failOperation(ReaderV2OperationToken token, Object error) {
    final failed = stateMachine.fail(token, error);
    if (failed) notifyListeners();
    return failed;
  }

  void updateVisibleLocation(ReaderV2Location location, {bool notify = true}) {
    if (disposed) return;
    stateMachine.updateVisibleLocation(location);
    if (notify) notifyListeners();
  }

  void commitProgressLocation(ReaderV2Location location) {
    if (disposed) return;
    stateMachine.commitLocation(location);
    notifyListeners();
  }

  void updateReadyPosition({
    required ReaderV2Location visibleLocation,
    required ReaderV2PageWindow pageWindow,
  }) {
    if (disposed) return;
    stateMachine.updateReadyPosition(
      visibleLocation: visibleLocation,
      pageWindow: pageWindow,
    );
    notifyListeners();
  }

  void updatePageWindow(ReaderV2PageWindow pageWindow) {
    if (disposed) return;
    stateMachine.updatePageWindow(pageWindow);
    notifyListeners();
  }

  void notifySessionChanged() {
    if (disposed) return;
    notifyListeners();
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

  Future<void> _jumpHybridToChapter(int chapterIndex) async {
    final location = ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: 0,
      visualOffsetPx: state.layoutSpec.anchorOffsetInViewport,
    );
    pendingChapterJumpTarget = location;
    try {
      await _jumpHybridToLocation(location, immediateSave: false);
      final normalized = location.normalized(
        chapterCount: repository.chapterCount,
      );
      if (disposed ||
          state.phase != ReaderV2Phase.ready ||
          state.visibleLocation != normalized) {
        return;
      }
      await viewportBridge.saveProgressLocation(normalized);
    } finally {
      if (identical(pendingChapterJumpTarget, location)) {
        pendingChapterJumpTarget = null;
      }
    }
  }

  Future<void> _jumpHybridToLocation(
    ReaderV2Location location, {
    required bool immediateSave,
  }) async {
    final token = beginJumpOperation();
    try {
      final positioned = await _positionHybridViewport(
        location: location,
        token: token,
      );
      if (!positioned) {
        if (stateMachine.isCurrent(token)) {
          failOperation(token, StateError('Hybrid jump restore failed.'));
        }
        return;
      }
      if (immediateSave) {
        await viewportBridge.saveProgressLocation(state.visibleLocation);
      }
    } catch (error) {
      failOperation(token, error);
    }
  }

  Future<bool> _positionHybridViewport({
    required ReaderV2Location location,
    required ReaderV2OperationToken token,
  }) async {
    await repository.ensureChapters();
    if (!stateMachine.isCurrent(token)) return false;
    final chapterCount = repository.chapterCount;
    if (chapterCount <= 0) return false;
    final chapterIndex =
        location.chapterIndex.clamp(0, chapterCount - 1).toInt();
    final content = await repository.loadContent(chapterIndex);
    if (!stateMachine.isCurrent(token)) return false;
    final normalized = ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: location.charOffset,
      visualOffsetPx: location.visualOffsetPx,
    ).normalized(
      chapterCount: chapterCount,
      chapterLength: content.displayText.length,
    );
    final restore = viewportBridge.viewportRestore;
    if (restore == null || !await restore(normalized)) return false;
    if (!stateMachine.isCurrent(token)) return false;
    return completeReadyOperation(token, visibleLocation: normalized);
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
    _hybridViewportOwner = null;
    _detachPerformanceLayoutObserver();
    preloadScheduler.dispose();
    progressController.dispose();
    super.dispose();
  }
}
