import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'theme_customization.dart';

ThemeData buildAppTheme(AppUiThemeColors colors, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: colors.primary,
    brightness: brightness,
  ).copyWith(
    primary: colors.primary,
    secondary: colors.secondary,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    outline: colors.border,
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
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: brightness == Brightness.light ? 2 : 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      color: colors.surface,
      shadowColor:
          brightness == Brightness.light ? const Color(0x0A241C10) : null,
    ),
    dialogTheme: DialogThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      backgroundColor: colors.surface,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      elevation: brightness == Brightness.light ? 4 : 8,
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
      indicatorColor: colors.primary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
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
