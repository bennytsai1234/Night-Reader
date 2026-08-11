import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'theme_customization.dart';

ThemeData buildAppTheme(AppUiThemeColors colors, Brightness brightness) {
  final primaryContainer = Color.alphaBlend(
    colors.primary.withValues(
      alpha: brightness == Brightness.light ? 0.09 : 0.16,
    ),
    colors.surface,
  );
  final secondaryContainer = Color.alphaBlend(
    colors.secondary.withValues(
      alpha: brightness == Brightness.light ? 0.08 : 0.14,
    ),
    colors.surface,
  );

  final scheme = ColorScheme.fromSeed(
    seedColor: colors.primary,
    brightness: brightness,
  ).copyWith(
    primary: colors.primary,
    onPrimary: brightness == Brightness.light ? Colors.white : AppPalette.ink600,
    primaryContainer: primaryContainer,
    onPrimaryContainer: colors.textPrimary,
    secondary: colors.secondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: colors.textPrimary,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.border,
    outlineVariant: colors.border.withValues(alpha: 0.72),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.appBar,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
      color: colors.surface,
      shadowColor: null,
    ),
    dialogTheme: DialogThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      backgroundColor: colors.surface,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
      elevation: brightness == Brightness.light ? 2 : 6,
      color: colors.surface,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetLg),
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: colors.navigation,
      indicatorColor: colors.primary.withValues(alpha: 0.10),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textSecondary,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      thickness: 1,
      space: 1,
      color: colors.border,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: const OutlineInputBorder(
        borderRadius: AppRadius.cardMd,
        borderSide: BorderSide.none,
      ),
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    ),
  );
}
