import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:reader/features/reader_v2/content/reader_v2_content.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:reader/features/reader_v2/render/reader_v2_render_page.dart';

import 'reader_v2_location.dart';
import 'reader_v2_page_window.dart';
import 'reader_v2_performance_metrics.dart';
import 'reader_v2_preload_scheduler.dart';
import 'reader_v2_progress_controller.dart';
import 'reader_v2_resolver.dart';
import 'reader_v2_state.dart';

typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore =
    Future<bool> Function(ReaderV2Location location);

class ReaderV2Runtime extends ChangeNotifier {
  static const double _fastPreloadVelocityLow = 1500;
  static const double _fastPreloadVelocityMedium = 2600;
  static const double _fastPreloadVelocityHigh = 3600;

  ReaderV2Runtime({
    required Book book,
    required ReaderV2ChapterRepository repository,
    required ReaderV2LayoutEngine layoutEngine,
    required ReaderV2ProgressController progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    required ReaderV2Mode initialMode,
    ReaderV2Location? initialLocation,
  }) : _repository = repository,
       _progressController = progressController,
       _initialLocation =
           (initialLocation ??
                   ReaderV2Location(
                     chapterIndex: book.chapterIndex,
                     charOffset: book.charOffset,
                     visualOffsetPx: book.visualOffsetPx,
                   ))
               .normalized(),
       _resolver = ReaderV2Resolver(
         repository: repository,
         layoutEngine: layoutEngine,
         layoutSpec: initialLayoutSpec,
       ),
       state = ReaderV2State(
         mode: initialMode,
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
    _preloadScheduler = ReaderV2PreloadScheduler(resolver: _resolver);
    _attachPerformanceLayoutObserver();
  }

  final ReaderV2ChapterRepository _repository;
  final ReaderV2ProgressController _progressController;
  final ReaderV2Location _initialLocation;
  final ReaderV2Resolver _resolver;
  late final ReaderV2PreloadScheduler _preloadScheduler;
  final ReaderV2PerformanceMetricsRecorder _performanceMetrics =
      ReaderV2PerformanceMetricsRecorder();
  ReaderV2State state;

  bool _disposed = false;
  bool _restoreInProgress = false;
  ReaderV2LayoutStatsObserver? _previousLayoutStatsObserver;
  ReaderV2LayoutStatsObserver? _performanceLayoutStatsObserver;
  Object? _visibleLocationCaptureOwner;
  ReaderV2VisibleLocationCapture? _visibleLocationCapture;
  Object? _viewportRestoreOwner;
  ReaderV2ViewportRestore? _viewportRestore;
  ReaderV2PageAddress? _pendingNeighborAdvanceOrigin;
  int _pendingNeighborAdvanceDirection = 0;
  int _jumpRequestId = 0;
  int _presentationRequestId = 0;
  String? _pendingUserNotice;
  ReaderV2Location? _pendingChapterJumpTarget;

  ReaderV2Resolver get debugResolver => _resolver;
  ReaderV2PerformanceSnapshot get performanceSnapshot =>
      _performanceMetrics.snapshot();
  String get performanceProfilingSignal =>
      performanceSnapshot.toProfilingSignal();
  int get chapterCount => _repository.chapterCount;
  List<BookChapter> get chapters => _repository.chapters;

  BookChapter? chapterAt(int index) => _repository.chapterAt(index);
  String titleFor(int index) => _repository.titleFor(index);
  String chapterUrlAt(int index) => chapterAt(index)?.url ?? '';

  void clearPerformanceMetrics() {
    if (_disposed) return;
    _performanceMetrics.clear();
  }

  void recordFrameTimings(List<FrameTiming> timings) {
    if (_disposed || timings.isEmpty) return;
    _performanceMetrics.recordFrameTimings(timings);
  }

  void debugRecordFrameSample({
    required double totalMs,
    required double buildMs,
    required double rasterMs,
  }) {
    if (_disposed) return;
    _performanceMetrics.recordFrameSample(
      totalMs: totalMs,
      buildMs: buildMs,
      rasterMs: rasterMs,
    );
  }

  void recordFullScreenLoadingSample() {
    if (_disposed) return;
    _performanceMetrics.recordFullScreenLoadingSample();
  }

  void recordOverlayLoadingSample() {
    if (_disposed) return;
    _performanceMetrics.recordOverlayLoadingSample();
  }

  void recordSlidePlaceholderExposure(int placeholderCount) {
    if (_disposed || placeholderCount <= 0) return;
    _performanceMetrics.recordSlidePlaceholderExposure(placeholderCount);
  }

  void registerVisibleLocationCapture(
    Object owner,
    ReaderV2VisibleLocationCapture capture,
  ) {
    _visibleLocationCaptureOwner = owner;
    _visibleLocationCapture = capture;
  }

  void unregisterVisibleLocationCapture(Object owner) {
    if (!identical(_visibleLocationCaptureOwner, owner)) return;
    _visibleLocationCaptureOwner = null;
    _visibleLocationCapture = null;
  }

  void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore) {
    _viewportRestoreOwner = owner;
    _viewportRestore = restore;
  }

  void unregisterViewportRestore(Object owner) {
    if (!identical(_viewportRestoreOwner, owner)) return;
    _viewportRestoreOwner = null;
    _viewportRestore = null;
  }

  String? takeUserNotice() {
    final notice = _pendingUserNotice;
    _pendingUserNotice = null;
    return notice;
  }

  Future<void> openBook() async {
    _setState(state.copyWith(phase: ReaderV2Phase.loading, clearError: true));
    try {
      await _repository.ensureChapters();
      final location = _initialLocation.normalized(
        chapterCount: _repository.chapterCount,
      );
      if (_viewportRestore != null) {
        final restored = await restoreFromLocation(location);
        if (restored || state.phase == ReaderV2Phase.error) return;
      }
      await jumpToLocation(location, immediateSave: false);
      unawaited(_preloadScheduler.scheduleOpen(location.chapterIndex));
    } catch (e) {
      _setState(
        state.copyWith(phase: ReaderV2Phase.error, errorMessage: e.toString()),
      );
    }
  }

  Future<void> applyPresentation({
    required ReaderV2LayoutSpec spec,
    required ReaderV2Mode mode,
  }) async {
    final needLayout = state.layoutSpec.layoutSignature != spec.layoutSignature;
    final needMode = state.mode != mode;
    if (!needLayout && !needMode) return;

    final requestId = ++_presentationRequestId;
    final previousMode = state.mode;
    _clearPendingNeighborAdvance();
    final location =
        _pendingChapterJumpTarget ??
        captureVisibleLocation() ??
        state.visibleLocation;

    var generation = state.layoutGeneration;
    if (needLayout) {
      generation = _preloadScheduler.bumpGeneration();
      _resolver.updateLayoutSpec(spec);
      _setState(
        state.copyWith(
          phase: ReaderV2Phase.switchingMode,
          mode: mode,
          layoutSpec: spec,
          layoutGeneration: generation,
          clearError: true,
          clearPageWindow: true,
          clearCurrentSlidePage: true,
        ),
      );
    } else {
      _setState(
        state.copyWith(
          phase: ReaderV2Phase.switchingMode,
          mode: mode,
          clearError: true,
        ),
      );
    }
    await jumpToLocation(location, immediateSave: false);

    bool stillCurrentPresentation() {
      return !_disposed &&
          requestId == _presentationRequestId &&
          state.layoutGeneration == generation &&
          state.layoutSpec.layoutSignature == spec.layoutSignature &&
          state.mode == mode;
    }

    void restoreStaleModeSwitch() {
      if (!needMode || _disposed || state.mode != mode) return;
      _setState(state.copyWith(mode: previousMode));
    }

    if (!stillCurrentPresentation()) {
      restoreStaleModeSwitch();
      return;
    }
    if (needMode) {
      await _saveVisibleAnchorAfterViewportSettled(
        fallbackLocation: location,
        restoreLocation: location,
        isCurrent: stillCurrentPresentation,
      );
      if (!stillCurrentPresentation()) {
        restoreStaleModeSwitch();
        return;
      }
    }
    if (!_disposed &&
        requestId == _presentationRequestId &&
        state.layoutGeneration == generation &&
        state.layoutSpec.layoutSignature == spec.layoutSignature &&
        state.mode == mode &&
        state.phase != ReaderV2Phase.error &&
        state.phase != ReaderV2Phase.ready) {
      _setState(state.copyWith(phase: ReaderV2Phase.ready));
    }
  }

  Future<void> reloadContentPreservingLocation() async {
    _presentationRequestId += 1;
    final location =
        _pendingChapterJumpTarget ??
        captureVisibleLocation() ??
        state.visibleLocation;
    final generation = _preloadScheduler.bumpGeneration();
    _repository.clearContentCache();
    _resolver.clearCachedLayouts();
    _setState(
      state.copyWith(
        phase: ReaderV2Phase.layingOut,
        layoutGeneration: generation,
        clearError: true,
        clearPageWindow: true,
        clearCurrentSlidePage: true,
      ),
    );
    await jumpToLocation(location, immediateSave: false);
  }

  Future<void> ensureChapters() {
    return _repository.ensureChapters();
  }

  Future<String> textFromVisibleLocation() async {
    final location = state.visibleLocation.normalized(
      chapterCount: _repository.chapterCount,
    );
    final content = await loadContentForTts(location);
    final safeOffset =
        location.charOffset.clamp(0, content.displayText.length).toInt();
    return content.displayText.substring(safeOffset).trim();
  }

  Future<ReaderV2Content> loadContentForTts(ReaderV2Location location) {
    final normalized = location.normalized(
      chapterCount: _repository.chapterCount,
    );
    return _repository.loadContent(normalized.chapterIndex);
  }

  Future<ReaderV2Content> loadContentAt(int chapterIndex) {
    return _repository.loadContent(chapterIndex);
  }

  Future<void> jumpToChapter(int chapterIndex) async {
    final location = _topAlignedChapterLocation(chapterIndex);
    _pendingChapterJumpTarget = location;
    try {
      await jumpToLocation(location, immediateSave: false);
      final normalized = location.normalized(
        chapterCount: _repository.chapterCount,
      );
      if (_disposed ||
          state.phase != ReaderV2Phase.ready ||
          state.visibleLocation != normalized) {
        return;
      }
      await _saveProgressLocation(normalized);
    } finally {
      _pendingChapterJumpTarget = null;
    }
  }

  Future<void> jumpToLocation(
    ReaderV2Location location, {
    bool immediateSave = true,
  }) async {
    _clearPendingNeighborAdvance();
    final requestId = ++_jumpRequestId;
    final generation = state.layoutGeneration;
    _setState(
      state.copyWith(
        phase: ReaderV2Phase.layingOut,
        clearError: true,
        clearPageWindow: true,
        clearCurrentSlidePage: true,
      ),
    );
    try {
      final normalized = location.normalized(
        chapterCount: _repository.chapterCount,
      );
      final page = await _resolver.pageForLocation(normalized);
      if (!_isCurrentJump(requestId, generation)) return;
      final window = await _windowAroundPage(page);
      if (!_isCurrentJump(requestId, generation)) return;
      final resolvedLocation =
          _isTopAlignedChapterStart(normalized)
              ? normalized.copyWith(chapterIndex: page.chapterIndex)
              : ReaderV2Location(
                chapterIndex: page.chapterIndex,
                charOffset:
                    normalized.charOffset
                        .clamp(page.startCharOffset, page.endCharOffset)
                        .toInt(),
                visualOffsetPx: normalized.visualOffsetPx,
              );
      _retainLayoutsForWindow(window);
      _setState(
        state.copyWith(
          phase: ReaderV2Phase.ready,
          visibleLocation: resolvedLocation,
          pageWindow: window,
          currentSlidePage: page,
          clearError: true,
        ),
      );
      unawaited(_preloadScheduler.scheduleJump(resolvedLocation.chapterIndex));
      if (immediateSave) {
        unawaited(
          _saveJumpLocationAfterViewportSettled(
            resolvedLocation,
            requestId: requestId,
            generation: generation,
          ),
        );
      }
    } catch (e) {
      if (!_isCurrentJump(requestId, generation)) return;
      _setState(
        state.copyWith(phase: ReaderV2Phase.error, errorMessage: e.toString()),
      );
    }
  }

  Future<bool> restoreFromLocation(ReaderV2Location location) async {
    if (_disposed || _viewportRestore == null) return false;
    _clearPendingNeighborAdvance();
    final generation = state.layoutGeneration;
    _restoreInProgress = true;
    _setState(
      state.copyWith(
        phase: ReaderV2Phase.restoring,
        clearError: true,
        clearPageWindow: true,
        clearCurrentSlidePage: true,
      ),
    );
    try {
      await _repository.ensureChapters();
      final normalized = await _normalizeRestoreLocation(location);
      final page = await _pageForRestoreLocation(normalized);
      if (_disposed || generation != state.layoutGeneration) return false;
      final window = await _windowAroundPage(page);
      if (_disposed || generation != state.layoutGeneration) return false;
      final restoreTarget = _locationForRestorePage(normalized, page);
      _retainLayoutsForWindow(window);
      _setState(
        state.copyWith(
          phase: ReaderV2Phase.ready,
          pageWindow: window,
          currentSlidePage: page,
          clearError: true,
        ),
      );
      final restore = _viewportRestore;
      if (restore == null) return false;
      final positioned = await restore(restoreTarget);
      if (!positioned || _disposed || generation != state.layoutGeneration) {
        return false;
      }
      if (_isTopAlignedChapterStart(restoreTarget)) {
        _setState(state.copyWith(visibleLocation: restoreTarget));
        return true;
      }
      final captured = _captureVisibleLocation(allowDuringRestore: true);
      return captured != null;
    } catch (e) {
      if (!_disposed && generation == state.layoutGeneration) {
        _setState(
          state.copyWith(
            phase: ReaderV2Phase.error,
            errorMessage: e.toString(),
          ),
        );
      }
      return false;
    } finally {
      _restoreInProgress = false;
    }
  }

  bool moveToNextPage({bool saveSettledProgress = true}) {
    final window = state.pageWindow;
    final next = window?.next;
    if (window == null) return false;
    if (next == null) {
      _clearPendingNeighborAdvance();
      return false;
    }
    if (next.isPlaceholder) {
      if (next.isLoading) {
        _rememberPendingNeighborAdvance(current: window.current, forward: true);
      } else {
        _clearPendingNeighborAdvance();
        _emitUserNotice('下一章載入失敗，請再試一次或返回目錄');
      }
      _scheduleMissingNeighborPreload(forward: true);
      return false;
    }
    _clearPendingNeighborAdvance();
    final newNext = _resolver.nextPageOrPlaceholder(next);
    final newWindow = ReaderV2PageWindow(
      prev: window.current,
      current: next,
      next: newNext,
      lookAhead: const <ReaderV2RenderPage>[],
    );
    _retainLayoutsForWindow(newWindow);
    final location = ReaderV2Location(
      chapterIndex: next.chapterIndex,
      charOffset: next.startCharOffset,
    );
    _setState(
      state.copyWith(
        pageWindow: newWindow,
        currentSlidePage: next,
        visibleLocation: location,
        phase: ReaderV2Phase.ready,
      ),
    );
    unawaited(_preloadScheduler.scheduleScrollSettled(next));
    if (saveSettledProgress) {
      _saveSettledSlideProgress(location);
    }
    return true;
  }

  bool moveToPrevPage({bool saveSettledProgress = true}) {
    final window = state.pageWindow;
    final prev = window?.prev;
    if (window == null) return false;
    if (prev == null) {
      _clearPendingNeighborAdvance();
      return false;
    }
    if (prev.isPlaceholder) {
      if (prev.isLoading) {
        _rememberPendingNeighborAdvance(
          current: window.current,
          forward: false,
        );
      } else {
        _clearPendingNeighborAdvance();
        _emitUserNotice('上一章載入失敗，請再試一次或返回目錄');
      }
      _scheduleMissingNeighborPreload(forward: false);
      return false;
    }
    _clearPendingNeighborAdvance();
    final newPrev = _resolver.prevPageOrPlaceholder(prev);
    final newWindow = ReaderV2PageWindow(
      prev: newPrev,
      current: prev,
      next: window.current,
      lookAhead: const <ReaderV2RenderPage>[],
    );
    _retainLayoutsForWindow(newWindow);
    final location = ReaderV2Location(
      chapterIndex: prev.chapterIndex,
      charOffset: prev.startCharOffset,
    );
    _setState(
      state.copyWith(
        pageWindow: newWindow,
        currentSlidePage: prev,
        visibleLocation: location,
        phase: ReaderV2Phase.ready,
      ),
    );
    unawaited(_preloadScheduler.scheduleScrollSettled(prev));
    if (saveSettledProgress) {
      _saveSettledSlideProgress(location);
    }
    return true;
  }

  bool moveToNextTile({bool saveSettledProgress = true}) {
    return moveToNextPage(saveSettledProgress: saveSettledProgress);
  }

  bool moveToPrevTile({bool saveSettledProgress = true}) {
    return moveToPrevPage(saveSettledProgress: saveSettledProgress);
  }

  bool moveSlidePageAndSettle({
    required bool forward,
    ReaderV2Location? settledLocation,
  }) {
    if (state.mode != ReaderV2Mode.slide) return false;
    final moved =
        forward
            ? moveToNextPage(saveSettledProgress: false)
            : moveToPrevPage(saveSettledProgress: false);
    if (!moved) return false;
    settleCurrentSlidePage(settledLocation: settledLocation);
    return true;
  }

  void preloadSlideNeighbor({required bool forward}) {
    if (state.mode != ReaderV2Mode.slide) return;
    final window = state.pageWindow;
    if (window == null) return;
    final current = window.current;
    if (current.isPlaceholder) return;
    final neighbor = forward ? window.next : window.prev;
    if (neighbor == null) return;
    if (neighbor.isPlaceholder) {
      unawaited(ensureSlideNeighborReady(forward: forward));
      return;
    }
    final nearCurrentBoundary = _isNearChapterBoundary(
      current,
      forward: forward,
    );
    final nearNeighborBoundary = _isNearChapterBoundary(
      neighbor,
      forward: forward,
    );
    if (!nearCurrentBoundary && !nearNeighborBoundary) return;
    unawaited(
      _scheduleNeighborPreloadFrom(
        chapterIndex: current.chapterIndex,
        forward: forward,
      ),
    );
  }

  void beginInteractivePreloadPause() {
    if (_disposed) return;
    _preloadScheduler.beginInteractive();
  }

  void endInteractivePreloadPause() {
    if (_disposed) return;
    _preloadScheduler.endInteractive();
  }

  bool get debugIsPreloadLayoutPaused => _preloadScheduler.isInteractive;

  Future<void> preloadDirectionalForVelocity({
    required int chapterIndex,
    required bool forward,
    required double velocity,
  }) {
    if (_disposed || _repository.chapterCount <= 0) {
      return Future<void>.value();
    }
    final speed = velocity.abs();
    final span =
        speed >= _fastPreloadVelocityHigh
            ? 3
            : speed >= _fastPreloadVelocityMedium
            ? 2
            : speed >= _fastPreloadVelocityLow
            ? 1
            : 0;
    if (span <= 0) return Future<void>.value();
    return _preloadScheduler.scheduleDirectional(
      fromChapterIndex: chapterIndex,
      forward: forward,
      chapterSpan: span,
    );
  }

  Future<bool> ensureSlideNeighborReady({required bool forward}) async {
    if (state.mode != ReaderV2Mode.slide) return false;
    final window = state.pageWindow;
    if (window == null) return false;
    final current = window.current;
    if (current.isPlaceholder) return false;
    final neighbor = forward ? window.next : window.prev;
    if (neighbor == null) return false;
    if (!neighbor.isPlaceholder) return true;

    final origin = _resolver.addressOf(current);
    await _scheduleNeighborPreloadFrom(
      chapterIndex: current.chapterIndex,
      forward: forward,
    );
    if (_disposed || state.mode != ReaderV2Mode.slide) return false;
    final latestWindow = state.pageWindow;
    if (latestWindow == null ||
        !_samePageAddress(_resolver.addressOf(latestWindow.current), origin)) {
      return false;
    }
    await refreshNeighbors();
    if (_disposed || state.mode != ReaderV2Mode.slide) return false;
    final refreshedWindow = state.pageWindow;
    if (refreshedWindow == null ||
        !_samePageAddress(
          _resolver.addressOf(refreshedWindow.current),
          origin,
        )) {
      return false;
    }
    final refreshedNeighbor =
        forward ? refreshedWindow.next : refreshedWindow.prev;
    return refreshedNeighbor != null && !refreshedNeighbor.isPlaceholder;
  }

  void settleCurrentSlidePage({ReaderV2Location? settledLocation}) {
    if (state.mode != ReaderV2Mode.slide) return;
    final current = state.pageWindow?.current;
    if (current == null || current.isPlaceholder) return;
    final location =
        settledLocation ??
        ReaderV2Location(
          chapterIndex: current.chapterIndex,
          charOffset: current.startCharOffset,
        );
    _setState(
      state.copyWith(currentSlidePage: current, visibleLocation: location),
    );
    unawaited(
      _saveVisibleAnchorAfterViewportSettled(
        fallbackLocation: location,
        isCurrent: () => _isCurrentSlidePage(_resolver.addressOf(current)),
      ),
    );
    unawaited(_preloadScheduler.scheduleSlidePageSettled(current));
  }

  Future<void> refreshNeighbors() async {
    final window = state.pageWindow;
    if (window == null) return;
    final generation = state.layoutGeneration;
    final current = window.current;
    final currentAddress = _resolver.addressOf(current);
    final prev =
        _resolver.prevPageSync(current) ??
        await _resolver.prevPage(current, allowAsyncLoad: false);
    final next =
        _resolver.nextPageSync(current) ??
        await _resolver.nextPage(current, allowAsyncLoad: false);
    final latestWindow = state.pageWindow;
    if (_disposed ||
        generation != state.layoutGeneration ||
        latestWindow == null ||
        !_samePageAddress(
          _resolver.addressOf(latestWindow.current),
          currentAddress,
        )) {
      return;
    }
    final refreshedWindow = ReaderV2PageWindow(
      prev: prev ?? _resolver.prevPageOrPlaceholder(current),
      current: current,
      next: next ?? _resolver.nextPageOrPlaceholder(current),
      lookAhead: const <ReaderV2RenderPage>[],
    );
    _retainLayoutsForWindow(refreshedWindow);
    _setState(state.copyWith(pageWindow: refreshedWindow));
    _maybeAutoAdvancePendingNeighbor();
  }

  ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true}) =>
      _captureVisibleLocation(notifyIfChanged: notifyIfChanged);

  Future<ReaderV2Location?> saveProgress({bool immediate = true}) async {
    if (_restoreInProgress) return null;
    final location = captureVisibleLocation(notifyIfChanged: false);
    if (location == null) return null;
    return _saveProgressLocation(location, immediate: immediate);
  }

  Future<ReaderV2Location?> flushProgress() {
    if (_restoreInProgress) return Future<ReaderV2Location?>.value();
    final location =
        captureVisibleLocation(notifyIfChanged: false) ?? state.visibleLocation;
    return _saveProgressLocation(location);
  }

  bool _isCurrentJump(int requestId, int generation) {
    return !_disposed &&
        requestId == _jumpRequestId &&
        generation == state.layoutGeneration;
  }

  Future<ReaderV2Location?> _saveJumpLocationAfterViewportSettled(
    ReaderV2Location location, {
    required int requestId,
    required int generation,
  }) {
    return _saveVisibleAnchorAfterViewportSettled(
      fallbackLocation: location,
      restoreLocation: location,
      isCurrent: () => _isCurrentJump(requestId, generation),
    );
  }

  Future<ReaderV2Location?> _saveVisibleAnchorAfterViewportSettled({
    required ReaderV2Location fallbackLocation,
    ReaderV2Location? restoreLocation,
    bool Function()? isCurrent,
    bool immediateSave = true,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (WidgetsBinding.instance.hasScheduledFrame) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (_disposed || _restoreInProgress) return null;
    if (isCurrent != null && !isCurrent()) return null;
    final restore = _viewportRestore;
    if (restoreLocation != null && restore != null) {
      final restored = await restore(restoreLocation);
      if (_disposed || _restoreInProgress) return null;
      if (isCurrent != null && !isCurrent()) return null;
      if (!restored) return null;
    }
    final saved = await saveProgress(immediate: immediateSave);
    if (saved != null) return saved;
    if (_disposed || _restoreInProgress) return null;
    if (isCurrent != null && !isCurrent()) return null;
    return _saveProgressLocation(fallbackLocation, immediate: immediateSave);
  }

  Future<ReaderV2Location> _normalizeRestoreLocation(
    ReaderV2Location location,
  ) async {
    await _repository.ensureChapters();
    final chapterCount = _repository.chapterCount;
    final chapterIndex =
        chapterCount <= 0
            ? 0
            : location.chapterIndex.clamp(0, chapterCount - 1).toInt();
    final content = await _repository.loadContent(chapterIndex);
    return ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: location.charOffset,
      visualOffsetPx: location.visualOffsetPx,
    ).normalized(
      chapterCount: chapterCount,
      chapterLength: content.displayText.length,
    );
  }

  Future<ReaderV2RenderPage> _pageForRestoreLocation(
    ReaderV2Location location,
  ) async {
    if (state.mode == ReaderV2Mode.slide) {
      return _slidePageForRestoreLocation(location);
    }
    return _resolver.pageForLocation(location);
  }

  Future<ReaderV2RenderPage> _slidePageForRestoreLocation(
    ReaderV2Location location,
  ) async {
    final layout = await _resolver.ensureLayout(location.chapterIndex);
    if (layout.pages.isEmpty) return layout.pageForCharOffset(0);
    final basePage = layout.pageForCharOffset(location.charOffset);
    final anchorY = _anchorOffsetInViewport();
    final desiredLineTopOnPage =
        anchorY - state.layoutSpec.style.paddingTop - location.visualOffsetPx;
    ReaderV2RenderPage? bestPage;
    int? bestCharDistance;
    double? bestVisualDistance;
    for (
      var index = basePage.pageIndex - 1;
      index <= basePage.pageIndex + 1;
      index++
    ) {
      if (index < 0 || index >= layout.pages.length) continue;
      final page = layout.pages[index];
      final nearestLine = _nearestLineOnPage(page, desiredLineTopOnPage);
      final charDistance =
          ((nearestLine?.startCharOffset ?? page.startCharOffset) -
                  location.charOffset)
              .abs();
      final visualDistance =
          nearestLine == null
              ? double.infinity
              : (nearestLine.top - desiredLineTopOnPage).abs();
      if (bestPage == null ||
          charDistance < bestCharDistance! ||
          (charDistance == bestCharDistance &&
              visualDistance < bestVisualDistance!)) {
        bestPage = page;
        bestCharDistance = charDistance;
        bestVisualDistance = visualDistance;
      }
    }
    return bestPage ?? basePage;
  }

  ReaderV2RenderLine? _nearestLineOnPage(
    ReaderV2RenderPage page,
    double pageY,
  ) {
    ReaderV2RenderLine? nearest;
    var nearestDistance = double.infinity;
    for (final line in page.lines) {
      if (line.text.isEmpty) continue;
      if (pageY >= line.top && pageY <= line.bottom) return line;
      final distance =
          pageY < line.top ? line.top - pageY : pageY - line.bottom;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = line;
      }
    }
    return nearest;
  }

  Future<ReaderV2PageWindow> _windowAroundPage(ReaderV2RenderPage page) async {
    final prev = _resolver.prevPageOrPlaceholder(page);
    final next = _resolver.nextPageOrPlaceholder(page);
    return ReaderV2PageWindow(
      prev: prev,
      current: page,
      next: next,
      lookAhead: const <ReaderV2RenderPage>[],
    );
  }

  ReaderV2Location _locationForRestorePage(
    ReaderV2Location location,
    ReaderV2RenderPage page,
  ) {
    return ReaderV2Location(
      chapterIndex: page.chapterIndex,
      charOffset:
          location.charOffset
              .clamp(page.startCharOffset, page.endCharOffset)
              .toInt(),
      visualOffsetPx: location.visualOffsetPx,
    );
  }

  double _anchorOffsetInViewport() => state.layoutSpec.anchorOffsetInViewport;

  ReaderV2Location _topAlignedChapterLocation(int chapterIndex) {
    return ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: 0,
      visualOffsetPx: _anchorOffsetInViewport(),
    );
  }

  bool _isTopAlignedChapterStart(ReaderV2Location location) {
    return location.charOffset == 0 &&
        (location.visualOffsetPx - _anchorOffsetInViewport()).abs() < 0.01;
  }

  bool _samePageAddress(ReaderV2PageAddress a, ReaderV2PageAddress b) {
    return a.chapterIndex == b.chapterIndex && a.pageIndex == b.pageIndex;
  }

  bool _isCurrentSlidePage(ReaderV2PageAddress address) {
    if (_disposed || state.mode != ReaderV2Mode.slide) return false;
    final current = state.pageWindow?.current;
    if (current == null || current.isPlaceholder) return false;
    return current.chapterIndex == address.chapterIndex &&
        current.pageIndex == address.pageIndex;
  }

  ReaderV2Location? _captureVisibleLocation({
    bool allowDuringRestore = false,
    bool notifyIfChanged = true,
  }) {
    if (_disposed || state.phase != ReaderV2Phase.ready) return null;
    if (_restoreInProgress && !allowDuringRestore) return null;
    final capture = _visibleLocationCapture;
    if (capture == null) return null;
    final captured = _normalizeCapturedLocation(capture());
    if (captured == null) return null;
    if (captured == state.visibleLocation) return captured;
    final next = state.copyWith(visibleLocation: captured);
    if (notifyIfChanged) {
      _setState(next);
    } else {
      state = next;
    }
    return captured;
  }

  Future<ReaderV2Location?> _saveProgressLocation(
    ReaderV2Location location, {
    bool immediate = true,
  }) async {
    if (_disposed || _restoreInProgress) return null;
    final normalized = location.normalized(
      chapterCount: _repository.chapterCount,
    );
    if (normalized == state.committedLocation) {
      if (normalized != state.visibleLocation) {
        _setState(state.copyWith(visibleLocation: normalized));
      }
      if (immediate) {
        await _progressController.flush();
      }
      return normalized;
    }
    _setState(
      state.copyWith(
        visibleLocation: normalized,
        committedLocation: normalized,
      ),
    );
    if (immediate) {
      await _progressController.saveImmediately(normalized);
    } else {
      _progressController.schedule(normalized);
    }
    return normalized;
  }

  void _saveSettledSlideProgress(ReaderV2Location location) {
    if (state.mode != ReaderV2Mode.slide) return;
    final current = state.pageWindow?.current;
    if (current == null || current.isPlaceholder) return;
    final pageAddress = ReaderV2PageAddress(
      chapterIndex: current.chapterIndex,
      pageIndex: current.pageIndex,
    );
    unawaited(
      _saveVisibleAnchorAfterViewportSettled(
        fallbackLocation: location,
        isCurrent: () => _isCurrentSlidePage(pageAddress),
        immediateSave: false,
      ),
    );
  }

  ReaderV2Location? _normalizeCapturedLocation(ReaderV2Location? location) {
    if (location == null) return null;
    final visualOffset = location.visualOffsetPx;
    if (!visualOffset.isFinite || visualOffset.isNaN) return null;
    if (visualOffset < ReaderV2Location.minVisualOffsetPx ||
        visualOffset > ReaderV2Location.maxVisualOffsetPx) {
      return null;
    }
    return location.normalized(chapterCount: _repository.chapterCount);
  }

  void _scheduleMissingNeighborPreload({required bool forward}) {
    final window = state.pageWindow;
    if (window == null) return;
    unawaited(
      _scheduleNeighborPreloadFrom(
        chapterIndex: window.current.chapterIndex,
        forward: forward,
        refreshAfter: true,
      ),
    );
  }

  Future<void> _scheduleNeighborPreloadFrom({
    required int chapterIndex,
    required bool forward,
    bool refreshAfter = false,
  }) {
    final target = chapterIndex + (forward ? 1 : -1);
    if (target < 0 || target >= _repository.chapterCount) {
      return Future<void>.value();
    }
    final preload = _preloadScheduler.scheduleLayout(target, priority: true);
    if (!refreshAfter) {
      return preload;
    }
    return preload.whenComplete(() {
      if (!_disposed) unawaited(refreshNeighbors());
    });
  }

  bool _isNearChapterBoundary(
    ReaderV2RenderPage page, {
    required bool forward,
  }) {
    if (page.isPlaceholder || page.pageSize <= 0) return false;
    if (forward) {
      return page.pageIndex >=
          page.pageSize - ReaderV2PreloadScheduler.boundaryPreloadPageDistance;
    }
    return page.pageIndex <
        ReaderV2PreloadScheduler.boundaryPreloadPageDistance;
  }

  void _rememberPendingNeighborAdvance({
    required ReaderV2RenderPage current,
    required bool forward,
  }) {
    _pendingNeighborAdvanceOrigin = _resolver.addressOf(current);
    _pendingNeighborAdvanceDirection = forward ? 1 : -1;
  }

  void _clearPendingNeighborAdvance() {
    _pendingNeighborAdvanceOrigin = null;
    _pendingNeighborAdvanceDirection = 0;
  }

  void _maybeAutoAdvancePendingNeighbor() {
    final direction = _pendingNeighborAdvanceDirection;
    final origin = _pendingNeighborAdvanceOrigin;
    final window = state.pageWindow;
    if (direction == 0 || origin == null || window == null) return;
    final currentAddress = _resolver.addressOf(window.current);
    if (currentAddress.chapterIndex != origin.chapterIndex ||
        currentAddress.pageIndex != origin.pageIndex) {
      _clearPendingNeighborAdvance();
      return;
    }
    final forward = direction > 0;
    final neighbor = forward ? window.next : window.prev;
    if (neighbor == null) {
      _clearPendingNeighborAdvance();
      return;
    }
    if (neighbor.isLoading) return;
    if (neighbor.errorMessage != null) {
      _clearPendingNeighborAdvance();
      _emitUserNotice(forward ? '下一章載入失敗，請再試一次或返回目錄' : '上一章載入失敗，請再試一次或返回目錄');
      return;
    }
    if (state.mode == ReaderV2Mode.slide) {
      moveSlidePageAndSettle(forward: forward);
      return;
    }
    if (forward) {
      moveToNextPage();
    } else {
      moveToPrevPage();
    }
  }

  void _emitUserNotice(String message) {
    if (_disposed || message.isEmpty) return;
    _pendingUserNotice = message;
    notifyListeners();
  }

  void _retainLayoutsForWindow(ReaderV2PageWindow window) {
    final chapterIndexes = <int>{...window.chapterIndexes};
    final currentChapterIndex = window.current.chapterIndex;
    if (currentChapterIndex > 0) {
      chapterIndexes.add(currentChapterIndex - 1);
    }
    if (currentChapterIndex + 1 < _repository.chapterCount) {
      chapterIndexes.add(currentChapterIndex + 1);
    }
    _resolver.retainLayoutsFor(chapterIndexes);
  }

  void _setState(ReaderV2State next) {
    if (_disposed) return;
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
    _disposed = true;
    _detachPerformanceLayoutObserver();
    _preloadScheduler.dispose();
    _progressController.dispose();
    super.dispose();
  }
}
