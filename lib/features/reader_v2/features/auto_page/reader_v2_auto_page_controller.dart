import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';

typedef ReaderV2AutoPageTimerFactory =
    Timer Function(Duration interval, void Function(Timer timer) onTick);

class ReaderV2AutoPageController extends ChangeNotifier {
  ReaderV2AutoPageController({
    required this.runtime,
    ReaderV2ViewportController? viewportController,
    double Function()? viewportExtent,
    double Function()? autoPageSpeed,
    Duration scrollInterval = const Duration(milliseconds: 16),
    Duration pageInterval = const Duration(seconds: 8),
    ReaderV2AutoPageTimerFactory? timerFactory,
  }) : _viewportController = viewportController,
       _viewportExtent = viewportExtent,
       _autoPageSpeed = autoPageSpeed,
       _scrollInterval = scrollInterval,
       _pageInterval = pageInterval,
       _timerFactory = timerFactory ?? Timer.periodic {
    _lastMode = runtime.state.mode;
    runtime.addListener(_handleRuntimeChanged);
  }

  static const double _minAutoPageSpeed = 0.04;
  static const double _maxAutoPageSpeed = 0.45;
  static const double _defaultAutoPageSpeed = 0.16;

  final ReaderV2Runtime runtime;
  final ReaderV2ViewportController? _viewportController;
  final double Function()? _viewportExtent;
  final double Function()? _autoPageSpeed;
  final Duration _scrollInterval;
  final Duration _pageInterval;
  final ReaderV2AutoPageTimerFactory _timerFactory;
  Timer? _timer;
  late ReaderV2Mode _lastMode;
  bool _stepping = false;
  DateTime? _lastScrollTick;

  bool get isRunning => _timer != null;

  void toggle() {
    if (isRunning) {
      stop();
      return;
    }
    start();
  }

  void start() {
    if (isRunning) return;
    _lastMode = runtime.state.mode;
    _lastScrollTick = null;
    _timer = _createTimerForCurrentMode();
    notifyListeners();
  }

  Future<bool> stepAsync() async {
    if (_stepping) return false;
    _stepping = true;
    try {
      final moved = await _step();
      if (!moved) stop();
      return moved;
    } finally {
      _stepping = false;
    }
  }

  Future<bool> _step() async {
    if (runtime.state.mode == ReaderV2Mode.scroll) {
      final delta = _scrollStepDeltaForElapsed();
      if (delta > 0) {
        final continuousScrollBy = _viewportController?.continuousScrollBy;
        if (continuousScrollBy != null && await continuousScrollBy(delta)) {
          return true;
        }
        final scrollBy = _viewportController?.scrollBy;
        if (scrollBy != null && await scrollBy(delta)) return true;
        final animateBy = _viewportController?.animateBy;
        if (animateBy != null && await animateBy(delta)) return true;
      }
      final moveToNextPage = _viewportController?.moveToNextPage;
      if (moveToNextPage != null && await moveToNextPage()) return true;
      final moved = runtime.moveToNextPage();
      return Future<bool>.value(moved);
    }
    final moveToNextPage = _viewportController?.moveToNextPage;
    if (moveToNextPage != null && await moveToNextPage()) return true;
    final moved = runtime.moveSlidePageAndSettle(forward: true);
    return Future<bool>.value(moved);
  }

  Duration _intervalForCurrentMode() {
    if (runtime.state.mode == ReaderV2Mode.scroll) return _scrollInterval;
    final millis = _pageInterval.inMilliseconds.toDouble();
    final speed = _speed;
    final fastest = millis * 0.5;
    final slowest = millis * 3.0;
    final normalized =
        speed <= _defaultAutoPageSpeed
            ? (speed - _minAutoPageSpeed) /
                (_defaultAutoPageSpeed - _minAutoPageSpeed)
            : (speed - _defaultAutoPageSpeed) /
                (_maxAutoPageSpeed - _defaultAutoPageSpeed);
    final targetMillis =
        speed <= _defaultAutoPageSpeed
            ? slowest - (slowest - millis) * normalized
            : millis - (millis - fastest) * normalized;
    return Duration(milliseconds: targetMillis.round());
  }

  Timer _createTimerForCurrentMode() {
    return _timerFactory(_intervalForCurrentMode(), (_) {
      unawaited(stepAsync());
    });
  }

  void _handleRuntimeChanged() {
    final mode = runtime.state.mode;
    if (mode == _lastMode) return;
    _lastMode = mode;
    if (!isRunning) return;
    _timer?.cancel();
    _lastScrollTick = null;
    _timer = _createTimerForCurrentMode();
  }

  void refreshConfiguration() {
    if (!isRunning || runtime.state.mode == ReaderV2Mode.scroll) return;
    _timer?.cancel();
    _timer = _createTimerForCurrentMode();
  }

  double _scrollStepDeltaForElapsed() {
    final explicit = _viewportExtent?.call();
    final viewportHeight =
        explicit != null && explicit.isFinite && explicit > 0
            ? explicit
            : runtime.state.layoutSpec.viewportSize.height;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return 0;
    final now = DateTime.now();
    final previous = _lastScrollTick;
    _lastScrollTick = now;
    final elapsedSeconds =
        previous == null
            ? _scrollInterval.inMicroseconds / Duration.microsecondsPerSecond
            : now.difference(previous).inMicroseconds /
                Duration.microsecondsPerSecond;
    final boundedElapsed = elapsedSeconds.clamp(0.004, 0.08).toDouble();
    return viewportHeight * _speed * boundedElapsed;
  }

  double get _speed {
    final value = _autoPageSpeed?.call() ?? _defaultAutoPageSpeed;
    if (!value.isFinite) return _defaultAutoPageSpeed;
    return value.clamp(_minAutoPageSpeed, _maxAutoPageSpeed).toDouble();
  }

  void stop() {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    _lastScrollTick = null;
    unawaited(_viewportController?.settleScroll?.call());
    notifyListeners();
  }

  @override
  void dispose() {
    runtime.removeListener(_handleRuntimeChanged);
    _timer?.cancel();
    super.dispose();
  }
}
