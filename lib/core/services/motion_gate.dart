import 'dart:async';

import 'package:flutter/scheduler.dart';

/// 畫面上正在播、不能被重工作卡掉的動畫（ADR 0018）。
///
/// 換頁、閱讀器的載入骨架與捲動、主題暈開、書卡移位播放時各自 [hold]，
/// 播完放開；背景下載與書架檢查更新每做一段之前先等 [idle]，動畫都播完
/// 才接著做。已經開始的那一段不會被打斷。
class MotionGate {
  MotionGate._();

  static final MotionGate instance = MotionGate._();

  int _holds = 0;
  Completer<void>? _idle;

  /// 剛放開、正在等這一幀畫完。
  bool _settling = false;

  /// 有動畫正在播（或剛停、還在等這一幀畫完）。
  bool get isMoving => _holds > 0 || _settling;

  /// 動畫開始時呼叫，回傳動畫結束時呼叫的放開函式（重複呼叫只算一次）。
  void Function() hold() {
    _holds += 1;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds -= 1;
      if (_holds == 0) unawaited(_releaseAfterFrame());
    };
  }

  // 放開後等這一幀畫完、確定沒有下一段動畫接上才放行：換頁與捲動常在同
  // 一幀裡一段停、一段開始，中間的空檔不能讓背景工作溜進來。
  Future<void> _releaseAfterFrame() async {
    _settling = true;
    await SchedulerBinding.instance.endOfFrame;
    _settling = false;
    if (_holds > 0) return;
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }

  /// 沒有動畫在播時完成。
  Future<void> get idle {
    if (!isMoving) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }
}

/// 跟著一個開關持有 [MotionGate]：[moving] 變成 true 時持有、變回 false 時
/// 放開。動畫元件用它把自己的播放狀態接到閘門上。
class MotionHold {
  void Function()? _release;

  set moving(bool value) {
    if (value) {
      _release ??= MotionGate.instance.hold();
    } else {
      _release?.call();
      _release = null;
    }
  }

  void release() => moving = false;
}
