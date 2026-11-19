import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/shared/navigation/back_swipe.dart';
import 'package:night_reader/shared/navigation/transition_origin.dart';
import 'package:night_reader/shared/navigation/transition_poses.dart';

/// 全 App 換頁共用的轉場，在「外觀與主題 → 換頁動畫」選擇。
///
/// 每一種都照來源 App 的參數：開啟與返回各自用減速曲線（先快後慢），返回
/// 不是開啟倒著播。往右拖返回（左緣右滑、Android 系統的預測返回）也照選的
/// 那一種返回的樣子跟著拖曳進度走（ADR 0020），放開後照 Telegram 的門檻與
/// 時長收尾。
enum AppPageTransition {
  /// 新頁從下方上浮 4% 並淡入，底下的頁面微暗 6%。
  paper('上浮', Duration(milliseconds: 280)),

  /// Telegram iOS：新頁從右滑入，底頁往左視差 30%、變暗 15%，新頁左緣有
  /// 陰影、轉場中帶螢幕圓角；0.5 秒彈簧。
  slide('平移', Duration(milliseconds: 500)),

  /// Telegram Android：新頁從右 48dp 滑入並淡入，底頁不動；150ms。
  glide('滑入', Duration(milliseconds: 150)),

  /// Android 14 起的系統轉場：新頁從右 25% 滑入淡入，舊頁往左 25% 很快淡掉。
  forward('推進', Duration(milliseconds: 450)),

  /// Legado（MD3 分支）：新頁整頁從右滑入並淡入，舊頁往左 25% 淡出；返回
  /// 時頂頁縮到 0.8 淡出，底頁從左滑回。
  cover('覆蓋', Duration(milliseconds: 480)),

  /// Material 共享 Z 軸：新頁從 0.8 放大淡入，舊頁放大到 1.1 淡出。
  zoom('縮放', Duration(milliseconds: 300)),

  /// iOS 18 縮放：新頁從被點的那張卡片（或手指按下處）長成整頁，返回縮回原處。
  expand('展開', Duration(milliseconds: 500));

  const AppPageTransition(this.label, this.duration);

  final String label;
  final Duration duration;

  static AppPageTransition fromStorage(String? name) =>
      values.where((value) => value.name == name).firstOrNull ?? slide;

  /// 主題目前選的換頁動畫（掛在 [PageTransitionsTheme]）；沒掛時用預設的
  /// [slide]。
  static AppPageTransition of(BuildContext context) {
    final theme = Theme.of(context);
    final builder = theme.pageTransitionsTheme.builders[theme.platform];
    return builder is AppPageTransitionsBuilder ? builder.transition : slide;
  }
}

/// 把 [AppPageTransition] 掛到 [PageTransitionsTheme]，所有
/// [MaterialPageRoute]（含開書的 `BookOpenRoute`）都用它。
///
/// 相同的換頁設定照值比較，App 根部重新套用相同主題時，不連帶重建所有讀
/// `Theme.of` 的元件（ADR 0018、0029）。
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder(this.transition);

  final AppPageTransition transition;

  @override
  bool operator ==(Object other) =>
      other is AppPageTransitionsBuilder && other.transition == transition;

  @override
  int get hashCode => transition.hashCode;

  @override
  Duration get transitionDuration => transition.duration;

  @override
  Duration get reverseTransitionDuration => transition.duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _AppTransition(
    transition: transition,
    route: route,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}

/// [context] 所在頁面的路由，不讓呼叫端依賴路由的狀態。
///
/// `ModalRoute.of` 會讓呼叫端在路由狀態改變時重建：上面推入或移走一頁
/// （isCurrent 改變）時，用頁面的 State 拿過路由的整頁跟著重建，每次推入與
/// 返回的第一幀都白白重建一次底下那頁（ADR 0018）。只是拿路由等換頁播完、
/// 判斷自己是不是最上層時用這個。換頁走 [AppPageTransitionsBuilder] 的頁面
/// 從轉場元件取得；其他路由（對話框、面板）照舊用 `ModalRoute.of`。
ModalRoute<Object?>? pageRouteOf(BuildContext context) =>
    context.findAncestorWidgetOfExactType<_AppTransition>()?.route ??
    ModalRoute.of(context);

class _AppTransition extends StatefulWidget {
  const _AppTransition({
    required this.transition,
    required this.route,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final AppPageTransition transition;
  final PageRoute<Object?> route;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_AppTransition> createState() => _AppTransitionState();
}

class _AppTransitionState extends State<_AppTransition>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// iOS 的左緣感應寬度（Flutter 的 Cupertino 返回手勢同樣是 20）。
  static const double _edgeWidth = 20;

  final _Trip _top = _Trip();
  final _Trip _under = _Trip();

  /// 這一頁最近一次在 offstage 的那一幀（推入的第一幀，見 [_Trip]）。
  Duration? _offstageFrame;

  late final HorizontalDragGestureRecognizer _drag;

  /// 手指放開後把頁面送完（或彈回）的那一段（[_Settling]）；進度直接寫回
  /// 路由。
  late final AnimationController _finish;

  /// 這一頁的返回手勢走到哪個階段（`docs/state-machines.md`「路由換頁」）。
  _Swipe _swipe = const _Idle();

  /// 系統預測返回：觸控速度與重新取樣的進度。
  final PredictiveBackTracker _back = PredictiveBackTracker();

  /// 系統預測返回：拖曳中每一格把頁面放到重新取樣後的進度。
  late final Ticker _backTicker;

  @override
  void initState() {
    super.initState();
    _drag = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _onDragStart
      ..onUpdate = _onDragUpdate
      ..onEnd = _onDragEnd
      ..onCancel = _onDragCancel;
    _finish = AnimationController(vsync: this)
      ..addListener(_onFinishTick)
      ..addStatusListener(_onFinishStatus);
    _backTicker = createTicker(_onBackTick);
    _listen(widget.animation, _top.update);
    _listen(widget.secondaryAnimation, _onCoveredStatus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 自己建的辨識器不會自動帶上裝置的觸控門檻（GestureDetector 與捲動
    // 元件才會），照 Flutter 的 Draggable 補上：左緣和底下橫向捲動的內容
    // 用同一個門檻搶這一下。
    _drag.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  @override
  void didUpdateWidget(_AppTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_top.update);
      _listen(widget.animation, _top.update);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      oldWidget.secondaryAnimation.removeStatusListener(_onCoveredStatus);
      _listen(widget.secondaryAnimation, _onCoveredStatus);
    }
  }

  void _listen(Animation<double> animation, AnimationStatusListener listener) {
    listener(animation.status);
    animation.addStatusListener(listener);
  }

  void _onCoveredStatus(AnimationStatus status) {
    _under.update(status);
    if (status.isDismissed && _swipe is _Stranded) _restore();
  }

  // 用公開的手勢入口把路由送回整頁：開始一次手勢、立刻取消，路由自己播完。
  void _restore() {
    _swipe = const _Idle();
    if (!_route.isCurrent || _progress >= 1) return;
    _route
      ..handleStartBackGesture(progress: _progress)
      ..handleCancelBackGesture();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.animation.removeStatusListener(_top.update);
    widget.secondaryAnimation.removeStatusListener(_onCoveredStatus);
    _drag.dispose();
    _finish.dispose();
    _backTicker.dispose();
    if (_swipe is _Dragging || _swipe is _Settling) {
      // 手勢途中頁面被程式關掉。卸載時整棵樹鎖著，通知 Navigator 會讓其他
      // 頁面重建，要等這一格畫完。
      final navigator = widget.route.navigator;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (navigator != null && navigator.mounted) {
          navigator.didStopUserGesture();
        }
      });
    }
    super.dispose();
  }

  PageRoute<Object?> get _route => widget.route;

  double get _width => context.size?.width ?? 1;

  bool get _canStart =>
      _swipe is _Idle && _route.isCurrent && _route.popGestureEnabled;

  // ---------- 左緣右滑 ----------

  void _onPointerDown(PointerDownEvent event) {
    if (_canStart) _drag.addPointer(event);
  }

  void _onDragStart(DragStartDetails details) {
    if (!_canStart) return;
    _begin();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_swipe is! _Dragging) return;
    _route.handleUpdateBackGestureProgress(
      progress: (_progress - details.primaryDelta! / _width).clamp(0.0, 1.0),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (_swipe is! _Dragging) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final dismissed = 1 - _progress;
    if (BackSwipe.goesBack(dismissed: dismissed, velocity: velocity)) {
      _completeWith(velocity);
    } else {
      _cancel();
    }
  }

  void _onDragCancel() {
    if (_swipe is _Dragging) _cancel();
  }

  // ---------- Android 系統的預測返回 ----------

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_canStart) return false;
    _begin();
    _back
      ..clear()
      ..record(backEvent, MediaQuery.devicePixelRatioOf(context));
    _route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
    _backTicker.start();
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_swipe is! _Dragging) return;
    _back.record(backEvent, MediaQuery.devicePixelRatioOf(context));
  }

  void _onBackTick(Duration _) {
    if (!_route.isCurrent || _swipe is! _Dragging) return;
    final progress = _back.progress;
    if (progress != null) {
      _route.handleUpdateBackGestureProgress(progress: 1 - progress);
    }
  }

  // 返回與否由系統決定；這裡只照 Telegram 的時長送完或彈回。
  @override
  void handleCommitBackGesture() {
    if (_swipe is _Dragging) _completeWith(_back.pixelsPerSecond);
  }

  @override
  void handleCancelBackGesture() {
    if (_swipe is _Dragging) _cancel();
  }

  // ---------- 共用 ----------

  double get _progress => widget.animation.value;

  void _begin() {
    _swipe = const _Dragging();
    _back.clear();
    _route.handleStartBackGesture(progress: _progress);
  }

  void _completeWith(double velocity) => _runFinish(
    to: 0,
    duration: BackSwipe.finishDuration(
      distance: _progress * _width,
      velocity: velocity,
    ),
  );

  void _cancel() => _runFinish(to: 1, duration: BackSwipe.cancelDuration);

  void _runFinish({required double to, required Duration duration}) {
    _backTicker.stop();
    _back.clear();
    _swipe = _Settling(from: _progress, to: to);
    _finish
      ..duration = duration
      ..forward(from: 0);
  }

  void _onFinishTick() {
    final swipe = _swipe;
    if (swipe is! _Settling) return;
    // 收尾途中有頁蓋上來：路由不讓手勢改進度，蓋上來的頁推完後這一頁不在
    // 畫面上、計時器也跟著停；等它關掉再接著收，被蓋住時放開的返回就會在
    // 那時才返回。現在就停在半途。
    if (!_route.isCurrent) {
      _finish.stop();
      _settle(swipe);
      return;
    }
    _route.handleUpdateBackGestureProgress(
      progress: lerpDouble(
        swipe.from,
        swipe.to,
        BackSwipe.curve.transform(_finish.value),
      )!,
    );
  }

  void _onFinishStatus(AnimationStatus status) {
    final swipe = _swipe;
    if (status == AnimationStatus.completed && swipe is _Settling) {
      _settle(swipe);
    }
  }

  // 收完時有頁蓋在上面，路由不讓手勢改進度，停在半途等補回整頁。
  void _settle(_Settling swipe) {
    _back.clear();
    _swipe = _route.isCurrent ? const _Idle() : const _Stranded();
    if (swipe.goesBack) {
      _route.handleCommitBackGesture();
    } else {
      _route.handleCancelBackGesture();
    }
  }

  // ---------- 畫面 ----------

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final page = AnimatedBuilder(
      animation: Listenable.merge([
        widget.animation,
        widget.secondaryAnimation,
      ]),
      // 頁面裡每個按鈕、開關、輸入框都有自己的 Focus，原本都直接依賴路由的
      // FocusScope：推入後路由取得焦點、返回時路由先停止接受焦點再交出焦點，
      // FocusScope 每變一次就通知一次，整頁的 Focus 全部重建（閱讀偏好約 48
      // 個，推入第 1 格、返回第 0 與第 1 格各一次），重建出來的東西不變。
      // 中間隔一層不取焦點、不進鍵盤巡覽的 Focus，頁面的控制項改依賴這一層；
      // 它只在頁面裡真的有控制項取得或交出焦點時才通知。
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        child: widget.child,
      ),
      builder: (context, child) {
        // 手勢是整個 Navigator 的狀態，上下兩頁同時切到跟手的樣子。
        final gesturing = _route.popGestureInProgress;
        final size = MediaQuery.sizeOf(context);
        final background = Theme.of(context).scaffoldBackgroundColor;
        // 關閉動畫時照樣包同一串元件、停在整頁，手勢開始時頁面不會被搬動。
        if (still && !gesturing) {
          return const UnderPose().wrap(
            const TopPose().wrap(child!, size),
            background,
          );
        }
        if (_route.offstage) {
          _offstageFrame = SchedulerBinding.instance.currentFrameTimeStamp;
        }
        final origin = TransitionOrigin.of(_route);
        final top = gesturing
            ? TopPose.follow(
                widget.transition,
                widget.animation.value,
                size: size,
                origin: origin,
              )
            : TopPose.of(
                widget.transition,
                trip: _top.of(widget.animation, offstageFrame: _offstageFrame),
                size: size,
                origin: origin,
              );
        final under = gesturing
            ? UnderPose.follow(
                widget.transition,
                widget.secondaryAnimation.value,
              )
            : UnderPose.of(
                widget.transition,
                trip: _under.of(widget.secondaryAnimation),
              );
        return under.wrap(top.wrap(child!, size), background);
      },
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        page,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: math.max(_edgeWidth, MediaQuery.paddingOf(context).left),
          child: Listener(
            onPointerDown: _onPointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

/// 這一頁的返回手勢走到哪個階段；放開後的收尾與被蓋住的停留都只屬於
/// 這一頁，被蓋住本身（[ModalRoute.isCurrent]）會和跟手、收尾同時成立，在
/// 進出階段時讀。
sealed class _Swipe {
  const _Swipe();
}

/// 沒在拖：頁面照路由的換頁動畫；在最上層、開完了、可以返回時，左緣與
/// 系統的返回手勢可以開始。
final class _Idle extends _Swipe {
  const _Idle();
}

/// 跟著左緣右滑或系統的預測返回走；系統手勢由 `_backTicker` 每一格補進度。
final class _Dragging extends _Swipe {
  const _Dragging();
}

/// 放開後照 [BackSwipe] 的時長從 [from] 送到 [to]：0 是返回，1 是彈回。
/// 途中再拖、系統再送都不接手；途中有頁蓋上來就停在半途（[_Stranded]）。
final class _Settling extends _Swipe {
  const _Settling({required this.from, required this.to});

  final double from;
  final double to;

  bool get goesBack => to == 0;
}

/// 收完時有新頁蓋在上面：不是最上層時 [ModalRoute] 不讓手勢改進度，路由
/// 停在半途；蓋上來的頁關掉後補回整頁。
final class _Stranded extends _Swipe {
  const _Stranded();
}

/// 一趟轉場（開啟或返回）走到哪：[of] 回傳的 `time` 為這一趟的時間比例
/// 0→1。中途反向時沿用原本那一趟（跟 [CurvedAnimation] 一樣），畫面不跳。
///
/// 從頭開始的一趟，第一幀花掉的時間不算進動畫：第一幀常常很重（推入時新頁
/// 第一次建立、返回時底下那頁重新排版），路由的時鐘照樣走，第二幀就直接跳到
/// 那段時間之後的位置，看起來是點下去就掉幀。這裡讓第一、二幀都停在起點，
/// 之後把剩下的時間照比例走完整段，最後一幀和路由同時到位（ADR 0018）。
class _Trip {
  /// 這一趟走到哪個階段（`docs/state-machines.md`「路由換頁」）。
  _TripPhase _phase = const _NoTrip();

  void update(AnimationStatus status) {
    if (!status.isAnimating) {
      _phase = const _NoTrip();
    } else if (_phase is _NoTrip) {
      _phase = _AtStart(closing: status == AnimationStatus.reverse);
    }
  }

  /// [offstageFrame] 是這一頁最近一次在 offstage 的那一幀（只有剛推入的
  /// 新頁有）。
  TripTime of(Animation<double> animation, {Duration? offstageFrame}) {
    final closing = switch (_phase) {
      _NoTrip() => animation.status == AnimationStatus.reverse,
      _Moving(:final closing) => closing,
    };
    final time = closing ? 1 - animation.value : animation.value;
    return (closing: closing, time: _pace(time, offstageFrame));
  }

  double _pace(double time, Duration? offstageFrame) {
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    switch (_phase) {
      case _NoTrip() || _OnRouteClock():
        return time;
      case _AtStart(:final closing, firstFrame: null):
        if (time > 0) {
          // 推入的第一幀新頁在 offstage（Hero 量位置），路由的動畫暫時是
          // 「已播完」，這一趟從第二幀才看得到；照底下那頁同樣的方式從這一幀
          // 起算，兩頁才會同步。
          if (offstageFrame != null && offstageFrame != stamp) {
            _phase = _CatchingUp(
              closing: closing,
              firstFrame: offstageFrame,
              resume: time,
            );
            return 0;
          }
          // 不是從起點開始的一趟不調整。
          _phase = _OnRouteClock(closing: closing);
          return time;
        }
        _phase = _AtStart(closing: closing, firstFrame: stamp);
        return 0;
      case _AtStart(:final closing, :final firstFrame?):
        if (stamp == firstFrame) return 0;
        _phase = _CatchingUp(
          closing: closing,
          firstFrame: firstFrame,
          resume: time,
        );
        return _pace(time, offstageFrame);
      case _CatchingUp(:final firstFrame, :final resume):
        if (stamp == firstFrame) return 0;
        if (resume >= 1) return time;
        return ((time - resume) / (1 - resume)).clamp(0.0, 1.0);
    }
  }
}

/// 一趟換頁走到哪個階段。
sealed class _TripPhase {
  const _TripPhase();
}

/// 路由沒在換頁：照路由的進度。
final class _NoTrip extends _TripPhase {
  const _NoTrip();
}

/// 路由正在換頁；[closing] 是這一趟一開始的方向，中途反向也沿用。
sealed class _Moving extends _TripPhase {
  const _Moving({required this.closing});

  final bool closing;
}

/// 從頭開始的一趟停在起點：[firstFrame] 是第一幀的時間戳（null 是還沒
/// 畫到），那一幀花掉的時間不算。
final class _AtStart extends _Moving {
  const _AtStart({required super.closing, this.firstFrame});

  final Duration? firstFrame;
}

/// 第二幀起照剩下的時間走完整段：[resume] 是那時這一趟已經走掉的時間比例，
/// 和路由同時到位。
final class _CatchingUp extends _Moving {
  const _CatchingUp({
    required super.closing,
    required this.firstFrame,
    required this.resume,
  });

  final Duration firstFrame;
  final double resume;
}

/// 不是從起點開始的一趟（中途接手）：照路由的時間。
final class _OnRouteClock extends _Moving {
  const _OnRouteClock({required super.closing});
}
