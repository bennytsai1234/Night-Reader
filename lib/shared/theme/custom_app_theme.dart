import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_chrome.dart';
import 'app_style.dart';
import 'app_text_styles.dart';
import 'app_tokens.dart';

ThemeData buildAppTheme(
  AppStyle style,
  Brightness brightness, {
  GlassStrength glassStrength = GlassStrength.frosted,
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
    // 換頁採 iOS 平移並支援邊緣右滑返回；開書的 [BookOpenRoute] 自帶轉場，
    // 不受影響，閱讀器內的橫向手勢因此不會觸發返回。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
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
