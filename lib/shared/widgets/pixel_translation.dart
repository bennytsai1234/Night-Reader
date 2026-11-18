import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 平移 [offset] 加上自己寬、高的 [fraction] 倍，對齊到整數個實體像素。
/// 繪製（Impeller）照字在畫面上橫向位置的小數分四格存字的貼圖，平移落在
/// 像素之間時，字每到新的一格就要在繪製執行緒補建一份；對齊後字落在像素
/// 裡的位置和靜止時一樣，不必補建（量測見 docs/research/pixel-snap-text.md）。
/// 一個實體像素在手機上約 0.38 個邏輯像素，看不出對齊。
///
/// 只對齊這一層加上的平移：放在靜止時就落在整數像素上的位置（換頁的整頁、
/// 貼著畫面左緣的面板）。對齊往遠離原位的方向取，平移到畫面外的東西
/// （例如收在左緣外、寬度不是整數實體像素的面板）不會露出一條邊。點擊和
/// [FractionalTranslation] 一樣直接交給子層，不先看點在不在自己的範圍裡。
class PixelTranslation extends SingleChildRenderObjectWidget {
  const PixelTranslation({
    super.key,
    this.offset = Offset.zero,
    required this.fraction,
    super.child,
  });

  final Offset offset;
  final Offset fraction;

  @override
  RenderPixelTranslation createRenderObject(BuildContext context) =>
      RenderPixelTranslation(
        offset,
        fraction,
        MediaQuery.devicePixelRatioOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPixelTranslation renderObject,
  ) {
    renderObject
      ..translation = offset
      ..fraction = fraction
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

/// [PixelTranslation] 的 render object：繪製、點擊與讀屏都用同一個對齊後
/// 的位移。
class RenderPixelTranslation extends RenderProxyBox {
  RenderPixelTranslation(
    this._translation,
    this._fraction,
    this._devicePixelRatio,
  );

  Offset _translation;
  set translation(Offset value) {
    if (value == _translation) return;
    _translation = value;
    _moved();
  }

  Offset _fraction;
  set fraction(Offset value) {
    if (value == _fraction) return;
    _fraction = value;
    _moved();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _moved();
  }

  /// 位移變了：重畫，讀屏的框也跟著移（同 [RenderTransform]、
  /// [RenderFractionalTranslation]）。
  void _moved() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Offset get _shift {
    final raw =
        _translation +
        Offset(_fraction.dx * size.width, _fraction.dy * size.height);
    final ratio = _devicePixelRatio;
    double snap(double value) {
      if (ratio <= 0) return value;
      final physical = value * ratio;
      final nearest = physical.roundToDouble();
      // 本來就在整數像素上（只差浮點誤差）的照原樣，例如換頁的兩端；其他
      // 往遠離原位的方向取。
      if ((physical - nearest).abs() < 1e-3) return nearest / ratio;
      return (physical < 0
              ? physical.floorToDouble()
              : physical.ceilToDouble()) /
          ratio;
    }

    return Offset(snap(raw.dx), snap(raw.dy));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _shift,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Offset>('translation', _translation))
      ..add(DiagnosticsProperty<Offset>('fraction', _fraction))
      ..add(DoubleProperty('devicePixelRatio', _devicePixelRatio));
  }
}
