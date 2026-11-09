import 'dart:io';

import 'package:flutter/material.dart';

/// 長按插圖打開的大圖（ADR 0050）：黑底、照原圖畫，可以雙指縮放；沒有
/// 放大時往下拖超過一段距離或按返回就關掉，拖的途中圖跟著手指、底色
/// 跟著變淡。
class ReaderV2IllustrationViewer extends StatefulWidget {
  const ReaderV2IllustrationViewer({super.key, required this.path});

  final String path;

  static Route<void> route(String path) => MaterialPageRoute<void>(
    builder: (_) => ReaderV2IllustrationViewer(path: path),
  );

  @override
  State<ReaderV2IllustrationViewer> createState() =>
      _ReaderV2IllustrationViewerState();
}

class _ReaderV2IllustrationViewerState
    extends State<ReaderV2IllustrationViewer> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  double _drag = 0;

  /// 往下拖超過畫面高度的這個比例就關掉。
  static const double _dismissFraction = 0.15;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(
      () => _drag = (_drag + details.delta.dy).clamp(0, double.infinity),
    );
  }

  void _onDragEnd(DragEndDetails details, double height) {
    final fling = (details.primaryVelocity ?? 0) > 800;
    if (_drag > height * _dismissFraction || fling) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final progress = height <= 0 ? 0.0 : (_drag / height).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - progress),
      body: GestureDetector(
        onVerticalDragUpdate: _zoomed ? null : _onDragUpdate,
        onVerticalDragEnd: _zoomed
            ? null
            : (details) => _onDragEnd(details, height),
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 5,
            panEnabled: _zoomed,
            onInteractionEnd: _onInteractionEnd,
            child: SizedBox.expand(
              child: Image.file(
                File(widget.path),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
