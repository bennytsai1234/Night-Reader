import 'dart:ui';

import 'package:night_reader/features/settings/theme_settings_provider.dart';

/// 朗讀高亮與選字反白共用的顏色。[theme] 沿用閱讀區配色裡的
/// 「高亮／選中背景」（未自訂時為琥珀）；其餘是固定色票。
enum ReaderV2HighlightColor {
  theme('跟隨主題', null),
  amber('琥珀', Color(0xFFFFC857)),
  blue('藍', Color(0xFF5AA9FF)),
  green('綠', Color(0xFF6CCB7A)),
  pink('粉', Color(0xFFFF7FAF)),
  gray('灰', Color(0xFF9E9E9E));

  const ReaderV2HighlightColor(this.label, this._color);

  final String label;
  final Color? _color;

  /// 依正文色判斷日夜，解析出實際的顏色。
  Color resolve(Color textColor) {
    final fixed = _color;
    if (fixed != null) return fixed;
    final darkReader = textColor.computeLuminance() > 0.5;
    final custom = ThemeSettingsProvider.resolveReaderAreaColors(
      dark: darkReader,
      menu: false,
    );
    return custom?.highlight ?? amber._color!;
  }

  static ReaderV2HighlightColor parse(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return theme;
  }
}

/// 朗讀高亮的深淺（鋪底色的不透明度）。
abstract final class ReaderV2HighlightStrength {
  static const double min = 0.06;
  static const double max = 0.6;
  static const double defaultValue = 0.16;

  static double normalize(double? value) {
    if (value == null || !value.isFinite) return defaultValue;
    return value.clamp(min, max).toDouble();
  }
}
