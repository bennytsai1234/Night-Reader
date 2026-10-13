import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 從一顆按鈕展開成整頁的轉場（分頁列的搜尋鈕 → 搜尋頁）。
///
/// 一塊頁面底色的圓角矩形從按鈕的範圍放大到整頁，頁面內容隨後淡入；返回
/// 時反過來縮回按鈕。每幀只改裁切範圍與一層底色遮罩的透明度：遮罩由不透明
/// 變透明，看起來就是內容淡入，不必對整頁做 Opacity（離屏合成）。
///
/// 沒有邊緣右滑返回（那是 Cupertino 平移轉場的手勢）；返回鍵照常。
class ExpandFromRectRoute<T> extends PageRoute<T> {
  ExpandFromRectRoute({
    required this.builder,
    required this.sourceRect,
    this.backgroundColor,
    super.settings,
  });

  final WidgetBuilder builder;

  /// 按鈕在螢幕上的範圍（全域座標）；展開的起點與收回的終點。
  final Rect sourceRect;

  /// 展開中的底色，與目的頁面的背景一致；預設為 scaffold 背景色。
  final Color? backgroundColor;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  /// 展開用彈簧，帶一點收尾；收回較短，與一般淡出同長。
  @override
  Duration get transitionDuration => AppMotion.spring;

  @override
  Duration get reverseTransitionDuration => AppMotion.fade;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _ExpandTransition(
    animation: animation,
    sourceRect: sourceRect,
    color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
    child: child,
  );
}

class _ExpandTransition extends StatefulWidget {
  const _ExpandTransition({
    required this.animation,
    required this.sourceRect,
    required this.color,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Color color;
  final Widget child;

  @override
  State<_ExpandTransition> createState() => _ExpandTransitionState();
}

class _ExpandTransitionState extends State<_ExpandTransition> {
  late CurvedAnimation _shape;
  late CurvedAnimation _content;

  void _createCurves() {
    // 收回時先快後慢，最後輕輕落回按鈕。
    _shape = CurvedAnimation(
      parent: widget.animation,
      curve: AppMotion.springCurve,
      reverseCurve: Curves.easeInCubic,
    );
    // 形狀先撐開，內容在中段淡入；收回時內容先淡出，再縮回按鈕。
    _content = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0.2, 0.7, curve: AppMotion.fadeCurve),
    );
  }

  @override
  void initState() {
    super.initState();
    _createCurves();
  }

  @override
  void didUpdateWidget(_ExpandTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _shape.dispose();
      _content.dispose();
      _createCurves();
    }
  }

  @override
  void dispose() {
    _shape.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = Offset.zero & constraints.biggest;
        return AnimatedBuilder(
          animation: widget.animation,
          child: widget.child,
          builder: (context, child) {
            final progress = _shape.value;
            final rect = Rect.lerp(widget.sourceRect, full, progress)!;
            final radius = lerpDouble(
              widget.sourceRect.shortestSide / 2,
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
                fit: StackFit.expand,
                children: [
                  child!,
                  if (veil > 0)
                    IgnorePointer(
                      child: ColoredBox(
                        color: widget.color.withValues(
                          alpha: widget.color.a * veil,
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
