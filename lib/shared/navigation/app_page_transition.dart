import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder(this.transition);

  final AppPageTransition transition;

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

/// 轉場用到的曲線，參數都取自來源 App 的原始碼。
abstract final class _Curves {
  /// Telegram iOS 對 0.5 秒系統彈簧（mass 3、stiffness 1000、damping 500）的
  /// 近似，也是 Telegram Android 的 EASE_OUT_QUINT。
  static const Curve telegramSpring = Cubic(0.23, 1.0, 0.32, 1.0);

  /// Android DecelerateInterpolator(1.5)：1 - (1 - t)^3。
  static const Curve decelerate = _Decelerate(1.5);

  /// 推進：開啟照 Android 系統的 emphasized（先慢後快再慢）；返回換成同一
  /// 系列只減速的 emphasizedDecelerate，先快後慢。
  static Curve forward(bool closing) =>
      closing ? Easing.emphasizedDecelerate : Curves.easeInOutCubicEmphasized;

  /// 覆蓋、縮放：開啟照來源的 FastOutSlowIn；返回換成同一系列只減速的
  /// LinearOutSlowIn，先快後慢。
  static Curve standard(bool closing) =>
      closing ? Easing.legacyDecelerate : Curves.fastOutSlowIn;
}

class _Decelerate extends Curve {
  const _Decelerate(this.factor);

  final double factor;

  @override
  double transformInternal(double t) =>
      1 - math.pow(1 - t, 2 * factor).toDouble();
}

/// 轉場中帶的螢幕圓角（Telegram 的做法）。啟動時向原生端量一次，量不到
/// （舊版 Android、非手機）時為 0，就不加圓角。
abstract final class ScreenCorner {
  static const MethodChannel _channel = MethodChannel(
    'night_reader/system_bars',
  );

  static double radius = 0;

  static Future<void> load() async {
    try {
      radius = await _channel.invokeMethod<double>('screenCornerRadius') ?? 0;
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

/// 「展開」的起點：開啟這頁時按下的那張卡片（[TransitionSource]）或手指
/// 按下的位置，返回時縮回同一處。
///
/// 掛在 App 根部（[TransitionOriginRecorder]）記下最後一次按下的地方，每個
/// 路由第一次建立轉場時取用並記住。沒有按過（例如外部連結開啟）時從畫面
/// 中央展開。
abstract final class TransitionOrigin {
  /// 沒有卡片時，起點的大小：Material 的最小觸控範圍，約等於被點的按鈕。
  static const double _size = kMinInteractiveDimension;

  static TransitionSourceRect? _last;
  static TransitionSourceRect? _pendingSource;
  static final Expando<TransitionSourceRect> _byRoute =
      Expando<TransitionSourceRect>();

  static TransitionSourceRect? of(Route<Object?> route) =>
      _byRoute[route] ??= _last;

  static TransitionSourceRect _around(Offset point) => (
    rect: Rect.fromCenter(center: point, width: _size, height: _size),
    radius: _size / 2,
  );
}

/// 起點的範圍與圓角（全域座標）。
typedef TransitionSourceRect = ({Rect rect, double radius});

/// 記下最後一次手指按下的地方，給 [TransitionOrigin] 用；同時量螢幕圓角。
class TransitionOriginRecorder extends StatefulWidget {
  const TransitionOriginRecorder({super.key, required this.child});

  final Widget child;

  @override
  State<TransitionOriginRecorder> createState() =>
      _TransitionOriginRecorderState();
}

class _TransitionOriginRecorderState extends State<TransitionOriginRecorder> {
  @override
  void initState() {
    super.initState();
    unawaited(ScreenCorner.load());
  }

  // 卡片的 Listener 在比較內層，先收到同一次按下並留下自己的範圍。
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (PointerDownEvent event) {
      TransitionOrigin._last =
          TransitionOrigin._pendingSource ??
          TransitionOrigin._around(event.position);
      TransitionOrigin._pendingSource = null;
    },
    child: widget.child,
  );
}

/// 按下時把自己的範圍交給 [TransitionOrigin]，「展開」從這裡長出來。
/// 包在會開新頁的卡片與列上。
class TransitionSource extends StatelessWidget {
  const TransitionSource({
    super.key,
    this.radius = 0,
    this.area,
    required this.child,
  });

  final double radius;

  /// 從整張卡片的範圍取出要長出來的那一塊（例如書架網格只取封面）；
  /// 沒給時用整張卡片。
  final Rect Function(Rect card)? area;

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final card = box.localToGlobal(Offset.zero) & box.size;
      TransitionOrigin._pendingSource = (
        rect: area?.call(card) ?? card,
        radius: radius,
      );
    },
    child: child,
  );
}

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
      child: widget.child,
      builder: (context, child) {
        // 手勢是整個 Navigator 的狀態，上下兩頁同時切到跟手的樣子。
        final gesturing = _route.popGestureInProgress;
        final size = MediaQuery.sizeOf(context);
        final background = Theme.of(context).scaffoldBackgroundColor;
        // 關閉動畫時照樣包同一串元件、停在整頁，手勢開始時頁面不會被搬動。
        if (still && !gesturing) {
          return const _UnderPose().wrap(
            const _TopPose().wrap(child!, size),
            background,
          );
        }
        if (_route.offstage) {
          _offstageFrame = SchedulerBinding.instance.currentFrameTimeStamp;
        }
        final origin = TransitionOrigin.of(_route);
        final top = gesturing
            ? _TopPose.follow(
                widget.transition,
                widget.animation.value,
                size: size,
                origin: origin,
              )
            : _TopPose.of(
                widget.transition,
                trip: _top.of(widget.animation, offstageFrame: _offstageFrame),
                size: size,
                origin: origin,
              );
        final under = gesturing
            ? _UnderPose.follow(
                widget.transition,
                widget.secondaryAnimation.value,
              )
            : _UnderPose.of(
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

/// 不經過路由、在同一處把一個畫面換成另一個時播選定的換頁動畫，例如點
/// 主頁的分頁。[forward] 時 [incoming] 像新開的頁蓋上 [outgoing]；否則
/// [outgoing] 像返回一樣離開、露出 [incoming]。
///
/// [animation] 是這一趟的時間比例 0→1，曲線由各動畫自己套；[follow] 時
/// 是拖曳返回的進度，照拖曳返回的樣子和進度成正比。「展開」從這一趟開始
/// 時（[trip] 換了值）最後按下的地方長出來（返回時縮回去）。
///
/// 沒在換頁時 [outgoing] 是 null，[incoming] 原樣畫在整頁。元件一直掛著、
/// [incoming] 不論換頁與否、往哪個方向，都包在同一串元件的同一個位置，換頁
/// 開始與結束時不會被搬動：原本換頁時才把它搬進來，帶著 GlobalKey 的整個
/// 分頁每次換頁開始與結束都整棵重建（ADR 0018）。
class AppTransitionSwitch extends StatefulWidget {
  const AppTransitionSwitch({
    super.key,
    required this.transition,
    required this.animation,
    required this.trip,
    required this.forward,
    required this.outgoing,
    required this.incoming,
    required this.outgoingBackground,
    required this.incomingBackground,
    this.follow = false,
  });

  final AppPageTransition transition;
  final Animation<double> animation;

  /// 每一趟換頁給不同的值。
  final Object? trip;
  final bool forward;
  final bool follow;

  /// 換頁中離開的畫面；null 是沒在換頁。
  final Widget? outgoing;
  final Widget incoming;

  /// 墊在淡掉的底下那一頁後面的顏色（見 [_UnderPose.wrap]）。
  final Color outgoingBackground;
  final Color incomingBackground;

  @override
  State<AppTransitionSwitch> createState() => _AppTransitionSwitchState();
}

class _AppTransitionSwitchState extends State<AppTransitionSwitch> {
  static const _incomingKey = ValueKey('incoming');
  static const _outgoingKey = ValueKey('outgoing');

  TransitionSourceRect? _origin;

  @override
  void initState() {
    super.initState();
    _takeOrigin();
  }

  @override
  void didUpdateWidget(AppTransitionSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trip != oldWidget.trip) _takeOrigin();
  }

  // 系統的返回手勢不經過 App 的按下，上一次按下的地方跟這一趟無關，
  // 「展開」改縮回畫面中央。
  void _takeOrigin() => _origin = widget.follow ? null : TransitionOrigin._last;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final outgoing = widget.outgoing;
      if (outgoing == null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _posed(
              widget.incoming,
              top: const _TopPose(),
              under: const _UnderPose(),
              size: size,
              background: widget.incomingBackground,
            ),
          ],
        );
      }
      final t = widget.animation.value;
      final _TopPose top;
      final _UnderPose under;
      if (widget.follow) {
        // 上面那頁露出、底下那頁被蓋住的比例：開啟時隨進度增加，返回時減少。
        final shown = widget.forward ? t : 1 - t;
        top = _TopPose.follow(
          widget.transition,
          shown,
          size: size,
          origin: _origin,
        );
        under = _UnderPose.follow(widget.transition, shown);
      } else {
        final trip = (closing: !widget.forward, time: t);
        top = _TopPose.of(
          widget.transition,
          trip: trip,
          size: size,
          origin: _origin,
        );
        under = _UnderPose.of(widget.transition, trip: trip);
      }
      // 上下兩層都包同一串元件，上層的「底下」與下層的「上面」停在原樣；
      // 兩層各有 key，往左往右換頁時上下對調只是搬動順序。
      final incoming = _posed(
        widget.incoming,
        top: widget.forward ? top : const _TopPose(),
        under: widget.forward ? const _UnderPose() : under,
        size: size,
        background: widget.incomingBackground,
      );
      final leaving = _posed(
        outgoing,
        top: widget.forward ? const _TopPose() : top,
        under: widget.forward ? under : const _UnderPose(),
        size: size,
        background: widget.outgoingBackground,
        key: _outgoingKey,
      );
      return Stack(
        fit: StackFit.expand,
        children: widget.forward ? [leaving, incoming] : [incoming, leaving],
      );
    },
  );

  Widget _posed(
    Widget child, {
    required _TopPose top,
    required _UnderPose under,
    required Size size,
    required Color background,
    Key key = _incomingKey,
  }) => KeyedSubtree(
    key: key,
    child: under.wrap(top.wrap(child, size), background),
  );
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

typedef _TripTime = ({bool closing, double time});

double _interval(double t, double begin, double end, [Curve? curve]) {
  final x = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return curve?.transform(x) ?? x;
}

/// 新開（或正要關掉）的那一頁此刻的樣子。
class _TopPose {
  const _TopPose({
    this.offset = Offset.zero,
    this.fractionalOffset = Offset.zero,
    this.scale = 1,
    this.opacity = 1,
    this.shadow = 0,
    this.radius = 0,
    this.frame,
  });

  /// Telegram iOS 平移：新頁從右滑入、左緣陰影、轉場中帶螢幕圓角。
  factory _TopPose.slide(double shown) => _TopPose(
    fractionalOffset: Offset(1 - shown, 0),
    shadow: 0.9 * shown,
    radius: shown < 1 ? ScreenCorner.radius : 0,
  );

  factory _TopPose.of(
    AppPageTransition transition, {
    required _TripTime trip,
    required Size size,
    required TransitionSourceRect? origin,
  }) {
    final (:closing, :time) = trip;
    // 開啟時露出多少：開啟照曲線走，返回是同一條曲線從滿往下扣（先快後慢）。
    double shown(Curve curve) =>
        closing ? 1 - curve.transform(time) : curve.transform(time);
    switch (transition) {
      case AppPageTransition.paper:
        final v = shown(Curves.easeOutCubic);
        return _TopPose(
          fractionalOffset: Offset(0, 0.04 * (1 - v)),
          opacity: v,
        );
      case AppPageTransition.slide:
        return _TopPose.slide(shown(_Curves.telegramSpring));
      case AppPageTransition.glide:
        final v = shown(_Curves.decelerate);
        return _TopPose(offset: Offset(48 * (1 - v), 0), opacity: v);
      case AppPageTransition.forward:
        final e = _Curves.forward(closing).transform(time);
        return closing
            ? _TopPose(
                fractionalOffset: Offset(0.25 * e, 0),
                opacity: 1 - _interval(time, 0, 0.25),
              )
            : _TopPose(
                fractionalOffset: Offset(0.25 * (1 - e), 0),
                opacity: _interval(time, 0, 0.75),
              );
      case AppPageTransition.cover:
        // 位移 480ms，淡入淡出 360ms（Compose 預設的 FastOutSlowIn）。
        final f = _Curves.standard(closing).transform(time);
        final fade = _interval(time, 0, 360 / 480);
        return closing
            ? _TopPose(
                scale: 1 - 0.2 * f,
                opacity: 1 - Easing.legacyDecelerate.transform(fade),
              )
            : _TopPose(
                fractionalOffset: Offset(1 - f, 0),
                opacity: Easing.legacyDecelerate.transform(fade),
              );
      case AppPageTransition.zoom:
        final s = _Curves.standard(closing).transform(time);
        return closing
            ? _TopPose(
                scale: 1 - 0.2 * s,
                opacity: 1 - _interval(time, 0, 0.3, Easing.legacyDecelerate),
              )
            : _TopPose(
                scale: 0.8 + 0.2 * s,
                opacity: _interval(time, 0.3, 1, Easing.legacyDecelerate),
              );
      case AppPageTransition.expand:
        return _TopPose.expand(
          shown(_Curves.telegramSpring),
          size: size,
          origin: origin,
        );
    }
  }

  /// 拖曳返回中露出 [shown]（1 為整頁）時的樣子：照這一種返回的幾何，位置、
  /// 縮放與透明度都和拖曳進度成正比，不套時間曲線，頁面才會跟著手指走。
  factory _TopPose.follow(
    AppPageTransition transition,
    double shown, {
    required Size size,
    required TransitionSourceRect? origin,
  }) {
    final gone = 1 - shown;
    switch (transition) {
      case AppPageTransition.paper:
        return _TopPose(
          fractionalOffset: Offset(0, 0.04 * gone),
          opacity: shown,
        );
      case AppPageTransition.slide:
        return _TopPose.slide(shown);
      case AppPageTransition.glide:
        return _TopPose(offset: Offset(48 * gone, 0), opacity: shown);
      case AppPageTransition.forward:
        return _TopPose(
          fractionalOffset: Offset(0.25 * gone, 0),
          opacity: shown,
        );
      case AppPageTransition.cover:
      case AppPageTransition.zoom:
        return _TopPose(scale: 1 - 0.2 * gone, opacity: shown);
      case AppPageTransition.expand:
        return _TopPose.expand(shown, size: size, origin: origin);
    }
  }

  /// iOS 18 縮放：整頁等比縮在起點裡，從那裡長成整頁、圓角由起點變成螢幕
  /// 圓角。
  factory _TopPose.expand(
    double shown, {
    required Size size,
    required TransitionSourceRect? origin,
  }) {
    final full = Offset.zero & size;
    final from = origin ?? TransitionOrigin._around(full.center);
    return _TopPose(
      frame: shown >= 1
          ? null
          : (
              rect: Rect.lerp(from.rect, full, shown)!,
              radius: lerpDouble(from.radius, ScreenCorner.radius, shown)!,
            ),
    );
  }

  final Offset offset;
  final Offset fractionalOffset;
  final double scale;
  final double opacity;

  /// 左緣陰影的濃度（0–1）。
  final double shadow;

  /// 整頁的圓角。
  final double radius;

  /// 整頁等比縮進這個範圍，超出的部分裁掉（「展開」）。
  final TransitionSourceRect? frame;

  /// 每一種、每一個進度都包同樣的一串元件，只改數值。原本用不到的那一層
  /// 就不包（例如圓角到 0 拿掉 ClipRRect、陰影出現才包 Stack），層數一變，
  /// 底下整頁（路由的頁面帶著 GlobalKey）就被搬到新的位置，搬過去的每個
  /// 元件都要重建：換頁的第一、二幀與最後一幀，整頁各重建一次（ADR 0018）。
  Widget wrap(Widget child, Size size) {
    final frame = this.frame;
    final Matrix4 fit;
    final RRect? clip;
    if (frame != null) {
      final rect = frame.rect;
      final s = rect.width / size.width;
      fit = Matrix4.translationValues(rect.left, rect.top, 0)
        ..scaleByDouble(s, s, 1, 1);
      clip = RRect.fromRectAndRadius(rect, Radius.circular(frame.radius));
    } else {
      fit = Matrix4.identity();
      clip = null;
    }
    return _PageOpacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: offset,
        child: FractionalTranslation(
          translation: fractionalOffset,
          child: Transform.scale(
            scale: scale,
            child: Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -_EdgeShadow.width,
                  width: _EdgeShadow.width,
                  top: 0,
                  bottom: 0,
                  child: shadow > 0
                      ? _EdgeShadow(strength: shadow)
                      : const SizedBox.shrink(),
                ),
                ClipRRect(
                  clipper: _PageClipper(rrect: clip, radius: radius),
                  clipBehavior: clip != null || radius > 0
                      ? Clip.antiAlias
                      : Clip.none,
                  child: Transform(transform: fit, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 被新頁蓋住（或正要露出來）的那一頁此刻的樣子。
class _UnderPose {
  const _UnderPose({
    this.fractionalOffset = Offset.zero,
    this.scale = 1,
    this.opacity = 1,
    this.dim = 0,
  });

  /// Telegram iOS 平移：底頁往左視差 30%，變暗 15%。
  factory _UnderPose.slide(double covered) => _UnderPose(
    fractionalOffset: Offset(-0.3 * covered, 0),
    dim: 0.15 * covered,
  );

  factory _UnderPose.of(
    AppPageTransition transition, {
    required _TripTime trip,
  }) {
    final (:closing, :time) = trip;
    double covered(Curve curve) =>
        closing ? 1 - curve.transform(time) : curve.transform(time);
    switch (transition) {
      case AppPageTransition.paper:
        return _UnderPose(dim: 0.06 * covered(Curves.easeOutCubic));
      case AppPageTransition.slide:
        return _UnderPose.slide(covered(_Curves.telegramSpring));
      case AppPageTransition.glide:
        return const _UnderPose();
      case AppPageTransition.forward:
        final e = _Curves.forward(closing).transform(time);
        return closing
            ? _UnderPose(
                fractionalOffset: Offset(-0.25 * (1 - e), 0),
                opacity: _interval(time, 0, 0.75),
              )
            : _UnderPose(
                fractionalOffset: Offset(-0.25 * e, 0),
                opacity: 1 - _interval(time, 0, 0.25),
              );
      case AppPageTransition.cover:
        final f = _Curves.standard(closing).transform(time);
        final fade = Easing.legacyDecelerate.transform(
          _interval(time, 0, 360 / 480),
        );
        return closing
            ? _UnderPose(
                fractionalOffset: Offset(-0.25 * (1 - f), 0),
                opacity: fade,
              )
            : _UnderPose(
                fractionalOffset: Offset(-0.25 * f, 0),
                opacity: 1 - fade,
              );
      case AppPageTransition.zoom:
        final s = _Curves.standard(closing).transform(time);
        return closing
            ? _UnderPose(
                scale: 1.1 - 0.1 * s,
                opacity: _interval(time, 0.3, 1, Easing.legacyDecelerate),
              )
            : _UnderPose(
                scale: 1 + 0.1 * s,
                opacity: 1 - _interval(time, 0, 0.3, Easing.legacyAccelerate),
              );
      case AppPageTransition.expand:
        return _UnderPose(dim: 0.12 * covered(_Curves.telegramSpring));
    }
  }

  /// 拖曳返回中被蓋住 [covered]（1 為完全蓋住）時的樣子，和
  /// [_TopPose.follow] 一樣照這一種返回的幾何、和拖曳進度成正比。
  factory _UnderPose.follow(AppPageTransition transition, double covered) {
    switch (transition) {
      case AppPageTransition.paper:
        return _UnderPose(dim: 0.06 * covered);
      case AppPageTransition.slide:
        return _UnderPose.slide(covered);
      case AppPageTransition.glide:
        return const _UnderPose();
      case AppPageTransition.forward:
      case AppPageTransition.cover:
        return _UnderPose(
          fractionalOffset: Offset(-0.25 * covered, 0),
          opacity: 1 - covered,
        );
      case AppPageTransition.zoom:
        return _UnderPose(scale: 1 + 0.1 * covered, opacity: 1 - covered);
      case AppPageTransition.expand:
        return _UnderPose(dim: 0.12 * covered);
    }
  }

  final Offset fractionalOffset;
  final double scale;
  final double opacity;

  /// 壓在這一頁上的黑色濃度。
  final double dim;

  /// [background] 墊在淡掉的頁面後面，透出來的是頁面底色而不是視窗底色。
  /// 和 [_TopPose.wrap] 一樣每個進度都包同樣的一串元件，底下的頁面不會在
  /// 換頁開始或結束時被搬動、整頁重建。
  Widget wrap(Widget child, Color background) {
    final faded = opacity < 1;
    return _Backdrop(
      color: faded ? background : null,
      child: _PageOpacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: FractionalTranslation(
          translation: fractionalOffset,
          child: Transform.scale(
            scale: scale,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: _Backdrop(
                      color: dim > 0
                          ? Colors.black.withValues(alpha: dim.clamp(0.0, 1.0))
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 換頁中整頁的透明度：和 [Opacity] 一樣，但完全不透明時直接畫、不另開
/// 圖層。換頁靜止時一直包著它，[Opacity] 在 1 時也會留一層 OpacityLayer。
class _PageOpacity extends Opacity {
  const _PageOpacity({required super.opacity, super.child});

  @override
  RenderOpacity createRenderObject(BuildContext context) =>
      _RenderPageOpacity(opacity: opacity);
}

class _RenderPageOpacity extends RenderOpacity {
  _RenderPageOpacity({super.opacity});

  @override
  bool get alwaysNeedsCompositing {
    final alpha = Color.getAlphaFromOpacity(opacity);
    return child != null && alpha > 0 && alpha < 255;
  }
}

/// 有顏色時鋪滿一層底色，null 時什麼都不畫；換頁中顏色出現、消失時元件
/// 結構不變。
class _Backdrop extends SingleChildRenderObjectWidget {
  const _Backdrop({required this.color, super.child});

  final Color? color;

  @override
  _RenderBackdrop createRenderObject(BuildContext context) =>
      _RenderBackdrop(color);

  @override
  void updateRenderObject(BuildContext context, _RenderBackdrop renderObject) {
    renderObject.color = color;
  }
}

class _RenderBackdrop extends RenderProxyBox {
  _RenderBackdrop(this._color);

  Color? _color;
  set color(Color? value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final color = _color;
    if (color != null && size > Size.zero) {
      context.canvas.drawRect(offset & size, Paint()..color = color);
    }
    super.paint(context, offset);
  }
}

/// 新頁左緣的陰影：Telegram 用 16pt 寬、模糊 16、50% 黑的陰影圖。這裡照
/// 高斯模糊（σ = 8）在 0、8、16pt 處的濃度畫成漸層。
class _EdgeShadow extends StatelessWidget {
  const _EdgeShadow({required this.strength});

  static const double width = 16;

  final double strength;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.011 * strength),
            Colors.black.withValues(alpha: 0.079 * strength),
            Colors.black.withValues(alpha: 0.25 * strength),
          ],
        ),
      ),
    ),
  );
}

/// 換頁中整頁的裁切：「展開」時是長到一半的範圍 [rrect]，其他是整頁加上
/// [radius] 的圓角。
class _PageClipper extends CustomClipper<RRect> {
  const _PageClipper({required this.rrect, required this.radius});

  final RRect? rrect;
  final double radius;

  @override
  RRect getClip(Size size) =>
      rrect ??
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));

  @override
  bool shouldReclip(_PageClipper oldClipper) =>
      oldClipper.rrect != rrect || oldClipper.radius != radius;
}
