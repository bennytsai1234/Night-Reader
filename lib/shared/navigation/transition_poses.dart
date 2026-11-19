import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/transition_origin.dart';
import 'package:night_reader/shared/widgets/pixel_translation.dart';

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

typedef TripTime = ({bool closing, double time});

double _interval(double t, double begin, double end, [Curve? curve]) {
  final x = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return curve?.transform(x) ?? x;
}

/// 新開（或正要關掉）的那一頁此刻的樣子。
class TopPose {
  const TopPose({
    this.offset = Offset.zero,
    this.fractionalOffset = Offset.zero,
    this.scale = 1,
    this.opacity = 1,
    this.shadow = 0,
    this.radius = 0,
    this.frame,
  });

  /// Telegram iOS 平移：新頁從右滑入、左緣陰影、轉場中帶螢幕圓角。
  factory TopPose.slide(double shown) => TopPose(
    fractionalOffset: Offset(1 - shown, 0),
    shadow: 0.9 * shown,
    radius: shown < 1 ? ScreenCorner.radius : 0,
  );

  factory TopPose.of(
    AppPageTransition transition, {
    required TripTime trip,
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
        return TopPose(fractionalOffset: Offset(0, 0.04 * (1 - v)), opacity: v);
      case AppPageTransition.slide:
        return TopPose.slide(shown(_Curves.telegramSpring));
      case AppPageTransition.glide:
        final v = shown(_Curves.decelerate);
        return TopPose(offset: Offset(48 * (1 - v), 0), opacity: v);
      case AppPageTransition.forward:
        final e = _Curves.forward(closing).transform(time);
        return closing
            ? TopPose(
                fractionalOffset: Offset(0.25 * e, 0),
                opacity: 1 - _interval(time, 0, 0.25),
              )
            : TopPose(
                fractionalOffset: Offset(0.25 * (1 - e), 0),
                opacity: _interval(time, 0, 0.75),
              );
      case AppPageTransition.cover:
        // 位移 480ms，淡入淡出 360ms（Compose 預設的 FastOutSlowIn）。
        final f = _Curves.standard(closing).transform(time);
        final fade = _interval(time, 0, 360 / 480);
        return closing
            ? TopPose(
                scale: 1 - 0.2 * f,
                opacity: 1 - Easing.legacyDecelerate.transform(fade),
              )
            : TopPose(
                fractionalOffset: Offset(1 - f, 0),
                opacity: Easing.legacyDecelerate.transform(fade),
              );
      case AppPageTransition.zoom:
        final s = _Curves.standard(closing).transform(time);
        return closing
            ? TopPose(
                scale: 1 - 0.2 * s,
                opacity: 1 - _interval(time, 0, 0.3, Easing.legacyDecelerate),
              )
            : TopPose(
                scale: 0.8 + 0.2 * s,
                opacity: _interval(time, 0.3, 1, Easing.legacyDecelerate),
              );
      case AppPageTransition.expand:
        return TopPose.expand(
          shown(_Curves.telegramSpring),
          size: size,
          origin: origin,
        );
    }
  }

  /// 拖曳返回中露出 [shown]（1 為整頁）時的樣子：照這一種返回的幾何，位置、
  /// 縮放與透明度都和拖曳進度成正比，不套時間曲線，頁面才會跟著手指走。
  factory TopPose.follow(
    AppPageTransition transition,
    double shown, {
    required Size size,
    required TransitionSourceRect? origin,
  }) {
    final gone = 1 - shown;
    switch (transition) {
      case AppPageTransition.paper:
        return TopPose(
          fractionalOffset: Offset(0, 0.04 * gone),
          opacity: shown,
        );
      case AppPageTransition.slide:
        return TopPose.slide(shown);
      case AppPageTransition.glide:
        return TopPose(offset: Offset(48 * gone, 0), opacity: shown);
      case AppPageTransition.forward:
        return TopPose(
          fractionalOffset: Offset(0.25 * gone, 0),
          opacity: shown,
        );
      case AppPageTransition.cover:
      case AppPageTransition.zoom:
        return TopPose(scale: 1 - 0.2 * gone, opacity: shown);
      case AppPageTransition.expand:
        return TopPose.expand(shown, size: size, origin: origin);
    }
  }

  /// iOS 18 縮放：整頁等比縮在起點裡，從那裡長成整頁、圓角由起點變成螢幕
  /// 圓角。
  factory TopPose.expand(
    double shown, {
    required Size size,
    required TransitionSourceRect? origin,
  }) {
    final full = Offset.zero & size;
    final from = origin ?? TransitionOrigin.around(full.center);
    return TopPose(
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
      // 視窗寬度短暫是 0 時不縮放：除以 0 的縮放比讓整頁的轉換含 NaN，
      // 底下的骨架算不出位置（#203）。
      final s = size.width > 0 ? rect.width / size.width : 1.0;
      fit = Matrix4.translationValues(rect.left, rect.top, 0)
        ..scaleByDouble(s, s, 1, 1);
      clip = RRect.fromRectAndRadius(rect, Radius.circular(frame.radius));
    } else {
      fit = Matrix4.identity();
      clip = null;
    }
    return _PageOpacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: PixelTranslation(
        offset: offset,
        fraction: fractionalOffset,
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
    );
  }
}

/// 被新頁蓋住（或正要露出來）的那一頁此刻的樣子。
class UnderPose {
  const UnderPose({
    this.fractionalOffset = Offset.zero,
    this.scale = 1,
    this.opacity = 1,
    this.dim = 0,
  });

  /// Telegram iOS 平移：底頁往左視差 30%，變暗 15%。
  factory UnderPose.slide(double covered) => UnderPose(
    fractionalOffset: Offset(-0.3 * covered, 0),
    dim: 0.15 * covered,
  );

  factory UnderPose.of(AppPageTransition transition, {required TripTime trip}) {
    final (:closing, :time) = trip;
    double covered(Curve curve) =>
        closing ? 1 - curve.transform(time) : curve.transform(time);
    switch (transition) {
      case AppPageTransition.paper:
        return UnderPose(dim: 0.06 * covered(Curves.easeOutCubic));
      case AppPageTransition.slide:
        return UnderPose.slide(covered(_Curves.telegramSpring));
      case AppPageTransition.glide:
        return const UnderPose();
      case AppPageTransition.forward:
        final e = _Curves.forward(closing).transform(time);
        return closing
            ? UnderPose(
                fractionalOffset: Offset(-0.25 * (1 - e), 0),
                opacity: _interval(time, 0, 0.75),
              )
            : UnderPose(
                fractionalOffset: Offset(-0.25 * e, 0),
                opacity: 1 - _interval(time, 0, 0.25),
              );
      case AppPageTransition.cover:
        final f = _Curves.standard(closing).transform(time);
        final fade = Easing.legacyDecelerate.transform(
          _interval(time, 0, 360 / 480),
        );
        return closing
            ? UnderPose(
                fractionalOffset: Offset(-0.25 * (1 - f), 0),
                opacity: fade,
              )
            : UnderPose(
                fractionalOffset: Offset(-0.25 * f, 0),
                opacity: 1 - fade,
              );
      case AppPageTransition.zoom:
        final s = _Curves.standard(closing).transform(time);
        return closing
            ? UnderPose(
                scale: 1.1 - 0.1 * s,
                opacity: _interval(time, 0.3, 1, Easing.legacyDecelerate),
              )
            : UnderPose(
                scale: 1 + 0.1 * s,
                opacity: 1 - _interval(time, 0, 0.3, Easing.legacyAccelerate),
              );
      case AppPageTransition.expand:
        return UnderPose(dim: 0.12 * covered(_Curves.telegramSpring));
    }
  }

  /// 拖曳返回中被蓋住 [covered]（1 為完全蓋住）時的樣子，和
  /// [TopPose.follow] 一樣照這一種返回的幾何、和拖曳進度成正比。
  factory UnderPose.follow(AppPageTransition transition, double covered) {
    switch (transition) {
      case AppPageTransition.paper:
        return UnderPose(dim: 0.06 * covered);
      case AppPageTransition.slide:
        return UnderPose.slide(covered);
      case AppPageTransition.glide:
        return const UnderPose();
      case AppPageTransition.forward:
      case AppPageTransition.cover:
        return UnderPose(
          fractionalOffset: Offset(-0.25 * covered, 0),
          opacity: 1 - covered,
        );
      case AppPageTransition.zoom:
        return UnderPose(scale: 1 + 0.1 * covered, opacity: 1 - covered);
      case AppPageTransition.expand:
        return UnderPose(dim: 0.12 * covered);
    }
  }

  final Offset fractionalOffset;
  final double scale;
  final double opacity;

  /// 壓在這一頁上的黑色濃度。
  final double dim;

  /// [background] 墊在淡掉的頁面後面，透出來的是頁面底色而不是視窗底色。
  /// 和 [TopPose.wrap] 一樣每個進度都包同樣的一串元件，底下的頁面不會在
  /// 換頁開始或結束時被搬動、整頁重建。
  Widget wrap(Widget child, Color background) {
    final faded = opacity < 1;
    return _Backdrop(
      color: faded ? background : null,
      child: _PageOpacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: PixelTranslation(
          fraction: fractionalOffset,
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
