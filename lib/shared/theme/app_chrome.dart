import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 分組清單與玻璃元件使用的衍生色。
///
/// 全部由 App 主題的既有語意色推導，不新增可序列化欄位；閱讀器面板等
/// 自帶 [ThemeData] 的區域沒有這個擴充時，[AppChrome.of] 會從該主題的
/// [ColorScheme] 即時推導，讓同一組元件在選單主題下也能使用。
@immutable
class AppChrome extends ThemeExtension<AppChrome> {
  const AppChrome({
    required this.groupedBackground,
    required this.groupedSurface,
    required this.separator,
    required this.sectionText,
    required this.pressedHighlight,
    required this.glassTint,
    required this.glassBorder,
    required this.glassShadow,
    required this.selectionLens,
    required this.barrier,
    required this.toastBackground,
    required this.toastForeground,
    required this.toastAction,
    this.glassStrength = GlassStrength.frosted,
  });

  /// 分組清單頁面底色。
  final Color groupedBackground;

  /// 分組卡片底色。
  final Color groupedSurface;

  /// 列與列之間的髮絲分隔線。
  final Color separator;

  /// 組標題與說明文字。
  final Color sectionText;

  /// 按下時整列的高亮底色（取代水波紋）。
  final Color pressedHighlight;

  /// 玻璃材質的紙／墨色調（已含透明度）。
  final Color glassTint;

  /// 玻璃邊緣的髮絲亮邊。
  final Color glassBorder;

  /// 浮動玻璃元件的漫射陰影。
  final Color glassShadow;

  /// 分頁列的選取膠囊。
  final Color selectionLens;

  /// 情境選單與提示框背後的暗化遮罩。
  final Color barrier;

  /// 提示訊息（toast）。
  final Color toastBackground;
  final Color toastForeground;
  final Color toastAction;

  /// 使用者選擇的玻璃強度；[glassTint] 已套用它的不透明度。
  final GlassStrength glassStrength;

  factory AppChrome.derive({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color bar,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required Color inversePrimary,
    GlassStrength glassStrength = GlassStrength.frosted,
  }) {
    final isLight = brightness == Brightness.light;
    return AppChrome(
      glassStrength: glassStrength,
      groupedBackground: background,
      groupedSurface: surface,
      separator: border.withValues(alpha: isLight ? 0.75 : 0.9),
      sectionText: textSecondary,
      pressedHighlight: textPrimary.withValues(alpha: isLight ? 0.06 : 0.08),
      glassTint: bar.withValues(alpha: glassStrength.opacity(dark: !isLight)),
      glassBorder: isLight
          ? surface.withValues(alpha: 0.7)
          : textPrimary.withValues(alpha: 0.08),
      glassShadow: isLight
          ? textPrimary.withValues(alpha: 0.1)
          : const Color(0x59000000),
      selectionLens: Color.alphaBlend(
        primary.withValues(alpha: isLight ? 0.12 : 0.18),
        surface.withValues(alpha: 0.6),
      ),
      barrier: isLight
          ? textPrimary.withValues(alpha: 0.18)
          : const Color(0x66000000),
      // 淺色時是墨色底配紙色字；深色時是比卡片再亮一階的浮層。
      toastBackground: isLight
          ? textPrimary.withValues(alpha: 0.94)
          : Color.alphaBlend(
              textPrimary.withValues(alpha: 0.1),
              surface,
            ).withValues(alpha: 0.96),
      toastForeground: isLight ? background : textPrimary,
      // 深色浮層比卡片亮一階，主色直接用對比不夠（紙墨深色只有 3.8:1），
      // 往文字色靠一些。
      toastAction: isLight
          ? inversePrimary
          : Color.lerp(primary, textPrimary, 0.3)!,
    );
  }

  /// 讀取目前主題的衍生色；主題沒有掛擴充時依 [ColorScheme] 推導。
  static AppChrome of(BuildContext context) {
    final theme = Theme.of(context);
    final ext = theme.extension<AppChrome>();
    if (ext != null) return ext;
    final scheme = theme.colorScheme;
    return AppChrome.derive(
      brightness: theme.brightness,
      primary: scheme.primary,
      background: theme.scaffoldBackgroundColor,
      surface: scheme.surface,
      bar: scheme.surface,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      border: scheme.outline,
      inversePrimary: scheme.inversePrimary,
    );
  }

  @override
  AppChrome copyWith({
    Color? groupedBackground,
    Color? groupedSurface,
    Color? separator,
    Color? sectionText,
    Color? pressedHighlight,
    Color? glassTint,
    Color? glassBorder,
    Color? glassShadow,
    Color? selectionLens,
    Color? barrier,
    Color? toastBackground,
    Color? toastForeground,
    Color? toastAction,
    GlassStrength? glassStrength,
  }) {
    return AppChrome(
      groupedBackground: groupedBackground ?? this.groupedBackground,
      groupedSurface: groupedSurface ?? this.groupedSurface,
      separator: separator ?? this.separator,
      sectionText: sectionText ?? this.sectionText,
      pressedHighlight: pressedHighlight ?? this.pressedHighlight,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      glassShadow: glassShadow ?? this.glassShadow,
      selectionLens: selectionLens ?? this.selectionLens,
      barrier: barrier ?? this.barrier,
      toastBackground: toastBackground ?? this.toastBackground,
      toastForeground: toastForeground ?? this.toastForeground,
      toastAction: toastAction ?? this.toastAction,
      glassStrength: glassStrength ?? this.glassStrength,
    );
  }

  @override
  AppChrome lerp(ThemeExtension<AppChrome>? other, double t) {
    if (other is! AppChrome) return this;
    return AppChrome(
      groupedBackground: Color.lerp(
        groupedBackground,
        other.groupedBackground,
        t,
      )!,
      groupedSurface: Color.lerp(groupedSurface, other.groupedSurface, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      sectionText: Color.lerp(sectionText, other.sectionText, t)!,
      pressedHighlight: Color.lerp(
        pressedHighlight,
        other.pressedHighlight,
        t,
      )!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      selectionLens: Color.lerp(selectionLens, other.selectionLens, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      toastBackground: Color.lerp(toastBackground, other.toastBackground, t)!,
      toastForeground: Color.lerp(toastForeground, other.toastForeground, t)!,
      toastAction: Color.lerp(toastAction, other.toastAction, t)!,
      glassStrength: t < 0.5 ? glassStrength : other.glassStrength,
    );
  }
}

/// 列首上色圖示方塊的顏料色；淺深色模式都用飽和的原色，圖示一律紙白。
/// 玻璃材質強度（外觀設定中由使用者選擇）：模糊越強、色調越透明，
/// 背後內容透出越多，繪製成本也越高。
enum GlassStrength {
  /// 實色：不模糊，色調完全不透明。
  solid('實色', blur: 0, lightOpacity: 1, darkOpacity: 1),

  /// 霧面紙：預設。
  frosted('霧面', blur: 12, lightOpacity: 0.84, darkOpacity: 0.82),

  /// 通透：較明顯的模糊與透色。
  clear('通透', blur: 20, lightOpacity: 0.68, darkOpacity: 0.62),

  /// 玻璃：接近 Telegram iOS 的高透明液態玻璃。
  glass('玻璃', blur: 28, lightOpacity: 0.5, darkOpacity: 0.44);

  const GlassStrength(
    this.label, {
    required this.blur,
    required this.lightOpacity,
    required this.darkOpacity,
  });

  final String label;

  /// 背景模糊的 sigma；0 表示不做背景模糊。
  final double blur;
  final double lightOpacity;
  final double darkOpacity;

  double opacity({required bool dark}) => dark ? darkOpacity : lightOpacity;

  static GlassStrength fromStorage(String? value) => GlassStrength.values
      .firstWhere((s) => s.name == value, orElse: () => GlassStrength.frosted);
}

enum AppTint {
  cinnabar(AppPalette.cinnabar),
  azurite(AppPalette.azurite),
  moss(AppPalette.moss),
  tea(AppPalette.tea),
  gold(AppPalette.gold),
  aubergine(AppPalette.aubergine),
  rust(AppPalette.rust),
  ink(AppPalette.ink300);

  const AppTint(this.color);
  final Color color;
}
