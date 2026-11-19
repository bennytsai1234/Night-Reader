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

  /// 手指放開後把頁面送完（或彈回）的那一段；進度直接寫回路由。
  late final AnimationController _finish;
  double _finishFrom = 1;
  double _finishTo = 1;

  /// 正在由這一頁處理的返回手勢。
  bool _tracking = false;

  /// 手勢途中有新頁蓋上來，路由停在半途（不是最上層時 [ModalRoute] 不讓
  /// 手勢改它的進度）；蓋上來的頁關掉後要把這一頁補回整頁。
  bool _stranded = false;

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
    if (status.isDismissed && _stranded) _restore();
  }

  // 用公開的手勢入口把路由送回整頁：開始一次手勢、立刻取消，路由自己播完。
  void _restore() {
    _stranded = false;
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
    if (_tracking) {
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
      !_tracking && _route.isCurrent && _route.popGestureEnabled;

  // ---------- 左緣右滑 ----------

  void _onPointerDown(PointerDownEvent event) {
    if (_canStart) _drag.addPointer(event);
  }

  void _onDragStart(DragStartDetails details) {
    if (!_canStart) return;
    _begin();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_tracking || _finish.isAnimating) return;
    _route.handleUpdateBackGestureProgress(
      progress: (_progress - details.primaryDelta! / _width).clamp(0.0, 1.0),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_tracking || _finish.isAnimating) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final dismissed = 1 - _progress;
    if (BackSwipe.goesBack(dismissed: dismissed, velocity: velocity)) {
      _completeWith(velocity);
    } else {
      _cancel();
    }
  }

  void _onDragCancel() {
    if (_tracking && !_finish.isAnimating) _cancel();
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
    if (!_tracking || _finish.isAnimating) return;
    _back.record(backEvent, MediaQuery.devicePixelRatioOf(context));
  }

  void _onBackTick(Duration _) {
    if (!_route.isCurrent || _finish.isAnimating) return;
    final progress = _back.progress;
    if (progress != null) {
      _route.handleUpdateBackGestureProgress(progress: 1 - progress);
    }
  }

  // 返回與否由系統決定；這裡只照 Telegram 的時長送完或彈回。
  @override
  void handleCommitBackGesture() {
    if (_tracking && !_finish.isAnimating) {
      _completeWith(_back.pixelsPerSecond);
    }
  }

  @override
  void handleCancelBackGesture() {
    if (_tracking && !_finish.isAnimating) _cancel();
  }

  // ---------- 共用 ----------

  double get _progress => widget.animation.value;

  void _begin() {
    _tracking = true;
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
    if (_backTicker.isActive) _backTicker.stop();
    _back.clear();
    _finishFrom = _progress;
    _finishTo = to;
    _finish
      ..duration = duration
      ..forward(from: 0);
  }

  void _onFinishTick() {
    if (!_route.isCurrent) return;
    _route.handleUpdateBackGestureProgress(
      progress: lerpDouble(
        _finishFrom,
        _finishTo,
        BackSwipe.curve.transform(_finish.value),
      )!,
    );
  }

  void _onFinishStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _tracking = false;
    _back.clear();
    _stranded = !_route.isCurrent;
    if (_finishTo == 0) {
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

/// 一趟轉場（開啟或返回）走到哪：[time] 為這一趟的時間比例 0→1。中途反向
/// 時沿用原本那一趟（跟 [CurvedAnimation] 一樣），畫面不跳。
///
/// 從頭開始的一趟，第一幀花掉的時間不算進動畫：第一幀常常很重（推入時新頁
/// 第一次建立、返回時底下那頁重新排版），路由的時鐘照樣走，第二幀就直接跳到
/// 那段時間之後的位置，看起來是點下去就掉幀。這裡讓第一、二幀都停在起點，
/// 之後把剩下的時間照比例走完整段，最後一幀和路由同時到位（ADR 0018）。
class _Trip {
  AnimationStatus? _direction;

  /// 這一趟第一幀的時間戳；null 是還沒畫到。
  Duration? _firstFrame;

  /// 第二幀時這一趟已經走掉的時間比例，之後照它把剩下的時間拉回整段。
  double? _resume;

  /// 這一趟從頭開始，照上面的方式起步；中途接手的（拖曳返回放開後、半途
  /// 反向）照路由的時間走。
  bool _paced = false;

  void update(AnimationStatus status) {
    if (status.isAnimating) {
      if (_direction == null) {
        _direction = status;
        _firstFrame = null;
        _resume = null;
        _paced = true;
      }
    } else {
      _direction = null;
      _paced = false;
    }
  }

  /// [offstageFrame] 是這一頁最近一次在 offstage 的那一幀（只有剛推入的
  /// 新頁有）。
  ({bool closing, double time}) of(
    Animation<double> animation, {
    Duration? offstageFrame,
  }) {
    final closing = (_direction ?? animation.status) == AnimationStatus.reverse;
    final time = closing ? 1 - animation.value : animation.value;
    return (closing: closing, time: _pace(time, offstageFrame));
  }

  double _pace(double time, Duration? offstageFrame) {
    if (!_paced) return time;
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    final first = _firstFrame;
    if (first == null) {
      if (time > 0) {
        // 推入的第一幀新頁在 offstage（Hero 量位置），路由的動畫暫時是
        // 「已播完」，這一趟從第二幀才看得到；照底下那頁同樣的方式從這一幀
        // 起算，兩頁才會同步。
        if (offstageFrame != null && offstageFrame != stamp) {
          _firstFrame = offstageFrame;
          _resume = time;
          return 0;
        }
        // 不是從起點開始的一趟不調整。
        _paced = false;
        return time;
      }
      _firstFrame = stamp;
      return 0;
    }
    if (stamp == first) return 0;
    final resume = _resume ??= time;
    if (resume >= 1) return time;
    return ((time - resume) / (1 - resume)).clamp(0.0, 1.0);
  }
}
