import 'package:flutter/material.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';

import 'app_chrome.dart';
import 'app_style.dart';
import 'app_text_styles.dart';
import 'app_tokens.dart';

ThemeData buildAppTheme(
  AppStyle style,
  Brightness brightness, {
  GlassStrength glassStrength = GlassStrength.frosted,
  AppPageTransition pageTransition = AppPageTransition.paper,
}) {
  final colors = style.of(brightness);
  // 淺色模式的提示訊息是深底，動作字取深色配色的主色才看得清楚。
  final inversePrimary =
      (brightness == Brightness.light ? style.dark : style.light).primary;
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

  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: brightness,
      ).copyWith(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: colors.text,
        secondary: colors.secondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: colors.text,
        surface: colors.surface,
        onSurface: colors.text,
        onSurfaceVariant: colors.textMuted,
        outline: colors.border,
        outlineVariant: colors.border.withValues(alpha: 0.72),
        inversePrimary: inversePrimary,
        // 危險色用設計的赭石（同 context.danger），不用 Material 預設紅。
        error: brightness == Brightness.light
            ? AppPalette.rust
            : AppPalette.rustDark,
        onError: brightness == Brightness.light
            ? AppPalette.paper50
            : AppPalette.ink700,
      );

  final textTheme = ThemeData(brightness: brightness).textTheme
      .copyWith(
        titleLarge: AppTextStyles.titleLg,
        titleMedium: AppTextStyles.titleMd,
        titleSmall: AppTextStyles.uiMd,
        bodyLarge: AppTextStyles.bodyMd,
        bodyMedium: AppTextStyles.bodyBase,
        bodySmall: AppTextStyles.bodySm,
        labelLarge: AppTextStyles.uiSm,
        labelMedium: AppTextStyles.labelSm,
        labelSmall: AppTextStyles.labelXs,
      )
      .apply(bodyColor: colors.text, displayColor: colors.text);

  final chrome = AppChrome.derive(
    brightness: brightness,
    primary: colors.primary,
    background: colors.background,
    surface: colors.surface,
    bar: colors.bar,
    textPrimary: colors.text,
    textSecondary: colors.textMuted,
    border: colors.border,
    inversePrimary: inversePrimary,
    glassStrength: glassStrength,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    extensions: [chrome, colors],
    // 點擊回饋採 Telegram 式整列高亮，不畫水波紋。
    splashFactory: NoSplash.splashFactory,
    highlightColor: chrome.pressedHighlight,
    hoverColor: Colors.transparent,
    // 全 App 換頁用使用者選的轉場（含開書），開關對稱，支援邊緣右滑返回；
    // 閱讀器關掉右滑返回（見 BookOpenRoute）。
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppPageTransitionsBuilder(pageTransition),
        TargetPlatform.iOS: AppPageTransitionsBuilder(pageTransition),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: chrome.toastBackground,
      actionTextColor: chrome.toastAction,
      closeIconColor: chrome.toastForeground,
      contentTextStyle: AppTextStyles.uiMd.copyWith(
        color: chrome.toastForeground,
        fontWeight: FontWeight.w400,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      insetPadding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        AppSpacing.md,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bar,
      foregroundColor: colors.text,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.text,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: brightness == Brightness.light ? 1 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardLg,
        side: BorderSide(
          color: colors.border.withValues(
            alpha: brightness == Brightness.light ? 0.35 : 0.6,
          ),
          width: 0.5,
        ),
      ),
      color: colors.surface,
      shadowColor: brightness == Brightness.light
          ? const Color(0x0A241C10)
          : null,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
    ),
    dividerTheme: DividerThemeData(
      thickness: 1,
      space: 1,
      color: colors.border,
    ),
    // outline 是髮絲分隔線色，當按鈕外框對頁面底只有約 1.3:1；外框按鈕
    // 改用主色框線。
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(side: BorderSide(color: colors.primary)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: const OutlineInputBorder(
        borderRadius: AppRadius.cardMd,
        borderSide: BorderSide.none,
      ),
    ),
    textTheme: textTheme,
  );
}
