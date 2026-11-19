import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// BuildContext extensions for design-system colors.
/// Prefer these over raw [Colors.xxx] calls in widget build methods.
extension AppColorsExt on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get warning => isDark ? AppPalette.teaDark : AppPalette.tea;
  Color get success => isDark ? AppPalette.mossDark : AppPalette.moss;
  Color get danger => isDark ? AppPalette.rustDark : AppPalette.rust;
  Color get info => isDark ? AppPalette.azuriteDark : AppPalette.azurite;

  /// 不能按的文字與圖示：一般字色降到 [AppDisabled.opacity]（中性灰）。
  Color get disabledForeground =>
      colorScheme.onSurface.withValues(alpha: AppDisabled.opacity);

  /// 能按時是 [color]，不能按時是 [disabledForeground]，不保留原色。
  Color actionColor(Color color, {required bool enabled}) =>
      enabled ? color : disabledForeground;
}
