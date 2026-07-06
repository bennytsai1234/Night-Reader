import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

class ScrollReaderV2MotionController {
  static const double maxFlingVelocity = 5000.0;
  static const int animationShiftThrottleEveryTicks = 2;
  static const double overscrollMaxViewportFactor = 0.18;
  static const double overscrollMinDistance = 48.0;
  static const double overscrollMaxDistance = 96.0;
  static const double overscrollBaseResistance = 0.45;

  ScrollReaderV2MotionController({
    required TickerProvider vsync,
    required ReaderV2Runtime runtime,
    required bool Function() isMounted,
    required bool Function() hasVisiblePages,
    required double Function() viewportHeight,
    required ({double min, double max})? Function() scrollBounds,
    required double Function() shiftThreshold,
    required bool Function(double target, double readingY)
    isArtificialScrollBoundaryForTarget,
    required bool Function({
      required bool forward,
      required double threshold,
      required double readingY,
    })
    isNearArtificialWindowEdge,
    required bool Function(double readingDelta, double readingY)
    isAtBookBoundaryForDelta,
    required int Function(double readingY) anchorChapterIndex,
    required void Function(double velocity) updateWindowBoostForFling,
    required void Function() scheduleVisibleLocationCapture,
    required void Function() scheduleWindowShiftForAnchor,
    required Future<void> Function() requestShiftWindowForAnchor,
    required Future<void> Function() handleScrollSettled,
  }) : _runtime = runtime,
       _isMounted = isMounted,
       _hasVisiblePages = hasVisiblePages,
       _viewportHeight = viewportHeight,
       _scrollBounds = scrollBounds,
       _shiftThreshold = shiftThreshold,
       _isArtificialScrollBoundaryForTarget =
           isArtificialScrollBoundaryForTarget,
       _isNearArtificialWindowEdge = isNearArtificialWindowEdge,
       _isAtBookBoundaryForDelta = isAtBookBoundaryForDelta,
       _anchorChapterIndex = anchorChapterIndex,
       _updateWindowBoostForFling = updateWindowBoostForFling,
       _scheduleVisibleLocationCapture = scheduleVisibleLocationCapture,
       _scheduleWindowShiftForAnchor = scheduleWindowShiftForAnchor,
       _requestShiftWindowForAnchor = requestShiftWindowForAnchor,
       _handleScrollSettled = handleScrollSettled,
       scrollAnimation = AnimationController.unbounded(vsync: vsync),
       overscrollAnimation = AnimationController.unbounded(vsync: vsync) {
    scrollAnimation.addListener(_handleScrollAnimationTick);
  }

  ReaderV2Runtime _runtime;
  final bool Function() _isMounted;
  final bool Function() _hasVisiblePages;
  final double Function() _viewportHeight;
  final ({double min, double max})? Function() _scrollBounds;
  final double Function() _shiftThreshold;
  final bool Function(double target, double readingY)
  _isArtificialScrollBoundaryForTarget;
  final bool Function({
    required bool forward,
    required double threshold,
    required double readingY,
  })
  _isNearArtificialWindowEdge;
  final bool Function(double readingDelta, double readingY)
  _isAtBookBoundaryForDelta;
  final int Function(double readingY) _anchorChapterIndex;
  final void Function(double velocity) _updateWindowBoostForFling;
  final void Function() _scheduleVisibleLocationCapture;
  final void Function() _scheduleWindowShiftForAnchor;
  final Future<void> Function() _requestShiftWindowForAnchor;
  final Future<void> Function() _handleScrollSettled;

  final AnimationController scrollAnimation;
  final AnimationController overscrollAnimation;
  final ValueNotifier<double> scrollOffset = ValueNotifier<double>(0.0);

  double readingY = 0.0;
  double _lastAnimationValue = 0.0;
  bool isDragging = false;
  bool dragMovedReadingY = false;
  double _pendingArtificialDelta = 0.0;
  double? _pendingArtificialFlingVelocity;
  bool pausedFlingAtArtificialBoundary = false;
  int _animationTickCount = 0;
  bool _interactivePreloadPaused = false;
  bool _activeScrollAnimationIsFling = false;

  bool get isScrollAnimating => scrollAnimation.isAnimating;
  bool get isFlingAnimating =>
      scrollAnimation.isAnimating && _activeScrollAnimationIsFling;
  bool get isOverscrollAnimating => overscrollAnimation.isAnimating;
  double get scrollAnimationValue => scrollAnimation.value;
  double get scrollVelocity =>
      scrollAnimation.isAnimating ? scrollAnimation.velocity.abs() : 0.0;
  double get overscrollY => overscrollAnimation.value;

  void updateRuntime(ReaderV2Runtime runtime) {
    if (identical(_runtime, runtime)) return;
    if (_interactivePreloadPaused) {
      _interactivePreloadPaused = false;
      _runtime.endInteractivePreloadPause();
    }
    _runtime = runtime;
  }

  void reset() {
    scrollAnimation.stop();
    _activeScrollAnimationIsFling = false;
    setReadingY(0.0);
    setOverscrollY(0.0);
    _lastAnimationValue = 0.0;
    _animationTickCount = 0;
    isDragging = false;
    dragMovedReadingY = false;
    clearArtificialMotionState();
  }

  void dispose() {
    endInteractivePreloadPause();
    clearArtificialMotionState();
    scrollAnimation
      ..removeListener(_handleScrollAnimationTick)
      ..dispose();
    overscrollAnimation.dispose();
    scrollOffset.dispose();
  }

  void beginInteractivePreloadPause() {
    if (_interactivePreloadPaused) return;
    _interactivePreloadPaused = true;
    _runtime.beginInteractivePreloadPause();
  }

  void endInteractivePreloadPause() {
    if (!_interactivePreloadPaused) return;
    _interactivePreloadPaused = false;
    _runtime.endInteractivePreloadPause();
  }

  void clearArtificialMotionState() {
    _pendingArtificialDelta = 0.0;
    _pendingArtificialFlingVelocity = null;
    pausedFlingAtArtificialBoundary = false;
  }

  void setReadingY(double value) {
    readingY = value;
    if (scrollOffset.value != value) {
      scrollOffset.value = value;
    }
  }

  void compensateReadingYForStripShift(double delta) {
    if (delta.abs() < 0.01) return;
    final wasAnimating = scrollAnimation.isAnimating;
    final velocity = wasAnimating ? scrollAnimation.velocity : 0.0;
    if (wasAnimating) scrollAnimation.stop();

    setReadingY(clampReadingY(readingY + delta));
    _lastAnimationValue = readingY;
    if (!wasAnimating) return;

    scrollAnimation.value = readingY;
    if (velocity.abs() >= 50.0 &&
        !_isAtBookBoundaryForDelta(velocity, readingY)) {
      startFling(velocity);
    }
  }

  void rebaseActiveFlingToCurrentReadingY() {
    if (!isFlingAnimating) return;
    final velocity = scrollAnimation.velocity;
    _activeScrollAnimationIsFling = false;
    scrollAnimation.stop();
    _lastAnimationValue = readingY;
    scrollAnimation.value = readingY;
    if (velocity.abs() < 50.0 ||
        _isAtBookBoundaryForDelta(velocity, readingY)) {
      unawaited(_handleScrollSettled());
      return;
    }
    startFling(velocity);
  }

  double clampReadingY(double target) {
    final bounds = _scrollBounds();
    if (bounds == null) return target;
    return target.clamp(bounds.min, bounds.max).toDouble();
  }

  bool applyReadingDelta(
    double delta, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    return applyReadingTarget(
      readingY + delta,
      scheduleShift: scheduleShift,
      captureVisibleLocation: captureVisibleLocation,
    );
  }

  bool applyReadingDeltaPreservingArtificialRemainder(
    double delta, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    if (delta == 0) return false;
    final before = readingY;
    final target = before + delta;
    final moved = applyReadingTarget(
      target,
      scheduleShift: scheduleShift,
      captureVisibleLocation: captureVisibleLocation,
    );
    final consumed = readingY - before;
    final remaining = delta - consumed;
    if (remaining.abs() >= 0.5 &&
        _isArtificialScrollBoundaryForTarget(target, readingY)) {
      _pendingArtificialDelta += remaining;
      _scheduleWindowShiftForAnchor();
    }
    return moved;
  }

  void consumePendingArtificialDelta() {
    final pending = _pendingArtificialDelta;
    if (pending.abs() < 0.5) {
      _pendingArtificialDelta = 0.0;
      return;
    }
    _pendingArtificialDelta = 0.0;
    final before = readingY;
    final target = before + pending;
    final moved = applyReadingTarget(
      target,
      scheduleShift: false,
      captureVisibleLocation: false,
    );
    final consumed = readingY - before;
    final remaining = pending - consumed;
    if (remaining.abs() >= 0.5 &&
        _isArtificialScrollBoundaryForTarget(target, readingY)) {
      _pendingArtificialDelta += remaining;
      _scheduleWindowShiftForAnchor();
    }
    if (moved) {
      _scheduleVisibleLocationCapture();
    }
  }

  void pauseFlingAtArtificialBoundary() {
    final velocity = scrollAnimation.velocity;
    pausedFlingAtArtificialBoundary = true;
    _pendingArtificialFlingVelocity = velocity.abs() >= 50.0 ? velocity : null;
    _activeScrollAnimationIsFling = false;
    scrollAnimation.stop();
    _lastAnimationValue = readingY;
    scrollAnimation.value = readingY;
    _scheduleWindowShiftForAnchor();
  }

  bool resumePendingArtificialFlingIfNeeded() {
    if (!pausedFlingAtArtificialBoundary) return false;
    pausedFlingAtArtificialBoundary = false;
    final velocity = _pendingArtificialFlingVelocity;
    _pendingArtificialFlingVelocity = null;
    if (isDragging) return false;
    if (velocity == null || velocity.abs() < 50.0) {
      unawaited(_handleScrollSettled());
      return false;
    }
    final deltaSign = velocity > 0 ? 1.0 : -1.0;
    if (_isAtBookBoundaryForDelta(deltaSign, readingY)) {
      unawaited(_handleScrollSettled());
      return false;
    }
    startFling(velocity);
    return true;
  }

  bool applyReadingTarget(
    double target, {
    bool scheduleShift = true,
    bool captureVisibleLocation = true,
  }) {
    if (!_hasVisiblePages()) return false;
    final direction = target - readingY;
    if (direction == 0) return false;
    final nextReadingY = clampReadingY(target);
    if ((nextReadingY - readingY).abs() < 0.01) {
      if (scheduleShift ||
          _isArtificialScrollBoundaryForTarget(target, readingY)) {
        _scheduleWindowShiftForAnchor();
      }
      return false;
    }
    setReadingY(nextReadingY);
    if (captureVisibleLocation) {
      _scheduleVisibleLocationCapture();
    }
    if (scheduleShift ||
        _isNearArtificialWindowEdge(
          forward: direction > 0,
          threshold: _shiftThreshold(),
          readingY: readingY,
        )) {
      _scheduleWindowShiftForAnchor();
    }
    return true;
  }

  void setOverscrollY(double value) {
    final maxDistance = _maxOverscrollDistance();
    final next = value.clamp(-maxDistance, maxDistance).toDouble();
    if ((overscrollAnimation.value - next).abs() < 0.01) return;
    overscrollAnimation.value = next;
  }

  void applyOverscrollDragDelta(double fingerDeltaY) {
    if (fingerDeltaY == 0) return;
    final current = overscrollY;
    if (current == 0 || current.sign == fingerDeltaY.sign) {
      setOverscrollY(current + fingerDeltaY * _overscrollResistance());
      return;
    }

    final next = current + fingerDeltaY;
    if (next != 0 && next.sign == current.sign) {
      setOverscrollY(next);
      return;
    }

    setOverscrollY(0.0);
    final moved = applyReadingDelta(-next);
    dragMovedReadingY = dragMovedReadingY || moved;
  }

  Future<void> settleOverscroll({required bool saveProgress}) async {
    if (overscrollY.abs() < 0.5) {
      setOverscrollY(0.0);
      if (saveProgress) {
        await _handleScrollSettled();
      } else {
        endInteractivePreloadPause();
      }
      return;
    }
    try {
      await overscrollAnimation
          .animateTo(
            0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      if (!_isMounted()) return;
    }
    if (!_isMounted()) return;
    if (saveProgress) {
      await _handleScrollSettled();
    } else {
      endInteractivePreloadPause();
    }
  }

  void handleDragStart(DragStartDetails details) {
    beginInteractivePreloadPause();
    clearArtificialMotionState();
    isDragging = true;
    _activeScrollAnimationIsFling = false;
    scrollAnimation.stop();
    overscrollAnimation.stop();
    _animationTickCount = 0;
    dragMovedReadingY = false;
  }

  bool holdCurrentScrollPositionIfAnimating() {
    final scrollAnimating = scrollAnimation.isAnimating;
    final overscrollAnimating = overscrollAnimation.isAnimating;
    if (!scrollAnimating && !overscrollAnimating) return false;

    if (scrollAnimating) {
      final currentTarget = scrollAnimation.value;
      _activeScrollAnimationIsFling = false;
      scrollAnimation.stop();
      applyReadingTarget(
        currentTarget,
        scheduleShift: false,
        captureVisibleLocation: false,
      );
      _lastAnimationValue = readingY;
    }
    if (overscrollAnimating) {
      overscrollAnimation.stop();
    }
    isDragging = false;
    dragMovedReadingY = false;
    _animationTickCount = 0;
    _scheduleVisibleLocationCapture();
    _scheduleWindowShiftForAnchor();
    unawaited(_handleScrollSettled());
    return true;
  }

  void handleDragUpdate(DragUpdateDetails details) {
    overscrollAnimation.stop();
    final fingerDeltaY = details.delta.dy;
    if (overscrollY.abs() >= 0.5) {
      applyOverscrollDragDelta(fingerDeltaY);
      return;
    }

    final readingDelta = -fingerDeltaY;
    final atBookBoundary = _isAtBookBoundaryForDelta(readingDelta, readingY);
    final moved = applyReadingDeltaPreservingArtificialRemainder(
      readingDelta,
      scheduleShift: !atBookBoundary,
    );
    dragMovedReadingY = dragMovedReadingY || moved;
    if (!moved && atBookBoundary) {
      applyOverscrollDragDelta(fingerDeltaY);
    }
  }

  void handleDragEnd(DragEndDetails details) {
    isDragging = false;
    if (overscrollY.abs() >= 0.5) {
      final saveProgress = dragMovedReadingY;
      dragMovedReadingY = false;
      unawaited(settleOverscroll(saveProgress: saveProgress));
      return;
    }
    dragMovedReadingY = false;
    final velocity = -(details.primaryVelocity ?? 0.0);
    if (velocity.abs() < 50) {
      unawaited(_handleScrollSettled());
      return;
    }
    startFling(velocity);
  }

  void handleDragCancel() {
    isDragging = false;
    if (overscrollY.abs() >= 0.5) {
      final saveProgress = dragMovedReadingY;
      dragMovedReadingY = false;
      unawaited(settleOverscroll(saveProgress: saveProgress));
      return;
    }
    dragMovedReadingY = false;
    unawaited(_handleScrollSettled());
  }

  void startFling(double velocity) {
    beginInteractivePreloadPause();
    final effectiveVelocity = velocity.clamp(
      -maxFlingVelocity,
      maxFlingVelocity,
    );
    _updateWindowBoostForFling(effectiveVelocity);
    _scheduleWindowShiftForAnchor();
    scrollAnimation.stop();
    _lastAnimationValue = readingY;
    scrollAnimation.value = readingY;
    _activeScrollAnimationIsFling = true;
    _animationTickCount = 0;
    unawaited(
      _runtime.preloadDirectionalForVelocity(
        chapterIndex: _anchorChapterIndex(readingY),
        forward: effectiveVelocity > 0,
        velocity: effectiveVelocity,
      ),
    );
    final simulation = ClampingScrollSimulation(
      position: readingY,
      velocity: effectiveVelocity,
    );
    unawaited(
      scrollAnimation.animateWith(simulation).whenComplete(() {
        _activeScrollAnimationIsFling = false;
        if (_isMounted()) unawaited(_handleScrollSettled());
      }),
    );
  }

  Future<bool> animateToReadingY(double target) async {
    if (!_isMounted() || !_hasVisiblePages()) return false;
    final start = readingY;
    final clampedTarget = clampReadingY(target);
    if ((clampedTarget - start).abs() < 0.01) return false;
    _activeScrollAnimationIsFling = false;
    scrollAnimation.stop();
    setOverscrollY(0.0);
    isDragging = false;
    _lastAnimationValue = readingY;
    scrollAnimation.value = readingY;
    try {
      await scrollAnimation
          .animateTo(
            clampedTarget,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      if (!_isMounted()) return false;
    }
    if (!_isMounted()) return false;
    final moved = (readingY - start).abs() >= 0.01;
    if (!moved) return false;
    await _requestShiftWindowForAnchor();
    await _handleScrollSettled();
    return _isMounted();
  }

  double _maxOverscrollDistance() {
    final viewport = _viewportHeight();
    return (viewport * overscrollMaxViewportFactor)
        .clamp(overscrollMinDistance, overscrollMaxDistance)
        .toDouble();
  }

  double _overscrollResistance() {
    final maxDistance = _maxOverscrollDistance();
    final remaining = 1.0 - (overscrollY.abs() / maxDistance).clamp(0.0, 1.0);
    return overscrollBaseResistance * remaining.clamp(0.25, 1.0);
  }

  void _handleScrollAnimationTick() {
    final current = scrollAnimation.value;
    if (current == _lastAnimationValue) return;
    final moved = applyReadingTarget(
      current,
      scheduleShift: false,
      captureVisibleLocation: false,
    );
    _lastAnimationValue = current;
    if (!moved) {
      if (_isArtificialScrollBoundaryForTarget(current, readingY)) {
        pauseFlingAtArtificialBoundary();
        return;
      }
      _activeScrollAnimationIsFling = false;
      scrollAnimation.stop();
      unawaited(_handleScrollSettled());
      return;
    }
    _animationTickCount += 1;
    if (_animationTickCount == 1 ||
        _animationTickCount % animationShiftThrottleEveryTicks == 0) {
      _scheduleVisibleLocationCapture();
    }
    if (_animationTickCount % animationShiftThrottleEveryTicks == 0) {
      _scheduleWindowShiftForAnchor();
    }
  }
}
