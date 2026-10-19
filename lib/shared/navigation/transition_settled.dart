import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 等換頁動畫播完（ADR 0018）：頁面的載入與重排從這之後才開始，不和換頁
/// 搶同一幀。
abstract final class TransitionSettled {
  /// 這一頁的進場動畫播完時完成；不在路由裡或已經播完時立即完成；進場
  /// 途中就被關掉時也完成，呼叫端照常檢查 `mounted`。
  static Future<void> entered(BuildContext context) async {
    final route = ModalRoute.of(context);
    if (route == null) return;
    // 推入後的第一幀，Hero 把新頁放在 offstage 量位置，這時路由的動畫暫時
    // 換成「已播完」；等這一幀過去，再看真正的進場動畫。
    if (route.offstage) await SchedulerBinding.instance.endOfFrame;
    final animation = route.animation;
    var moved = animation?.isAnimating ?? false;
    await until(animation, (status) {
      if (status.isAnimating) moved = true;
      return status.isCompleted || (moved && status.isDismissed);
    });
  }

  /// 蓋在這一頁上的頁面完全移走（返回動畫播完）時完成。
  static Future<void> uncovered(BuildContext context) =>
      until(ModalRoute.of(context)?.secondaryAnimation, (s) => s.isDismissed);

  /// [animation] 的狀態符合 [done] 時完成；沒有動畫時立即完成。
  static Future<void> until(
    Animation<double>? animation,
    bool Function(AnimationStatus status) done,
  ) {
    if (animation == null || done(animation.status)) {
      return Future<void>.value();
    }
    final settled = Completer<void>();
    void listener(AnimationStatus status) {
      if (!done(status)) return;
      animation.removeStatusListener(listener);
      settled.complete();
    }

    animation.addStatusListener(listener);
    return settled.future;
  }
}
