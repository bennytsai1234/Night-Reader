import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_canvas.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_command_queue.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_motion_controller.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_viewport_model.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_visible_line.dart';

class ScrollReaderV2Viewport extends StatefulWidget {
  const ScrollReaderV2Viewport({
    super.key,
    required this.runtime,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.onTapUp,
    this.controller,
    this.ttsHighlight,
  });

  final ReaderV2Runtime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final GestureTapUpCallback? onTapUp;
  final ReaderV2ViewportController? controller;
  final ReaderV2TtsHighlight? ttsHighlight;

  @override
  State<ScrollReaderV2Viewport> createState() => _ScrollReaderV2ViewportState();
}

class _ScrollReaderV2ViewportState extends State<ScrollReaderV2Viewport>
    with TickerProviderStateMixin {
  late final ScrollReaderV2MotionController _motion;
  late ScrollReaderV2ViewportModel _viewportModel;
  final ScrollReaderV2CommandQueue _viewportCommands =
      ScrollReaderV2CommandQueue();
  final ScrollReaderV2VisibleLineCalculator _visibleLineCalculator =
      const ScrollReaderV2VisibleLineCalculator();

  ReaderV2Location? _lastReportedLocation;
  ReaderV2Location? _lastSyncedLocation;
  int _lastLayoutGeneration = 0;
  int _runtimeLocationRevision = 0;
  bool _initialJumpCompleted = false;
  bool _capturingVisibleLocation = false;
  bool _visibleLocationCaptureFramePending = false;
  bool _shiftWindowFramePending = false;
  bool _shiftWindowAgainRequested = false;
  Future<void>? _shiftWindowTask;

  @override
  void initState() {
    super.initState();
    _viewportModel = ScrollReaderV2ViewportModel(
      runtime: widget.runtime,
      style: widget.style,
    );
    _motion = ScrollReaderV2MotionController(
      vsync: this,
      runtime: widget.runtime,
      isMounted: () => mounted,
      hasVisiblePages: () => _viewportModel.visiblePages.hasPages,
      viewportHeight: _viewportModel.viewportHeight,
      scrollBounds: _viewportModel.scrollBounds,
      shiftThreshold: _shiftThreshold,
      isArtificialScrollBoundaryForTarget:
          _viewportModel.isArtificialScrollBoundaryForTarget,
      isNearArtificialWindowEdge: _viewportModel.isNearArtificialWindowEdge,
      isAtBookBoundaryForDelta: _viewportModel.isAtBookBoundaryForDelta,
      anchorChapterIndex: _viewportModel.anchorChapterIndex,
      updateWindowBoostForFling: _viewportModel.updateWindowBoostForFling,
      scheduleVisibleLocationCapture: _scheduleVisibleLocationCapture,
      scheduleWindowShiftForAnchor: _scheduleWindowShiftForAnchor,
      requestShiftWindowForAnchor: _requestShiftWindowForAnchor,
      handleScrollSettled: _handleScrollSettled,
    );
    _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
    _lastReportedLocation = widget.runtime.state.visibleLocation;
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.registerVisibleLocationCapture(
      this,
      _captureVisibleLocation,
    );
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
    _attachController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_primeAndSyncToRuntimeLocation(force: true));
    });
  }

  void _endInteractivePreloadPause() {
    _motion.endInteractivePreloadPause();
  }

  @override
  void didUpdateWidget(covariant ScrollReaderV2Viewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _motion.updateRuntime(widget.runtime);
      oldWidget.runtime.unregisterVisibleLocationCapture(this);
      oldWidget.runtime.unregisterViewportRestore(this);
      oldWidget.runtime.removeListener(_onRuntimeChanged);
      widget.runtime.addListener(_onRuntimeChanged);
      widget.runtime.registerVisibleLocationCapture(
        this,
        _captureVisibleLocation,
      );
      widget.runtime.registerViewportRestore(this, _restoreToLocation);
      _viewportModel.updateRuntime(widget.runtime);
      _resetLoadedState();
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _lastReportedLocation = widget.runtime.state.visibleLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_primeAndSyncToRuntimeLocation(force: true));
      });
    } else if (oldWidget.style != widget.style) {
      _viewportModel.updateStyle(widget.style);
      _resetLoadedState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_primeAndSyncToRuntimeLocation(force: true));
      });
    }
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController();
    }
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_onRuntimeChanged);
    widget.runtime.unregisterVisibleLocationCapture(this);
    widget.runtime.unregisterViewportRestore(this);
    _detachController(widget.controller);
    _motion.dispose();
    super.dispose();
  }

  void _attachController() {
    widget.controller
      ?..scrollBy = _scrollBy
      ..continuousScrollBy = _continuousScrollBy
      ..animateBy = _animateBy
      ..moveToNextPage = _moveToNextPage
      ..moveToPrevPage = _moveToPrevPage
      ..settleScroll = _handleScrollSettled
      ..ensureCharRangeVisible = _ensureCharRangeVisible;
  }

  void _detachController(ReaderV2ViewportController? controller) {
    controller
      ?..scrollBy = null
      ..continuousScrollBy = null
      ..animateBy = null
      ..moveToNextPage = null
      ..moveToPrevPage = null
      ..settleScroll = null
      ..ensureCharRangeVisible = null;
  }

  void _resetLoadedState() {
    _viewportModel.resetLoadedState();
    _lastSyncedLocation = null;
    _motion.reset();
    _initialJumpCompleted = false;
  }

  void _clearArtificialMotionState() {
    _motion.clearArtificialMotionState();
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    final state = widget.runtime.state;
    final layoutChanged = _lastLayoutGeneration != state.layoutGeneration;
    if (layoutChanged) {
      _lastLayoutGeneration = state.layoutGeneration;
      _resetLoadedState();
    }

    if (state.phase == ReaderV2Phase.layingOut ||
        state.phase == ReaderV2Phase.switchingMode) {
      setState(() {});
      return;
    }

    if (_capturingVisibleLocation) {
      setState(() {});
      return;
    }

    final locationChanged = state.visibleLocation != _lastReportedLocation;
    if (layoutChanged || locationChanged) {
      _runtimeLocationRevision += 1;
    }
    if (layoutChanged || locationChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _primeAndSyncToRuntimeLocation(
            force: layoutChanged || locationChanged,
          ),
        );
      });
    }
    setState(() {});
  }

  double _viewportHeight() => _viewportModel.viewportHeight();

  double _anchorOffsetInViewport() => _viewportModel.anchorOffsetInViewport();

  // Vertical padding belongs to the viewport/chapter edge in scroll mode, not
  // every paginated tile boundary.
  ReaderV2Style _scrollRenderStyle() => _viewportModel.scrollRenderStyle();

  double _shiftThreshold() {
    return _viewportModel.shiftThreshold(
      scrollVelocity: _motion.scrollVelocity,
    );
  }

  void _clearWindowBoost() {
    if (_viewportModel.clearWindowBoost()) _scheduleWindowShiftForAnchor();
  }

  int _safeChapterIndex(int chapterIndex) =>
      _viewportModel.safeChapterIndex(chapterIndex);

  Future<bool> _tryEnsureChapterLoaded(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    return _viewportModel.tryEnsureChapterLoaded(
      chapterIndex,
      isCurrent: () => mounted && (isCurrent?.call() ?? true),
    );
  }

  Future<void> _ensureWindowAround(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    if (widget.runtime.chapterCount <= 0) return;
    bool stillCurrent() {
      return mounted && (isCurrent?.call() ?? true);
    }

    final placed = await _viewportModel.ensureWindowAround(
      chapterIndex,
      isCurrent: stillCurrent,
    );
    if (!stillCurrent() || !placed) return;

    _motion.consumePendingArtificialDelta();
    final resumedFling = _motion.resumePendingArtificialFlingIfNeeded();
    if (!resumedFling && _motion.isScrollAnimating) {
      _motion.applyReadingTarget(
        _motion.scrollAnimationValue,
        scheduleShift: false,
        captureVisibleLocation: false,
      );
    }
    setState(() {});
  }

  Future<void> _primeAndSyncToRuntimeLocation({bool force = false}) async {
    final location = widget.runtime.state.visibleLocation.normalized(
      chapterCount: widget.runtime.chapterCount,
    );
    final layoutGeneration = widget.runtime.state.layoutGeneration;
    bool stillAtLocation() {
      if (!mounted) return false;
      final currentLocation = widget.runtime.state.visibleLocation.normalized(
        chapterCount: widget.runtime.chapterCount,
      );
      return widget.runtime.state.layoutGeneration == layoutGeneration &&
          currentLocation == location;
    }

    await _ensureWindowAround(
      location.chapterIndex,
      isCurrent: stillAtLocation,
    );
    if (!stillAtLocation()) return;
    if (!force && _initialJumpCompleted && _lastSyncedLocation == location) {
      return;
    }

    final target = _readingYForLocation(location);
    if (target != null) {
      _setReadingY(_clampReadingY(target));
    }
    _initialJumpCompleted = true;
    _lastSyncedLocation = location;
    final captured =
        _isTopAlignedChapterStart(location)
            ? location
            : widget.runtime.captureVisibleLocation(notifyIfChanged: false);
    _lastReportedLocation = captured ?? location;
    if (mounted) setState(() {});
  }

  double? _readingYForLocation(ReaderV2Location location) =>
      _viewportModel.readingYForLocation(location);

  double _clampReadingY(double target) => _viewportModel.clampReadingY(target);

  ReaderV2Location? _captureVisibleLocation() {
    return _viewportModel.captureVisibleLocation(
      initialJumpCompleted: _initialJumpCompleted,
      readingY: _motion.readingY,
    );
  }

  bool _isTopAlignedChapterStart(ReaderV2Location location) =>
      _viewportModel.isTopAlignedChapterStart(location);

  Future<bool> _restoreToLocation(ReaderV2Location location) async {
    if (!mounted || widget.runtime.chapterCount <= 0) return false;
    _clearArtificialMotionState();
    _motion.scrollAnimation.stop();
    _motion.isDragging = false;
    final layoutGeneration = widget.runtime.state.layoutGeneration;
    bool stillCurrent() {
      return mounted &&
          widget.runtime.state.layoutGeneration == layoutGeneration;
    }

    await _ensureWindowAround(location.chapterIndex, isCurrent: stillCurrent);
    if (!stillCurrent()) return false;
    final target = _readingYForLocation(location);
    if (target == null) return false;
    _setOverscrollY(0.0);
    _setReadingY(_clampReadingY(target));
    _initialJumpCompleted = true;
    _lastSyncedLocation = location;
    _lastReportedLocation = location;
    if (mounted) setState(() {});
    if (WidgetsBinding.instance.hasScheduledFrame) {
      await WidgetsBinding.instance.endOfFrame;
    }
    return mounted && _captureVisibleLocation() != null;
  }

  ReaderV2Location? _captureAndReportVisibleLocation() {
    _capturingVisibleLocation = true;
    final ReaderV2Location? location;
    try {
      location = widget.runtime.captureVisibleLocation();
    } finally {
      _capturingVisibleLocation = false;
    }
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  bool _applyReadingTarget(
    double target, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    return _motion.applyReadingTarget(
      target,
      scheduleShift: scheduleShift,
      captureVisibleLocation: captureVisibleLocation,
    );
  }

  void _setReadingY(double value) {
    _motion.setReadingY(value);
  }

  void _setOverscrollY(double value) {
    _motion.setOverscrollY(value);
  }

  void _scheduleVisibleLocationCapture() {
    if (_visibleLocationCaptureFramePending) return;
    _visibleLocationCaptureFramePending = true;
    final revision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleLocationCaptureFramePending = false;
      if (!mounted) return;
      if (revision != _runtimeLocationRevision) return;
      _captureAndReportVisibleLocation();
    });
  }

  void _scheduleWindowShiftForAnchor() {
    if (_shiftWindowFramePending) return;
    _shiftWindowFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shiftWindowFramePending = false;
      if (!mounted) return;
      unawaited(_requestShiftWindowForAnchor());
    });
  }

  Future<void> _requestShiftWindowForAnchor() {
    final existing = _shiftWindowTask;
    if (existing != null) {
      _shiftWindowAgainRequested = true;
      return existing;
    }
    final task = _runCoalescedWindowShift();
    _shiftWindowTask = task;
    task.whenComplete(() {
      if (identical(_shiftWindowTask, task)) {
        _shiftWindowTask = null;
      }
    });
    return task;
  }

  Future<void> _runCoalescedWindowShift() async {
    do {
      _shiftWindowAgainRequested = false;
      await _shiftWindowForAnchor();
    } while (mounted && _shiftWindowAgainRequested);
  }

  Future<void> _shiftWindowForAnchor() async {
    final current = _viewportModel.currentChapterIndex;
    if (current == null) return;
    final anchorWorldY = _motion.readingY + _anchorOffsetInViewport();
    final placement = _viewportModel.visiblePages.placementAtWorldY(
      anchorWorldY,
    );
    if (placement == null) return;
    final targetChapter = placement.page.chapterIndex;
    final threshold = _shiftThreshold();
    final nearArtificialEdge =
        _isNearArtificialWindowEdge(forward: true, threshold: threshold) ||
        _isNearArtificialWindowEdge(forward: false, threshold: threshold);
    if (targetChapter == current && !nearArtificialEdge) return;
    if (!nearArtificialEdge &&
        !_shouldShiftWindow(current, targetChapter, anchorWorldY)) {
      return;
    }
    final layoutGeneration = widget.runtime.state.layoutGeneration;
    bool anchorStillTargetsShift() {
      if (!mounted ||
          widget.runtime.state.layoutGeneration != layoutGeneration) {
        return false;
      }
      final latestAnchorWorldY = _motion.readingY + _anchorOffsetInViewport();
      final latestPlacement = _viewportModel.visiblePages.placementAtWorldY(
        latestAnchorWorldY,
      );
      return latestPlacement?.page.chapterIndex == targetChapter;
    }

    await _ensureWindowAround(
      targetChapter,
      isCurrent: anchorStillTargetsShift,
    );
  }

  bool _isArtificialScrollBoundaryForTarget(double target) {
    return _viewportModel.isArtificialScrollBoundaryForTarget(
      target,
      _motion.readingY,
    );
  }

  bool _isNearArtificialWindowEdge({
    required bool forward,
    required double threshold,
  }) {
    return _viewportModel.isNearArtificialWindowEdge(
      forward: forward,
      threshold: threshold,
      readingY: _motion.readingY,
    );
  }

  bool _shouldShiftWindow(
    int currentChapter,
    int targetChapter,
    double anchorWorldY,
  ) {
    return _viewportModel.shouldShiftWindow(
      currentChapter: currentChapter,
      targetChapter: targetChapter,
      anchorWorldY: anchorWorldY,
      threshold: _shiftThreshold(),
      readingY: _motion.readingY,
    );
  }

  void _handleDragStart(DragStartDetails details) {
    _motion.handleDragStart(details);
  }

  bool _holdCurrentScrollPositionIfAnimating() {
    return _motion.holdCurrentScrollPositionIfAnimating();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _motion.handleDragUpdate(details);
  }

  void _handleDragEnd(DragEndDetails details) {
    _motion.handleDragEnd(details);
  }

  void _handleDragCancel() {
    _motion.handleDragCancel();
  }

  Future<bool> _scrollBy(double delta) {
    return _enqueueViewportCommand(() => _scrollByNow(delta));
  }

  Future<bool> _continuousScrollBy(double delta) {
    return _enqueueViewportCommand(() => _continuousScrollByNow(delta));
  }

  Future<bool> _continuousScrollByNow(double delta) async {
    if (!mounted || delta == 0 || !_viewportModel.visiblePages.hasPages) {
      return false;
    }
    _motion.scrollAnimation.stop();
    _setOverscrollY(0.0);
    _motion.isDragging = false;
    var remaining = delta;
    var moved = false;
    for (
      var attempts = 0;
      attempts < 8 && remaining.abs() >= 0.01;
      attempts++
    ) {
      final before = _motion.readingY;
      final target = before + remaining;
      final advanced = _applyReadingTarget(
        target,
        scheduleShift: false,
        captureVisibleLocation: false,
      );
      final consumed = _motion.readingY - before;
      moved = moved || advanced;
      remaining -= consumed;
      if (!_isArtificialScrollBoundaryForTarget(target)) break;
      await _requestShiftWindowForAnchor();
      if (!mounted) return false;
      if (consumed.abs() < 0.01 &&
          !_isArtificialScrollBoundaryForTarget(target)) {
        break;
      }
    }
    if (!moved) return false;
    _scheduleVisibleLocationCapture();
    if (_isNearArtificialWindowEdge(forward: delta > 0, threshold: 80.0)) {
      _scheduleWindowShiftForAnchor();
    }
    return mounted;
  }

  Future<bool> _scrollByNow(double delta) async {
    if (!mounted || delta == 0 || !_viewportModel.visiblePages.hasPages) {
      return false;
    }
    _motion.scrollAnimation.stop();
    _setOverscrollY(0.0);
    _motion.isDragging = false;
    var remaining = delta;
    var moved = false;
    for (
      var attempts = 0;
      attempts < 8 && remaining.abs() >= 0.01;
      attempts++
    ) {
      final before = _motion.readingY;
      final target = before + remaining;
      final advanced = _applyReadingTarget(target, scheduleShift: false);
      final consumed = _motion.readingY - before;
      moved = moved || advanced;
      remaining -= consumed;
      if (!_isArtificialScrollBoundaryForTarget(target)) break;
      await _requestShiftWindowForAnchor();
      if (!mounted) return false;
      if (consumed.abs() < 0.01 &&
          !_isArtificialScrollBoundaryForTarget(target)) {
        break;
      }
    }
    if (!moved) return false;
    await _requestShiftWindowForAnchor();
    await _handleScrollSettled();
    return mounted;
  }

  Future<bool> _animateBy(double delta) {
    return _enqueueViewportCommand(() => _animateByNow(delta));
  }

  Future<bool> _animateByNow(double delta) async {
    if (!mounted || delta == 0 || !_viewportModel.visiblePages.hasPages) {
      return false;
    }
    var remaining = delta;
    var moved = false;
    for (
      var attempts = 0;
      attempts < 8 && remaining.abs() >= 0.01;
      attempts++
    ) {
      final before = _motion.readingY;
      final target = before + remaining;
      final advanced = await _animateToReadingY(target);
      if (!mounted) return false;
      final consumed = _motion.readingY - before;
      moved = moved || advanced;
      remaining -= consumed;
      if (!_isArtificialScrollBoundaryForTarget(target)) break;
      await _requestShiftWindowForAnchor();
      if (!mounted) return false;
      if (consumed.abs() < 0.01 &&
          !_isArtificialScrollBoundaryForTarget(target)) {
        break;
      }
    }
    return moved && mounted;
  }

  Future<bool> _moveToNextPage() {
    return _enqueueViewportCommand(() => _moveByVisibleLine(forward: true));
  }

  Future<bool> _moveToPrevPage() {
    return _enqueueViewportCommand(() => _moveByVisibleLine(forward: false));
  }

  Future<bool> _moveByVisibleLine({required bool forward}) {
    if (!mounted || !_viewportModel.visiblePages.hasPages) {
      return Future<bool>.value(false);
    }
    final lines = _visibleTextLines();
    if (lines.isEmpty) {
      return _animateByNow(_viewportHeight() * (forward ? 0.9 : -0.9));
    }

    final viewportHeight = _viewportHeight();
    final minUsefulDelta = math.max(
      24.0,
      widget.style.fontSize * widget.style.effectiveLineHeight,
    );
    final target =
        forward
            ? lines.last.worldTop
            : lines.first.worldBottom - viewportHeight;
    var delta = target - _motion.readingY;
    if (delta.abs() < minUsefulDelta) {
      delta = viewportHeight * (forward ? 0.9 : -0.9);
    }
    return _animateByNow(delta);
  }

  List<ScrollReaderV2VisibleLine> _visibleTextLines() {
    return _visibleLineCalculator.visibleTextLines(
      visiblePages: _viewportModel.visiblePages,
      readingY: _motion.readingY,
      viewportHeight: _viewportHeight(),
      renderStyle: _scrollRenderStyle(),
    );
  }

  Future<bool> _enqueueViewportCommand(Future<bool> Function() command) {
    return _viewportCommands.enqueue(
      isMounted: () => mounted,
      command: command,
    );
  }

  Future<bool> _animateToReadingY(double target) async {
    return _motion.animateToReadingY(target);
  }

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) {
    return _enqueueViewportCommand(
      () => _ensureCharRangeVisibleNow(
        chapterIndex: chapterIndex,
        startCharOffset: startCharOffset,
        endCharOffset: endCharOffset,
      ),
    );
  }

  Future<bool> _ensureCharRangeVisibleNow({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) async {
    if (!mounted || widget.runtime.chapterCount <= 0) return false;
    final safeChapterIndex = _safeChapterIndex(chapterIndex);
    final layoutGeneration = widget.runtime.state.layoutGeneration;
    bool stillCurrent() {
      return mounted &&
          widget.runtime.state.layoutGeneration == layoutGeneration;
    }

    final ready = await _tryEnsureChapterLoaded(
      safeChapterIndex,
      isCurrent: stillCurrent,
    );
    if (!stillCurrent() || !ready) return false;
    await _ensureWindowAround(safeChapterIndex, isCurrent: stillCurrent);
    if (!stillCurrent()) return false;

    final chapter = _viewportModel.cacheManager.chapterAt(safeChapterIndex);
    final chapterTop = _viewportModel.strip.chapterTop(safeChapterIndex);
    if (chapter == null || chapterTop == null) return false;
    final rangeStart =
        startCharOffset <= endCharOffset ? startCharOffset : endCharOffset;
    final rangeEnd =
        startCharOffset <= endCharOffset ? endCharOffset : startCharOffset;
    final rangeLines = chapter.layout.linesForRange(rangeStart, rangeEnd);
    final fallback = chapter.layout.lineForCharOffset(rangeStart);
    final first = rangeLines.isEmpty ? fallback : rangeLines.first;
    final last = rangeLines.isEmpty ? fallback : rangeLines.last;
    if (first == null || last == null) return false;

    final firstTop = _viewportModel.positionTracker.lineWorldTop(
      chapter: chapter,
      chapterTop: chapterTop,
      line: first,
      style: _scrollRenderStyle(),
    );
    final lastBottom = _viewportModel.positionTracker.lineWorldBottom(
      chapter: chapter,
      chapterTop: chapterTop,
      line: last,
      style: _scrollRenderStyle(),
    );
    if (firstTop == null || lastBottom == null) return false;

    final viewportHeight = _viewportHeight();
    final topPadding = math.min(80.0, viewportHeight * 0.14);
    final bottomPadding = math.min(120.0, viewportHeight * 0.20);
    final preferredTopInset = math.min(180.0, viewportHeight * 0.32);
    final comfortBottom =
        _motion.readingY + math.min(220.0, viewportHeight * 0.46);
    final visibleTop = _motion.readingY + topPadding;
    final visibleBottom = _motion.readingY + viewportHeight - bottomPadding;
    final safelyVisible = firstTop >= visibleTop && lastBottom <= visibleBottom;
    if (safelyVisible && firstTop <= comfortBottom) {
      return true;
    }

    final preferredTarget = firstTop - preferredTopInset;
    final minTarget = lastBottom - viewportHeight + bottomPadding;
    final maxTarget = firstTop - topPadding;
    final target =
        minTarget <= maxTarget
            ? preferredTarget.clamp(minTarget, maxTarget).toDouble()
            : minTarget;
    return _animateToReadingY(target);
  }

  Future<void> _handleScrollSettled() async {
    if (!mounted ||
        _motion.isDragging ||
        _motion.pausedFlingAtArtificialBoundary) {
      return;
    }
    try {
      final location = _captureAndReportVisibleLocation();
      if (location != null) {
        // Persist immediately on settle so the DB always reflects the latest
        // position. Relying on the (unawaited) background flush at app pause is
        // unreliable: Android can reclaim a backgrounded app before the async
        // write lands, leaving a stale position that restores to the chapter
        // start (or an earlier point) on cold restart.
        final saved = await widget.runtime.saveProgress(
          location: location,
          immediate: true,
        );
        if (saved != null) _lastReportedLocation = saved;
      }
    } finally {
      _clearWindowBoost();
      _endInteractivePreloadPause();
    }
  }

  Widget _buildLoadingState(ReaderV2State state) {
    if (state.phase != ReaderV2Phase.error) {
      widget.runtime.recordFullScreenLoadingSample();
    }
    return ScrollReaderV2LoadingState(
      state: state,
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
      onTapUp: widget.onTapUp,
    );
  }

  Widget _buildCanvas() {
    return ScrollReaderV2Canvas(
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
      renderStyle: _scrollRenderStyle(),
      visiblePages: _viewportModel.visiblePages,
      scrollOffset: _motion.scrollOffset,
      overscrollAnimation: _motion.overscrollAnimation,
      viewportHeight: _viewportHeight(),
      layoutRevision: widget.runtime.state.layoutGeneration,
      onTapUp: widget.onTapUp,
      ttsHighlight: widget.ttsHighlight,
      onPointerDownTapPolicy: _holdCurrentScrollPositionIfAnimating,
      onVerticalDragStart: _handleDragStart,
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      onVerticalDragCancel: _handleDragCancel,
    );
  }

  Widget _buildCanvasWithLoadingOverlay() {
    widget.runtime.recordOverlayLoadingSample();
    return ScrollReaderV2CanvasWithLoadingOverlay(
      canvas: _buildCanvas(),
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
      style: widget.style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.runtime.state;
    final currentChapter = _safeChapterIndex(
      _viewportModel.currentChapterIndex ?? state.visibleLocation.chapterIndex,
    );
    final currentLoaded = _viewportModel.cacheManager.containsChapter(
      currentChapter,
    );
    if (state.phase != ReaderV2Phase.ready && !_initialJumpCompleted) {
      return _buildLoadingState(state);
    }
    if (!currentLoaded) {
      final layoutGeneration = state.layoutGeneration;
      unawaited(
        _ensureWindowAround(
          currentChapter,
          isCurrent:
              () =>
                  mounted &&
                  widget.runtime.state.layoutGeneration == layoutGeneration &&
                  _safeChapterIndex(
                        widget.runtime.state.visibleLocation.chapterIndex,
                      ) ==
                      currentChapter,
        ),
      );
      if (_viewportModel.cacheManager.hasChapters &&
          _viewportModel.visiblePages.hasPages) {
        return _buildCanvasWithLoadingOverlay();
      }
      return _buildLoadingState(state);
    }
    return _buildCanvas();
  }
}
