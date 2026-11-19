import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/shared/shelf_trial.dart';

/// 書架「統一封面」：開著時書架上的書與它們的書籍詳情一律畫預設封面，
/// 不用書源的封面（搜尋與發現的結果照舊）。值存在書架設定，由
/// `BookshelfProvider` 載入與變更時同步；書籍詳情從這裡讀。
abstract final class UnifiedCovers {
  /// 沒設定過時開著（維護者自己讀書用的設定，2026-11-06）。
  static const bool defaultEnabled = true;

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(
    defaultEnabled,
  );

  /// 這本書要畫的封面：統一封面開著、而且書在書架上時為 null，畫預設封面。
  static String? coverOf(Book book) =>
      enabled.value && book.isInBookshelf ? null : book.getDisplayCover();
}

/// 沒有封面（或封面載不到）時的預設封面：深色是夜空，淺色是白天。月亮
/// （白天是太陽）與兩層遠山在每本書都一樣，星星（白天是雲）照書名放；
/// 天空的顏色照書在書架上的位置，由上到下深色從黃昏排到入夜、淺色從清晨
/// 排到正午（使用者 2026-11-19 選的），不在書架上的書取中間。不放文字。
///
/// 漫畫與有聲書在同一片天空加一個記號：漫畫在右上角加一片網點，有聲書把
/// 前面那層山換成一排音量條（`docs/design/components.md`「預設封面」）。
class DefaultBookCover extends StatelessWidget {
  const DefaultBookCover({
    super.key,
    required this.bookName,
    this.kind = BookSourceKind.novel,
  });

  final String bookName;

  /// 這本書是哪一類；漫畫、有聲畫各自的變體，其他畫原本的天空。
  final BookSourceKind kind;

  /// 把 [bookName] 的預設封面畫成 [width]×[height] 像素的 PNG，給 App 以外
  /// 的地方用（系統播放資訊的封面，一律畫夜空）。
  static Future<Uint8List> renderPng(
    String bookName, {
    required int width,
    required int height,
    BookSourceKind kind = BookSourceKind.novel,
  }) async {
    final recorder = ui.PictureRecorder();
    _SkyPainter(
      bookName,
      kind,
      position: ShelfTrial.positionOf(bookName),
      day: false,
    ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SkyPainter(
      bookName,
      kind,
      position: ShelfTrial.positionOf(bookName),
      day: Theme.of(context).brightness == Brightness.light,
    ),
    size: Size.infinite,
  );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(
    this.bookName,
    this.kind, {
    required this.position,
    required this.day,
  });

  final String bookName;
  final BookSourceKind kind;

  /// 書架上的位置，0 是最上面、1 是最下面；null 是不在書架上。
  final double? position;

  /// 淺色畫白天（太陽、雲），深色畫夜空（月亮、星星）。
  final bool day;

  static const Color _moonlight = Color(0xFFF4E3B5);
  static const Color _sunlight = Color(0xFFFFF7E0);

  /// 夜空：黃昏的紫紅 → 紫 → 靛 → 夜藍 → 青 → 深青（取自網站的天空）。
  static const List<Color> _nightStops = [
    Color(0xFF7A3B5E),
    Color(0xFF5E3572),
    Color(0xFF3B326E),
    Color(0xFF233C63),
    Color(0xFF17414F),
    Color(0xFF0F2C35),
  ];

  /// 白天：清晨的桃粉 → 日出的金 → 淡青 → 淺藍 → 藍 → 正午的藍。
  static const List<Color> _dayStops = [
    Color(0xFFEFB49E),
    Color(0xFFF1CB8F),
    Color(0xFFC9DCD2),
    Color(0xFFA6C8E0),
    Color(0xFF7FB0D8),
    Color(0xFF5C96CC),
  ];

  /// 書名的 FNV-1a 雜湊：跟 `String.hashCode` 不同，保證每次啟動都一樣。
  static int _seedOf(String name) {
    var hash = 0x811C9DC5;
    for (final unit in name.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static Color _along(List<Color> stops, double t) {
    final at = t.clamp(0.0, 1.0) * (stops.length - 1);
    final i = at.floor().clamp(0, stops.length - 2);
    return Color.lerp(stops[i], stops[i + 1], at - i)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = math.Random(_seedOf(bookName));
    final rect = Offset.zero & size;
    final sky = _along(day ? _dayStops : _nightStops, position ?? 0.5);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: day
              ? [
                  Color.lerp(sky, const Color(0xFF2C4A6E), 0.22)!,
                  Color.lerp(sky, const Color(0xFFFFFFFF), 0.38)!,
                ]
              : [Color.lerp(sky, const Color(0xFF05070C), 0.45)!, sky],
        ).createShader(rect),
    );

    // 月亮或太陽：每本書同一個位置，外圍一圈暈。
    final center = Offset(size.width * 0.34, size.height * 0.24);
    final radius = size.width * 0.12;
    final light = day ? _sunlight : _moonlight;
    final haloRadius = radius * (day ? 3 : 2.4);
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            light.withValues(alpha: day ? 0.55 : 0.18),
            light.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: haloRadius)),
    );
    final disc = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(
      day
          ? disc
          : Path.combine(
              PathOperation.difference,
              disc,
              Path()..addOval(
                Rect.fromCircle(
                  center: center + Offset(radius * 0.5, -radius * 0.25),
                  radius: radius * 0.9,
                ),
              ),
            ),
      Paint()..color = light,
    );

    if (day) {
      _paintClouds(canvas, size, random, center, radius);
    } else {
      _paintStars(canvas, size, random, center, radius);
    }

    if (kind == BookSourceKind.comic) {
      _paintHalftone(canvas, size, center, radius, day: day);
    }

    // 遠山兩層，後面的淡、前面的深，每本書同一個輪廓；有聲書前面那層換成
    // 音量條。
    final ridges = math.Random(7);
    final ink = day ? const Color(0xFF2E4A6B) : const Color(0xFF000000);
    for (final (layer, alpha)
        in day ? [(0, 0.22), (1, 0.4)] : [(0, 0.18), (1, 0.32)]) {
      final color = ink.withValues(alpha: alpha);
      if (layer == 1 && kind == BookSourceKind.audio) {
        _paintVolumeBars(canvas, size, random, color);
        continue;
      }
      final ridge = Path()..moveTo(0, size.height);
      final baseY = size.height * (0.72 + layer * 0.1);
      for (var x = 0.0; x <= size.width; x += size.width / 6) {
        ridge.lineTo(x, baseY - ridges.nextDouble() * size.height * 0.08);
      }
      ridge
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(ridge, Paint()..color = color);
    }
  }

  /// 星星：上半部，避開月亮附近，位置照書名。
  static void _paintStars(
    Canvas canvas,
    Size size,
    math.Random random,
    Offset moon,
    double radius,
  ) {
    for (var i = 0; i < 6; i++) {
      final star = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height * 0.55,
      );
      if ((star - moon).distance < radius * 2) continue;
      canvas.drawCircle(
        star,
        size.width * (0.006 + random.nextDouble() * 0.01),
        Paint()
          ..color = _moonlight.withValues(
            alpha: 0.5 + random.nextDouble() * 0.4,
          ),
      );
    }
  }

  /// 雲：兩朵，避開太陽，位置與大小照書名。
  static void _paintClouds(
    Canvas canvas,
    Size size,
    math.Random random,
    Offset sun,
    double radius,
  ) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.82);
    var drawn = 0;
    for (var tries = 0; tries < 8 && drawn < 2; tries++) {
      final at = Offset(
        size.width * (0.1 + random.nextDouble() * 0.8),
        size.height * (0.12 + random.nextDouble() * 0.45),
      );
      if ((at - sun).distance < radius * 2.6) continue;
      final w = size.width * (0.16 + random.nextDouble() * 0.1);
      canvas
        ..drawOval(
          Rect.fromCenter(center: at, width: w * 1.6, height: w * 0.5),
          paint,
        )
        ..drawCircle(at + Offset(-w * 0.25, -w * 0.18), w * 0.3, paint)
        ..drawCircle(at + Offset(w * 0.15, -w * 0.25), w * 0.36, paint);
      drawn++;
    }
  }

  /// 漫畫：右上角一片網點，由角落往外由大到小，避開月亮（太陽）與暈。
  static void _paintHalftone(
    Canvas canvas,
    Size size,
    Offset moonCenter,
    double moonRadius, {
    required bool day,
  }) {
    final corner = Offset(size.width, 0);
    final reach = size.width * 0.62;
    final step = size.width * 0.075;
    final maxDot = step * 0.46;
    final paint = Paint()
      ..color = (day ? const Color(0xFFFFFFFF) : _moonlight).withValues(
        alpha: day ? 0.4 : 0.28,
      );
    for (var y = step / 2; y < reach; y += step) {
      for (var x = size.width - step / 2; x > size.width - reach; x -= step) {
        final dot = Offset(x, y);
        final fade = 1 - (dot - corner).distance / reach;
        if (fade <= 0.08) continue;
        final r = maxDot * fade;
        if ((dot - moonCenter).distance < moonRadius * 1.7 + r) continue;
        canvas.drawCircle(dot, r, paint);
      }
    }
  }

  /// 有聲書：九根頂端圓角的音量條，高低由書名決定，佔前面那層山的位置。
  static void _paintVolumeBars(
    Canvas canvas,
    Size size,
    math.Random random,
    Color color,
  ) {
    const count = 9;
    final slot = size.width / count;
    final barWidth = slot * 0.62;
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final height = size.height * (0.08 + random.nextDouble() * 0.16);
      final left = slot * i + (slot - barWidth) / 2;
      final top = size.height - height;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left, top, left + barWidth, size.height),
          topLeft: Radius.circular(barWidth / 2),
          topRight: Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) =>
      oldDelegate.bookName != bookName ||
      oldDelegate.kind != kind ||
      oldDelegate.position != position ||
      oldDelegate.day != day;
}
