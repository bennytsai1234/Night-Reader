import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 平移 [offset] 加上自己寬、高的 [fraction] 倍，對齊到整數個實體像素。
/// 繪製（Impeller）照字在畫面上橫向位置的小數分四格存字的貼圖，平移落在
/// 像素之間時，字每到新的一格就要補建一份；對齊後字落在像素裡的位置和
/// 靜止時一樣，不必補建（docs/research/pixel-snap-text.md）。2026-11-05 手機上
/// 換頁返回書架、進搜尋頁的頭幾幀，建字的貼圖 6–14ms，漏一拍。一個實體像素
/// 在手機上約 0.33 個邏輯像素，看不出對齊。
///
/// 只對齊這一層加上的平移：放在靜止時就落在整數像素上的位置（換頁的整頁、
/// 貼著畫面左緣的面板）。換頁、閱讀器的目錄面板共用。
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
    double snap(double value) => _devicePixelRatio > 0
        ? (value * _devicePixelRatio).roundToDouble() / _devicePixelRatio
        : value;
    return Offset(snap(raw.dx), snap(raw.dy));
  }

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
}
