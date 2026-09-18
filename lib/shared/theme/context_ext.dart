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
}
