import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 按下的那一刻詢問：這次觸碰是否只是用來停住正在進行的捲動。
typedef ReaderV2PointerDownTapPolicy = bool Function();

const double _stationaryTapToleranceSquared = kTouchSlop * kTouchSlop;

class ReaderV2PointerTapLayer extends StatefulWidget {
  const ReaderV2PointerTapLayer({
    super.key,
    required this.child,
    this.onTapUp,
    this.suppressTapAtPointerDown,
  });

  final Widget child;
  final GestureTapUpCallback? onTapUp;

  /// 在命中測試時呼叫，早於任何手勢收到按下事件。捲動元件收到按下事件
  /// 就會停住慣性，事後再查捲動狀態已經看不出這一下是不是在停捲動。
  final ReaderV2PointerDownTapPolicy? suppressTapAtPointerDown;

  @override
  State<ReaderV2PointerTapLayer> createState() =>
      _ReaderV2PointerTapLayerState();
}

class _ReaderV2PointerTapLayerState extends State<ReaderV2PointerTapLayer> {
  int? _pointer;
  Offset? _downPosition;
  Duration? _downTime;
  bool _dragged = false;
  bool _suppressTap = false;

  /// 最近一次命中測試的結果；緊接著派送的按下事件會取走它。
  bool _suppressAtHitTest = false;

  void _handleHitTest() {
    _suppressAtHitTest =
        widget.onTapUp != null &&
        (widget.suppressTapAtPointerDown?.call() ?? false);
  }

  void _handlePointerDown(PointerDownEvent event) {
    final suppress = _suppressAtHitTest;
    _suppressAtHitTest = false;
    if (widget.onTapUp == null) return;
    if (event.buttons != kPrimaryButton) {
      _resetTracking();
      return;
    }
    if (_pointer != null) {
      _resetTracking();
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _downTime = event.timeStamp;
    _dragged = false;
    _suppressTap = suppress;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final downPosition = _downPosition;
    if (downPosition == null) return;
    if ((event.position - downPosition).distanceSquared >
        _stationaryTapToleranceSquared) {
      _dragged = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    // 按住到長按門檻就是長按（選字），不是點擊。
    final downTime = _downTime;
    final held =
        downTime != null && event.timeStamp - downTime >= kLongPressTimeout;
    final shouldTap = !_dragged && !_suppressTap && !held;
    _resetTracking();
    if (!shouldTap) return;
    widget.onTapUp?.call(
      TapUpDetails(
        kind: event.kind,
        globalPosition: event.position,
        localPosition: event.localPosition,
      ),
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) {
      _resetTracking();
    }
  }

  void _resetTracking() {
    _pointer = null;
    _downPosition = null;
    _downTime = null;
    _dragged = false;
    _suppressTap = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTapUp != null;
    // 樹的形狀不隨啟用與否改變，正文（含捲動位置）才不會被重新掛載。
    return _HitTestProbe(
      onHitTest: _handleHitTest,
      child: Listener(
        behavior: enabled
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onPointerDown: enabled ? _handlePointerDown : null,
        onPointerMove: enabled ? _handlePointerMove : null,
        onPointerUp: enabled ? _handlePointerUp : null,
        onPointerCancel: enabled ? _handlePointerCancel : null,
        child: widget.child,
      ),
    );
  }
}

/// 命中測試經過時通知一聲，不影響命中結果。
class _HitTestProbe extends SingleChildRenderObjectWidget {
  const _HitTestProbe({required this.onHitTest, super.child});

  final VoidCallback onHitTest;

  @override
  _RenderHitTestProbe createRenderObject(BuildContext context) =>
      _RenderHitTestProbe(onHitTest);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHitTestProbe renderObject,
  ) {
    renderObject.onHitTest = onHitTest;
  }
}

class _RenderHitTestProbe extends RenderProxyBox {
  _RenderHitTestProbe(this.onHitTest);

  VoidCallback onHitTest;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) onHitTest();
    return super.hitTest(result, position: position);
  }
}
