import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// BuildContext extensions for design-system colors.
/// Prefer these over raw [Colors.xxx] calls in widget build methods.
extension AppColorsExt on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Warning / attention color (orange-ish), adaptive to brightness.
  Color get warning =>
      isDark ? AppPalette.warningDark : AppPalette.warningLight;

  /// Success / healthy color (green), adaptive to brightness.
  Color get success =>
      isDark ? AppPalette.successDark : AppPalette.successLight;

  /// Danger / error / destructive color, adaptive to brightness.
  Color get danger => isDark ? AppPalette.dangerDark : AppPalette.dangerLight;
}
