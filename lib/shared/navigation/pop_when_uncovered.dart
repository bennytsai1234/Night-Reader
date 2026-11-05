import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 返回前先讓底下的頁在這一頁後面畫出來，畫面不動；畫好再停
/// [AppMotion.stillGap] 才開始返回動畫（ADR 0037 策略一）。
///
/// 給畫了大量文字的頁面（閱讀器）用：字的貼圖換成這一頁的字，底下那頁的
/// 字要重新建貼圖。原本建在返回動畫的頭兩幀裡：2026-11-05 手機上閱讀器返回
/// 書架，這兩幀繪製 16.1、14.7ms（建字的貼圖 14.4、13.4ms），漏一拍。這一頁
/// 不透明，底下那頁畫在它後面看不見；返回動畫開始時 Navigator 本來就會讓它
/// 露出來（同一個 `opaque`），這裡只是提前到畫面靜止時。
mixin PopWhenUncovered<T> on TransitionRoute<T> {
  bool _leaving = false;

  /// 正在等底下那頁畫好、還沒開始返回。
  bool get isLeaving => _leaving;

  /// 照上面的順序返回；重複呼叫只返回一次。
  Future<void> popWhenUncovered([T? result]) async {
    if (_leaving) return;
    _leaving = true;
    final navigator = this.navigator;
    if (navigator == null || !isActive) return;
    if (isCurrent && overlayEntries.isNotEmpty) {
      overlayEntries.first.opaque = false;
      // 這一幀建好、畫出底下那頁，下一幀畫完才開始算停頓。
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(AppMotion.stillGap);
    }
    if (isActive) navigator.pop(result);
  }
}
