import 'package:flutter/material.dart';

/// ColorUtils - 顏色輔助工具 (原 Android utils/ColorUtils.kt)
class ColorUtils {
  ColorUtils._();

  /// 判斷顏色是否為淺色
  static bool isColorLight(Color color) {
    // 使用 Flutter 內建的 computeLuminance
    return color.computeLuminance() >= 0.5;
  }

  /// 顏色轉十六進位字串 (#RRGGBB)
  static String colorToString(Color color) {
    return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// 調整亮度
  static Color shiftColor(Color color, double factor) {
    if (factor == 1.0) return color;

    // 將顏色轉換為 HSL
    final hsl = HSLColor.fromColor(color);
    final newLightness = (hsl.lightness * factor).clamp(0.0, 1.0);
    return hsl.withLightness(newLightness).toColor();
  }

  /// 變暗
  static Color darkenColor(Color color) {
    return shiftColor(color, 0.9);
  }

  /// 變亮
  static Color lightenColor(Color color) {
    return shiftColor(color, 1.1);
  }

  /// 反轉顏色
  static Color invertColor(Color color) {
    return Color.from(
      alpha: color.a,
      red: 1.0 - color.r,
      green: 1.0 - color.g,
      blue: 1.0 - color.b,
    );
  }

  /// 調整透明度
  static Color adjustAlpha(Color color, double factor) {
    final alpha = (color.a * factor).clamp(0.0, 1.0);
    return color.withAlpha((alpha * 255).round());
  }

  /// 混合顏色
  static Color blendColors(Color color1, Color color2, double ratio) {
    return Color.lerp(color1, color2, ratio) ?? color1;
  }
}
