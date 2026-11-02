import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// 正文裡一個書籤的位置：[location] 的章節序號已經對到這台的目錄，章內
/// 第幾個字還要照那一章目前的正文解析（正文變了照錨點找回同一句）。
typedef ReaderMark = ({int id, ReaderV2Location location});

/// 書籤在正文旁的記號：書籤那一句開頭那一行，左側邊距畫一條細短線
/// （使用者 2026-11-02 從緞帶、短線、圓點三個候選選定）。
///
/// [lines] 是每個書籤那一行在 viewport 上的行框（只有排好、在附近的章節
/// 才有）；短線畫在左邊距中間，不擋字、不接點擊。
final class BookmarkMarksOverlay extends StatelessWidget {
  const BookmarkMarksOverlay({
    super.key,
    required this.lines,
    required this.textLeft,
    required this.color,
  });

  final List<HybridLineBox> lines;

  /// 正文欄的左緣（viewport 座標），也就是左邊距的寬。
  final double textLeft;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BookmarkMarksPainter(
          lines: lines,
          textLeft: textLeft,
          color: color,
        ),
      ),
    );
  }
}

final class _BookmarkMarksPainter extends CustomPainter {
  const _BookmarkMarksPainter({
    required this.lines,
    required this.textLeft,
    required this.color,
  });

  final List<HybridLineBox> lines;
  final double textLeft;
  final Color color;

  static const double _width = 3;

  /// 短線佔那一行行框的幾成高，和字差不多高。
  static const double _heightFactor = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    // 左邊距中間；邊距窄到放不下時貼著畫面左緣。
    final centerX = (textLeft / 2).clamp(_width, double.infinity);
    final paint = Paint()..color = color;
    for (final line in lines) {
      final height = (line.bottom - line.top) * _heightFactor;
      final centerY = (line.top + line.bottom) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX, centerY),
            width: _width,
            height: height,
          ),
          const Radius.circular(_width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BookmarkMarksPainter old) =>
      old.color != color ||
      old.textLeft != textLeft ||
      !_sameLines(old.lines, lines);

  static bool _sameLines(List<HybridLineBox> a, List<HybridLineBox> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].top != b[i].top || a[i].bottom != b[i].bottom) return false;
    }
    return true;
  }
}
