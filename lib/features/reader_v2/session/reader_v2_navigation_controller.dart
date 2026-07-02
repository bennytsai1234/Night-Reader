import 'dart:async';

import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';

import 'reader_v2_location.dart';
import 'reader_v2_operation_token.dart';
import 'reader_v2_page_window.dart';
import 'reader_v2_resolver.dart';
import 'reader_v2_runtime.dart';
import 'reader_v2_state.dart';

class ReaderV2NavigationController {
  final ReaderV2Runtime _runtime;

  ReaderV2NavigationController(this._runtime);

  ReaderV2PageAddress? _pendingNeighborAdvanceOrigin;
  int _pendingNeighborAdvanceDirection = 0;
  String? _pendingUserNotice;

  String? takeUserNotice() {
    final notice = _pendingUserNotice;
    _pendingUserNotice = null;
    return notice;
  }

  void clearPendingNeighborAdvance() {
    _pendingNeighborAdvanceOrigin = null;
    _pendingNeighborAdvanceDirection = 0;
  }

  ReaderV2Location? get pendingChapterJumpTarget =>
      _runtime.pendingChapterJumpTarget;

  void set pendingChapterJumpTarget(ReaderV2Location? value) {
    _runtime.pendingChapterJumpTarget = value;
  }

  bool moveToNextPage({bool saveSettledProgress = true}) {
    final window = _runtime.state.pageWindow;
    final next = window?.next;
    if (window == null) return false;
    if (next == null) {
      clearPendingNeighborAdvance();
      return false;
    }
    if (next.isPlaceholder) {
      if (next.isLoading) {
        _rememberPendingNeighborAdvance(current: window.current, forward: true);
      } else {
        clearPendingNeighborAdvance();
        _emitUserNotice('下一章載入失敗，請再試一次或返回目錄');
      }
      _scheduleMissingNeighborPreload(forward: true);
      return false;
    }
    clearPendingNeighborAdvance();
    final newNext = _runtime.resolver.nextPageOrPlaceholder(next);
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
    _runtime.setState(
      _runtime.state.copyWith(
        pageWindow: newWindow,
        visibleLocation: location,
        phase: ReaderV2Phase.ready,
      ),
    );
    unawaited(_runtime.preloadScheduler.scheduleScrollSettled(next));
    return true;
  }

  bool moveToPrevPage({bool saveSettledProgress = true}) {
    final window = _runtime.state.pageWindow;
    final prev = window?.prev;
    if (window == null) return false;
    if (prev == null) {
      clearPendingNeighborAdvance();
      return false;
    }
    if (prev.isPlaceholder) {
      if (prev.isLoading) {
        _rememberPendingNeighborAdvance(
          current: window.current,
          forward: false,
        );
      } else {
        clearPendingNeighborAdvance();
        _emitUserNotice('上一章載入失敗，請再試一次或返回目錄');
      }
      _scheduleMissingNeighborPreload(forward: false);
      return false;
    }
    clearPendingNeighborAdvance();
    final newPrev = _runtime.resolver.prevPageOrPlaceholder(prev);
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
    _runtime.setState(
      _runtime.state.copyWith(
        pageWindow: newWindow,
        visibleLocation: location,
        phase: ReaderV2Phase.ready,
      ),
    );
    unawaited(_runtime.preloadScheduler.scheduleScrollSettled(prev));
    return true;
  }

  bool moveToNextTile({bool saveSettledProgress = true}) {
    return moveToNextPage(saveSettledProgress: saveSettledProgress);
  }

  bool moveToPrevTile({bool saveSettledProgress = true}) {
    return moveToPrevPage(saveSettledProgress: saveSettledProgress);
  }

  void beginInteractivePreloadPause() {
    if (_runtime.disposed) return;
    _runtime.preloadScheduler.beginInteractive();
  }

  void endInteractivePreloadPause() {
    if (_runtime.disposed) return;
    _runtime.preloadScheduler.endInteractive();
  }

  bool get debugIsPreloadLayoutPaused =>
      _runtime.preloadScheduler.isInteractive;

  Future<void> preloadDirectionalForVelocity({
    required int chapterIndex,
    required bool forward,
    required double velocity,
  }) {
    if (_runtime.disposed || _runtime.repository.chapterCount <= 0) {
      return Future<void>.value();
    }
    const fastPreloadVelocityLow = 1500;
    const fastPreloadVelocityMedium = 2600;
    const fastPreloadVelocityHigh = 3600;
    final speed = velocity.abs();
    final span =
        speed >= fastPreloadVelocityHigh
            ? 3
            : speed >= fastPreloadVelocityMedium
            ? 2
            : speed >= fastPreloadVelocityLow
            ? 1
            : 0;
    if (span <= 0) return Future<void>.value();
    return _runtime.preloadScheduler.scheduleDirectional(
      fromChapterIndex: chapterIndex,
      forward: forward,
      chapterSpan: span,
    );
  }

  Future<void> jumpToChapter(int chapterIndex) async {
    final location = _topAlignedChapterLocation(chapterIndex);
    _runtime.pendingChapterJumpTarget = location;
    try {
      await jumpToLocation(location, immediateSave: false);
      final normalized = location.normalized(
        chapterCount: _runtime.repository.chapterCount,
      );
      if (_runtime.disposed ||
          _runtime.state.phase != ReaderV2Phase.ready ||
          _runtime.state.visibleLocation != normalized) {
        return;
      }
      await _runtime.viewportBridge.saveProgressLocation(normalized);
    } finally {
      _runtime.pendingChapterJumpTarget = null;
    }
  }

  Future<void> jumpToLocation(
    ReaderV2Location location, {
    bool immediateSave = true,
    ReaderV2OperationToken? operationToken,
  }) async {
    clearPendingNeighborAdvance();
    final token = operationToken ?? _runtime.beginJumpOperation();
    try {
      final normalized = location.normalized(
        chapterCount: _runtime.repository.chapterCount,
      );
      final page = await _runtime.resolver.pageForLocation(normalized);
      if (!_isCurrentOperation(token)) return;
      final window = await _windowAroundPage(page);
      if (!_isCurrentOperation(token)) return;
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
      _runtime.completeReadyOperation(
        token,
        visibleLocation: resolvedLocation,
        pageWindow: window,
      );
      unawaited(
        _runtime.preloadScheduler.scheduleJump(resolvedLocation.chapterIndex),
      );
      if (immediateSave) {
        unawaited(
          _runtime.viewportBridge.saveJumpAfterSettled(
            resolvedLocation,
            token: token,
          ),
        );
      }
    } catch (e) {
      _runtime.failOperation(token, e);
    }
  }

  Future<bool> restoreFromLocation(ReaderV2Location location) async {
    if (_runtime.disposed || _runtime.viewportBridge.viewportRestore == null) {
      return false;
    }
    clearPendingNeighborAdvance();
    final token = _runtime.beginRestoreOperation();
    _runtime.restoreInProgress = true;
    try {
      await _runtime.repository.ensureChapters();
      final normalized = await _normalizeRestoreLocation(location);
      final page = await _runtime.resolver.pageForLocation(normalized);
      if (!_isCurrentOperation(token)) return false;
      final window = await _windowAroundPage(page);
      if (!_isCurrentOperation(token)) return false;
      final restoreTarget = _locationForRestorePage(normalized, page);
      _retainLayoutsForWindow(window);
      _runtime.completeReadyOperation(token, pageWindow: window);
      final restore = _runtime.viewportBridge.viewportRestore;
      if (restore == null) return false;
      final positioned = await restore(restoreTarget);
      if (!positioned || !_isCurrentOperation(token)) {
        return false;
      }
      if (_isTopAlignedChapterStart(restoreTarget)) {
        _runtime.setState(
          _runtime.state.copyWith(visibleLocation: restoreTarget),
        );
        return true;
      }
      final captured = _runtime.viewportBridge.captureVisibleLocation(
        allowDuringRestore: true,
      );
      return captured != null;
    } catch (e) {
      _runtime.failOperation(token, e);
      return false;
    } finally {
      _runtime.restoreInProgress = false;
    }
  }

  Future<void> refreshNeighbors() async {
    final window = _runtime.state.pageWindow;
    if (window == null) return;
    final generation = _runtime.state.layoutGeneration;
    final current = window.current;
    final currentAddress = _runtime.resolver.addressOf(current);
    final prev =
        _runtime.resolver.prevPageSync(current) ??
        await _runtime.resolver.prevPage(current, allowAsyncLoad: false);
    final next =
        _runtime.resolver.nextPageSync(current) ??
        await _runtime.resolver.nextPage(current, allowAsyncLoad: false);
    final latestWindow = _runtime.state.pageWindow;
    if (_runtime.disposed ||
        generation != _runtime.state.layoutGeneration ||
        latestWindow == null ||
        !_samePageAddress(
          _runtime.resolver.addressOf(latestWindow.current),
          currentAddress,
        )) {
      return;
    }
    final refreshedWindow = ReaderV2PageWindow(
      prev: prev ?? _runtime.resolver.prevPageOrPlaceholder(current),
      current: current,
      next: next ?? _runtime.resolver.nextPageOrPlaceholder(current),
      lookAhead: const <ReaderV2RenderPage>[],
    );
    _retainLayoutsForWindow(refreshedWindow);
    _runtime.setState(_runtime.state.copyWith(pageWindow: refreshedWindow));
    _maybeAutoAdvancePendingNeighbor();
  }

  void _rememberPendingNeighborAdvance({
    required ReaderV2RenderPage current,
    required bool forward,
  }) {
    _pendingNeighborAdvanceOrigin = _runtime.resolver.addressOf(current);
    _pendingNeighborAdvanceDirection = forward ? 1 : -1;
  }

  void _maybeAutoAdvancePendingNeighbor() {
    final direction = _pendingNeighborAdvanceDirection;
    final origin = _pendingNeighborAdvanceOrigin;
    final window = _runtime.state.pageWindow;
    if (direction == 0 || origin == null || window == null) return;
    final currentAddress = _runtime.resolver.addressOf(window.current);
    if (currentAddress.chapterIndex != origin.chapterIndex ||
        currentAddress.pageIndex != origin.pageIndex) {
      clearPendingNeighborAdvance();
      return;
    }
    final forward = direction > 0;
    final neighbor = forward ? window.next : window.prev;
    if (neighbor == null) {
      clearPendingNeighborAdvance();
      return;
    }
    if (neighbor.isLoading) return;
    if (neighbor.errorMessage != null) {
      clearPendingNeighborAdvance();
      _emitUserNotice(forward ? '下一章載入失敗，請再試一次或返回目錄' : '上一章載入失敗，請再試一次或返回目錄');
      return;
    }
    if (forward) {
      moveToNextPage();
    } else {
      moveToPrevPage();
    }
  }

  bool _isCurrentOperation(ReaderV2OperationToken token) {
    return _runtime.isCurrentOperationToken(token);
  }

  Future<ReaderV2PageWindow> _windowAroundPage(ReaderV2RenderPage page) async {
    final prev = _runtime.resolver.prevPageOrPlaceholder(page);
    final next = _runtime.resolver.nextPageOrPlaceholder(page);
    return ReaderV2PageWindow(
      prev: prev,
      current: page,
      next: next,
      lookAhead: const <ReaderV2RenderPage>[],
    );
  }

  void _retainLayoutsForWindow(ReaderV2PageWindow window) {
    final chapterIndexes = <int>{...window.chapterIndexes};
    final currentChapterIndex = window.current.chapterIndex;
    if (currentChapterIndex > 0) {
      chapterIndexes.add(currentChapterIndex - 1);
    }
    if (currentChapterIndex + 1 < _runtime.repository.chapterCount) {
      chapterIndexes.add(currentChapterIndex + 1);
    }
    _runtime.resolver.retainLayoutsFor(chapterIndexes);
  }

  Future<ReaderV2Location> _normalizeRestoreLocation(
    ReaderV2Location location,
  ) async {
    await _runtime.repository.ensureChapters();
    final chapterCount = _runtime.repository.chapterCount;
    final chapterIndex =
        chapterCount <= 0
            ? 0
            : location.chapterIndex.clamp(0, chapterCount - 1).toInt();
    final content = await _runtime.repository.loadContent(chapterIndex);
    return ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: location.charOffset,
      visualOffsetPx: location.visualOffsetPx,
    ).normalized(
      chapterCount: chapterCount,
      chapterLength: content.displayText.length,
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

  double _anchorOffsetInViewport() =>
      _runtime.state.layoutSpec.anchorOffsetInViewport;

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

  void _scheduleMissingNeighborPreload({required bool forward}) {
    final window = _runtime.state.pageWindow;
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
    if (target < 0 || target >= _runtime.repository.chapterCount) {
      return Future<void>.value();
    }
    final preload = _runtime.preloadScheduler.scheduleLayout(
      target,
      priority: true,
    );
    if (!refreshAfter) {
      return preload;
    }
    return preload.whenComplete(() {
      if (!_runtime.disposed) unawaited(refreshNeighbors());
    });
  }

  void _emitUserNotice(String message) {
    if (_runtime.disposed || message.isEmpty) return;
    _pendingUserNotice = message;
    _runtime.setState(_runtime.state);
  }
}
