import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';

typedef ReaderV2TtsHighlightPaintObserver =
    void Function(ReaderV2PageCache tile, List<Rect> rects);

class ReaderV2TtsHighlightOverlayLayer extends StatelessWidget {
  const ReaderV2TtsHighlightOverlayLayer({
    super.key,
    required this.tile,
    required this.style,
    required this.textColor,
    this.highlight,
  });

  final ReaderV2PageCache tile;
  final ReaderV2Style style;
  final Color textColor;
  final ReaderV2TtsHighlight? highlight;

  @override
  Widget build(BuildContext context) {
    // Skip building a RepaintBoundary + CustomPaint for tiles that have no
    // active TTS highlight: with many visible tiles on tablet, the idle
    // overlay layers add up in composition.
    final current = highlight;
    if (current == null ||
        !current.isValid ||
        current.chapterIndex != tile.chapterIndex ||
        !tile.intersectsCharRange(
          current.highlightStart,
          current.highlightEnd,
        )) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ReaderV2TtsHighlightOverlayPainter(
            tile: tile,
            style: style,
            textColor: textColor,
            highlight: current,
          ),
        ),
      ),
    );
  }
}

class ReaderV2TtsHighlightOverlayPainter extends CustomPainter {
  ReaderV2TtsHighlightOverlayPainter({
    required this.tile,
    required this.style,
    required this.textColor,
    this.highlight,
  });

  final ReaderV2PageCache tile;
  final ReaderV2Style style;
  final Color textColor;
  final ReaderV2TtsHighlight? highlight;

  static ReaderV2TtsHighlightPaintObserver? debugOnPaintRects;

  @override
  void paint(Canvas canvas, Size size) {
    final rects = _highlightRects(size);
    assert(() {
      debugOnPaintRects?.call(tile, rects);
      return true;
    }());
    if (rects.isEmpty) return;

    final shadowPaint =
        Paint()
          ..color = const Color(0xFFFFC857).withValues(alpha: 0.14)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12);
    final fillPaint =
        Paint()..color = const Color(0xFFFFC857).withValues(alpha: 0.20);
    final strokePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = textColor.withValues(alpha: 0.10);

    for (final rect in rects) {
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rounded.inflate(2), shadowPaint);
      canvas.drawRRect(rounded, fillPaint);
      canvas.drawRRect(rounded, strokePaint);
    }
  }

  List<Rect> _highlightRects(Size size) {
    final current = highlight;
    if (current == null ||
        !current.isValid ||
        current.chapterIndex != tile.chapterIndex) {
      return const <Rect>[];
    }
    final lines = tile.linesForRange(
      current.highlightStart,
      current.highlightEnd,
    );
    if (lines.isEmpty) return const <Rect>[];

    final left = (style.paddingLeft - 6).clamp(0.0, size.width).toDouble();
    final right =
        (size.width - style.paddingRight + 6)
            .clamp(left, size.width)
            .toDouble();
    final maxBottom = size.height.isFinite ? size.height : tile.height;
    return lines
        .map((line) {
          final top =
              (style.paddingTop + line.top - 1)
                  .clamp(0.0, maxBottom)
                  .toDouble();
          final bottom =
              (style.paddingTop + line.bottom + 1)
                  .clamp(top, maxBottom)
                  .toDouble();
          return Rect.fromLTRB(left, top, right, bottom);
        })
        .toList(growable: false);
  }

  @override
  bool shouldRepaint(covariant ReaderV2TtsHighlightOverlayPainter oldDelegate) {
    if (oldDelegate.tile != tile ||
        oldDelegate.style != style ||
        oldDelegate.textColor != textColor) {
      return true;
    }
    return _highlightAffectsTile(oldDelegate.highlight) ||
        _highlightAffectsTile(highlight);
  }

  bool _highlightAffectsTile(ReaderV2TtsHighlight? value) {
    return value != null &&
        value.isValid &&
        value.chapterIndex == tile.chapterIndex &&
        tile.intersectsCharRange(value.highlightStart, value.highlightEnd);
  }
}
