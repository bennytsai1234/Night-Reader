import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/services/motion_gate.dart';

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

final MotionGateNavigatorObserver motionGateObserver =
    MotionGateNavigatorObserver();

/// 換頁、底部面板與對話框的進出場、返回手勢進行中都持有 [MotionGate]
/// （ADR 0018），背景工作等它們播完再做。
class MotionGateNavigatorObserver extends NavigatorObserver {
  final MotionHold _gesture = MotionHold();

  /// 每個路由一個，跟著它的動畫狀態持有或放開，直到路由移除。
  final Expando<MotionHold> _routes = Expando<MotionHold>();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _follow(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _follow(newRoute);
    if (oldRoute != null) _routes[oldRoute]?.release();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes[route]?.release();

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) => _gesture.moving = true;

  @override
  void didStopUserGesture() => _gesture.moving = false;

  // 進場、返回都看同一個動畫：播放中持有，停下放開。推入後第一幀 Hero
  // 會暫時把動畫換成「已播完」，接著換回來，持有也跟著接上。
  void _follow(Route<dynamic>? route) {
    if (route is! TransitionRoute || _routes[route] != null) return;
    final animation = route.animation;
    if (animation == null) return;
    final hold = _routes[route] = MotionHold()..moving = animation.isAnimating;
    animation.addStatusListener((status) => hold.moving = status.isAnimating);
  }
}
