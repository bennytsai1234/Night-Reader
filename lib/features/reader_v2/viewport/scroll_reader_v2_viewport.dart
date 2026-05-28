import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:reader/features/reader_v2/render/reader_v2_tile_key.dart';
import 'package:reader/features/reader_v2/render/reader_v2_tile_layer.dart';
import 'package:reader/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_infinite_segment_strip.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_position_tracker.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_visible_page_calculator.dart';

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
  static const double _maxFlingVelocity = 5000.0;
  static const int _animationShiftThrottleEveryTicks = 2;
  static const double _overscrollMaxViewportFactor = 0.18;
  static const double _overscrollMinDistance = 48.0;
  static const double _overscrollMaxDistance = 96.0;
  static const double _overscrollBaseResistance = 0.45;
  static const double _maxForwardWindowExtent = 6000.0;
  static const double _maxBackwardWindowExtent = 2400.0;
  static const double _maxFlingWindowBoost = 4000.0;
  static const double _flingWindowBoostSeconds = 0.6;

  late final AnimationController _scrollAnimation;
  late final AnimationController _overscrollAnimation;
  late ReaderV2ChapterPageCacheManager _cacheManager;
  late ReaderV2VisiblePageCalculator _visiblePages;
  final ReaderV2InfiniteSegmentStrip _strip = ReaderV2InfiniteSegmentStrip();
  final ReaderV2PositionTracker _positionTracker =
      const ReaderV2PositionTracker();

  ReaderV2Location? _lastReportedLocation;
  ReaderV2Location? _lastSyncedLocation;
  int? _currentChapterIndex;
  int _lastLayoutGeneration = 0;
  int _windowRequestId = 0;
  int _runtimeLocationRevision = 0;
  double _readingY = 0.0;
  double _lastAnimationValue = 0.0;
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  bool _initialJumpCompleted = false;
  bool _isDragging = false;
  bool _capturingVisibleLocation = false;
  bool _visibleLocationCaptureFramePending = false;
  bool _shiftWindowFramePending = false;
  bool _shiftWindowAgainRequested = false;
  bool _dragMovedReadingY = false;
  bool _interactivePreloadPaused = false;
  double _pendingArtificialDelta = 0.0;
  double? _pendingArtificialFlingVelocity;
  bool _pausedFlingAtArtificialBoundary = false;
  double _activeForwardWindowBoost = 0.0;
  double _activeBackwardWindowBoost = 0.0;
  int _animationTickCount = 0;
  Future<void>? _shiftWindowTask;
  Future<void> _viewportCommandTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _configureViewportModel();
    _scrollAnimation = AnimationController.unbounded(vsync: this)
      ..addListener(_handleScrollAnimationTick);
    _overscrollAnimation = AnimationController.unbounded(vsync: this);
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

  void _configureViewportModel() {
    _cacheManager = ReaderV2ChapterPageCacheManager(
      runtime: widget.runtime,
      pageExtent: _scrollPageExtent,
    );
    _visiblePages = ReaderV2VisiblePageCalculator(
      cacheManager: _cacheManager,
      strip: _strip,
    );
  }

  void _beginInteractivePreloadPause() {
    if (_interactivePreloadPaused) return;
    _interactivePreloadPaused = true;
    widget.runtime.beginInteractivePreloadPause();
  }

  void _endInteractivePreloadPause() {
    if (!_interactivePreloadPaused) return;
    _interactivePreloadPaused = false;
    widget.runtime.endInteractivePreloadPause();
  }

  @override
  void didUpdateWidget(covariant ScrollReaderV2Viewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      if (_interactivePreloadPaused) {
        _interactivePreloadPaused = false;
        oldWidget.runtime.endInteractivePreloadPause();
      }
      oldWidget.runtime.unregisterVisibleLocationCapture(this);
      oldWidget.runtime.unregisterViewportRestore(this);
      oldWidget.runtime.removeListener(_onRuntimeChanged);
      widget.runtime.addListener(_onRuntimeChanged);
      widget.runtime.registerVisibleLocationCapture(
        this,
        _captureVisibleLocation,
      );
      widget.runtime.registerViewportRestore(this, _restoreToLocation);
      _configureViewportModel();
      _resetLoadedState();
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _lastReportedLocation = widget.runtime.state.visibleLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_primeAndSyncToRuntimeLocation(force: true));
      });
    } else if (oldWidget.style != widget.style) {
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
    _endInteractivePreloadPause();
    _clearArtificialMotionState();
    widget.runtime.removeListener(_onRuntimeChanged);
    widget.runtime.unregisterVisibleLocationCapture(this);
    widget.runtime.unregisterViewportRestore(this);
    _detachController(widget.controller);
    _scrollAnimation
      ..removeListener(_handleScrollAnimationTick)
      ..dispose();
    _overscrollAnimation.dispose();
    _scrollOffset.dispose();
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
    _scrollAnimation.stop();
    _cacheManager.invalidateAll(reason: 'viewport reset');
    _strip.clear();
    _windowRequestId += 1;
    _lastSyncedLocation = null;
    _currentChapterIndex = null;
    _setReadingY(0.0);
    _setOverscrollY(0.0);
    _lastAnimationValue = 0.0;
    _animationTickCount = 0;
    _initialJumpCompleted = false;
    _dragMovedReadingY = false;
    _clearArtificialMotionState();
    _activeForwardWindowBoost = 0.0;
    _activeBackwardWindowBoost = 0.0;
  }

  void _clearArtificialMotionState() {
    _pendingArtificialDelta = 0.0;
    _pendingArtificialFlingVelocity = null;
    _pausedFlingAtArtificialBoundary = false;
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

  double _viewportHeight() {
    final height = widget.runtime.state.layoutSpec.viewportSize.height;
    return height.isFinite && height > 0 ? height : 1.0;
  }

  double _anchorOffsetInViewport() =>
      widget.runtime.state.layoutSpec.anchorOffsetInViewport;

  ({double min, double max})? _scrollBounds() {
    return _strip.scrollBounds(
      viewportHeight: _viewportHeight(),
      anchorOffset: _anchorOffsetInViewport(),
    );
  }

  // Vertical padding belongs to the viewport/chapter edge in scroll mode, not
  // every paginated tile boundary.
  ReaderV2Style _scrollRenderStyle() =>
      widget.style.copyWith(paddingTop: 0, paddingBottom: 0);

  double _shiftThreshold() {
    final base = math.min(120.0, _viewportHeight() * 0.2);
    final speed =
        _scrollAnimation.isAnimating ? _scrollAnimation.velocity.abs() : 0.0;
    final dynamicLookahead = math.min(_viewportHeight() * 1.5, speed * 0.18);
    return math.max(base, dynamicLookahead);
  }

  double _fullPageHeight(ReaderV2PageCache page) {
    return page.height.isFinite && page.height > 0 ? page.height : 1.0;
  }

  double _scrollPageExtent(ReaderV2PageCache page) {
    final fullHeight = _fullPageHeight(page);
    if (page.lines.isEmpty) return fullHeight;

    final contentBottom = page.lines.fold<double>(
      0.0,
      (bottom, line) => math.max(bottom, line.bottom),
    );
    return math.max(1.0, contentBottom);
  }

  double _forwardWindowExtent() {
    final base = _viewportHeight() * 8.0 + _anchorOffsetInViewport();
    return math.min(base, _maxForwardWindowExtent) + _activeForwardWindowBoost;
  }

  double _backwardWindowExtent() {
    final base = _viewportHeight() * 3.0;
    return math.min(base, _maxBackwardWindowExtent) +
        _activeBackwardWindowBoost;
  }

  void _updateWindowBoostForFling(double velocity) {
    final boost = math.min(
      velocity.abs() * _flingWindowBoostSeconds,
      _maxFlingWindowBoost,
    );
    _activeForwardWindowBoost = velocity > 0 ? boost : 0.0;
    _activeBackwardWindowBoost = velocity < 0 ? boost : 0.0;
  }

  void _clearWindowBoost() {
    if (_activeForwardWindowBoost == 0.0 && _activeBackwardWindowBoost == 0.0) {
      return;
    }
    _activeForwardWindowBoost = 0.0;
    _activeBackwardWindowBoost = 0.0;
    _scheduleWindowShiftForAnchor();
  }

  int _safeChapterIndex(int chapterIndex) {
    final chapterCount = widget.runtime.chapterCount;
    if (chapterCount <= 0) return 0;
    return chapterIndex.clamp(0, chapterCount - 1).toInt();
  }

  Future<bool> _tryEnsureChapterLoaded(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    if (widget.runtime.chapterCount <= 0) return false;
    final safeChapterIndex = _safeChapterIndex(chapterIndex);
    return _cacheManager.ensureChapterLoaded(
      safeChapterIndex,
      isCurrent: () => mounted && (isCurrent?.call() ?? true),
    );
  }

  Future<void> _ensureWindowAround(
    int chapterIndex, {
    bool Function()? isCurrent,
  }) async {
    if (widget.runtime.chapterCount <= 0) return;
    final requestId = ++_windowRequestId;
    bool stillCurrent() {
      return mounted &&
          requestId == _windowRequestId &&
          (isCurrent?.call() ?? true);
    }

    final center = _safeChapterIndex(chapterIndex);
    final window = await _cacheManager.ensureWindowAround(
      centerChapterIndex: center,
      backwardExtent: _backwardWindowExtent(),
      forwardExtent: _forwardWindowExtent(),
      isCurrent: stillCurrent,
    );
    if (!stillCurrent() || window == null) return;

    _placeWindowInStrip(window);
    _currentChapterIndex = window.center.chapterIndex;
    _consumePendingArtificialDelta();
    final resumedFling = _resumePendingArtificialFlingIfNeeded();
    if (!resumedFling && _scrollAnimation.isAnimating) {
      _applyReadingTarget(
        _scrollAnimation.value,
        scheduleShift: false,
        captureVisibleLocation: false,
      );
    }
    setState(() {});
  }

  void _placeWindowInStrip(ReaderV2ChapterPageCacheWindow window) {
    final center = window.center;
    final centerTop = _strip.chapterTop(center.chapterIndex) ?? 0.0;
    _strip.placeChapter(
      chapterIndex: center.chapterIndex,
      startY: centerTop,
      height: center.extent,
    );

    var backwardTop = centerTop;
    for (final chapter in window.previous) {
      backwardTop -= chapter.extent;
      _strip.placeChapter(
        chapterIndex: chapter.chapterIndex,
        startY: backwardTop,
        height: chapter.extent,
      );
    }

    var forwardTop = centerTop + center.extent;
    for (final chapter in window.next) {
      _strip.placeChapter(
        chapterIndex: chapter.chapterIndex,
        startY: forwardTop,
        height: chapter.extent,
      );
      forwardTop += chapter.extent;
    }

    _strip.retain(window.retainedChapterIndexes);
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

  double? _readingYForLocation(ReaderV2Location location) {
    final chapterIndex = _safeChapterIndex(location.chapterIndex);
    if (_isTopAlignedChapterStart(location)) {
      return _strip.chapterTop(chapterIndex);
    }
    return _positionTracker.readingYForLocation(
      location: location.copyWith(chapterIndex: chapterIndex),
      cacheManager: _cacheManager,
      strip: _strip,
      anchorOffset: _anchorOffsetInViewport(),
      style: _scrollRenderStyle(),
    );
  }

  double _clampReadingY(double target) {
    final bounds = _scrollBounds();
    if (bounds == null) return target;
    return target.clamp(bounds.min, bounds.max).toDouble();
  }

  ReaderV2Location? _captureVisibleLocation() {
    if (!_initialJumpCompleted || widget.runtime.chapterCount <= 0) {
      return null;
    }
    return _positionTracker.captureVisibleLocation(
      calculator: _visiblePages,
      cacheManager: _cacheManager,
      strip: _strip,
      readingY: _readingY,
      anchorOffset: _anchorOffsetInViewport(),
      style: _scrollRenderStyle(),
    );
  }

  bool _isTopAlignedChapterStart(ReaderV2Location location) {
    return location.charOffset == 0 &&
        (location.visualOffsetPx - _anchorOffsetInViewport()).abs() < 0.01;
  }

  Future<bool> _restoreToLocation(ReaderV2Location location) async {
    if (!mounted || widget.runtime.chapterCount <= 0) return false;
    _clearArtificialMotionState();
    _scrollAnimation.stop();
    _isDragging = false;
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
    await Future<void>.delayed(Duration.zero);
    return mounted && _captureVisibleLocation() != null;
  }

  void _captureAndReportVisibleLocation() {
    _capturingVisibleLocation = true;
    final ReaderV2Location? location;
    try {
      location = widget.runtime.captureVisibleLocation();
    } finally {
      _capturingVisibleLocation = false;
    }
    if (location != null) _lastReportedLocation = location;
  }

  bool _applyReadingDelta(
    double delta, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    return _applyReadingTarget(
      _readingY + delta,
      scheduleShift: scheduleShift,
      captureVisibleLocation: captureVisibleLocation,
    );
  }

  bool _applyReadingDeltaPreservingArtificialRemainder(
    double delta, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    if (delta == 0) return false;
    final before = _readingY;
    final target = before + delta;
    final moved = _applyReadingTarget(
      target,
      scheduleShift: scheduleShift,
      captureVisibleLocation: captureVisibleLocation,
    );
    final consumed = _readingY - before;
    final remaining = delta - consumed;
    if (remaining.abs() >= 0.5 &&
        _isArtificialScrollBoundaryForTarget(target)) {
      _pendingArtificialDelta += remaining;
      _scheduleWindowShiftForAnchor();
    }
    return moved;
  }

  void _consumePendingArtificialDelta() {
    final pending = _pendingArtificialDelta;
    if (pending.abs() < 0.5) {
      _pendingArtificialDelta = 0.0;
      return;
    }
    _pendingArtificialDelta = 0.0;
    final before = _readingY;
    final target = before + pending;
    final moved = _applyReadingTarget(
      target,
      scheduleShift: false,
      captureVisibleLocation: false,
    );
    final consumed = _readingY - before;
    final remaining = pending - consumed;
    if (remaining.abs() >= 0.5 &&
        _isArtificialScrollBoundaryForTarget(target)) {
      _pendingArtificialDelta += remaining;
      _scheduleWindowShiftForAnchor();
    }
    if (moved) {
      _scheduleVisibleLocationCapture();
    }
  }

  void _pauseFlingAtArtificialBoundary() {
    final velocity = _scrollAnimation.velocity;
    _pausedFlingAtArtificialBoundary = true;
    _pendingArtificialFlingVelocity = velocity.abs() >= 50.0 ? velocity : null;
    _scrollAnimation.stop();
    _lastAnimationValue = _readingY;
    _scrollAnimation.value = _readingY;
    _scheduleWindowShiftForAnchor();
  }

  bool _resumePendingArtificialFlingIfNeeded() {
    if (!_pausedFlingAtArtificialBoundary) return false;
    _pausedFlingAtArtificialBoundary = false;
    final velocity = _pendingArtificialFlingVelocity;
    _pendingArtificialFlingVelocity = null;
    if (_isDragging) return false;
    if (velocity == null || velocity.abs() < 50.0) {
      unawaited(_handleScrollSettled());
      return false;
    }
    final deltaSign = velocity > 0 ? 1.0 : -1.0;
    if (_isAtBookBoundaryForDelta(deltaSign)) {
      unawaited(_handleScrollSettled());
      return false;
    }
    _startFling(velocity);
    return true;
  }

  bool _applyReadingTarget(
    double target, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    if (!_visiblePages.hasPages) return false;
    final direction = target - _readingY;
    if (direction == 0) return false;
    final nextReadingY = _clampReadingY(target);
    if ((nextReadingY - _readingY).abs() < 0.01) {
      if (scheduleShift || _isArtificialScrollBoundaryForTarget(target)) {
        _scheduleWindowShiftForAnchor();
      }
      return false;
    }
    _setReadingY(nextReadingY);
    if (captureVisibleLocation) {
      _scheduleVisibleLocationCapture();
    }
    if (scheduleShift ||
        _isNearArtificialWindowEdge(
          forward: direction > 0,
          threshold: _shiftThreshold(),
        )) {
      _scheduleWindowShiftForAnchor();
    }
    return true;
  }

  void _setReadingY(double value) {
    _readingY = value;
    if (_scrollOffset.value != value) {
      _scrollOffset.value = value;
    }
  }

  double get _overscrollY => _overscrollAnimation.value;

  double _maxOverscrollDistance() {
    final viewport = _viewportHeight();
    return (viewport * _overscrollMaxViewportFactor)
        .clamp(_overscrollMinDistance, _overscrollMaxDistance)
        .toDouble();
  }

  double _overscrollResistance() {
    final maxDistance = _maxOverscrollDistance();
    final remaining = 1.0 - (_overscrollY.abs() / maxDistance).clamp(0.0, 1.0);
    return _overscrollBaseResistance * remaining.clamp(0.25, 1.0);
  }

  void _setOverscrollY(double value) {
    final maxDistance = _maxOverscrollDistance();
    final next = value.clamp(-maxDistance, maxDistance).toDouble();
    if ((_overscrollAnimation.value - next).abs() < 0.01) return;
    _overscrollAnimation.value = next;
  }

  bool _isAtBookBoundaryForDelta(double readingDelta) {
    final bounds = _scrollBounds();
    if (bounds == null || widget.runtime.chapterCount <= 0) return false;
    const tolerance = 0.5;
    if (readingDelta < 0) {
      return _strip.containsChapter(0) && _readingY <= bounds.min + tolerance;
    }
    if (readingDelta > 0) {
      final lastChapterIndex = widget.runtime.chapterCount - 1;
      return _strip.containsChapter(lastChapterIndex) &&
          _readingY >= bounds.max - tolerance;
    }
    return false;
  }

  void _applyOverscrollDragDelta(double fingerDeltaY) {
    if (fingerDeltaY == 0) return;
    final current = _overscrollY;
    if (current == 0 || current.sign == fingerDeltaY.sign) {
      _setOverscrollY(current + fingerDeltaY * _overscrollResistance());
      return;
    }

    final next = current + fingerDeltaY;
    if (next != 0 && next.sign == current.sign) {
      _setOverscrollY(next);
      return;
    }

    _setOverscrollY(0.0);
    final moved = _applyReadingDelta(-next);
    _dragMovedReadingY = _dragMovedReadingY || moved;
  }

  Future<void> _settleOverscroll({required bool saveProgress}) async {
    if (_overscrollY.abs() < 0.5) {
      _setOverscrollY(0.0);
      if (saveProgress) {
        await _handleScrollSettled();
      } else {
        _endInteractivePreloadPause();
      }
      return;
    }
    try {
      await _overscrollAnimation
          .animateTo(
            0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      if (!mounted) return;
    }
    if (!mounted) return;
    if (saveProgress) {
      await _handleScrollSettled();
    } else {
      _endInteractivePreloadPause();
    }
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
    final current = _currentChapterIndex;
    if (current == null) return;
    final anchorWorldY = _readingY + _anchorOffsetInViewport();
    final placement = _visiblePages.placementAtWorldY(anchorWorldY);
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
      final latestAnchorWorldY = _readingY + _anchorOffsetInViewport();
      final latestPlacement = _visiblePages.placementAtWorldY(
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
    final bounds = _scrollBounds();
    if (bounds == null || widget.runtime.chapterCount <= 0) return false;
    const tolerance = 0.5;
    if (target > _readingY && target >= bounds.max - tolerance) {
      return !_strip.containsChapter(widget.runtime.chapterCount - 1);
    }
    if (target < _readingY && target <= bounds.min + tolerance) {
      return !_strip.containsChapter(0);
    }
    return false;
  }

  bool _isNearArtificialWindowEdge({
    required bool forward,
    required double threshold,
  }) {
    final bounds = _scrollBounds();
    if (bounds == null || widget.runtime.chapterCount <= 0) return false;
    const tolerance = 0.5;
    if (forward) {
      return !_strip.containsChapter(widget.runtime.chapterCount - 1) &&
          bounds.max - _readingY <= threshold + tolerance;
    }
    return !_strip.containsChapter(0) &&
        _readingY - bounds.min <= threshold + tolerance;
  }

  bool _shouldShiftWindow(
    int currentChapter,
    int targetChapter,
    double anchorWorldY,
  ) {
    final targetTop = _strip.chapterTop(targetChapter);
    final currentTop = _strip.chapterTop(currentChapter);
    if (targetTop == null || currentTop == null) return false;
    final threshold = _shiftThreshold();
    if (targetChapter > currentChapter) {
      if (_isNearWindowEdge(forward: true, threshold: threshold)) return true;
      return anchorWorldY - targetTop >= threshold;
    }
    if (_isNearWindowEdge(forward: false, threshold: threshold)) return true;
    return currentTop - anchorWorldY >= threshold;
  }

  bool _isNearWindowEdge({required bool forward, required double threshold}) {
    return _strip.isNearEdge(
      forward: forward,
      readingY: _readingY,
      threshold: threshold,
      viewportHeight: _viewportHeight(),
      anchorOffset: _anchorOffsetInViewport(),
    );
  }

  int _anchorChapterIndex() {
    final anchorWorldY = _readingY + _anchorOffsetInViewport();
    final placement = _visiblePages.placementAtWorldY(anchorWorldY);
    final chapterIndex =
        placement?.page.chapterIndex ??
        widget.runtime.state.visibleLocation.chapterIndex;
    return _safeChapterIndex(chapterIndex);
  }

  void _handleScrollAnimationTick() {
    final current = _scrollAnimation.value;
    if (current == _lastAnimationValue) return;
    final moved = _applyReadingTarget(
      current,
      scheduleShift: false,
      captureVisibleLocation: false,
    );
    _lastAnimationValue = current;
    if (!moved) {
      if (_isArtificialScrollBoundaryForTarget(current)) {
        _pauseFlingAtArtificialBoundary();
        return;
      }
      _scrollAnimation.stop();
      unawaited(_handleScrollSettled());
      return;
    }
    _animationTickCount += 1;
    if (_animationTickCount == 1 ||
        _animationTickCount % _animationShiftThrottleEveryTicks == 0) {
      _scheduleVisibleLocationCapture();
    }
    if (_animationTickCount % _animationShiftThrottleEveryTicks == 0) {
      _scheduleWindowShiftForAnchor();
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _beginInteractivePreloadPause();
    _clearArtificialMotionState();
    _isDragging = true;
    _scrollAnimation.stop();
    _overscrollAnimation.stop();
    _animationTickCount = 0;
    _dragMovedReadingY = false;
  }

  bool _holdCurrentScrollPositionIfAnimating() {
    final scrollAnimating = _scrollAnimation.isAnimating;
    final overscrollAnimating = _overscrollAnimation.isAnimating;
    if (!scrollAnimating && !overscrollAnimating) return false;

    if (scrollAnimating) {
      final currentTarget = _scrollAnimation.value;
      _scrollAnimation.stop();
      _applyReadingTarget(
        currentTarget,
        scheduleShift: false,
        captureVisibleLocation: false,
      );
      _lastAnimationValue = _readingY;
    }
    if (overscrollAnimating) {
      _overscrollAnimation.stop();
    }
    _isDragging = false;
    _dragMovedReadingY = false;
    _animationTickCount = 0;
    _scheduleVisibleLocationCapture();
    _scheduleWindowShiftForAnchor();
    unawaited(_handleScrollSettled());
    return true;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _overscrollAnimation.stop();
    final fingerDeltaY = details.delta.dy;
    if (_overscrollY.abs() >= 0.5) {
      _applyOverscrollDragDelta(fingerDeltaY);
      return;
    }

    final readingDelta = -fingerDeltaY;
    final atBookBoundary = _isAtBookBoundaryForDelta(readingDelta);
    final moved = _applyReadingDeltaPreservingArtificialRemainder(
      readingDelta,
      scheduleShift: !atBookBoundary,
    );
    _dragMovedReadingY = _dragMovedReadingY || moved;
    if (!moved && atBookBoundary) {
      _applyOverscrollDragDelta(fingerDeltaY);
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    _isDragging = false;
    if (_overscrollY.abs() >= 0.5) {
      final saveProgress = _dragMovedReadingY;
      _dragMovedReadingY = false;
      unawaited(_settleOverscroll(saveProgress: saveProgress));
      return;
    }
    _dragMovedReadingY = false;
    final velocity = -(details.primaryVelocity ?? 0.0);
    if (velocity.abs() < 50) {
      unawaited(_handleScrollSettled());
      return;
    }
    _startFling(velocity);
  }

  void _handleDragCancel() {
    _isDragging = false;
    if (_overscrollY.abs() >= 0.5) {
      final saveProgress = _dragMovedReadingY;
      _dragMovedReadingY = false;
      unawaited(_settleOverscroll(saveProgress: saveProgress));
      return;
    }
    _dragMovedReadingY = false;
    unawaited(_handleScrollSettled());
  }

  void _startFling(double velocity) {
    _beginInteractivePreloadPause();
    final effectiveVelocity = velocity.clamp(
      -_maxFlingVelocity,
      _maxFlingVelocity,
    );
    _updateWindowBoostForFling(effectiveVelocity);
    _scheduleWindowShiftForAnchor();
    _scrollAnimation.stop();
    _scrollAnimation.value = _readingY;
    _lastAnimationValue = _readingY;
    _animationTickCount = 0;
    unawaited(
      widget.runtime.preloadDirectionalForVelocity(
        chapterIndex: _anchorChapterIndex(),
        forward: effectiveVelocity > 0,
        velocity: effectiveVelocity,
      ),
    );
    final simulation = ClampingScrollSimulation(
      position: _readingY,
      velocity: effectiveVelocity,
    );
    unawaited(
      _scrollAnimation.animateWith(simulation).whenComplete(() {
        if (mounted) unawaited(_handleScrollSettled());
      }),
    );
  }

  Future<bool> _scrollBy(double delta) {
    return _enqueueViewportCommand(() => _scrollByNow(delta));
  }

  Future<bool> _continuousScrollBy(double delta) {
    return _enqueueViewportCommand(() => _continuousScrollByNow(delta));
  }

  Future<bool> _continuousScrollByNow(double delta) async {
    if (!mounted || delta == 0 || !_visiblePages.hasPages) return false;
    _scrollAnimation.stop();
    _setOverscrollY(0.0);
    _isDragging = false;
    var remaining = delta;
    var moved = false;
    for (
      var attempts = 0;
      attempts < 8 && remaining.abs() >= 0.01;
      attempts++
    ) {
      final before = _readingY;
      final target = before + remaining;
      final advanced = _applyReadingTarget(
        target,
        scheduleShift: false,
        captureVisibleLocation: false,
      );
      final consumed = _readingY - before;
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
    if (!mounted || delta == 0 || !_visiblePages.hasPages) return false;
    _scrollAnimation.stop();
    _setOverscrollY(0.0);
    _isDragging = false;
    var remaining = delta;
    var moved = false;
    for (
      var attempts = 0;
      attempts < 8 && remaining.abs() >= 0.01;
      attempts++
    ) {
      final before = _readingY;
      final target = before + remaining;
      final advanced = _applyReadingTarget(target, scheduleShift: false);
      final consumed = _readingY - before;
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
    if (!mounted || delta == 0 || !_visiblePages.hasPages) return false;
    var remaining = delta;
    var moved = false;
    for (
      var attempts = 0;
      attempts < 8 && remaining.abs() >= 0.01;
      attempts++
    ) {
      final before = _readingY;
      final target = before + remaining;
      final advanced = await _animateToReadingY(target);
      if (!mounted) return false;
      final consumed = _readingY - before;
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
    if (!mounted || !_visiblePages.hasPages) {
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
    var delta = target - _readingY;
    if (delta.abs() < minUsefulDelta) {
      delta = viewportHeight * (forward ? 0.9 : -0.9);
    }
    return _animateByNow(delta);
  }

  List<_ScrollVisibleLine> _visibleTextLines() {
    final visibleTop = _readingY;
    final visibleBottom = _readingY + _viewportHeight();
    final renderStyle = _scrollRenderStyle();
    final lines = <_ScrollVisibleLine>[];
    for (final placement in _visiblePages.visiblePages(
      readingY: _readingY,
      viewportHeight: _viewportHeight(),
    )) {
      for (final line in placement.page.lines) {
        if (line.text.isEmpty) continue;
        final worldTop = placement.worldTop + renderStyle.paddingTop + line.top;
        final worldBottom =
            placement.worldTop + renderStyle.paddingTop + line.bottom;
        if (worldBottom <= visibleTop + 0.5 ||
            worldTop >= visibleBottom - 0.5) {
          continue;
        }
        lines.add(
          _ScrollVisibleLine(worldTop: worldTop, worldBottom: worldBottom),
        );
      }
    }
    lines.sort((a, b) => a.worldTop.compareTo(b.worldTop));
    return lines;
  }

  Future<bool> _enqueueViewportCommand(Future<bool> Function() command) {
    if (!mounted) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _viewportCommandTail = _viewportCommandTail
        .catchError((_) {})
        .then((_) async {
          if (!mounted) return false;
          return command();
        })
        .then(
          completer.complete,
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted)
              completer.completeError(error, stackTrace);
          },
        );
    return completer.future;
  }

  Future<bool> _animateToReadingY(double target) async {
    if (!mounted || !_visiblePages.hasPages) return false;
    final start = _readingY;
    final clampedTarget = _clampReadingY(target);
    if ((clampedTarget - start).abs() < 0.01) return false;
    _scrollAnimation.stop();
    _setOverscrollY(0.0);
    _isDragging = false;
    _scrollAnimation.value = _readingY;
    _lastAnimationValue = _readingY;
    try {
      await _scrollAnimation
          .animateTo(
            clampedTarget,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      if (!mounted) return false;
    }
    if (!mounted) return false;
    final moved = (_readingY - start).abs() >= 0.01;
    if (!moved) return false;
    await _requestShiftWindowForAnchor();
    await _handleScrollSettled();
    return mounted;
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

    final chapter = _cacheManager.chapterAt(safeChapterIndex);
    final chapterTop = _strip.chapterTop(safeChapterIndex);
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

    final firstTop = _positionTracker.lineWorldTop(
      chapter: chapter,
      chapterTop: chapterTop,
      line: first,
      style: _scrollRenderStyle(),
    );
    final lastBottom = _positionTracker.lineWorldBottom(
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
    final comfortBottom = _readingY + math.min(220.0, viewportHeight * 0.46);
    final visibleTop = _readingY + topPadding;
    final visibleBottom = _readingY + viewportHeight - bottomPadding;
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
    if (!mounted || _isDragging || _pausedFlingAtArtificialBoundary) return;
    try {
      _captureAndReportVisibleLocation();
      final saved = await widget.runtime.saveProgress(immediate: false);
      if (saved != null) _lastReportedLocation = saved;
    } finally {
      _clearWindowBoost();
      _endInteractivePreloadPause();
    }
  }

  ReaderV2TileKey _tileKey(ReaderV2PageCache tile) {
    return ReaderV2TileKey.fromPageCache(
      tile,
      layoutRevision: widget.runtime.state.layoutGeneration,
    );
  }

  Widget _buildLoadingState(ReaderV2State state) {
    if (state.phase != ReaderV2Phase.error) {
      widget.runtime.recordFullScreenLoadingSample();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.onTapUp,
      child: ColoredBox(
        color: widget.backgroundColor,
        child: Center(
          child:
              state.phase == ReaderV2Phase.error
                  ? Text(
                    state.errorMessage ?? 'Reader error',
                    style: TextStyle(color: widget.textColor),
                  )
                  : CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.textColor.withValues(alpha: 0.35),
                  ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    final viewportHeight = _viewportHeight();
    return ReaderV2PointerTapLayer(
      onTapUp: widget.onTapUp,
      onPointerDownTapPolicy: (_) => _holdCurrentScrollPositionIfAnimating(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _handleDragStart,
        onVerticalDragUpdate: _handleDragUpdate,
        onVerticalDragEnd: _handleDragEnd,
        onVerticalDragCancel: _handleDragCancel,
        child: ColoredBox(
          color: widget.backgroundColor,
          child: ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollOffset,
              builder: (context, readingY, _) {
                return AnimatedBuilder(
                  animation: _overscrollAnimation,
                  builder: (context, _) {
                    return _buildVisiblePageStack(
                      readingY: readingY,
                      viewportHeight: viewportHeight,
                      overscrollY: _overscrollY,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasWithLoadingOverlay() {
    widget.runtime.recordOverlayLoadingSample();
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCanvas(),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.backgroundColor.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '載入中',
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: 0.7),
                          fontSize:
                              math
                                  .max(11, widget.style.fontSize * 0.72)
                                  .toDouble(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVisiblePageStack({
    required double readingY,
    required double viewportHeight,
    required double overscrollY,
  }) {
    final children = <Widget>[];
    final renderStyle = _scrollRenderStyle();
    for (final placement in _visiblePages.visiblePages(
      readingY: readingY,
      viewportHeight: viewportHeight,
    )) {
      final screenY = placement.screenY(readingY) + overscrollY;
      final pageHeight = placement.extent;
      children.add(
        Positioned(
          left: 0,
          right: 0,
          top: screenY,
          height: pageHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ReaderV2TileLayer(
                tile: placement.page,
                tileKey: _tileKey(placement.page),
                style: renderStyle,
                backgroundColor: widget.backgroundColor,
                textColor: widget.textColor,
                expand: true,
                paintBackground: false,
              ),
              ReaderV2TtsHighlightOverlayLayer(
                tile: placement.page,
                style: renderStyle,
                textColor: widget.textColor,
                highlight: widget.ttsHighlight,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.runtime.state;
    final currentChapter = _safeChapterIndex(
      _currentChapterIndex ?? state.visibleLocation.chapterIndex,
    );
    final currentLoaded = _cacheManager.containsChapter(currentChapter);
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
      if (_cacheManager.hasChapters && _visiblePages.hasPages) {
        return _buildCanvasWithLoadingOverlay();
      }
      return _buildLoadingState(state);
    }
    return _buildCanvas();
  }
}

class _ScrollVisibleLine {
  const _ScrollVisibleLine({required this.worldTop, required this.worldBottom});

  final double worldTop;
  final double worldBottom;
}
