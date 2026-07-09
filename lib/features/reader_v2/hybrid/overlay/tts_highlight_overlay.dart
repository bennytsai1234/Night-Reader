import 'package:flutter/material.dart';

import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';

final class HybridTtsHighlightOverlay extends StatelessWidget {
  const HybridTtsHighlightOverlay({
    super.key,
    required this.lines,
    required this.style,
    required this.textColor,
    required this.highlight,
  });

  final List<HybridLineBox> lines;
  final ReaderV2Style style;
  final Color textColor;
  final ReaderV2TtsHighlight? highlight;

  @override
  Widget build(BuildContext context) {
    final current = highlight;
    if (current == null || !current.isValid) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: HybridTtsHighlightPainter(
            lines: lines,
            style: style,
            textColor: textColor,
            highlight: current,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

final class HybridTtsHighlightPainter extends CustomPainter {
  const HybridTtsHighlightPainter({
    required this.lines,
    required this.style,
    required this.textColor,
    required this.highlight,
  });

  final List<HybridLineBox> lines;
  final ReaderV2Style style;
  final Color textColor;
  final ReaderV2TtsHighlight highlight;

  static List<Rect> rectsFor({
    required List<HybridLineBox> lines,
    required ReaderV2Style style,
    required Size size,
    required ReaderV2TtsHighlight highlight,
  }) {
    final range = HybridTextRange(
      highlight.highlightStart,
      highlight.highlightEnd,
    );
    final left = (style.paddingLeft - 6).clamp(0.0, size.width).toDouble();
    final right =
        (size.width - style.paddingRight + 6)
            .clamp(left, size.width)
            .toDouble();
    final maxBottom = size.height.isFinite ? size.height : double.infinity;
    final rects = <Rect>[];
    for (final line in lines) {
      if (line.key.chapterIndex != highlight.chapterIndex) continue;
      if (!line.charRange.intersects(range)) continue;
      final top = (style.paddingTop + line.top - 1).clamp(0.0, maxBottom);
      final bottom = (style.paddingTop + line.bottom + 1).clamp(
        top.toDouble(),
        maxBottom,
      );
      rects.add(Rect.fromLTRB(left, top.toDouble(), right, bottom.toDouble()));
    }
    return rects;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rects = rectsFor(
      lines: lines,
      style: style,
      size: size,
      highlight: highlight,
    );
    if (rects.isEmpty) return;
    final shadowPaint =
        Paint()
          ..color = const Color(0xFFFFC857).withValues(alpha: 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
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

  @override
  bool shouldRepaint(HybridTtsHighlightPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.style != style ||
        oldDelegate.textColor != textColor ||
        oldDelegate.highlight != highlight;
  }
}
