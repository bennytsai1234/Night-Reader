import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_tokens.dart';

/// 骨架換場的方式；App 固定用 [sweep]（不給選，ADR 0024），[fade] 用在骨架
/// 自己淡掉的地方。
enum SkeletonRevealStyle {
  /// 左緣先開始淡入，右緣在一半的時間才開始，最後同時到位；漸層跨整個
  /// 寬度，看不到一條掃過去的帶子。
  sweep('由左而右'),

  /// 整頁同時淡入。
  fade('整頁淡入');

  const SkeletonRevealStyle(this.label);

  final String label;
}

/// 骨架換場的設定，掛在主題上；書架、發現、書籍詳情與閱讀器共用。骨架出現
/// （開 App、重新載入、閱讀器蓋上紙）也照同一個方式與時長。
@immutable
class SkeletonReveal extends ThemeExtension<SkeletonReveal> {
  const SkeletonReveal({
    this.style = SkeletonRevealStyle.sweep,
    this.duration = defaultDuration,
  });

  final SkeletonRevealStyle style;
  final Duration duration;

  /// 使用者定的時長（2026-10-17），App 固定用它（ADR 0024）。
  static const Duration defaultDuration = Duration(milliseconds: 600);

  static SkeletonReveal of(BuildContext context) =>
      Theme.of(context).extension<SkeletonReveal>() ?? const SkeletonReveal();

  bool get sweeps => style == SkeletonRevealStyle.sweep;

  /// 換進來的那一層（換成內容時是內容，骨架出現時是骨架）在橫向位置
  /// [u]（0 左緣、1 右緣）的濃度：[progress] 是整段換場經過的時間比例（不套
  /// 曲線），0 還沒開始、1 完全換好。
  ///
  /// 由左而右時每個位置在自己那一半的時間裡各自套一次 [AppMotion.fadeCurve]：
  /// 左緣在前一半、右緣在後一半，中間依位置錯開，每一處都是慢慢開始、慢慢
  /// 停住。原本是整段套一次曲線、每個位置照進度直線淡入，左半邊在最快的
  /// 時候急停、右半邊一開始就急衝出來，畫面看起來在抖（2026-10-22）。
  static double incomingOpacityAt(
    double progress,
    double u, {
    bool sweep = true,
  }) => AppMotion.fadeCurve.transform(
    sweep ? (2 * progress - u).clamp(0.0, 1.0) : progress.clamp(0.0, 1.0),
  );

  /// 由左而右時，畫成漸層用的停點（位置、換進來那一層的濃度），依位置排好。
  /// 正在變的那一段取 [_rampSegments] 段直線，兩側已經到底的部分只要兩端。
  static List<(double, double)> sweepStops(double progress) {
    final points = <double>{0, 1};
    for (var i = 0; i <= _rampSegments; i++) {
      final u = 2 * progress - 1 + i / _rampSegments;
      if (u > 0 && u < 1) points.add(u);
    }
    return [
      for (final u in points.toList()..sort())
        (u, incomingOpacityAt(progress, u)),
    ];
  }

  /// [sweepStops] 在正在變的那一段取幾段直線：16 段時直線與曲線最多差
  /// 0.22% 的濃度，看不出來。
  static const int _rampSegments = 16;

  @override
  SkeletonReveal copyWith({SkeletonRevealStyle? style, Duration? duration}) =>
      SkeletonReveal(
        style: style ?? this.style,
        duration: duration ?? this.duration,
      );

  @override
  SkeletonReveal lerp(SkeletonReveal? other, double t) =>
      other == null || t < 0.5 ? this : other;

  @override
  bool operator ==(Object other) =>
      other is SkeletonReveal &&
      other.style == style &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(style, duration);
}

/// 換場時的哪一層：骨架或內容。
enum SkeletonRevealSide { content, skeleton }

/// 骨架換場的一層：照 [presence] 淡入淡出；[sweep] 時改成換進來的那一層
/// 左邊先、右邊後出現（[SkeletonReveal.incomingOpacityAt]），換出去的那一層
/// 在每個位置補滿剩下的濃度。
///
/// [presence] 是這一層自己出現的進度，0 不在、1 完全在，是經過的時間比例、
/// 不套曲線（曲線由 [SkeletonReveal.incomingOpacityAt] 套）；[incoming] 是
/// 這一次換進來的是哪一層：換成
/// 內容時是 [SkeletonRevealSide.content]，骨架出現時是
/// [SkeletonRevealSide.skeleton]。同一次換場的兩層要給同一個 [incoming]。
/// 完全不透明時直接畫、不另開圖層，換場結束後沒有額外負擔；子樹一直在
/// 同一個位置，不會因為換場開始或結束而重建。
class SkeletonRevealLayer extends SingleChildRenderObjectWidget {
  const SkeletonRevealLayer({
    super.key,
    required this.presence,
    required this.side,
    this.incoming = SkeletonRevealSide.content,
    this.sweep = false,
    super.child,
  });

  final Animation<double> presence;
  final SkeletonRevealSide side;
  final SkeletonRevealSide incoming;
  final bool sweep;

  @override
  RenderSkeletonRevealLayer createRenderObject(BuildContext context) =>
      RenderSkeletonRevealLayer(
        presence: presence,
        side: side,
        incoming: incoming,
        sweep: sweep,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSkeletonRevealLayer renderObject,
  ) {
    renderObject
      ..presence = presence
      ..side = side
      ..incoming = incoming
      ..sweep = sweep;
  }
}

class RenderSkeletonRevealLayer extends RenderProxyBox
    with SkeletonRevealPainting {
  RenderSkeletonRevealLayer({
    required this._presence,
    required this._side,
    required this._incoming,
    required this._sweep,
  });

  Animation<double> _presence;
  set presence(Animation<double> value) {
    if (identical(_presence, value)) return;
    if (attached) _presence.removeListener(revealChanged);
    _presence = value;
    if (attached) _presence.addListener(revealChanged);
    revealChanged();
  }

  SkeletonRevealSide _side;
  set side(SkeletonRevealSide value) {
    if (_side == value) return;
    _side = value;
    revealChanged();
  }

  SkeletonRevealSide _incoming;
  set incoming(SkeletonRevealSide value) {
    if (_incoming == value) return;
    _incoming = value;
    revealChanged();
  }

  bool _sweep;
  set sweep(bool value) {
    if (_sweep == value) return;
    _sweep = value;
    revealChanged();
  }

  bool get _isIncoming => _side == _incoming;

  /// 換場進度（0 還沒開始、1 換好），由這一層自己出現的進度換算。
  @override
  double get revealProgress =>
      _isIncoming ? _presence.value : 1 - _presence.value;

  @override
  bool get revealSweep => _sweep;

  @override
  double revealAlphaFor(double incoming) =>
      _isIncoming ? incoming : 1 - incoming;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _presence.addListener(revealChanged);
    syncRevealPartial();
  }

  @override
  void detach() {
    _presence.removeListener(revealChanged);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && revealPartial;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      clearRevealLayers();
      return;
    }
    paintRevealed(context, offset, size, super.paint);
  }
}

/// 骨架換場一層的畫法，box 版（[RenderSkeletonRevealLayer]）與清單版
/// （`SliverSkeletonSwitcher` 的內容層）共用：完全透明時不畫，完全不透明時
/// 直接畫、不另開圖層；整頁淡時一層透明度，由左而右時一層橫向漸層的遮罩
/// （每個位置的濃度是 [alphaAt]）。
///
/// 用它的 render object 掛上去、開始聽進度之後呼叫 [syncRevealPartial]，
/// 進度或方式變了時呼叫 [revealChanged]，`alwaysNeedsCompositing` 照
/// [revealPartial] 回答。
mixin SkeletonRevealPainting on RenderObject {
  /// 換場進度：0 還沒開始、1 換好，是經過的時間比例、不套曲線。
  double get revealProgress;

  /// 這一次換場是不是由左而右。
  bool get revealSweep;

  /// 換進來那一層的濃度換算成這一層的濃度；這一層就是換進來的那一層時
  /// 不變。
  double revealAlphaFor(double incoming) => incoming;

  /// 這一層在橫向位置 [u]（0 左緣、1 右緣）的濃度。
  double alphaAt(double u) => revealAlphaFor(
    SkeletonReveal.incomingOpacityAt(revealProgress, u, sweep: revealSweep),
  );

  bool get _fullyOpaque => alphaAt(0) >= 1 && alphaAt(1) >= 1;
  bool get _fullyClear => alphaAt(0) <= 0 && alphaAt(1) <= 0;

  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();
  final LayerHandle<ShaderMaskLayer> _maskLayer =
      LayerHandle<ShaderMaskLayer>();

  /// 正在換場途中（不是完全透明、也不是完全不透明）：這時要另開圖層。
  bool get revealPartial => _partial;
  bool _partial = false;

  /// 進度或方式變了：重畫，透明到一半與否變了時更新要不要另開圖層。
  void revealChanged() {
    final partial = !_fullyOpaque && !_fullyClear;
    if (partial != _partial) {
      _partial = partial;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  /// 掛上去、開始聽進度之後呼叫一次，照當下的進度記下要不要另開圖層：
  /// 開始聽的那一刻，進度可能才剛被設好。
  void syncRevealPartial() {
    _partial = !_fullyOpaque && !_fullyClear;
  }

  @override
  void dispose() {
    clearRevealLayers();
    super.dispose();
  }

  /// 這一幀不畫（沒有內容或看不到）時放掉上一幀的圖層。
  void clearRevealLayers() {
    _opacityLayer.layer = null;
    _maskLayer.layer = null;
  }

  /// 照這一刻的濃度畫 [size] 大小的這一層，[paintChild] 畫底下的內容。
  void paintRevealed(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback paintChild,
  ) {
    if (_fullyClear) {
      clearRevealLayers();
      return;
    }
    if (_fullyOpaque) {
      clearRevealLayers();
      paintChild(context, offset);
      return;
    }
    if (!revealSweep) {
      _maskLayer.layer = null;
      _opacityLayer.layer = context.pushOpacity(
        offset,
        ui.Color.getAlphaFromOpacity(alphaAt(0)),
        paintChild,
        oldLayer: _opacityLayer.layer,
      );
      return;
    }
    _opacityLayer.layer = null;
    final stops = SkeletonReveal.sweepStops(revealProgress);
    // 與 RenderShaderMask 相同：漸層用這一層自己的座標，遮罩範圍用畫面座標。
    final local = Offset.zero & size;
    final shader = ui.Gradient.linear(
      local.centerLeft,
      local.centerRight,
      [
        for (final (_, incoming) in stops)
          Color.fromRGBO(0, 0, 0, revealAlphaFor(incoming)),
      ],
      [for (final (u, _) in stops) u],
    );
    final layer = _maskLayer.layer ??= ShaderMaskLayer();
    layer
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer, paintChild, offset);
  }
}
