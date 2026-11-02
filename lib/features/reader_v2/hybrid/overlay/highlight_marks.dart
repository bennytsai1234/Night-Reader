import 'package:flutter/widgets.dart';

import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// 正文裡一個標註：[location] 是開頭（章節序號已經對到這台的目錄，章內
/// 第幾個字還要照那一章目前的正文解析），往後畫 [length] 個字。
typedef ReaderHighlightMark = ({
  int id,
  ReaderV2Location location,
  int length,
  HighlightColor color,
  HighlightStyle style,
});

/// 一個標註在 viewport 上的字形範圍，每條視覺行一個框。
typedef HighlightPaint = ({
  List<HybridLineBox> boxes,
  HighlightColor color,
  HighlightStyle style,
});

/// 標註的顏色。淺色、深色紙上都用同一組，底色以不透明度疊在字上。
extension HighlightColorValue on HighlightColor {
  Color get value => switch (this) {
    HighlightColor.amber => const Color(0xFFFFC857),
    HighlightColor.green => const Color(0xFF6CCB7A),
    HighlightColor.blue => const Color(0xFF5AA9FF),
    HighlightColor.pink => const Color(0xFFFF7FAF),
    HighlightColor.purple => const Color(0xFFB38CFF),
  };
}

/// 正文上的標註：底色貼著字形鋪（同朗讀高亮，左右貼著頭尾字、上下以
/// 行格為界），底線畫在每一行字的下緣。不擋字、不接點擊；點已畫的標註由
/// 閱讀畫面照點到的字判斷。
final class HighlightMarksOverlay extends StatelessWidget {
  const HighlightMarksOverlay({super.key, required this.items});

  final List<HighlightPaint> items;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: HighlightMarksPainter(items: items),
          size: Size.infinite,
        ),
      ),
    );
  }
}

final class HighlightMarksPainter extends CustomPainter {
  const HighlightMarksPainter({required this.items});

  final List<HighlightPaint> items;

  /// 底色的不透明度：比朗讀高亮的預設深一些，捲過去也一眼看得到。
  static const double fillAlpha = 0.32;
  static const double underlineAlpha = 0.9;
  static const double underlineWidth = 2;
  static const Radius _radius = Radius.circular(4);

  /// 底色略為外擴，包住字形而不是切齊字緣（同朗讀高亮）。
  static Rect fillRectOf(HybridLineBox box) =>
      Rect.fromLTRB(box.left - 2, box.top, box.right + 2, box.bottom);

  @override
  void paint(Canvas canvas, Size size) {
    for (final (:boxes, :color, :style) in items) {
      switch (style) {
        case HighlightStyle.fill:
          final paint = Paint()
            ..color = color.value.withValues(alpha: fillAlpha);
          for (final box in boxes) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(fillRectOf(box), _radius),
              paint,
            );
          }
        case HighlightStyle.underline:
          final paint = Paint()
            ..color = color.value.withValues(alpha: underlineAlpha);
          for (final box in boxes) {
            // 行格下緣含行距，底線貼著那一行的字：取行格下方約一成處。
            final height = box.bottom - box.top;
            final y = box.bottom - height * 0.12;
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTRB(
                  box.left,
                  y - underlineWidth / 2,
                  box.right,
                  y + underlineWidth / 2,
                ),
                const Radius.circular(underlineWidth / 2),
              ),
              paint,
            );
          }
      }
    }
  }

  @override
  bool shouldRepaint(HighlightMarksPainter old) {
    if (old.items.length != items.length) return true;
    for (var i = 0; i < items.length; i++) {
      final a = old.items[i];
      final b = items[i];
      if (a.color != b.color || a.style != b.style) return true;
      if (!_sameBoxes(a.boxes, b.boxes)) return true;
    }
    return false;
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

/// 標註清單列首的一條顏色，和正文上那個標註同色。
class HighlightColorBar extends StatelessWidget {
  const HighlightColorBar({super.key, required this.color});

  final HighlightColor color;

  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: 28,
    decoration: BoxDecoration(
      color: color.value,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
