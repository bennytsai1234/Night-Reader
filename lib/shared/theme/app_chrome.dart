import 'package:flutter/material.dart';

import 'app_layers.dart';
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
    required this.glassShadow,
    required this.selectionLens,
    required this.popupSurface,
    required this.popupSeparator,
    required this.barrier,
    required this.menuBarrier,
    required this.toastBackground,
    required this.toastForeground,
    required this.toastAction,
    this.glassStrength = GlassStrength.unspecified,
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

  /// 浮動玻璃元件的漫射陰影。
  final Color glassShadow;

  /// 分頁列的選取膠囊。
  final Color selectionLens;

  /// 彈出層（彈出選單、提示框、動作表）的底色，不含透明度；畫的時候用
  /// [popupTint]。淺色和卡片同色，靠遮罩把底下壓暗來分開；深色用玻璃那
  /// 一階，比卡片亮（docs/design/appearance.md「層次」）。
  final Color popupSurface;

  /// 彈出層裡的髮絲分隔線：和 [separator] 對卡片的深淺差一樣，照
  /// [popupSurface] 算。
  final Color popupSeparator;

  /// 提示框、底部面板與長按預覽背後的遮罩。
  final Color barrier;

  /// 彈出選單背後的遮罩：選單小、點了就走，壓得比 [barrier] 淺。
  final Color menuBarrier;

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
    GlassStrength glassStrength = GlassStrength.unspecified,
  }) {
    final isLight = brightness == Brightness.light;
    final barrier = isLight
        ? textPrimary.withValues(alpha: 0.18)
        : const Color(0x66000000);
    // 深色取卡片與玻璃裡亮的那個：閱讀器面板的主題把卡片放在比玻璃亮的
    // 那一階。
    final popupSurface =
        isLight || surface.computeLuminance() > bar.computeLuminance()
        ? surface
        : bar;
    final separatorAlpha = isLight ? 0.75 : 0.9;
    final popupBorder = popupSurface == surface
        ? border
        : AppLayers.step(
            popupSurface,
            textPrimary,
            (AppLayers.lightness(border) - AppLayers.lightness(surface)).abs(),
          );
    return AppChrome(
      glassStrength: glassStrength,
      groupedBackground: background,
      groupedSurface: surface,
      separator: border.withValues(alpha: separatorAlpha),
      sectionText: textSecondary,
      pressedHighlight: textPrimary.withValues(alpha: isLight ? 0.06 : 0.08),
      glassTint: bar.withValues(alpha: glassStrength.opacity(dark: !isLight)),
      glassShadow: isLight
          ? textPrimary.withValues(alpha: 0.1)
          : const Color(0x59000000),
      selectionLens: Color.alphaBlend(
        primary.withValues(alpha: isLight ? 0.12 : 0.18),
        surface.withValues(alpha: 0.6),
      ),
      popupSurface: popupSurface,
      popupSeparator: popupBorder.withValues(alpha: separatorAlpha),
      barrier: barrier,
      menuBarrier: barrier.withValues(alpha: barrier.a * debugMenuBarrierRatio),
      // 淺色時是墨色底配紙色字；深色時比卡片再亮一階。提示訊息沒有模糊，
      // 底色完全不透明。
      toastBackground: isLight
          ? textPrimary
          : Color.alphaBlend(textPrimary.withValues(alpha: 0.1), surface),
      toastForeground: isLight ? background : textPrimary,
      // 深色浮層比卡片亮一階，主色直接用對比不夠（紙墨深色只有 3.8:1），
      // 往文字色靠一些。
      toastAction: isLight
          ? inversePrimary
          : Color.lerp(primary, textPrimary, 0.3)!,
    );
  }

  // PROTOTYPE：候選圖用的旋鈕，使用者選定後換成常數。
  static double debugMenuBarrierRatio = 0.4;

  /// 彈出層的底色：玻璃強度有模糊時用 [blurred] 的不透明度，實色完全不透明
  /// （[GlassStrength.overBlur]）。
  Color popupTint(double blurred) =>
      popupSurface.withValues(alpha: glassStrength.overBlur(blurred));

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
    Color? glassShadow,
    Color? selectionLens,
    Color? popupSurface,
    Color? popupSeparator,
    Color? barrier,
    Color? menuBarrier,
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
      glassShadow: glassShadow ?? this.glassShadow,
      selectionLens: selectionLens ?? this.selectionLens,
      popupSurface: popupSurface ?? this.popupSurface,
      popupSeparator: popupSeparator ?? this.popupSeparator,
      barrier: barrier ?? this.barrier,
      menuBarrier: menuBarrier ?? this.menuBarrier,
      toastBackground: toastBackground ?? this.toastBackground,
      toastForeground: toastForeground ?? this.toastForeground,
      toastAction: toastAction ?? this.toastAction,
      glassStrength: glassStrength ?? this.glassStrength,
    );
  }

  // 照值比較：每次建主題都推導一份新的（閱讀選單的 `toSheetTheme`、App 的
  // `buildAppTheme`），沒有照值比較時 ThemeData 永遠不相等，上層一重建，
  // 底下每個用到主題的元件都跟著重建，按鈕的主題漸變也重播一次（ADR 0018）。
  @override
  bool operator ==(Object other) =>
      other is AppChrome &&
      other.groupedBackground == groupedBackground &&
      other.groupedSurface == groupedSurface &&
      other.separator == separator &&
      other.sectionText == sectionText &&
      other.pressedHighlight == pressedHighlight &&
      other.glassTint == glassTint &&
      other.glassShadow == glassShadow &&
      other.selectionLens == selectionLens &&
      other.popupSurface == popupSurface &&
      other.popupSeparator == popupSeparator &&
      other.barrier == barrier &&
      other.menuBarrier == menuBarrier &&
      other.toastBackground == toastBackground &&
      other.toastForeground == toastForeground &&
      other.toastAction == toastAction &&
      other.glassStrength == glassStrength;

  @override
  int get hashCode => Object.hash(
    groupedBackground,
    groupedSurface,
    separator,
    sectionText,
    pressedHighlight,
    glassTint,
    glassShadow,
    selectionLens,
    popupSurface,
    popupSeparator,
    barrier,
    menuBarrier,
    toastBackground,
    toastForeground,
    toastAction,
    glassStrength,
  );

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
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      selectionLens: Color.lerp(selectionLens, other.selectionLens, t)!,
      popupSurface: Color.lerp(popupSurface, other.popupSurface, t)!,
      popupSeparator: Color.lerp(popupSeparator, other.popupSeparator, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      menuBarrier: Color.lerp(menuBarrier, other.menuBarrier, t)!,
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
  /// 實色：不模糊，色調完全不透明。預設（維護者自己讀書用的設定，2026-11-06）。
  solid('實色', blur: 0, lightOpacity: 1, darkOpacity: 1),

  /// 霧面紙。
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

  /// 半透明一定配模糊：這個強度有模糊時是 [opacity]，沒有模糊（實色）時
  /// 完全不透明，底下的字才不會清楚地透出來。
  double overBlur(double opacity) => blur > 0 ? opacity : 1;

  /// 使用者沒選過時的玻璃效果。
  static const GlassStrength defaultStrength = GlassStrength.solid;

  /// 主題沒帶玻璃效果時（元件測試、單獨預覽一個元件）用的：會模糊的霧面，
  /// 玻璃的進出場與模糊才看得到。App 一律照使用者的設定建主題，用不到它。
  static const GlassStrength unspecified = GlassStrength.frosted;

  static GlassStrength fromStorage(String? value) => GlassStrength.values
      .firstWhere((s) => s.name == value, orElse: () => defaultStrength);
}

enum AppTint {
  cinnabar(AppPalette.cinnabar),
  azurite(AppPalette.azurite),
  moss(AppPalette.moss),
  tea(AppPalette.tea),
  // 點金 gold 對紙白圖示只有 2.85:1；顏料色方塊用深一階的金，達 3:1 以上。
  gold(Color(0xFF9A7A3C)),
  aubergine(AppPalette.aubergine),
  rust(AppPalette.rust),
  ink(AppPalette.ink300);

  const AppTint(this.color);
  final Color color;
}
