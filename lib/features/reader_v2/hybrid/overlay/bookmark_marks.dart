import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// 正文裡一個書籤的位置：[location] 的章節序號已經對到這台的目錄，章內
/// 第幾個字還要照那一章目前的正文解析（正文變了照錨點找回同一句）。
typedef ReaderMark = ({int id, ReaderV2Location location});

/// 書籤在正文旁的記號：書籤那個字所在的那一行，右側邊距畫一條小緞帶。
///
/// [lines] 是每個書籤那一行在 viewport 上的行框（只有排好、在附近的章節
/// 才有）；記號畫在正文欄右緣和畫面右緣中間，不擋字、不接點擊。
final class BookmarkMarksOverlay extends StatelessWidget {
  const BookmarkMarksOverlay({
    super.key,
    required this.lines,
    required this.textRight,
    required this.color,
  });

  final List<HybridLineBox> lines;

  /// 正文欄的右緣（viewport 座標）。
  final double textRight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BookmarkMarksPainter(
          lines: lines,
          textRight: textRight,
          color: color,
        ),
      ),
    );
  }
}

final class _BookmarkMarksPainter extends CustomPainter {
  const _BookmarkMarksPainter({
    required this.lines,
    required this.textRight,
    required this.color,
  });

  final List<HybridLineBox> lines;
  final double textRight;
  final Color color;

  static const double _width = 5;
  static const double _height = 10;
  static const double _notch = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final margin = size.width - textRight;
    // 邊距放得下就置中，放不下貼著正文欄。
    final left = margin >= _width + 4
        ? textRight + (margin - _width) / 2
        : textRight + 1;
    final paint = Paint()..color = color;
    for (final line in lines) {
      final top = (line.top + line.bottom) / 2 - _height / 2;
      final path = Path()
        ..moveTo(left, top)
        ..lineTo(left + _width, top)
        ..lineTo(left + _width, top + _height)
        ..lineTo(left + _width / 2, top + _height - _notch)
        ..lineTo(left, top + _height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_BookmarkMarksPainter old) =>
      old.color != color ||
      old.textRight != textRight ||
      !_sameLines(old.lines, lines);

  static bool _sameLines(List<HybridLineBox> a, List<HybridLineBox> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].top != b[i].top || a[i].bottom != b[i].bottom) return false;
    }
    return true;
  }
}
