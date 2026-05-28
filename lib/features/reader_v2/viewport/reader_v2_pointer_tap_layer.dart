import 'package:flutter/material.dart';

typedef ReaderV2PointerDownTapPolicy = bool Function(PointerDownEvent event);

const double _stationaryTapTolerance = 2.0;
const double _stationaryTapToleranceSquared =
    _stationaryTapTolerance * _stationaryTapTolerance;

class ReaderV2PointerTapLayer extends StatefulWidget {
  const ReaderV2PointerTapLayer({
    super.key,
    required this.child,
    this.onTapUp,
    this.onPointerDownTapPolicy,
  });

  final Widget child;
  final GestureTapUpCallback? onTapUp;
  final ReaderV2PointerDownTapPolicy? onPointerDownTapPolicy;

  @override
  State<ReaderV2PointerTapLayer> createState() =>
      _ReaderV2PointerTapLayerState();
}

class _ReaderV2PointerTapLayerState extends State<ReaderV2PointerTapLayer> {
  int? _pointer;
  Offset? _downPosition;
  bool _dragged = false;
  bool _suppressTap = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.onTapUp == null) return;
    if (_pointer != null) {
      _resetTracking();
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _dragged = false;
    _suppressTap = widget.onPointerDownTapPolicy?.call(event) ?? false;
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
    final shouldTap = !_dragged && !_suppressTap;
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
    _dragged = false;
    _suppressTap = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTapUp != null;
    return Listener(
      behavior: enabled ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onPointerDown: enabled ? _handlePointerDown : null,
      onPointerMove: enabled ? _handlePointerMove : null,
      onPointerUp: enabled ? _handlePointerUp : null,
      onPointerCancel: enabled ? _handlePointerCancel : null,
      child: widget.child,
    );
  }
}
