import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [shown] 為 false 時 [child] 照常建、照常排版，但不畫：玻璃不取樣背景、
/// 不另開圖層，底下的字與封面也不畫出來。
class PaintedWhen extends SingleChildRenderObjectWidget {
  const PaintedWhen({super.key, required this.shown, required super.child});

  final bool shown;

  @override
  RenderPaintedWhen createRenderObject(BuildContext context) =>
      RenderPaintedWhen(shown);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPaintedWhen renderObject,
  ) {
    renderObject.shown = shown;
  }
}

class RenderPaintedWhen extends RenderProxyBox {
  RenderPaintedWhen(this._shown);

  bool _shown;
  set shown(bool value) {
    if (_shown == value) return;
    _shown = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shown) super.paint(context, offset);
  }
}
