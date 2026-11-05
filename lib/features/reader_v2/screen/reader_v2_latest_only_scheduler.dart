import 'dart:async';

import 'package:flutter/widgets.dart';

/// 只送最新那一次的排程，排版與內容設定生效共用（見 `ReaderV2ControllerHost`）。
///
/// [request] 記下要送的值並排一次送出。送出在下一幀；[quietFrames] 為真時要
/// 等到一幀沒有新的 [request] 才送，旋轉與 inset 動畫每幀都會變，只送最後
/// 那一次。送出中又來新的，等這次送完再送最新的。
///
/// [gate] 在送出當下再看一次要不要送，所以看「送出當下」狀態的呼叫端不必在
/// [request] 時先判斷。[send] 自己記下成敗與不再重送的世界；[onSettled] 在送
/// 完後呼叫，[completed] 為假表示 [send] 丟了例外。離開畫面之後不再送，也不
/// 再排。
final class LatestOnlyScheduler<T> {
  LatestOnlyScheduler({
    required this.isMounted,
    required this.send,
    this.gate,
    this.onSettled,
    this.quietFrames = false,
  });

  final bool Function() isMounted;
  final Future<void> Function(T value) send;
  final bool Function(T value)? gate;
  final void Function(T value, {required bool completed})? onSettled;
  final bool quietFrames;

  T? _requested;
  T? _inFlight;
  int _revision = 0;
  bool _queued = false;

  /// 等著送的最新值；沒有時為 null。
  T? get requested => _requested;

  /// 送出中的值；沒有在送時為 null。
  T? get inFlight => _inFlight;

  void request(T value) {
    _requested = value;
    _revision += 1;
    _queue();
  }

  /// 不再送等著的值（已經是要的狀態）。
  void cancelRequest() => _requested = null;

  void _queue() {
    if (_queued || _inFlight != null) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!quietFrames) {
        _queued = false;
        if (!isMounted()) {
          _requested = null;
          return;
        }
        _dispatch();
        return;
      }
      if (!isMounted()) {
        _queued = false;
        _requested = null;
        return;
      }
      _waitForQuietFrame(_revision);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _waitForQuietFrame(int observedRevision) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) {
        _queued = false;
        _requested = null;
        return;
      }
      if (_revision != observedRevision) {
        _waitForQuietFrame(_revision);
        return;
      }
      _queued = false;
      _dispatch();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _dispatch() {
    final value = _requested;
    _requested = null;
    if (value == null) return;
    if (gate != null && !gate!(value)) return;
    unawaited(_run(value));
  }

  Future<void> _run(T value) async {
    _inFlight = value;
    var completed = false;
    try {
      await send(value);
      completed = true;
    } finally {
      _inFlight = null;
      if (isMounted()) {
        onSettled?.call(value, completed: completed);
        if (_requested != null) _queue();
      } else {
        _requested = null;
      }
    }
  }
}
