import 'dart:async';
import 'dart:ui' show DartPerformanceMode, PlatformDispatcher;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 有動畫在播時請 Dart 延後舊生區的記憶體回收（低延遲模式，
/// `DartPerformanceMode.latency`），畫面靜止一段時間後才放開，讓 Dart 在
/// 靜止時補做（ADR 0036、0037）。
///
/// 每一幀畫完、離下一幀還有空檔時，Flutter 通知 Dart「空閒」，Dart 趁這時
/// 開始舊生區的標記，也在這時收尾；收尾的時間不照空檔算，一次停住主執行緒
/// 十幾毫秒，落在動畫裡下一幀就趕不上。低延遲模式開著時 Flutter 不通知空閒，
/// 用量超過門檻也不開始標記；放開那一刻 Dart 補做（可能當場開始標記）。已經
/// 開始的標記照樣會收尾，新生區的回收也照常。
///
/// 框架的 [SchedulerBinding.requestPerformanceMode] 只在框架裡記有幾個人要，
/// 不會告訴 Dart（Flutter 3.47，`TransitionRoute` 換頁時要的也只是記數），
/// 所以一律用 [request]：拿到記數再直接通知 Dart；記數全部放掉時框架自己
/// 會通知 Dart 回到一般模式。
///
/// 包在整個 App 外面一次。每一幀畫的時候看有沒有動畫要下一幀
/// （[SchedulerBinding.transientCallbackCount]），有就開著；每隔 [settle]
/// 看一次，這段時間裡沒有動畫的幀就放開（動畫停了之後 [settle] 到兩倍
/// [settle] 之間）。動畫在幀外被停掉、之後沒有再畫，照樣放得開。兩段動畫之間
/// 的預留停頓（0.1 秒）比 [settle] 短，放開不落在那裡：放開時開始的標記要在
/// 下一段動畫前收尾。一直在播的動畫（網路慢時的骨架呼吸、漫畫自動捲動）開著
/// 最多 [maxHold] 就放開，之後直到畫面靜止滿 [settle] 都不再開：Dart 說這個
/// 模式不能一直開，開著時舊生區只長不收。
class AnimationLatency extends StatefulWidget {
  const AnimationLatency({super.key, required this.child});

  final Widget child;

  /// 畫面靜止多久才放開。
  static const Duration settle = Duration(milliseconds: 500);

  /// 連續開著最多多久。
  static const Duration maxHold = Duration(seconds: 5);

  /// 開低延遲模式，放掉回傳的那一個才算不要了；別人要了別的模式時回傳 null。
  static PerformanceModeRequestHandle? request() {
    final handle = SchedulerBinding.instance.requestPerformanceMode(
      DartPerformanceMode.latency,
    );
    if (handle != null) {
      PlatformDispatcher.instance.requestDartPerformanceMode(
        DartPerformanceMode.latency,
      );
    }
    return handle;
  }

  @override
  State<AnimationLatency> createState() => _AnimationLatencyState();
}

class _AnimationLatencyState extends State<AnimationLatency> {
  /// 每一幀畫的時候通知的那一個；持續的幀回呼登記了就拿不掉，換成 null。
  static _AnimationLatencyState? _active;
  static bool _registered = false;

  PerformanceModeRequestHandle? _handle;

  /// 開著或剛開滿 [AnimationLatency.maxHold] 時，每隔
  /// [AnimationLatency.settle] 看一次這段時間有沒有動畫的幀（[_animated]）。
  Timer? _check;
  bool _animated = false;
  Timer? _cap;

  /// 開滿 [AnimationLatency.maxHold] 放開過，靜止滿一段 settle 前不再開。
  bool _capped = false;

  @override
  void initState() {
    super.initState();
    _active = this;
    if (!_registered) {
      _registered = true;
      SchedulerBinding.instance.addPersistentFrameCallback(
        (_) => _active?._onFrame(),
      );
    }
  }

  void _onFrame() {
    if (SchedulerBinding.instance.transientCallbackCount == 0) return;
    _animated = true;
    if (_handle != null || _capped) return;
    _handle = AnimationLatency.request();
    _cap = Timer(AnimationLatency.maxHold, () {
      _capped = true;
      _drop();
    });
    _check?.cancel();
    _armCheck();
  }

  void _armCheck() {
    _animated = false;
    _check = Timer(AnimationLatency.settle, _onCheck);
  }

  void _onCheck() {
    if (_animated) {
      _armCheck();
      return;
    }
    _check = null;
    _capped = false;
    _drop();
  }

  /// 放開：Dart 當場補做延後的回收（開始標記）。
  void _drop() {
    _cap?.cancel();
    _cap = null;
    _handle?.dispose();
    _handle = null;
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    _check?.cancel();
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
