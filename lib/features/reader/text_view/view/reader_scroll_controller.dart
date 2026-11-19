import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/widgets.dart';

/// 正文的捲動控制器，位置物件換成 [HybridScrollPosition]。
final class HybridScrollController extends ScrollController {
  HybridScrollController({super.initialScrollOffset, super.keepScrollOffset});

  @override
  HybridScrollPosition get position => super.position as HybridScrollPosition;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return HybridScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

/// 翻頁動畫期間，手指按下不會停住動畫。
///
/// 原生 Scrollable 在按下的瞬間就會 hold 住進行中的捲動，這時還分不出
/// 是點擊還是拖動。翻頁的連點每一下都要接著前一下繼續捲，所以翻頁動畫
/// 不讓按下停住；手指真的拖動時，拖動照常取代動畫、由使用者接手。
final class HybridScrollPosition extends ScrollPositionWithSingleContext {
  HybridScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  ScrollActivity? _pageTurn;

  /// 目前是否正在跑 [animatePageTo] 開始的動畫。
  bool get isPageTurning => activity != null && identical(activity, _pageTurn);

  /// 翻頁動畫；動畫進行中再呼叫一次會從目前位置改捲到新的目標。
  Future<void> animatePageTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    final done = animateTo(to, duration: duration, curve: curve);
    _pageTurn = activity is DrivenScrollActivity ? activity : null;
    return done;
  }

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    if (!isPageTurning) return super.hold(holdCancelCallback);
    return _PassiveHold(holdCancelCallback);
  }

  /// 正文上只有捲動手勢時，單純的點擊也會在放開時贏得手勢競技場，發出
  /// 零位移的拖動開始。翻頁動畫期間先不讓拖動接手，等手指真的移動了才
  /// 開始拖動。
  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    if (!isPageTurning) return super.drag(details, dragCancelCallback);
    return _DeferredDrag(
      begin: () => super.drag(details, dragCancelCallback),
      onCanceled: dragCancelCallback,
    );
  }
}

/// 不停住動畫的 hold：手勢結束（點擊、長按）時只通知 Scrollable 放掉它。
final class _PassiveHold implements ScrollHoldController {
  _PassiveHold(this._onCanceled);

  final VoidCallback _onCanceled;

  @override
  void cancel() => _onCanceled();
}

/// 第一次有位移時才開始的拖動；沒移動就結束的手勢只放掉它。
final class _DeferredDrag implements Drag {
  _DeferredDrag({required this.begin, required this.onCanceled});

  final Drag Function() begin;
  final VoidCallback onCanceled;
  Drag? _drag;

  @override
  void update(DragUpdateDetails details) {
    if (_drag == null && details.delta == Offset.zero) return;
    (_drag ??= begin()).update(details);
  }

  @override
  void end(DragEndDetails details) {
    final drag = _drag;
    if (drag == null) {
      onCanceled();
    } else {
      drag.end(details);
    }
  }

  @override
  void cancel() {
    final drag = _drag;
    if (drag == null) {
      onCanceled();
    } else {
      drag.cancel();
    }
  }
}
