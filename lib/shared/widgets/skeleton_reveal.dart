import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 骨架換場的方式，在「外觀與主題 → 骨架換場」選（ADR 0024）。
enum SkeletonRevealStyle {
  /// 左緣先開始淡入，右緣在一半的時間才開始，最後同時到位；漸層跨整個
  /// 寬度，看不到一條掃過去的帶子。
  sweep('由左而右'),

  /// 整頁同時淡入。
  fade('整頁淡入');

  const SkeletonRevealStyle(this.label);

  final String label;

  static SkeletonRevealStyle fromStorage(String? name) =>
      values.where((value) => value.name == name).firstOrNull ?? sweep;
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

  /// 使用者定的預設（2026-10-17）。
  static const Duration defaultDuration = Duration(milliseconds: 600);

  /// 設定頁可調的範圍與每一步。短於 0.2 秒看不出是換場、只像閃一下；
  /// 長於 1.5 秒內容已經清楚了還在慢慢淡，等於擋著不給看。
  static const Duration minDuration = Duration(milliseconds: 200);
  static const Duration maxDuration = Duration(milliseconds: 1500);
  static const Duration durationStep = Duration(milliseconds: 100);

  static SkeletonReveal of(BuildContext context) =>
      Theme.of(context).extension<SkeletonReveal>() ?? const SkeletonReveal();

  bool get sweeps => style == SkeletonRevealStyle.sweep;

  /// 換進來的那一層（換成內容時是內容，骨架出現時是骨架）在橫向位置
  /// [u]（0 左緣、1 右緣）的濃度：[progress] 是整段換場套過曲線的進度，
  /// 0 還沒開始、1 完全換好。
  static double incomingOpacityAt(
    double progress,
    double u, {
    bool sweep = true,
  }) => sweep ? (2 * progress - u).clamp(0.0, 1.0) : progress;

  /// 由左而右時，換進來那一層的濃度沿橫向的轉折點（位置、濃度），依位置
  /// 排好。濃度在轉折點之間是直線，畫成漸層只要這幾個停點。
  static List<(double, double)> sweepStops(double progress) {
    final points = <double>{0, 1};
    for (final u in [2 * progress - 1, 2 * progress]) {
      if (u > 0 && u < 1) points.add(u);
    }
    return [
      for (final u in points.toList()..sort())
        (u, incomingOpacityAt(progress, u)),
    ];
  }

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

/// 骨架換場的一層：照 [opacity] 淡入淡出；[sweep] 時改成換進來的那一層
/// 左邊先、右邊後出現（[SkeletonReveal.incomingOpacityAt]），換出去的那一層
/// 在每個位置補滿剩下的濃度。
///
/// [opacity] 是這一層自己的濃度；[incoming] 是這一次換進來的是哪一層：換成
/// 內容時是 [SkeletonRevealSide.content]，骨架出現時是
/// [SkeletonRevealSide.skeleton]。同一次換場的兩層要給同一個 [incoming]。
/// 完全不透明時直接畫、不另開圖層，換場結束後沒有額外負擔；子樹一直在
/// 同一個位置，不會因為換場開始或結束而重建。
class SkeletonRevealLayer extends SingleChildRenderObjectWidget {
  const SkeletonRevealLayer({
    super.key,
    required this.opacity,
    required this.side,
    this.incoming = SkeletonRevealSide.content,
    this.sweep = false,
    super.child,
  });

  final Animation<double> opacity;
  final SkeletonRevealSide side;
  final SkeletonRevealSide incoming;
  final bool sweep;

  @override
  RenderSkeletonRevealLayer createRenderObject(BuildContext context) =>
      RenderSkeletonRevealLayer(
        opacity: opacity,
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
      ..opacity = opacity
      ..side = side
      ..incoming = incoming
      ..sweep = sweep;
  }
}

class RenderSkeletonRevealLayer extends RenderProxyBox {
  RenderSkeletonRevealLayer({
    required this._opacity,
    required this._side,
    required this._incoming,
    required this._sweep,
  });

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (identical(_opacity, value)) return;
    if (attached) _opacity.removeListener(_onTick);
    _opacity = value;
    if (attached) _opacity.addListener(_onTick);
    _onTick();
  }

  SkeletonRevealSide _side;
  set side(SkeletonRevealSide value) {
    if (_side == value) return;
    _side = value;
    _onTick();
  }

  SkeletonRevealSide _incoming;
  set incoming(SkeletonRevealSide value) {
    if (_incoming == value) return;
    _incoming = value;
    _onTick();
  }

  bool _sweep;
  set sweep(bool value) {
    if (_sweep == value) return;
    _sweep = value;
    _onTick();
  }

  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();
  final LayerHandle<ShaderMaskLayer> _maskLayer =
      LayerHandle<ShaderMaskLayer>();
  bool _partial = false;

  bool get _isIncoming => _side == _incoming;

  /// 換場進度（0 還沒開始、1 換好），由這一層自己的濃度換算。
  double get _progress => _isIncoming ? _opacity.value : 1 - _opacity.value;

  /// 這一層在橫向位置 [u]（0 左緣、1 右緣）的濃度。
  @visibleForTesting
  double alphaAt(double u) => _alphaAt(u);

  double _alphaAt(double u) =>
      _alphaFor(SkeletonReveal.incomingOpacityAt(_progress, u, sweep: _sweep));

  /// 換進來那一層的濃度 [incoming] 換算成這一層的濃度。
  double _alphaFor(double incoming) => _isIncoming ? incoming : 1 - incoming;

  bool get _fullyOpaque => _alphaAt(0) >= 1 && _alphaAt(1) >= 1;
  bool get _fullyClear => _alphaAt(0) <= 0 && _alphaAt(1) <= 0;

  void _onTick() {
    final partial = !_fullyOpaque && !_fullyClear;
    if (partial != _partial) {
      _partial = partial;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity.addListener(_onTick);
    _partial = !_fullyOpaque && !_fullyClear;
  }

  @override
  void detach() {
    _opacity.removeListener(_onTick);
    super.detach();
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    _maskLayer.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _partial;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _fullyClear) {
      _opacityLayer.layer = null;
      _maskLayer.layer = null;
      return;
    }
    if (_fullyOpaque) {
      _opacityLayer.layer = null;
      _maskLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    if (!_sweep) {
      _maskLayer.layer = null;
      _opacityLayer.layer = context.pushOpacity(
        offset,
        ui.Color.getAlphaFromOpacity(_alphaAt(0)),
        super.paint,
        oldLayer: _opacityLayer.layer,
      );
      return;
    }
    _opacityLayer.layer = null;
    final stops = SkeletonReveal.sweepStops(_progress);
    // 與 RenderShaderMask 相同：漸層用這一層自己的座標，遮罩範圍用畫面座標。
    final local = Offset.zero & size;
    final shader = ui.Gradient.linear(
      local.centerLeft,
      local.centerRight,
      [
        for (final (_, incoming) in stops)
          Color.fromRGBO(0, 0, 0, _alphaFor(incoming)),
      ],
      [for (final (u, _) in stops) u],
    );
    final layer = _maskLayer.layer ??= ShaderMaskLayer();
    layer
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer, super.paint, offset);
  }
}
