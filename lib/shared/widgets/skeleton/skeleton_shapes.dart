import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_tokens.dart';

import 'skeleton.dart';

/// 方塊佔位（封面、按鈕）。放在 [Skeleton] 底下時跟著呼吸。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AppRadius.cardXs,
    this.color,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  /// 佔位底色；null 時取 [Skeleton.colorOf]。不從 App 主題取色的畫面
  /// （例如閱讀器）傳 [Skeleton.tint] 算好的顏色。
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: _SkeletonBoxPaint(
      color: color ?? Skeleton.colorOf(context),
      borderRadius: borderRadius,
      phase: Skeleton.phaseOf(context),
      breath: SkeletonLook.of(context).breath,
      viewWidth: MediaQuery.sizeOf(context).width,
    ),
  );
}

/// [SkeletonBox] 的圓角方塊：呼吸時每一幀只重畫自己，不重建。由左而右呼吸
/// 時照方塊在畫面上的橫向位置畫成漸層，同一直行的方塊深淺一致。
class _SkeletonBoxPaint extends LeafRenderObjectWidget {
  const _SkeletonBoxPaint({
    required this.color,
    required this.borderRadius,
    required this.phase,
    required this.breath,
    required this.viewWidth,
  });

  final Color color;
  final BorderRadius borderRadius;
  final SkeletonPhase? phase;
  final SkeletonBreath breath;
  final double viewWidth;

  @override
  _RenderSkeletonBox createRenderObject(BuildContext context) =>
      _RenderSkeletonBox(
        color: color,
        borderRadius: borderRadius,
        phase: phase,
        breath: breath,
        viewWidth: viewWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSkeletonBox renderObject,
  ) {
    renderObject
      ..color = color
      ..borderRadius = borderRadius
      ..phase = phase
      ..breath = breath
      ..viewWidth = viewWidth;
  }
}

class _RenderSkeletonBox extends RenderBox {
  _RenderSkeletonBox({
    required this._color,
    required this._borderRadius,
    required this._phase,
    required this._breath,
    required this._viewWidth,
  });

  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  SkeletonPhase? _phase;
  set phase(SkeletonPhase? value) {
    if (identical(_phase, value)) return;
    if (attached) _phase?.removeListener(markNeedsPaint);
    _phase = value;
    if (attached) _phase?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  SkeletonBreath _breath;
  set breath(SkeletonBreath value) {
    if (_breath == value) return;
    _breath = value;
    markNeedsPaint();
  }

  double _viewWidth;
  set viewWidth(double value) {
    if (_viewWidth == value) return;
    _viewWidth = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _phase?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _phase?.removeListener(markNeedsPaint);
    super.detach();
  }

  // 和原本的 DecoratedBox 一樣取最小的尺寸，由外層的 SizedBox 決定大小。
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  /// 每一幀重畫都用同一支畫筆（畫的當下就記下了），不每次新建。
  final Paint _paint = Paint();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    _drawBreathing(
      context.canvas,
      _paint,
      this,
      offset,
      _borderRadius.toRRect(Offset.zero & size),
      color: _color,
      phase: _phase,
      breath: _breath,
      viewWidth: _viewWidth,
    );
  }
}

/// 畫一個跟著呼吸的佔位形狀。[shape] 是形狀在 [box] 裡的位置，[offset] 是
/// [box] 這次畫在圖層上的位置。[toScreen] 是 [box] 到螢幕的轉換
/// （[SkeletonPhase.toScreen]），一次畫好幾個形狀時由呼叫端算一次傳進來；null 時
/// 這裡算。
///
/// 由左而右呼吸時，每個形狀用骨架這一幀共用的那一道漸層
/// （[SkeletonPhase.gradient]，螢幕座標）：畫之前把畫布的橫軸換成螢幕的橫軸，
/// 形狀也換到螢幕的橫向位置上畫，畫完換回來。換頁途中整頁在平移、縮放，
/// 同一個螢幕位置的骨架照樣一樣深。每個形狀自己畫在原本的位置，裁切、捲動、
/// 先後順序都和其他元件一樣。
///
/// 骨架呼吸時每一幀每個形狀都要重畫，這裡是骨架本身每一幀的成本：到螢幕
/// 的轉換要沿著元件樹一路往上乘，一個形狀只算一次；漸層每個骨架每一幀只建
/// 一道。每一幀也盡量不產生新的物件：開 App 的呼吸與換場加起來約 1.5 秒，
/// 呼吸前清過記憶體（`_collectGarbage`），這段期間產生的東西撐不滿新生區，
/// Dart 就不會在動畫途中回收（2026-10-28 量到原本每個形狀每一幀新建畫筆、
/// 停點清單與轉換時，呼吸 0.9 秒裡固定回收 5 次）。
void _drawBreathing(
  Canvas canvas,
  Paint paint,
  RenderBox box,
  Offset offset,
  RRect shape, {
  required Color color,
  required SkeletonPhase? phase,
  required SkeletonBreath breath,
  required double viewWidth,
  Matrix4? toScreen,
}) {
  final gradient = phase?.gradient(color, breath, viewWidth);
  // 重用的畫筆先回到新建時的樣子：畫漸層時畫筆的透明度會乘上去，上一筆
  // 留下的半透明顏色（實色的形狀、單色）會讓漸層變淡。
  paint
    ..shader = null
    ..color = const Color(0xFF000000);
  if (gradient == null) {
    paint.color = phase == null
        ? color
        : color.withValues(alpha: color.a * phase.depthAt(0, breath));
    canvas.drawRRect(shape.shift(offset), paint);
    return;
  }
  // 形狀左上角在螢幕上的橫向位置是 scale·x + shift（x 是在 box 裡的位置）。
  // 只照平移、縮放與左右翻轉換算：斜切、旋轉時整個形狀照頂邊那一行的位置
  // 算深淺（App 裡沒有這種轉換，原本逐個形狀畫漸層時也是這樣）。
  final transform = toScreen ?? phase!.toScreen(box);
  final scale = transform.storage[0];
  final shift = transform.storage[12] + transform.storage[4] * shape.top;
  if (!scale.isFinite || !shift.isFinite) {
    // 轉換含 NaN 或無限大（換頁途中短暫的退化尺寸）：算不出螢幕上的位置，
    // 這一格畫單色，不讓一個形狀弄壞整幀（#203）。
    paint.color = color.withValues(alpha: color.a * phase!.depthAt(0, breath));
    canvas.drawRRect(shape.shift(offset), paint);
    return;
  }
  if (scale == 0) {
    // 縮到沒有寬度：看不到，照左緣的深淺畫單色。
    paint.color = color.withValues(
      alpha: color.a * phase!.depthAt(shift / viewWidth, breath),
    );
    canvas.drawRRect(shape.shift(offset), paint);
    return;
  }
  paint.shader = gradient;
  // 畫布的 x' 對到螢幕的 x：畫布 x = offset.dx + (x' − shift) / scale。
  canvas
    ..save()
    ..translate(offset.dx - shift / scale, offset.dy)
    ..scale(1 / scale, 1)
    ..drawRRect(_scaleX(shape, scale, shift), paint)
    ..restore();
}

/// [shape] 的橫向照 x' = scale·x + shift 換過去，縱向不變；scale 是負的
/// （左右翻過來）時左右兩邊對調。
RRect _scaleX(RRect shape, double scale, double shift) {
  if (scale == 1) return shape.shift(Offset(shift, 0));
  Radius x(Radius r) => Radius.elliptical(r.x * scale.abs(), r.y);
  final flip = scale < 0;
  return RRect.fromLTRBAndCorners(
    (flip ? shape.right : shape.left) * scale + shift,
    shape.top,
    (flip ? shape.left : shape.right) * scale + shift,
    shape.bottom,
    topLeft: x(flip ? shape.trRadius : shape.tlRadius),
    topRight: x(flip ? shape.tlRadius : shape.trRadius),
    bottomRight: x(flip ? shape.blRadius : shape.brRadius),
    bottomLeft: x(flip ? shape.brRadius : shape.blRadius),
  );
}

/// [SkeletonShapes] 畫的一個形狀：[fill] 為 null 時是跟著呼吸的佔位色，
/// 給了就是不呼吸的實色（例如卡片底）。
@immutable
class SkeletonShape {
  const SkeletonShape(this.rect, {this.radius = AppRadius.cardXs, this.fill});

  final Rect rect;
  final BorderRadius radius;
  final Color? fill;
}

/// 一次畫好一整塊骨架（一組設定卡片：卡片底、組標題條、每列的文字條與
/// 圖示方塊），整塊只有一個元件。換頁的第一格要建的骨架越少越好，一條條
/// [SkeletonBox] 各是好幾個元件（ADR 0029）。
///
/// 寬度撐滿父層、高度是 [height]；[shapes] 照實際寬度給出各形狀在這塊裡的
/// 位置，照順序畫。
class SkeletonShapes extends LeafRenderObjectWidget {
  const SkeletonShapes({super.key, required this.height, required this.shapes});

  final double height;
  final List<SkeletonShape> Function(Size size) shapes;

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderSkeletonShapes(
    height: height,
    shapes: shapes,
    color: Skeleton.colorOf(context),
    phase: Skeleton.phaseOf(context),
    breath: SkeletonLook.of(context).breath,
    viewWidth: MediaQuery.sizeOf(context).width,
  );

  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) {
    (renderObject as _RenderSkeletonShapes)
      ..height = height
      ..shapes = shapes
      ..color = Skeleton.colorOf(context)
      ..phase = Skeleton.phaseOf(context)
      ..breath = SkeletonLook.of(context).breath
      ..viewWidth = MediaQuery.sizeOf(context).width;
  }
}

class _RenderSkeletonShapes extends _RenderSkeletonBox {
  _RenderSkeletonShapes({
    required this._height,
    required this._shapes,
    required super.color,
    required super.phase,
    required super.breath,
    required super.viewWidth,
  }) : super(borderRadius: BorderRadius.zero);

  double _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  List<SkeletonShape> Function(Size size) _shapes;
  set shapes(List<SkeletonShape> Function(Size size) value) {
    if (identical(_shapes, value)) return;
    _shapes = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => false;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth, _height));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final canvas = context.canvas;
    // 由左而右呼吸時，整塊到螢幕的轉換只算一次，每個形狀共用。
    final toScreen = _phase?.gradient(_color, _breath, _viewWidth) == null
        ? null
        : _phase!.toScreen(this);
    for (final shape in _shapes(size)) {
      final rrect = shape.radius.toRRect(shape.rect);
      final fill = shape.fill;
      if (fill != null) {
        canvas.drawRRect(
          rrect.shift(offset),
          _paint
            ..shader = null
            ..color = fill,
        );
        continue;
      }
      _drawBreathing(
        canvas,
        _paint,
        this,
        offset,
        rrect,
        color: _color,
        phase: _phase,
        breath: _breath,
        viewWidth: _viewWidth,
        toScreen: toScreen,
      );
    }
  }
}

/// 一行文字的佔位：佔用與 [style] 一行文字相同的高度（跟著系統字級
/// 放大），中間畫一條和字一樣高的圓角條，版面不會在內容出現時跳動。
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, required this.style, this.widthFactor = 1});

  final TextStyle style;

  /// 佔可用寬度的比例；同一區塊的幾行用不同長度，看起來才像文字。
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final fontSize = MediaQuery.textScalerOf(context)
        .scale(style.fontSize ?? 14);
    return SizedBox(
      height: fontSize * (style.height ?? 1.3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: SkeletonBox(
            height: fontSize * Skeleton.barHeightFactor,
            borderRadius: AppRadius.cardXs,
          ),
        ),
      ),
    );
  }
}
