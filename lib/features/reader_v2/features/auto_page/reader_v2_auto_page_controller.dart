import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_operation_token.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

/// 每一幀呼叫一次，帶著從開始算起的幀時間。
typedef ReaderV2FrameCallback = void Function(Duration elapsed);

/// 開始在每一幀呼叫 [onFrame]，回傳停止的函式。
typedef ReaderV2FrameSource = VoidCallback Function(
  ReaderV2FrameCallback onFrame,
);

VoidCallback _tickerFrameSource(ReaderV2FrameCallback onFrame) {
  final ticker = Ticker(onFrame, debugLabel: 'ReaderV2AutoPage');
  unawaited(ticker.start());
  // 正文在捲時持有 [MotionGate]（ADR 0018）；每一幀的 jumpTo 各自發出捲動
  // 開始與結束，接不成一整段，所以由這裡持有到停下。
  final release = MotionGate.instance.hold();
  return () {
    release();
    ticker.dispose();
  };
}

/// 自動捲動。每一幀依幀時間推進正文，跟著螢幕的更新率走（120Hz 螢幕
/// 每秒推 120 次），位移量只看經過的時間，不看更新率。
class ReaderV2AutoPageController extends ChangeNotifier {
  ReaderV2AutoPageController({
    required this.runtime,
    this._viewportController,
    this._viewportExtent,
    this._autoPageSpeed,
    ReaderV2FrameSource? frameSource,
  }) : _frameSource = frameSource ?? _tickerFrameSource;

  static const double _minAutoPageSpeed =
      ReaderV2PrefsRepository.minAutoPageSpeed;
  static const double _maxAutoPageSpeed =
      ReaderV2PrefsRepository.maxAutoPageSpeed;
  static const double _defaultAutoPageSpeed = 0.16;

  /// 單幀最多推進的時間。卡頓超過這麼久時不一口氣補上，免得正文跳一大段。
  static const double _maxFrameSeconds = 0.08;

  final ReaderV2Runtime runtime;
  final ReaderV2ViewportController? _viewportController;
  final double Function()? _viewportExtent;
  final double Function()? _autoPageSpeed;
  final ReaderV2FrameSource _frameSource;
  VoidCallback? _stopFrames;
  Duration? _lastFrame;

  bool _running = false;
  bool _stepping = false;

  /// 每次開始或停止都換號；停止前就在等待的步進，回來後不得再推動正文
  /// 或停掉新的一輪。
  int _run = 0;
  bool _paused = false;
  bool get isRunning => _running;

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
    _running = true;
    _startFrames();
    notifyListeners();
  }

  /// 選單開著時暫停位移，關上後從原處接著捲；不改變是否在自動捲動。
  /// 暫停期間不要求新的幀。
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (!_running) return;
    if (paused) {
      _stopFrameSource();
    } else {
      _startFrames();
    }
  }

  void _startFrames() {
    if (_paused || _stopFrames != null) return;
    _lastFrame = null;
    _stopFrames = _frameSource(_onFrame);
  }

  void _stopFrameSource() {
    _stopFrames?.call();
    _stopFrames = null;
    _lastFrame = null;
  }

  void _onFrame(Duration elapsed) {
    // 上一步還沒做完時不更新時鐘，下一步的位移會涵蓋這段時間。
    if (_stepping) return;
    final last = _lastFrame;
    _lastFrame = elapsed;
    if (last == null) return;
    final seconds =
        (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    unawaited(_stepAsync(seconds));
  }

  Future<bool> _stepAsync(double seconds) async {
    if (_stepping || _paused) return false;
    _stepping = true;
    final run = _run;
    try {
      final moved = await _step(run, seconds);
      if (!moved && run == _run && !_paused) stop();
      return moved;
    } catch (error, stackTrace) {
      // Stop the frame producer, but do not reinterpret a thrown viewport
      // invariant failure as the ordinary "could not move" false result.
      if (run == _run) stop();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _stepping = false;
    }
  }

  Future<bool> _step(int run, double seconds) async {
    bool current() => run == _run && !_paused;
    // 等跳章正文時紙下的正文不動；這一步跳過，不當成到了書尾而停下。
    if (runtime.stateMachine.currentOperation?.kind ==
        ReaderV2OperationKind.jump) {
      return true;
    }
    final delta = _scrollDelta(seconds);
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

  double _scrollDelta(double seconds) {
    final explicit = _viewportExtent?.call();
    final viewportHeight = explicit != null && explicit.isFinite && explicit > 0
        ? explicit
        : runtime.state.layoutSpec.viewportSize.height;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return 0;
    final bounded = seconds.clamp(0.0, _maxFrameSeconds).toDouble();
    return viewportHeight * _speed * bounded;
  }

  double get _speed {
    final value = _autoPageSpeed?.call() ?? _defaultAutoPageSpeed;
    if (!value.isFinite) return _defaultAutoPageSpeed;
    return value.clamp(_minAutoPageSpeed, _maxAutoPageSpeed).toDouble();
  }

  void stop() {
    if (!_running) return;
    _run += 1;
    _running = false;
    _stopFrameSource();
    unawaited(_viewportController?.settleScroll?.call());
    notifyListeners();
  }

  @override
  void dispose() {
    _stopFrameSource();
    super.dispose();
  }
}
