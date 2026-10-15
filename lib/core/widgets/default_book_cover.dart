import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 書架「統一封面」：開著時書架上的書與它們的書籍詳情一律畫預設封面，
/// 不用書源的封面（搜尋與發現的結果照舊）。值存在書架設定，由
/// `BookshelfProvider` 載入與變更時同步；書籍詳情從這裡讀。
abstract final class UnifiedCovers {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// 這本書要畫的封面：統一封面開著、而且書在書架上時為 null，畫預設封面。
  static String? coverOf(Book book) =>
      enabled.value && book.isInBookshelf ? null : book.getDisplayCover();
}

/// 沒有封面（或封面載不到）時的預設封面：夜空。墨色底帶一點顏料色調，
/// 一彎月、幾顆星與兩層遠山，不放文字。顏色、月亮與星星的位置、山的
/// 輪廓都由書名決定：不同的書看起來不同，同一本書每次都一樣。
class DefaultBookCover extends StatelessWidget {
  const DefaultBookCover({super.key, required this.bookName});

  final String bookName;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _NightSkyPainter(bookName), size: Size.infinite);
}

class _NightSkyPainter extends CustomPainter {
  _NightSkyPainter(this.bookName);

  final String bookName;

  static const Color _moonlight = Color(0xFFF4E3B5);

  static const List<Color> _pigments = [
    AppPalette.cinnabar,
    AppPalette.rust,
    AppPalette.tea,
    AppPalette.gold,
    AppPalette.azurite,
    AppPalette.moss,
    AppPalette.ink300,
    AppPalette.aubergine,
  ];

  /// 書名的 FNV-1a 雜湊：跟 `String.hashCode` 不同，保證每次啟動都一樣。
  static int _seedOf(String name) {
    var hash = 0x811C9DC5;
    for (final unit in name.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final seed = _seedOf(bookName);
    final pigment = _pigments[seed % _pigments.length];
    final random = math.Random(seed);
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(AppPalette.ink600, pigment, 0.25)!,
            Color.lerp(AppPalette.ink500, pigment, 0.55)!,
          ],
        ).createShader(rect),
    );

    // 月亮：上方三成以內、水平置中附近，外圍一圈淡淡的月暈。
    final moonCenter = Offset(
      size.width * (0.28 + random.nextDouble() * 0.44),
      size.height * (0.2 + random.nextDouble() * 0.1),
    );
    final radius = size.width * 0.12;
    final haloRect = Rect.fromCircle(center: moonCenter, radius: radius * 2.4);
    canvas.drawCircle(
      moonCenter,
      radius * 2.4,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _moonlight.withValues(alpha: 0.18),
            _moonlight.withValues(alpha: 0),
          ],
        ).createShader(haloRect),
    );
    final moon = Path()
      ..addOval(Rect.fromCircle(center: moonCenter, radius: radius));
    final bite = Path()
      ..addOval(
        Rect.fromCircle(
          center: moonCenter + Offset(radius * 0.5, -radius * 0.25),
          radius: radius * 0.9,
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, moon, bite),
      Paint()..color = _moonlight,
    );

    // 星星：上半部，避開月亮附近。
    for (var i = 0; i < 6; i++) {
      final star = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height * 0.55,
      );
      if ((star - moonCenter).distance < radius * 2) continue;
      canvas.drawCircle(
        star,
        size.width * (0.006 + random.nextDouble() * 0.01),
        Paint()
          ..color = _moonlight.withValues(
            alpha: 0.5 + random.nextDouble() * 0.4,
          ),
      );
    }

    // 遠山兩層，後面的淡、前面的深。
    for (final (layer, alpha) in [(0, 0.18), (1, 0.32)]) {
      final ridge = Path()..moveTo(0, size.height);
      final baseY = size.height * (0.72 + layer * 0.1);
      for (var x = 0.0; x <= size.width; x += size.width / 6) {
        ridge.lineTo(x, baseY - random.nextDouble() * size.height * 0.08);
      }
      ridge
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        ridge,
        Paint()..color = const Color(0xFF000000).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_NightSkyPainter oldDelegate) =>
      oldDelegate.bookName != bookName;
}
