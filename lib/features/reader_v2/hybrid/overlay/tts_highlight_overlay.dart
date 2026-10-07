import 'package:flutter/material.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

/// 朗讀高亮：目前朗讀的句段鋪底。
///
/// 左右貼著句段的頭尾字，不是整行色帶；上下以行格為界。
final class HybridTtsHighlightOverlay extends StatelessWidget {
  const HybridTtsHighlightOverlay({
    super.key,
    required this.sentence,
    required this.color,
  });

  final List<HybridLineBox> sentence;

  /// 鋪底色，已含使用者設定的深淺（不透明度）。
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (sentence.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: HybridTtsHighlightPainter(sentence: sentence, color: color),
          size: Size.infinite,
        ),
      ),
    );
  }
}

final class HybridTtsHighlightPainter extends CustomPainter {
  const HybridTtsHighlightPainter({
    required this.sentence,
    required this.color,
  });

  final List<HybridLineBox> sentence;
  final Color color;

  static const Radius _radius = Radius.circular(4);

  /// 框略為外擴，讓色塊包住字形而不是切齊字緣。
  static Rect rectOf(HybridLineBox box) =>
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
  bool shouldRepaint(HybridTtsHighlightPainter oldDelegate) {
    return !_sameBoxes(oldDelegate.sentence, sentence) ||
        oldDelegate.color != color;
  }

  static bool _sameBoxes(List<HybridLineBox> a, List<HybridLineBox> b) {
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
