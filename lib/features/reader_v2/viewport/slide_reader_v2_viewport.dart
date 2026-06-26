import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_key.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_layer.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_page_window.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';

class SlideReaderV2Viewport extends StatefulWidget {
  const SlideReaderV2Viewport({
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
  State<SlideReaderV2Viewport> createState() => _SlideReaderV2ViewportState();
}

class _SlideReaderV2ViewportState extends State<SlideReaderV2Viewport>
    with SingleTickerProviderStateMixin {
  static const double _dragWarmupDistance = 12;
  static const double _axisIntentSlop = 12;
  static const double _verticalIntentRatio = 1.2;

  late final AnimationController _slideController;
  late int _lastLayoutGeneration;
  double _dragDx = 0;
  double _rawDragDx = 0;
  double _lastAnimationValue = 0;
  double _lastViewportWidth = 0;
  int _pendingDirection = 0;
  int _warmedDragDirection = 0;
  ReaderV2Location? _pendingSettledLocation;
  bool _postFrameCapturePending = false;
  bool _pageTurnInProgress = false;
  bool _dragActive = false;
  bool _queueingBusyDrag = false;
  bool _rejectingVerticalIntent = false;
  bool _horizontalIntentAccepted = false;
  double _queuedBusyDragDx = 0;
  Offset? _dragDownGlobalPosition;
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0.0);
  Future<void> _pageCommandTail = Future<void>.value();
  Completer<void> _pageTurnCompleter = Completer<void>()..complete();

  void _checkCompleter() {
    final isIdle = !_dragActive && !_pageTurnInProgress && !_slideController.isAnimating;
    if (isIdle && !_pageTurnCompleter.isCompleted) {
      _pageTurnCompleter.complete();
    } else if (!isIdle && _pageTurnCompleter.isCompleted) {
      _pageTurnCompleter = Completer<void>();
    }
  }

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController.unbounded(vsync: this)
      ..addListener(_onAnimationTick);
    _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.registerVisibleLocationCapture(
      this,
      _captureVisibleLocation,
    );
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
    _attachController();
    _schedulePostFrameVisibleLocationCapture();
  }

  @override
  void didUpdateWidget(covariant SlideReaderV2Viewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      oldWidget.runtime.unregisterVisibleLocationCapture(this);
      oldWidget.runtime.unregisterViewportRestore(this);
      oldWidget.runtime.removeListener(_onRuntimeChanged);
      widget.runtime.addListener(_onRuntimeChanged);
      widget.runtime.registerVisibleLocationCapture(
        this,
        _captureVisibleLocation,
      );
      widget.runtime.registerViewportRestore(this, _restoreToLocation);
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _resetViewport();
      _schedulePostFrameVisibleLocationCapture();
    } else if (oldWidget.style.pageMode != widget.style.pageMode) {
      _resetViewport();
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
    _dragOffset.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _attachController() {
    widget.controller
      ?..moveToNextPage = _moveToNextPage
      ..moveToPrevPage = _moveToPrevPage
      ..ensureCharRangeVisible = _ensureCharRangeVisible;
  }

  void _detachController(ReaderV2ViewportController? controller) {
    controller
      ?..moveToNextPage = null
      ..moveToPrevPage = null
      ..ensureCharRangeVisible = null;
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    final layoutChanged =
        _lastLayoutGeneration != widget.runtime.state.layoutGeneration;
    if (layoutChanged) {
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _resetViewport();
    }
    if (widget.runtime.state.phase == ReaderV2Phase.ready) {
      _schedulePostFrameVisibleLocationCapture();
    }
    setState(() {});
  }

  void _schedulePostFrameVisibleLocationCapture() {
    if (_postFrameCapturePending) return;
    _postFrameCapturePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameCapturePending = false;
      if (!mounted) return;
      widget.runtime.captureVisibleLocation(notifyIfChanged: false);
    });
  }

  void _onAnimationTick() {
    final current = _slideController.value;
    final delta = current - _lastAnimationValue;
    _lastAnimationValue = current;
    if (delta == 0) return;
    final nextDx = _dragDx + delta;
    _setDragOffsets(nextDx, rawDx: nextDx);
  }

  void _setDragOffsets(double dx, {double? rawDx}) {
    _dragDx = dx;
    _rawDragDx = rawDx ?? dx;
    if (_dragOffset.value != dx) {
      _dragOffset.value = dx;
    }
  }

  void _resetViewport() {
    _slideController.stop();
    _slideController.value = 0;
    _lastAnimationValue = 0;
    _pendingDirection = 0;
    _warmedDragDirection = 0;
    _pendingSettledLocation = null;
    _pageTurnInProgress = false;
    _dragActive = false;
    _queueingBusyDrag = false;
    _rejectingVerticalIntent = false;
    _horizontalIntentAccepted = false;
    _queuedBusyDragDx = 0;
    _dragDownGlobalPosition = null;
    _dragDx = 0;
    _rawDragDx = 0;
    _dragOffset.value = 0;
    _checkCompleter();
  }

  bool _canMoveBackward(ReaderV2PageWindow window) {
    return window.prev != null && !window.prev!.isPlaceholder;
  }

  bool _canMoveForward(ReaderV2PageWindow window) {
    return window.next != null && !window.next!.isPlaceholder;
  }

  double _boundaryAdjustedDx(double nextDx, ReaderV2PageWindow window) {
    if (nextDx > 0 && !_canMoveBackward(window)) {
      return nextDx * 0.35;
    }
    if (nextDx < 0 && !_canMoveForward(window)) {
      return nextDx * 0.35;
    }
    return nextDx;
  }

  bool _isMostlyVerticalDrag(Offset currentGlobalPosition) {
    final down = _dragDownGlobalPosition;
    if (down == null) return false;
    final delta = currentGlobalPosition - down;
    final dx = delta.dx.abs();
    final dy = delta.dy.abs();
    return dy > _axisIntentSlop && dy > dx * _verticalIntentRatio;
  }

  bool _ensureHorizontalIntent(Offset currentGlobalPosition) {
    if (_horizontalIntentAccepted) return true;
    if (_isMostlyVerticalDrag(currentGlobalPosition)) {
      _rejectingVerticalIntent = true;
      _setDragOffsets(0, rawDx: 0);
      return false;
    }
    final down = _dragDownGlobalPosition;
    if (down == null) {
      _horizontalIntentAccepted = true;
      return true;
    }
    final dx = (currentGlobalPosition.dx - down.dx).abs();
    if (dx <= _axisIntentSlop) return false;
    _horizontalIntentAccepted = true;
    return true;
  }

  double _rawDxForUpdate(DragUpdateDetails details) {
    final down = _dragDownGlobalPosition;
    if (down == null) return _rawDragDx + details.delta.dx;
    return details.globalPosition.dx - down.dx;
  }

  Future<bool> _animateTo(
    double target, {
    Curve curve = Curves.easeOutCubic,
  }) async {
    _slideController.stop();
    _lastAnimationValue = 0;
    _slideController.value = 0;
    _checkCompleter();
    try {
      await _slideController
          .animateTo(
            target - _dragDx,
            duration: const Duration(milliseconds: 220),
            curve: curve,
          )
          .orCancel;
    } on TickerCanceled {
      return false;
    } finally {
      _checkCompleter();
    }
    if (!mounted) return false;
    _finalizeAnimation(target);
    return true;
  }

  Future<bool> _moveToNextPage() =>
      _enqueuePageCommand(() => _animateToAdjacentPage(forward: true));

  Future<bool> _moveToPrevPage() =>
      _enqueuePageCommand(() => _animateToAdjacentPage(forward: false));

  Future<bool> _enqueuePageCommand(Future<bool> Function() command) {
    if (!mounted) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _pageCommandTail = _pageCommandTail
        .catchError((_) {})
        .then((_) async {
          await _waitForSlideIdle();
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

  Future<void> _waitForSlideIdle() {
    _checkCompleter();
    return _pageTurnCompleter.future;
  }

  Future<bool> _animateToAdjacentPage({
    required bool forward,
    ReaderV2Location? settledLocation,
  }) async {
    if (!mounted) return false;
    if (_pageTurnInProgress || _slideController.isAnimating || _dragActive) {
      return false;
    }
    widget.runtime.preloadSlideNeighbor(forward: forward);
    final width = _commandViewportWidth();
    if (!width.isFinite || width <= 0) {
      return widget.runtime.moveSlidePageAndSettle(forward: forward);
    }
    var window = widget.runtime.state.pageWindow;
    var neighbor =
        window == null ? null : (forward ? window.next : window.prev);
    if (neighbor == null) return false;
    if (neighbor.isPlaceholder) {
      final ready = await widget.runtime.ensureSlideNeighborReady(
        forward: forward,
      );
      if (!mounted) return false;
      window = widget.runtime.state.pageWindow;
      neighbor = window == null ? null : (forward ? window.next : window.prev);
      if (neighbor == null) return false;
      if (neighbor.isPlaceholder || !ready) {
        widget.runtime.moveSlidePageAndSettle(forward: forward);
        return false;
      }
    }
    _pageTurnInProgress = true;
    _checkCompleter();
    try {
      _pendingDirection = forward ? 1 : -1;
      _pendingSettledLocation = settledLocation;
      return await _animateTo(forward ? -width : width);
    } finally {
      if (mounted) {
        _pageTurnInProgress = false;
        _checkCompleter();
      }
    }
  }

  double _commandViewportWidth() {
    if (_lastViewportWidth.isFinite && _lastViewportWidth > 0) {
      return _lastViewportWidth;
    }
    final specWidth = widget.runtime.state.layoutSpec.viewportSize.width;
    return specWidth.isFinite && specWidth > 0 ? specWidth : 0.0;
  }

  void _finalizeAnimation(double target) {
    if (!mounted) return;
    final direction = _pendingDirection;
    final settledLocation = _pendingSettledLocation;
    final moved =
        direction == 0
            ? false
            : widget.runtime.moveSlidePageAndSettle(
              forward: direction > 0,
              settledLocation: settledLocation,
            );
    _slideController.value = 0;
    _lastAnimationValue = 0;
    _pendingDirection = 0;
    _pendingSettledLocation = null;
    _setDragOffsets(0, rawDx: 0);
    if (target != 0 && moved) return;
  }

  void _handleDragStart(DragStartDetails details) {
    if (_pageTurnInProgress || _slideController.isAnimating) {
      _queueingBusyDrag = true;
      _queuedBusyDragDx = 0;
      return;
    }
    _dragActive = true;
    _checkCompleter();
    _queueingBusyDrag = false;
    _rejectingVerticalIntent = false;
    _horizontalIntentAccepted = false;
    _queuedBusyDragDx = 0;
    _slideController.stop();
    _slideController.value = 0;
    _lastAnimationValue = 0;
    _pendingDirection = 0;
    _warmedDragDirection = 0;
    _rawDragDx = _dragDx;
  }

  bool _isSlideMotionActive() {
    return _dragActive ||
        _pageTurnInProgress ||
        _queueingBusyDrag ||
        _slideController.isAnimating;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_rejectingVerticalIntent) return;
    if (!_ensureHorizontalIntent(details.globalPosition)) return;
    if (_queueingBusyDrag) {
      _queuedBusyDragDx += details.delta.dx;
      return;
    }
    if (_pageTurnInProgress) return;
    final window = widget.runtime.state.pageWindow;
    if (window == null) return;
    final nextRawDx = _rawDxForUpdate(details);
    if (nextRawDx.abs() >= _dragWarmupDistance) {
      _warmSlideNeighbor(forward: nextRawDx < 0);
    }
    _setDragOffsets(_boundaryAdjustedDx(nextRawDx, window), rawDx: nextRawDx);
  }

  void _warmSlideNeighbor({required bool forward}) {
    final direction = forward ? 1 : -1;
    if (_warmedDragDirection == direction) return;
    _warmedDragDirection = direction;
    widget.runtime.preloadSlideNeighbor(forward: forward);
  }

  void _handleDragEnd(DragEndDetails details, double width) {
    _dragDownGlobalPosition = null;
    if (_rejectingVerticalIntent) {
      _rejectingVerticalIntent = false;
      _horizontalIntentAccepted = false;
      _dragActive = false;
      _checkCompleter();
      _queueingBusyDrag = false;
      _queuedBusyDragDx = 0;
      _setDragOffsets(0, rawDx: 0);
      return;
    }
    if (_queueingBusyDrag) {
      _queueingBusyDrag = false;
      if (width <= 0) return;
      final velocity = details.primaryVelocity ?? 0;
      final forward =
          _queuedBusyDragDx.abs() >= _dragWarmupDistance
              ? _queuedBusyDragDx < 0
              : velocity < 0;
      final distancePassed = _queuedBusyDragDx.abs() > width * 0.25;
      final velocityPassed = velocity.abs() > 700;
      if (distancePassed || velocityPassed) {
        _queueAdjacentPageTurn(forward: forward);
      }
      _queuedBusyDragDx = 0;
      return;
    }
    if (_pageTurnInProgress) return;
    _dragActive = false;
    _checkCompleter();
    if (width <= 0) {
      _resetViewport();
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final forward = _rawDragDx < 0;
    final distancePassed = _rawDragDx.abs() > width * 0.25;
    final velocityPassed = velocity.abs() > 700;
    final window = widget.runtime.state.pageWindow;
    final neighbor =
        window == null ? null : (forward ? window.next : window.prev);
    if ((distancePassed || velocityPassed) &&
        window != null &&
        neighbor != null &&
        neighbor.isPlaceholder) {
      unawaited(_animateToAdjacentPage(forward: forward));
      return;
    }
    final shouldAdvance =
        (distancePassed || velocityPassed) &&
        window != null &&
        (forward ? _canMoveForward(window) : _canMoveBackward(window));
    _pendingDirection = shouldAdvance ? (forward ? 1 : -1) : 0;
    final target = shouldAdvance ? (forward ? -width : width) : 0.0;
    _pageTurnInProgress = true;
    _animateTo(target).whenComplete(() {
      if (mounted) {
        _pageTurnInProgress = false;
      }
    });
  }

  void _handleDragCancel() {
    _dragDownGlobalPosition = null;
    if (_queueingBusyDrag) {
      _queueingBusyDrag = false;
      _queuedBusyDragDx = 0;
      return;
    }
    _resetViewport();
  }

  void _queueAdjacentPageTurn({required bool forward}) {
    _pageCommandTail = _pageCommandTail.catchError((_) {}).then((_) async {
      await _waitForSlideIdle();
      if (!mounted) return;
      await _animateToAdjacentPage(forward: forward);
    });
  }

  ReaderV2TileKey _tileKey(ReaderV2PageCache tile) {
    return ReaderV2TileKey.fromPageCache(
      tile,
      layoutRevision: widget.runtime.state.layoutGeneration,
    );
  }

  ReaderV2SlidePagePlacement _placementForPage({
    required ReaderV2RenderPage page,
    required int pageSlot,
    required double width,
  }) {
    return ReaderV2SlidePagePlacement(
      page: ReaderV2PageCacheFactory.fromRenderPage(page),
      virtualLeft: width * pageSlot,
      pageSlot: pageSlot,
    );
  }

  Widget _buildTile(ReaderV2SlidePagePlacement placement) {
    final pageCache = placement.page;
    return Stack(
      key: ValueKey<ReaderV2TileKey>(_tileKey(pageCache)),
      fit: StackFit.expand,
      children: [
        ReaderV2TileLayer(
          tile: pageCache,
          tileKey: _tileKey(pageCache),
          style: widget.style,
          backgroundColor: widget.backgroundColor,
          textColor: widget.textColor,
          expand: true,
          paintBackground: false,
        ),
        ReaderV2TtsHighlightOverlayLayer(
          tile: pageCache,
          style: widget.style,
          textColor: widget.textColor,
          highlight: widget.ttsHighlight,
        ),
      ],
    );
  }

  ReaderV2Location? _captureVisibleLocation() {
    if (_dragDx.abs() > 0.5 ||
        _slideController.isAnimating ||
        widget.runtime.state.phase != ReaderV2Phase.ready) {
      return null;
    }
    final current = widget.runtime.state.pageWindow?.current;
    if (current == null || current.isPlaceholder) return null;
    final page = ReaderV2PageCacheFactory.fromRenderPage(current);
    if (page.lines.isEmpty) return null;
    final anchorLineY = _anchorOffsetInViewport();
    final anchorContentY = anchorLineY - widget.runtime.state.layoutSpec.style.paddingTop;
    final contentY = anchorContentY.clamp(0.0, page.contentHeight).toDouble();
    final nearest = page.lineAtOrNearLocalY(page.localStartY + contentY);
    if (nearest == null) return null;
    return ReaderV2Location(
      chapterIndex: page.chapterIndex,
      charOffset: nearest.startCharOffset,
      visualOffsetPx: anchorContentY - nearest.top,
    );
  }

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) {
    return _enqueuePageCommand(
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
    final safeChapterIndex =
        chapterIndex.clamp(0, widget.runtime.chapterCount - 1).toInt();
    final targetOffset =
        (startCharOffset <= endCharOffset ? startCharOffset : endCharOffset);
    final safeTargetOffset = targetOffset < 0 ? 0 : targetOffset;
    final state = widget.runtime.state;
    if (state.phase != ReaderV2Phase.ready) return false;
    final window = state.pageWindow;
    if (window == null) return false;
    if (_pageContainsChar(
      window.current,
      chapterIndex: safeChapterIndex,
      charOffset: safeTargetOffset,
    )) {
      return true;
    }
    if (_pageContainsChar(
      window.next,
      chapterIndex: safeChapterIndex,
      charOffset: safeTargetOffset,
    )) {
      return _moveToAdjacentTtsPage(
        forward: true,
        chapterIndex: safeChapterIndex,
        charOffset: safeTargetOffset,
      );
    }
    if (_pageContainsChar(
      window.prev,
      chapterIndex: safeChapterIndex,
      charOffset: safeTargetOffset,
    )) {
      return _moveToAdjacentTtsPage(
        forward: false,
        chapterIndex: safeChapterIndex,
        charOffset: safeTargetOffset,
      );
    }
    final warmed = await _warmAdjacentTtsTarget(chapterIndex: safeChapterIndex);
    if (warmed && mounted) {
      final refreshedWindow = widget.runtime.state.pageWindow;
      if (refreshedWindow != null) {
        if (_pageContainsChar(
          refreshedWindow.next,
          chapterIndex: safeChapterIndex,
          charOffset: safeTargetOffset,
        )) {
          return _moveToAdjacentTtsPage(
            forward: true,
            chapterIndex: safeChapterIndex,
            charOffset: safeTargetOffset,
          );
        }
        if (_pageContainsChar(
          refreshedWindow.prev,
          chapterIndex: safeChapterIndex,
          charOffset: safeTargetOffset,
        )) {
          return _moveToAdjacentTtsPage(
            forward: false,
            chapterIndex: safeChapterIndex,
            charOffset: safeTargetOffset,
          );
        }
      }
    }
    return _jumpToTtsPage(
      chapterIndex: safeChapterIndex,
      charOffset: safeTargetOffset,
    );
  }

  Future<bool> _warmAdjacentTtsTarget({required int chapterIndex}) async {
    final current = widget.runtime.state.pageWindow?.current;
    if (current == null || current.isPlaceholder) return false;
    if (chapterIndex == current.chapterIndex + 1) {
      return widget.runtime.ensureSlideNeighborReady(forward: true);
    }
    if (chapterIndex == current.chapterIndex - 1) {
      return widget.runtime.ensureSlideNeighborReady(forward: false);
    }
    return false;
  }

  bool _pageContainsChar(
    ReaderV2RenderPage? page, {
    required int chapterIndex,
    required int charOffset,
  }) {
    if (page == null || page.isPlaceholder) return false;
    return page.chapterIndex == chapterIndex &&
        page.containsCharOffset(charOffset);
  }

  Future<bool> _moveToAdjacentTtsPage({
    required bool forward,
    required int chapterIndex,
    required int charOffset,
  }) async {
    final targetLocation = ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: charOffset,
    );
    final moved = await _animateToAdjacentPage(
      forward: forward,
      settledLocation: targetLocation,
    );
    if (!moved || !mounted) return false;
    final current = widget.runtime.state.pageWindow?.current;
    return _pageContainsChar(
      current,
      chapterIndex: chapterIndex,
      charOffset: charOffset,
    );
  }

  Future<bool> _jumpToTtsPage({
    required int chapterIndex,
    required int charOffset,
  }) async {
    final layoutGeneration = widget.runtime.state.layoutGeneration;
    _resetViewport();
    await widget.runtime.jumpToLocation(
      ReaderV2Location(chapterIndex: chapterIndex, charOffset: charOffset),
      immediateSave: false,
    );
    if (!mounted ||
        widget.runtime.state.layoutGeneration != layoutGeneration ||
        widget.runtime.state.phase != ReaderV2Phase.ready) {
      return false;
    }
    final current = widget.runtime.state.pageWindow?.current;
    if (!_pageContainsChar(
      current,
      chapterIndex: chapterIndex,
      charOffset: charOffset,
    )) {
      return false;
    }
    widget.runtime.settleCurrentSlidePage(
      settledLocation: ReaderV2Location(
        chapterIndex: chapterIndex,
        charOffset: charOffset,
      ),
    );
    return true;
  }

  Future<bool> _restoreToLocation(ReaderV2Location location) async {
    if (!mounted || widget.runtime.state.phase != ReaderV2Phase.ready) {
      return false;
    }
    _resetViewport();
    if (WidgetsBinding.instance.hasScheduledFrame) {
      await WidgetsBinding.instance.endOfFrame;
    }
    return mounted && _captureVisibleLocation() != null;
  }

  double _screenXFor({
    required int pageSlot,
    required double width,
    required double dragDx,
    ReaderV2SlidePagePlacement? placement,
  }) {
    final pageOffsetX = -dragDx;
    return placement?.screenX(pageOffsetX) ?? width * pageSlot - pageOffsetX;
  }

  double _anchorOffsetInViewport() =>
      widget.runtime.state.layoutSpec.anchorOffsetInViewport;

  @override
  Widget build(BuildContext context) {
    final state = widget.runtime.state;
    final window = state.pageWindow;
    if (state.phase != ReaderV2Phase.ready || window == null) {
      widget.runtime.recordFullScreenLoadingSample();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onTapUp,
        child: ColoredBox(
          color: widget.backgroundColor,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.textColor.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
    }

    widget.runtime.recordSlidePlaceholderExposure(
      _placeholderExposureCount(window),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width.isFinite && width > 0) {
          _lastViewportWidth = width;
        }
        final height =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : widget.runtime.state.layoutSpec.viewportSize.height;

        return ReaderV2PointerTapLayer(
          onTapUp: widget.onTapUp,
          onPointerDownTapPolicy: (_) => _isSlideMotionActive(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragDown:
                (details) => _dragDownGlobalPosition = details.globalPosition,
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: (details) => _handleDragEnd(details, width),
            onHorizontalDragCancel: _handleDragCancel,
            child: CustomPaint(
              size: Size(width, height),
              painter: _ReaderV2SlidePainter(
                prevPage: window.prev,
                currentPage: window.current,
                nextPage: window.next,
                style: widget.style,
                backgroundColor: widget.backgroundColor,
                textColor: widget.textColor,
                ttsHighlight: widget.ttsHighlight,
                layoutGeneration: widget.runtime.state.layoutGeneration,
                dragDx: _dragOffset,
                width: width,
              ),
            ),
          ),
        );
      },
    );
  }

  int _placeholderExposureCount(ReaderV2PageWindow window) {
    var count = 0;
    if (window.prev?.isPlaceholder == true) count += 1;
    if (window.current.isPlaceholder) count += 1;
    if (window.next?.isPlaceholder == true) count += 1;
    return count;
  }
}

class _ReaderV2SlidePainter extends CustomPainter {
  _ReaderV2SlidePainter({
    required this.prevPage,
    required this.currentPage,
    required this.nextPage,
    required this.style,
    required this.backgroundColor,
    required this.textColor,
    required this.ttsHighlight,
    required this.layoutGeneration,
    required this.dragDx,
    required this.width,
  }) : super(repaint: dragDx);

  final ReaderV2RenderPage? prevPage;
  final ReaderV2RenderPage currentPage;
  final ReaderV2RenderPage? nextPage;
  final ReaderV2Style style;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2TtsHighlight? ttsHighlight;
  final int layoutGeneration;
  final ValueNotifier<double> dragDx;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final dx = dragDx.value;

    // 1. Draw prevPage (slot -1)
    _paintPage(
      canvas: canvas,
      size: size,
      page: prevPage,
      offsetX: -width + dx,
      placeholderMessage: '已經是第一頁',
    );

    // 2. Draw currentPage (slot 0)
    _paintPage(
      canvas: canvas,
      size: size,
      page: currentPage,
      offsetX: dx,
    );

    // 3. Draw nextPage (slot 1)
    _paintPage(
      canvas: canvas,
      size: size,
      page: nextPage,
      offsetX: width + dx,
      placeholderMessage: '已經是最後一頁',
    );
  }

  void _paintPage({
    required Canvas canvas,
    required Size size,
    required ReaderV2RenderPage? page,
    required double offsetX,
    String? placeholderMessage,
  }) {
    if (offsetX + width <= 0 || offsetX >= size.width) {
      return;
    }

    canvas.save();
    canvas.translate(offsetX, 0);
    canvas.clipRect(Rect.fromLTWH(0, 0, width, size.height));

    if (page == null) {
      if (placeholderMessage != null) {
        _paintPlaceholderText(canvas, size, placeholderMessage);
      }
    } else if (page.isPlaceholder) {
      _paintPlaceholderText(canvas, size, '載入中...');
    } else {
      final pageCache = ReaderV2PageCacheFactory.fromRenderPage(page);
      final tilePainter = ReaderV2TilePainter(
        tile: pageCache,
        backgroundColor: backgroundColor,
        textColor: textColor,
        style: style,
        paintBackground: false,
      );
      tilePainter.paint(canvas, Size(width, size.height));

      final highlight = ttsHighlight;
      if (highlight != null &&
          highlight.isValid &&
          highlight.chapterIndex == pageCache.chapterIndex &&
          pageCache.intersectsCharRange(
            highlight.highlightStart,
            highlight.highlightEnd,
          )) {
        final ttsPainter = ReaderV2TtsHighlightOverlayPainter(
          tile: pageCache,
          style: style,
          textColor: textColor,
          highlight: highlight,
        );
        ttsPainter.paint(canvas, Size(width, size.height));
      }
    }

    canvas.restore();
  }

  void _paintPlaceholderText(Canvas canvas, Size size, String message) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: TextStyle(
          color: textColor.withValues(alpha: 0.7),
          fontSize: style.fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

    final textX = (width - textPainter.width) / 2;
    final textY = (size.height - textPainter.height) / 2;
    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant _ReaderV2SlidePainter oldDelegate) {
    return oldDelegate.prevPage != prevPage ||
        oldDelegate.currentPage != currentPage ||
        oldDelegate.nextPage != nextPage ||
        oldDelegate.style != style ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.ttsHighlight != ttsHighlight ||
        oldDelegate.layoutGeneration != layoutGeneration ||
        oldDelegate.width != width;
  }
}
