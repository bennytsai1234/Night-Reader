import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart'
    show CupertinoPageTransition, CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 全 App 換頁共用的轉場，在「外觀與主題 → 換頁動畫」選擇。
///
/// 每一種只定義開啟；返回一律是開啟倒著播（同一條曲線、同樣時長），開關
/// 對稱。從左緣右滑返回在每一種都能用：拖曳中頁面改成跟手的平移，放開後
/// 返回或彈回。
enum AppPageTransition {
  /// 新頁從下方上浮一小段並淡入，底下的頁面微暗。
  paper('上浮', Duration(milliseconds: 280), Curves.easeOutCubic),

  /// iOS 平移：新頁從右側滑入，底下的頁面往左視差。
  slide('平移', Duration(milliseconds: 500), Curves.linearToEaseOut),

  /// 原地切換：新頁從 0.96 放大淡入，底下的頁面微縮微暗。
  fade('淡入', Duration(milliseconds: 250), AppMotion.fadeCurve),

  /// 從按下的位置展開成整頁，內容在中段淡入。
  expand('展開', AppMotion.spring, AppMotion.springCurve);

  const AppPageTransition(this.label, this.duration, this.curve);

  final String label;
  final Duration duration;
  final Curve curve;

  static AppPageTransition fromStorage(String? name) =>
      values.where((value) => value.name == name).firstOrNull ?? paper;
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
  ) {
    // 右滑返回的手勢沿用 iOS 換頁的偵測與跟手平移：拖曳中（含放開後跑完的
    // 那一段）把真正的進度交給平移、轉場停在全開；平常平移停在全開，由
    // 轉場播進出場。手勢是整個 Navigator 的狀態，上下兩頁同時切換，兩種
    // 狀態的元件結構相同，頁面狀態不會因切換而重建。
    final gesturing = route.popGestureInProgress;
    final still = MediaQuery.disableAnimationsOf(context);
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      route,
      context,
      gesturing ? animation : kAlwaysCompleteAnimation,
      gesturing ? secondaryAnimation : kAlwaysDismissedAnimation,
      _AppTransition(
        transition: transition,
        animation: gesturing || still ? kAlwaysCompleteAnimation : animation,
        secondaryAnimation: gesturing || still
            ? kAlwaysDismissedAnimation
            : secondaryAnimation,
        origin: TransitionOrigin.of(route),
        child: child,
      ),
    );
  }
}

/// 「展開」的起點：開啟這頁時手指按下的位置，返回時縮回同一處。
///
/// 掛在 App 根部（[TransitionOriginRecorder]）記下最後一次按下的位置，
/// 每個路由第一次建立轉場時取用並記住。沒有按過（例如外部連結開啟）時
/// 從畫面中央展開。
abstract final class TransitionOrigin {
  /// 起點的大小：Material 的最小觸控範圍，約等於被點的按鈕。
  static const double _size = kMinInteractiveDimension;

  static Offset? _lastPointerDown;
  static final Expando<Rect> _byRoute = Expando<Rect>();

  static Rect? of(Route<Object?> route) =>
      _byRoute[route] ??= switch (_lastPointerDown) {
        final point? => Rect.fromCenter(
          center: point,
          width: _size,
          height: _size,
        ),
        null => null,
      };
}

/// 記下最後一次手指按下的位置，給 [TransitionOrigin] 用。
class TransitionOriginRecorder extends StatelessWidget {
  const TransitionOriginRecorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (PointerDownEvent event) =>
        TransitionOrigin._lastPointerDown = event.position,
    child: child,
  );
}

class _AppTransition extends StatefulWidget {
  const _AppTransition({
    required this.transition,
    required this.animation,
    required this.secondaryAnimation,
    required this.origin,
    required this.child,
  });

  final AppPageTransition transition;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Rect? origin;
  final Widget child;

  @override
  State<_AppTransition> createState() => _AppTransitionState();
}

class _AppTransitionState extends State<_AppTransition> {
  // 不設 reverseCurve：返回是同一條曲線倒著走，開關對稱。
  late CurvedAnimation _in;
  late CurvedAnimation _under;

  void _createCurves() {
    final curve = widget.transition.curve;
    _in = CurvedAnimation(parent: widget.animation, curve: curve);
    _under = CurvedAnimation(parent: widget.secondaryAnimation, curve: curve);
  }

  @override
  void initState() {
    super.initState();
    _createCurves();
  }

  @override
  void didUpdateWidget(_AppTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation ||
        oldWidget.transition != widget.transition) {
      _in.dispose();
      _under.dispose();
      _createCurves();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _under.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    return switch (widget.transition) {
      AppPageTransition.paper => _Dim(
        animation: _under,
        child: FadeTransition(
          opacity: _in,
          child: SlideTransition(
            position: _in.drive(
              Tween(begin: const Offset(0, 0.04), end: Offset.zero),
            ),
            child: child,
          ),
        ),
      ),
      // 曲線已經套好，平移本身照進度走。
      AppPageTransition.slide => CupertinoPageTransition(
        primaryRouteAnimation: _in,
        secondaryRouteAnimation: _under,
        linearTransition: true,
        child: child,
      ),
      AppPageTransition.fade => _Dim(
        animation: _under,
        child: ScaleTransition(
          scale: _under.drive(Tween(begin: 1, end: 0.98)),
          child: FadeTransition(
            opacity: _in,
            child: ScaleTransition(
              scale: _in.drive(Tween(begin: 0.96, end: 1)),
              child: child,
            ),
          ),
        ),
      ),
      AppPageTransition.expand => _Dim(
        animation: _under,
        child: _Expand(
          animation: widget.animation,
          shape: _in,
          origin: widget.origin,
          child: child,
        ),
      ),
    };
  }
}

/// 被蓋住的頁面隨新頁進場微暗一點，分出上下層。
class _Dim extends StatelessWidget {
  const _Dim({required this.animation, required this.child});

  static const double _maxAlpha = 0.06;

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => animation.value <= 0
                ? const SizedBox.shrink()
                : ColoredBox(
                    color: Colors.black.withValues(
                      alpha: _maxAlpha * animation.value.clamp(0.0, 1.0),
                    ),
                  ),
          ),
        ),
      ),
    ],
  );
}

/// 一塊頁面底色的圓角矩形從 [origin] 放大到整頁，頁面內容在中段淡入。
/// 每幀只改裁切範圍與一層底色遮罩的透明度：遮罩由不透明變透明，看起來就
/// 是內容淡入，不必對整頁做 Opacity（離屏合成）。
class _Expand extends StatefulWidget {
  const _Expand({
    required this.animation,
    required this.shape,
    required this.origin,
    required this.child,
  });

  /// 原始進度：內容淡入的區段照它切，倒著播時同樣對稱。
  final Animation<double> animation;

  /// 套好曲線的進度：形狀照它撐開（彈簧，結尾輕微回彈）。
  final Animation<double> shape;
  final Rect? origin;
  final Widget child;

  @override
  State<_Expand> createState() => _ExpandState();
}

class _ExpandState extends State<_Expand> {
  late CurvedAnimation _content;

  void _createCurve() {
    // 形狀先撐開，內容在中段淡入；返回時內容先淡出，再縮回起點。
    _content = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0.2, 0.7, curve: AppMotion.fadeCurve),
    );
  }

  @override
  void initState() {
    super.initState();
    _createCurve();
  }

  @override
  void didUpdateWidget(_Expand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _content.dispose();
      _createCurve();
    }
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).scaffoldBackgroundColor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = Offset.zero & constraints.biggest;
        final origin =
            widget.origin ??
            Rect.fromCenter(
              center: full.center,
              width: TransitionOrigin._size,
              height: TransitionOrigin._size,
            );
        return AnimatedBuilder(
          animation: widget.animation,
          child: widget.child,
          builder: (context, child) {
            final progress = widget.shape.value;
            final rect = Rect.lerp(origin, full, progress)!;
            final radius = lerpDouble(
              origin.shortestSide / 2,
              0,
              progress.clamp(0.0, 1.0),
            )!;
            final veil = 1 - _content.value;
            final settled = widget.animation.isCompleted;
            return ClipRRect(
              // 展開完不再裁切，頁面平常不多一層裁切圖層。
              clipBehavior: settled ? Clip.none : Clip.antiAlias,
              clipper: _RRectClipper(
                RRect.fromRectAndRadius(rect, Radius.circular(radius)),
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  child!,
                  if (veil > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: color.withValues(alpha: color.a * veil),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RRectClipper extends CustomClipper<RRect> {
  const _RRectClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RRectClipper oldClipper) => oldClipper.rrect != rrect;
}
