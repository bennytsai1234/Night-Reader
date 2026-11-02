import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 頁首頁尾的電池：橫式圓角外框、右側一個小凸點，裡面照電量從左填到對應
/// 的長度，顏色跟資訊列的字一樣，大小照資訊列的字級（[fontSize]）。
///
/// [label] 為 null 時只畫電池（「電量（含圖示）」，數字另外排在旁邊）；
/// 有字時外框包住這段字（「電量（數字在電池裡）」），填滿改用淡色墊在字底下，
/// 字照樣看得清楚。[percent] 為 null（還沒拿到電量）時不填。充電中在電池右邊
/// 多一個小閃電。
class ReaderV2BatteryGlyph extends StatelessWidget {
  const ReaderV2BatteryGlyph({
    super.key,
    required this.percent,
    required this.charging,
    required this.color,
    required this.fontSize,
    this.label,
  });

  final int? percent;
  final bool charging;
  final Color color;
  final double fontSize;
  final String? label;

  /// 數字在電池裡時，填滿那一塊的不透明度。
  static const double insideFillAlpha = 0.22;

  @override
  Widget build(BuildContext context) {
    final stroke = math.max(1.0, fontSize / 11);
    final nub = fontSize * 0.14;
    final label = this.label;
    final Widget body;
    if (label == null) {
      final height = fontSize * 0.8;
      body = SizedBox(width: height * 1.9 + nub, height: height);
    } else {
      body = Padding(
        padding: EdgeInsets.fromLTRB(
          fontSize * 0.3 + stroke,
          stroke,
          fontSize * 0.3 + stroke + nub,
          stroke,
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: fontSize * 0.88, height: 1.2),
          maxLines: 1,
          softWrap: false,
        ),
      );
    }
    final battery = CustomPaint(
      painter: _BatteryPainter(
        level: percent == null ? null : (percent! / 100).clamp(0.0, 1.0),
        color: color,
        stroke: stroke,
        nub: nub,
        fillAlpha: label == null ? 1.0 : insideFillAlpha,
      ),
      child: body,
    );
    if (!charging) return battery;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        battery,
        Icon(Icons.bolt, size: fontSize * 0.95, color: color),
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({
    required this.level,
    required this.color,
    required this.stroke,
    required this.nub,
    required this.fillAlpha,
  });

  final double? level;
  final Color color;
  final double stroke;
  final double nub;
  final double fillAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyWidth = size.width - nub;
    final half = stroke / 2;
    final radius = Radius.circular(size.height * 0.22);
    final outline = RRect.fromRectAndRadius(
      Rect.fromLTWH(half, half, bodyWidth - stroke, size.height - stroke),
      radius,
    );
    canvas.drawRRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );
    final nubHeight = size.height * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(bodyWidth, (size.height - nubHeight) / 2, nub, nubHeight),
        topRight: Radius.circular(nub),
        bottomRight: Radius.circular(nub),
      ),
      Paint()..color = color,
    );
    final level = this.level;
    if (level == null || level <= 0) return;
    // 填滿和外框之間留一道縫，看得出是電池不是一塊色。
    final inset = stroke * 1.5;
    final inner = Rect.fromLTRB(
      inset,
      inset,
      bodyWidth - inset,
      size.height - inset,
    );
    if (inner.width <= 0 || inner.height <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inner.left, inner.top, inner.width * level, inner.height),
        Radius.circular(inner.height * 0.18),
      ),
      Paint()..color = color.withValues(alpha: color.a * fillAlpha),
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.level != level ||
      old.color != color ||
      old.stroke != stroke ||
      old.nub != nub ||
      old.fillAlpha != fillAlpha;
}
