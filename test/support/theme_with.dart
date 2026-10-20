import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// App 主題再掛上（或換掉同型別的）[extras] 擴充；測試用來換骨架的樣子
/// 與換場這類 App 不給使用者選的設定。
ThemeData themeWith(
  AppStyle style,
  Brightness brightness,
  List<ThemeExtension<dynamic>> extras,
) {
  final base = buildAppTheme(style, brightness);
  return base.copyWith(extensions: [...base.extensions.values, ...extras]);
}
