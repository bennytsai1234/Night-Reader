import 'package:flutter/material.dart';

import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';

/// 朗讀高亮：目前朗讀的句段鋪底。
///
/// 左右貼著句段的頭尾字，不是整行色帶；上下以行格為界。
final class TtsHighlightOverlay extends StatelessWidget {
  const TtsHighlightOverlay({
    super.key,
    required this.sentence,
    required this.color,
  });

  final List<LineBox> sentence;

  /// 鋪底色，已含使用者設定的深淺（不透明度）。
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (sentence.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: TtsHighlightPainter(sentence: sentence, color: color),
          size: Size.infinite,
        ),
      ),
    );
  }
}

final class TtsHighlightPainter extends CustomPainter {
  const TtsHighlightPainter({required this.sentence, required this.color});

  final List<LineBox> sentence;
  final Color color;

  static const Radius _radius = Radius.circular(4);

  /// 框略為外擴，讓色塊包住字形而不是切齊字緣。
  static Rect rectOf(LineBox box) =>
      Rect.fromLTRB(box.left - 2, box.top, box.right + 2, box.bottom);

  @override
  void paint(Canvas canvas, Size size) {
    final sentencePaint = Paint()..color = color;
    for (final box in sentence) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rectOf(box), _radius),
        sentencePaint,
      );
    }
  }

  @override
  bool shouldRepaint(TtsHighlightPainter oldDelegate) {
    return !_sameBoxes(oldDelegate.sentence, sentence) ||
        oldDelegate.color != color;
  }

  static bool _sameBoxes(List<LineBox> a, List<LineBox> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      final x = a[i];
      final y = b[i];
      if (x.left != y.left ||
          x.top != y.top ||
          x.right != y.right ||
          x.bottom != y.bottom) {
        return false;
      }
    }
    return true;
  }
}
