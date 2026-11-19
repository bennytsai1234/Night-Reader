import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// 往右拖返回放開後的收尾，照 Telegram。頁面的拖曳返回與主頁分頁的預測
/// 返回共用。
abstract final class BackSwipe {
  /// 拖過 20% 或往右快過 1000pt/s 就返回。
  static const double _popFraction = 0.2;
  static const double _popVelocity = 1000;

  /// 剩下的距離 / 放開時的速度，夾在 0.05–0.2 秒；彈回固定 0.1 秒。
  static const double _minFinishSeconds = 0.05;
  static const double _maxFinishSeconds = 0.2;
  static const Duration cancelDuration = Duration(milliseconds: 100);

  /// 送完或彈回的曲線（Telegram 的 easeInOut）。
  static const Curve curve = Curves.easeInOut;

  /// 拖走了 [dismissed]（0–1）、放開時往右 [velocity] px/s，算不算返回。
  static bool goesBack({required double dismissed, required double velocity}) =>
      velocity > _popVelocity || dismissed > _popFraction;

  /// 剩下 [distance] px、放開時 [velocity] px/s，送完要多久。
  static Duration finishDuration({
    required double distance,
    required double velocity,
  }) {
    final seconds = velocity.abs() < 1e-6
        ? _maxFinishSeconds
        : (distance / velocity.abs()).clamp(
            _minFinishSeconds,
            _maxFinishSeconds,
          );
    return Duration(microseconds: (seconds * 1e6).round());
  }
}

/// 系統預測返回的紀錄，頁面的預測返回與主頁分頁的預測返回共用：觸控留
/// 最近 100ms，放開時估速度；進度補成每一格都動。
///
/// 手指慢的時候，系統只在觸控座標變動時才送一次進度，間隔可長到數十毫秒；
/// 直接套用的話頁面停幾格、跳一下，看起來像掉到 60 或 30 幀。[progress] 照
/// Flutter 觸控重新取樣（[GestureBinding.resamplingEnabled]）的做法：取
/// [_delay] 之前那一刻，在前後兩筆進度之間內插。呼叫端拖曳中每一格讀一次。
/// App 自己的左緣拖曳走觸控事件，已經經過同樣的取樣。
class PredictiveBackTracker {
  /// 與 Flutter 觸控重新取樣的預設延遲相同（`GestureBinding.samplingOffset`）。
  static const Duration _delay = Duration(milliseconds: 38);

  final List<({Offset at, Duration time})> _touches = [];
  final List<({Duration time, double value})> _progress = [];

  /// 測試裡跟著假時間走（同 Flutter 的觸控重新取樣）。
  final Stopwatch _clock = GestureBinding.instance.samplingClock.stopwatch()
    ..start();

  void clear() {
    _touches.clear();
    _progress.clear();
  }

  /// 記下一筆事件的觸控位置與進度（[PredictiveBackEvent.progress]）。
  /// Android 送來的是實體像素，除以 [devicePixelRatio] 換成和頁寬一樣的
  /// 邏輯像素。
  void record(PredictiveBackEvent event, double devicePixelRatio) {
    final now = _clock.elapsed;
    _progress.add((time: now, value: event.progress));
    final at = event.touchOffset;
    if (at == null) return;
    _touches
      ..add((at: at / devicePixelRatio, time: now))
      ..removeWhere(
        (touch) => now - touch.time > const Duration(milliseconds: 100),
      );
  }

  /// 這一格該畫的進度（同 [PredictiveBackEvent.progress]）；還沒有任何一筆
  /// 時為 null。
  double? get progress {
    if (_progress.isEmpty) return null;
    final time = _clock.elapsed - _delay;
    // 只留取樣時間之前的最後一筆和之後的。
    while (_progress.length > 1 && _progress[1].time <= time) {
      _progress.removeAt(0);
    }
    final before = _progress.first;
    if (_progress.length == 1 || time <= before.time) return before.value;
    final after = _progress[1];
    final span = (after.time - before.time).inMicroseconds;
    return lerpDouble(
      before.value,
      after.value,
      (time - before.time).inMicroseconds / span,
    )!;
  }

  /// 最近 100ms 的水平速度（px/s）；左緣拖往右、右緣拖往左都算成把頁面
  /// 送走的方向。
  double get pixelsPerSecond {
    if (_touches.length < 2) return 0;
    final first = _touches.first, last = _touches.last;
    final seconds = (last.time - first.time).inMicroseconds / 1e6;
    if (seconds <= 0) return 0;
    return ((last.at.dx - first.at.dx) / seconds).abs();
  }
}
