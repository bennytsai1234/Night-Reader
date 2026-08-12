import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'theme_customization.dart';

ThemeData buildAppTheme(AppUiThemeColors colors, Brightness brightness) {
  final primaryContainer = Color.alphaBlend(
    colors.primary.withValues(
      alpha: brightness == Brightness.light ? 0.14 : 0.24,
    ),
    colors.surface,
  );
  final secondaryContainer = Color.alphaBlend(
    colors.secondary.withValues(
      alpha: brightness == Brightness.light ? 0.13 : 0.22,
    ),
    colors.surface,
  );
  final onPrimary =
      colors.primary.computeLuminance() > 0.5
          ? AppPalette.ink700
          : AppPalette.paper50;

  final scheme = ColorScheme.fromSeed(
    seedColor: colors.primary,
    brightness: brightness,
  ).copyWith(
    primary: colors.primary,
    onPrimary: onPrimary,
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
      elevation: brightness == Brightness.light ? 1 : 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      color: colors.surface,
      shadowColor:
          brightness == Brightness.light ? const Color(0x0A241C10) : null,
    ),
    dialogTheme: DialogThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardXl),
      backgroundColor: colors.surface,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      elevation: brightness == Brightness.light ? 3 : 8,
      color: colors.surface,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.navigation,
      indicatorColor: colors.primary.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color:
              states.contains(WidgetState.selected)
                  ? colors.primary
                  : colors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight:
              states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
          color:
              states.contains(WidgetState.selected)
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
