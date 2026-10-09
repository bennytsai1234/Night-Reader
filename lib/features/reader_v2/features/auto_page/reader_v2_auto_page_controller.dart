import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

typedef ReaderV2AutoPageTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) onTick,
);

class ReaderV2AutoPageController extends ChangeNotifier {
  ReaderV2AutoPageController({
    required this.runtime,
    this._viewportController,
    this._viewportExtent,
    this._autoPageSpeed,
    this._scrollInterval = const Duration(milliseconds: 16),
    ReaderV2AutoPageTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.periodic;

  static const double _minAutoPageSpeed =
      ReaderV2PrefsRepository.minAutoPageSpeed;
  static const double _maxAutoPageSpeed =
      ReaderV2PrefsRepository.maxAutoPageSpeed;
  static const double _defaultAutoPageSpeed = 0.16;

  final ReaderV2Runtime runtime;
  final ReaderV2ViewportController? _viewportController;
  final double Function()? _viewportExtent;
  final double Function()? _autoPageSpeed;
  final Duration _scrollInterval;
  final ReaderV2AutoPageTimerFactory _timerFactory;
  Timer? _timer;
  bool _stepping = false;
  DateTime? _lastScrollTick;

  /// 每次開始或停止都換號；停止前就在等待的步進，回來後不得再推動正文
  /// 或停掉新的一輪。
  int _run = 0;
  bool _paused = false;
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
    _run += 1;
    _lastScrollTick = null;
    _timer = _createTimerForCurrentMode();
    notifyListeners();
  }

  /// 選單開著時暫停位移，關上後從原處接著捲；不改變是否在自動捲動。
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    _lastScrollTick = null;
  }

  Future<bool> stepAsync() async {
    if (_stepping || _paused) return false;
    _stepping = true;
    final run = _run;
    try {
      final moved = await _step(run);
      if (!moved && run == _run && !_paused) stop();
      return moved;
    } catch (error, stackTrace) {
      // Stop the periodic producer, but do not reinterpret a thrown viewport
      // invariant failure as the ordinary "could not move" false result.
      if (run == _run) stop();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _stepping = false;
    }
  }

  Future<bool> _step(int run) async {
    bool current() => run == _run && !_paused;
    final delta = _scrollStepDeltaForElapsed();
    if (delta > 0) {
      final continuousScrollBy = _viewportController?.continuousScrollBy;
      if (continuousScrollBy != null && await continuousScrollBy(delta)) {
        return true;
      }
      if (!current()) return false;
      final scrollBy = _viewportController?.scrollBy;
      if (scrollBy != null && await scrollBy(delta)) return true;
    }
    if (!current()) return false;
    final moveToNextPage = _viewportController?.moveToNextPage;
    if (moveToNextPage != null && await moveToNextPage()) return true;
    return false;
  }

  Duration _intervalForCurrentMode() {
    return _scrollInterval;
  }

  Timer _createTimerForCurrentMode() {
    return _timerFactory(_intervalForCurrentMode(), (_) {
      unawaited(stepAsync());
    });
  }

  void refreshConfiguration() {
    if (!isRunning) return;
    _timer?.cancel();
    _timer = _createTimerForCurrentMode();
  }

  double _scrollStepDeltaForElapsed() {
    final explicit = _viewportExtent?.call();
    final viewportHeight = explicit != null && explicit.isFinite && explicit > 0
        ? explicit
        : runtime.state.layoutSpec.viewportSize.height;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return 0;
    final now = DateTime.now();
    final previous = _lastScrollTick;
    _lastScrollTick = now;
    final elapsedSeconds = previous == null
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
    _run += 1;
    timer.cancel();
    _timer = null;
    _lastScrollTick = null;
    unawaited(_viewportController?.settleScroll?.call());
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
