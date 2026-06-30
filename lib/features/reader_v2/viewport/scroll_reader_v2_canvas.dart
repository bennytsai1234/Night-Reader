import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_key.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_layer.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_visible_page_calculator.dart';

class ScrollReaderV2LoadingState extends StatelessWidget {
  const ScrollReaderV2LoadingState({
    super.key,
    required this.state,
    required this.backgroundColor,
    required this.textColor,
    this.onTapUp,
  });

  final ReaderV2State state;
  final Color backgroundColor;
  final Color textColor;
  final GestureTapUpCallback? onTapUp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onTapUp,
      child: ColoredBox(
        color: backgroundColor,
        child: Center(
          child:
              state.phase == ReaderV2Phase.error
                  ? Text(
                    state.errorMessage ?? 'Reader error',
                    style: TextStyle(color: textColor),
                  )
                  : CircularProgressIndicator(
                    strokeWidth: 2,
                    color: textColor.withValues(alpha: 0.35),
                  ),
        ),
      ),
    );
  }
}

class ScrollReaderV2CanvasWithLoadingOverlay extends StatelessWidget {
  const ScrollReaderV2CanvasWithLoadingOverlay({
    super.key,
    required this.canvas,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
  });

  final Widget canvas;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        canvas,
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '載入中',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.7),
                          fontSize:
                              math.max(11, style.fontSize * 0.72).toDouble(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ScrollReaderV2Canvas extends StatelessWidget {
  const ScrollReaderV2Canvas({
    super.key,
    required this.backgroundColor,
    required this.textColor,
    required this.renderStyle,
    required this.visiblePages,
    required this.scrollOffset,
    required this.overscrollAnimation,
    required this.viewportHeight,
    required this.layoutRevision,
    required this.onPointerDownTapPolicy,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
    this.onTapUp,
    this.ttsHighlight,
  });

  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style renderStyle;
  final ReaderV2VisiblePageCalculator visiblePages;
  final ValueListenable<double> scrollOffset;
  final Animation<double> overscrollAnimation;
  final double viewportHeight;
  final int layoutRevision;
  final bool Function() onPointerDownTapPolicy;
  final void Function(DragStartDetails details) onVerticalDragStart;
  final void Function(DragUpdateDetails details) onVerticalDragUpdate;
  final void Function(DragEndDetails details) onVerticalDragEnd;
  final VoidCallback onVerticalDragCancel;
  final GestureTapUpCallback? onTapUp;
  final ReaderV2TtsHighlight? ttsHighlight;

  @override
  Widget build(BuildContext context) {
    return ReaderV2PointerTapLayer(
      onTapUp: onTapUp,
      onPointerDownTapPolicy: (_) => onPointerDownTapPolicy(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: onVerticalDragStart,
        onVerticalDragUpdate: onVerticalDragUpdate,
        onVerticalDragEnd: onVerticalDragEnd,
        onVerticalDragCancel: onVerticalDragCancel,
        child: ColoredBox(
          color: backgroundColor,
          child: ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: scrollOffset,
              builder: (context, readingY, _) {
                return AnimatedBuilder(
                  animation: overscrollAnimation,
                  builder: (context, _) {
                    return _buildVisiblePageStack(
                      readingY: readingY,
                      overscrollY: overscrollAnimation.value,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisiblePageStack({
    required double readingY,
    required double overscrollY,
  }) {
    final children = <Widget>[];
    for (final placement in visiblePages.visiblePages(
      readingY: readingY,
      viewportHeight: viewportHeight,
    )) {
      final screenY = placement.screenY(readingY) + overscrollY;
      final pageHeight = placement.extent;
      children.add(
        Positioned(
          left: 0,
          right: 0,
          top: screenY,
          height: pageHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ReaderV2TileLayer(
                tile: placement.page,
                tileKey: ReaderV2TileKey.fromPageCache(
                  placement.page,
                  layoutRevision: layoutRevision,
                ),
                style: renderStyle,
                backgroundColor: backgroundColor,
                textColor: textColor,
                expand: true,
                paintBackground: false,
              ),
              ReaderV2TtsHighlightOverlayLayer(
                tile: placement.page,
                style: renderStyle,
                textColor: textColor,
                highlight: ttsHighlight,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: children);
  }
}
