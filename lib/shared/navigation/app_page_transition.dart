import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 全 App 換頁共用的轉場，在「外觀與主題 → 換頁動畫」選擇。
///
/// 每一種都照來源 App 的參數：開啟與返回各自用減速曲線（先快後慢），返回
/// 不是開啟倒著播。往右拖返回（左緣右滑、Android 系統的預測返回）不分
/// 哪一種，一律是 [slide] 的跟手平移，放開後照 Telegram 的門檻與時長收尾。
enum AppPageTransition {
  /// 新頁從下方上浮 4% 並淡入，底下的頁面微暗 6%。
  paper('上浮', Duration(milliseconds: 280)),

  /// Telegram iOS：新頁從右滑入，底頁往左視差 30%、變暗 15%，新頁左緣有
  /// 陰影、轉場中帶螢幕圓角；0.5 秒彈簧。
  slide('平移', Duration(milliseconds: 500)),

  /// 同 [slide]，曲線換成 Telegram 在 iOS 26 用的臨界阻尼彈簧：起步更猛、
  /// 尾巴更短。
  slideCrisp('俐落平移', Duration(milliseconds: 500)),

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

/// 轉場用到的曲線，參數都取自來源 App 的原始碼。
abstract final class _Curves {
  /// Telegram iOS 對 0.5 秒系統彈簧（mass 3、stiffness 1000、damping 500）的
  /// 近似，也是 Telegram Android 的 EASE_OUT_QUINT。
  static const Curve telegramSpring = Cubic(0.23, 1.0, 0.32, 1.0);

  /// Telegram iOS 26：mass 1、stiffness 555.027、damping 47.118 的彈簧。
  static const Curve crispSpring = _CriticalSpring(
    stiffness: 555.027,
    seconds: 0.5,
  );

  /// Android DecelerateInterpolator(1.5)：1 - (1 - t)^3。
  static const Curve decelerate = _Decelerate(1.5);

  /// Telegram 放開手指後收尾用的 easeInOut。
  static const Curve settle = Curves.easeInOut;

  /// 推進：開啟照 Android 系統的 emphasized（先慢後快再慢）；返回換成同一
  /// 系列只減速的 emphasizedDecelerate，先快後慢。
  static Curve forward(bool closing) =>
      closing ? Easing.emphasizedDecelerate : Curves.easeInOutCubicEmphasized;

  /// 覆蓋、縮放：開啟照來源的 FastOutSlowIn；返回換成同一系列只減速的
  /// LinearOutSlowIn，先快後慢。
  static Curve standard(bool closing) =>
      closing ? Easing.legacyDecelerate : Curves.fastOutSlowIn;
}

/// 臨界阻尼彈簧 x(t) = 1 - (1 + ωt)e^(-ωt)，在 [seconds] 內跑完。
class _CriticalSpring extends Curve {
  const _CriticalSpring({required this.stiffness, required this.seconds});

  final double stiffness;
  final double seconds;

  double _at(double t) {
    final wt = math.sqrt(stiffness) * seconds * t;
    return 1 - (1 + wt) * math.exp(-wt);
  }

  // 0.5 秒時剩不到萬分之一，除以終點值讓 t = 1 時精確落在 1。
  @override
  double transformInternal(double t) => _at(t) / _at(1);
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

  /// Telegram：拖過 20% 或往右快過 1000pt/s 就返回。
  static const double _popFraction = 0.2;
  static const double _popVelocity = 1000;

  /// Telegram：剩下的距離 / 放開時的速度，夾在 0.05–0.2 秒；彈回固定 0.1 秒。
  static const double _minFinishSeconds = 0.05;
  static const double _maxFinishSeconds = 0.2;
  static const Duration _cancelDuration = Duration(milliseconds: 100);

  final _Trip _top = _Trip();
  final _Trip _under = _Trip();

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

  /// 系統預測返回：最近的觸控位置與時間，放開時估速度。
  final List<({Offset at, Duration time})> _touches = [];

  /// 測試裡跟著假時間走（同 Flutter 的觸控重新取樣）。
  final Stopwatch _clock = GestureBinding.instance.samplingClock.stopwatch()
    ..start();

  /// 系統預測返回：拖曳中每一格把頁面放到重新取樣後的進度。
  late final Ticker _backTicker;
  final _ProgressResampler _resampler = _ProgressResampler();

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
    if (velocity > _popVelocity || dismissed > _popFraction) {
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
    _record(backEvent);
    _resampler.clear();
    _resampler.add(_clock.elapsed, 1 - backEvent.progress);
    _route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
    _backTicker.start();
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_tracking || _finish.isAnimating) return;
    _record(backEvent);
    _resampler.add(_clock.elapsed, 1 - backEvent.progress);
  }

  void _onBackTick(Duration _) {
    if (!_route.isCurrent || _finish.isAnimating) return;
    final progress = _resampler.at(_clock.elapsed);
    if (progress != null) {
      _route.handleUpdateBackGestureProgress(progress: progress);
    }
  }

  // 返回與否由系統決定；這裡只照 Telegram 的時長送完或彈回。
  @override
  void handleCommitBackGesture() {
    if (_tracking && !_finish.isAnimating) _completeWith(_touchVelocity());
  }

  @override
  void handleCancelBackGesture() {
    if (_tracking && !_finish.isAnimating) _cancel();
  }

  void _record(PredictiveBackEvent event) {
    // Android 送來的是實體像素，換成和頁寬一樣的邏輯像素。
    final at = event.touchOffset;
    if (at == null) return;
    final now = _clock.elapsed;
    _touches
      ..add((at: at / MediaQuery.devicePixelRatioOf(context), time: now))
      ..removeWhere(
        (touch) => now - touch.time > const Duration(milliseconds: 100),
      );
  }

  /// 最近 100ms 的水平速度（px/s，往右為正）；左緣拖往右、右緣拖往左都
  /// 算成把頁面送走的方向。
  double _touchVelocity() {
    if (_touches.length < 2) return 0;
    final first = _touches.first, last = _touches.last;
    final seconds = (last.time - first.time).inMicroseconds / 1e6;
    if (seconds <= 0) return 0;
    return ((last.at.dx - first.at.dx) / seconds).abs();
  }

  // ---------- 共用 ----------

  double get _progress => widget.animation.value;

  void _begin() {
    _tracking = true;
    _touches.clear();
    _route.handleStartBackGesture(progress: _progress);
  }

  void _completeWith(double velocity) {
    final distance = _progress * _width;
    final seconds = velocity.abs() < 1e-6
        ? _maxFinishSeconds
        : (distance / velocity.abs()).clamp(
            _minFinishSeconds,
            _maxFinishSeconds,
          );
    _runFinish(
      to: 0,
      duration: Duration(microseconds: (seconds * 1e6).round()),
    );
  }

  void _cancel() => _runFinish(to: 1, duration: _cancelDuration);

  void _runFinish({required double to, required Duration duration}) {
    if (_backTicker.isActive) _backTicker.stop();
    _resampler.clear();
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
        _Curves.settle.transform(_finish.value),
      )!,
    );
  }

  void _onFinishStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _tracking = false;
    _touches.clear();
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
        // 手勢是整個 Navigator 的狀態，上下兩頁同時切到跟手平移。
        final gesturing = _route.popGestureInProgress;
        if (still && !gesturing) return child!;
        final size = MediaQuery.sizeOf(context);
        final background = Theme.of(context).scaffoldBackgroundColor;
        final top = gesturing
            ? _TopPose.slide(widget.animation.value)
            : _TopPose.of(
                widget.transition,
                trip: _top.of(widget.animation),
                size: size,
                origin: TransitionOrigin.of(_route),
              );
        final under = gesturing
            ? _UnderPose.slide(widget.secondaryAnimation.value)
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

/// 系統預測返回的進度，補成每一格都動。
///
/// 手指慢的時候，系統只在觸控座標變動時才送一次進度，間隔可長到數十毫秒；
/// 直接套用的話頁面停幾格、跳一下，看起來像掉到 60 或 30 幀。這裡照 Flutter
/// 觸控重新取樣（[GestureBinding.resamplingEnabled]）的做法：每一格取
/// [_delay] 之前那一刻，在前後兩筆進度之間內插。App 自己的左緣拖曳走觸控
/// 事件，已經經過同樣的取樣。
class _ProgressResampler {
  /// 與 Flutter 觸控重新取樣的預設延遲相同（`GestureBinding.samplingOffset`）。
  static const Duration _delay = Duration(milliseconds: 38);

  final List<({Duration time, double value})> _samples = [];

  void add(Duration time, double value) =>
      _samples.add((time: time, value: value));

  void clear() => _samples.clear();

  /// [now] 這一格該畫的進度；還沒有任何一筆時為 null。
  double? at(Duration now) {
    if (_samples.isEmpty) return null;
    final time = now - _delay;
    // 只留取樣時間之前的最後一筆和之後的。
    while (_samples.length > 1 && _samples[1].time <= time) {
      _samples.removeAt(0);
    }
    final before = _samples.first;
    if (_samples.length == 1 || time <= before.time) return before.value;
    final after = _samples[1];
    final span = (after.time - before.time).inMicroseconds;
    return lerpDouble(
      before.value,
      after.value,
      (time - before.time).inMicroseconds / span,
    )!;
  }
}

/// 一趟轉場（開啟或返回）走到哪：[time] 為這一趟的時間比例 0→1。中途反向
/// 時沿用原本那一趟（跟 [CurvedAnimation] 一樣），畫面不跳。
class _Trip {
  AnimationStatus? _direction;

  void update(AnimationStatus status) {
    if (status.isAnimating) {
      _direction ??= status;
    } else {
      _direction = null;
    }
  }

  ({bool closing, double time}) of(Animation<double> animation) {
    final closing = (_direction ?? animation.status) == AnimationStatus.reverse;
    return (
      closing: closing,
      time: closing ? 1 - animation.value : animation.value,
    );
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
      case AppPageTransition.slideCrisp:
        return _TopPose.slide(shown(_Curves.crispSpring));
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
        final v = shown(_Curves.telegramSpring);
        final full = Offset.zero & size;
        final from = origin ?? TransitionOrigin._around(full.center);
        return _TopPose(
          frame: v >= 1
              ? null
              : (
                  rect: Rect.lerp(from.rect, full, v)!,
                  radius: lerpDouble(from.radius, ScreenCorner.radius, v)!,
                ),
        );
    }
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

  Widget wrap(Widget child, Size size) {
    var page = child;
    final frame = this.frame;
    if (frame != null) {
      final rect = frame.rect;
      final s = rect.width / size.width;
      return ClipRRect(
        clipper: _RRectClipper(
          RRect.fromRectAndRadius(rect, Radius.circular(frame.radius)),
        ),
        child: Transform(
          transform: Matrix4.translationValues(rect.left, rect.top, 0)
            ..scaleByDouble(s, s, 1, 1),
          child: page,
        ),
      );
    }
    if (radius > 0) {
      page = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: page,
      );
    }
    if (shadow > 0) {
      page = Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -_EdgeShadow.width,
            width: _EdgeShadow.width,
            top: 0,
            bottom: 0,
            child: _EdgeShadow(strength: shadow),
          ),
          page,
        ],
      );
    }
    if (scale != 1) page = Transform.scale(scale: scale, child: page);
    if (fractionalOffset != Offset.zero) {
      page = FractionalTranslation(translation: fractionalOffset, child: page);
    }
    if (offset != Offset.zero) {
      page = Transform.translate(offset: offset, child: page);
    }
    if (opacity < 1) {
      page = Opacity(opacity: opacity.clamp(0.0, 1.0), child: page);
    }
    return page;
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
      case AppPageTransition.slideCrisp:
        return _UnderPose.slide(covered(_Curves.crispSpring));
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

  final Offset fractionalOffset;
  final double scale;
  final double opacity;

  /// 壓在這一頁上的黑色濃度。
  final double dim;

  /// [background] 墊在淡掉的頁面後面，透出來的是頁面底色而不是視窗底色。
  Widget wrap(Widget child, Color background) {
    var page = child;
    if (dim > 0) {
      page = Stack(
        fit: StackFit.passthrough,
        children: [
          page,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: dim.clamp(0.0, 1.0)),
              ),
            ),
          ),
        ],
      );
    }
    if (scale != 1) page = Transform.scale(scale: scale, child: page);
    if (fractionalOffset != Offset.zero) {
      page = FractionalTranslation(translation: fractionalOffset, child: page);
    }
    if (opacity < 1) {
      page = ColoredBox(
        color: background,
        child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: page),
      );
    }
    return page;
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

class _RRectClipper extends CustomClipper<RRect> {
  const _RRectClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RRectClipper oldClipper) => oldClipper.rrect != rrect;
}
