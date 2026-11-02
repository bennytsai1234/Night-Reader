import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_layers.dart';
import 'app_tokens.dart';

// 高亮色以使用者設定的深淺（不透明度）疊在正文上，取鮮明的螢光筆色，
// 淺色與深色共用。
const _amber = Color(0xFFFFC857);
const _citron = Color(0xFFE8C547);
const _apricot = Color(0xFFF5A742);

const _black = Color(0xFF000000);

/// 外觀風格：一套同時套到 App 介面、閱讀正文與閱讀選單的配色，各有淺色
/// 與深色。使用者替淺色、深色各選一個風格（例如白天茶褐、晚上素色），再選
/// 強調色（[AppAccent]）與深色要不要純黑，不個別調色。
enum AppStyle {
  plain(
    '素色',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFDDDDDD),
      surface: Color(0xFFFFFFFF),
      bar: Color(0xFFFFFFFF),
      text: Color(0xFF111111),
      textMuted: Color(0xFF6B6B6B),
      border: Color(0xFFDADADA),
      primary: Color(0xFF333333),
      secondary: Color(0xFF8E8E93),
      readerBackground: Color(0xFFFFFFFF),
      readerMenu: Color(0xFFDDDDDD),
      readerText: Color(0xFF1A1A1A),
      readerInfo: Color(0xFF636363),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: _black,
      surface: Color(0xFF262626),
      bar: Color(0xFF323232),
      text: Color(0xFFEDEDED),
      textMuted: Color(0xFF999999),
      border: Color(0xFF363636),
      primary: Color(0xFFD6D6D6),
      secondary: Color(0xFF8E8E93),
      readerBackground: _black,
      readerMenu: Color(0xFF262626),
      readerText: Color(0xFFC4C4C4),
      readerInfo: Color(0xFF808080),
      highlight: _amber,
    ),
  ),
  paper(
    '紙墨',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFDDD9D1),
      surface: AppPalette.paper50,
      bar: AppPalette.paper50,
      text: AppPalette.ink700,
      textMuted: AppPalette.ink300,
      border: AppPalette.paper400,
      primary: AppPalette.cinnabar,
      secondary: AppPalette.gold,
      readerBackground: AppPalette.paper100,
      readerMenu: Color(0xFFD8D3C8),
      readerText: Color(0xFF2A241C),
      readerInfo: Color(0xFF6D675E),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: AppPalette.ink600,
      surface: Color(0xFF3A352F),
      bar: Color(0xFF47433B),
      text: AppPalette.ink50,
      textMuted: Color(0xFFA19A87),
      border: Color(0xFF464239),
      primary: AppPalette.cinnabarDark,
      secondary: AppPalette.gold,
      readerBackground: Color(0xFF14110D),
      readerMenu: Color(0xFF34302A),
      readerText: Color(0xFFCFC6B2),
      readerInfo: Color(0xFF938C7D),
      highlight: _amber,
    ),
  ),
  tea(
    '茶褐',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFD5CCBC),
      surface: Color(0xFFF6EEDD),
      bar: Color(0xFFF6EEDD),
      text: Color(0xFF2C2014),
      textMuted: Color(0xFF6B5840),
      border: Color(0xFFD2C2A2),
      primary: Color(0xFF7E5124),
      secondary: AppPalette.gold,
      readerBackground: Color(0xFFF0E4CA),
      readerMenu: Color(0xFFCFC2AB),
      readerText: Color(0xFF33241A),
      readerInfo: Color(0xFF6A5945),
      highlight: _apricot,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF1B140D),
      surface: Color(0xFF3B3329),
      bar: Color(0xFF494135),
      text: Color(0xFFEDDFC5),
      textMuted: Color(0xFFAE9D7F),
      border: Color(0xFF474034),
      primary: Color(0xFFD9A66B),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF18120B),
      readerMenu: Color(0xFF3A3124),
      readerText: Color(0xFFCDB892),
      readerInfo: Color(0xFF938367),
      highlight: _apricot,
    ),
  ),

  /// 閱讀紙與字取自 Legado 內建的「预设2」；深色是 Legado 的灰底，這裡
  /// 換成和茶褐同一類的近黑暖底。
  kraft(
    '牛皮紙',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFD2C5AD),
      surface: Color(0xFFF4E7CC),
      bar: Color(0xFFF4E7CC),
      text: Color(0xFF2E2416),
      textMuted: Color(0xFF6F5D40),
      border: Color(0xFFDDD0B7),
      primary: Color(0xFF86561C),
      secondary: AppPalette.gold,
      readerBackground: Color(0xFFDDC090),
      readerMenu: Color(0xFFB8A077),
      readerText: Color(0xFF3E3422),
      readerInfo: Color(0xFF55462D),
      highlight: _apricot,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF1A140B),
      surface: Color(0xFF3B3426),
      bar: Color(0xFF494232),
      text: Color(0xFFEEDDBA),
      textMuted: Color(0xFFAE9C78),
      border: Color(0xFF4B4434),
      primary: Color(0xFFDDA55C),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF19130A),
      readerMenu: Color(0xFF3B3222),
      readerText: Color(0xFFD6BF91),
      readerInfo: Color(0xFF958262),
      highlight: _apricot,
    ),
  ),
  bamboo(
    '竹青',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFD3D7CE),
      surface: Color(0xFFF6F9F0),
      bar: Color(0xFFF6F9F0),
      text: Color(0xFF1C2619),
      textMuted: Color(0xFF5A6854),
      border: Color(0xFFC9D4BC),
      primary: Color(0xFF4A6B45),
      secondary: Color(0xFFA0844A),
      readerBackground: Color(0xFFE4ECD6),
      readerMenu: Color(0xFFC1CAB6),
      readerText: Color(0xFF202D21),
      readerInfo: Color(0xFF56664F),
      highlight: _citron,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF101713),
      surface: Color(0xFF2F3730),
      bar: Color(0xFF3C443D),
      text: Color(0xFFDCE8D6),
      textMuted: Color(0xFF94A48E),
      border: Color(0xFF404741),
      primary: Color(0xFF8FB58A),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF0F1D19),
      readerMenu: Color(0xFF2D3E37),
      readerText: Color(0xFFB9D7C2),
      readerInfo: Color(0xFF839B8C),
      highlight: _citron,
    ),
  ),

  /// 閱讀紙與字照搬 Legado 內建的「微信读书」：淺色豆綠紙配近黑字，深色
  /// 純黑配灰字。
  bean(
    '豆綠',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFC7D5CA),
      surface: Color(0xFFEAF7EC),
      bar: Color(0xFFEAF7EC),
      text: Color(0xFF112016),
      textMuted: Color(0xFF4E6354),
      border: Color(0xFFD3E0D6),
      primary: Color(0xFF2F7445),
      secondary: AppPalette.gold,
      readerBackground: Color(0xFFC0EDC6),
      readerMenu: Color(0xFFA4C9A9),
      readerText: Color(0xFF0B0B0B),
      readerInfo: Color(0xFF4A5A4C),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: _black,
      surface: Color(0xFF252625),
      bar: Color(0xFF323332),
      text: Color(0xFFE6EDE7),
      textMuted: Color(0xFF929C94),
      border: Color(0xFF343534),
      primary: Color(0xFF8CC79A),
      secondary: AppPalette.teaDark,
      readerBackground: _black,
      readerMenu: Color(0xFF262626),
      readerText: Color(0xFFADADAD),
      readerInfo: Color(0xFF7A7A7A),
      highlight: _amber,
    ),
  );

  const AppStyle(this.label, {required this.light, required this.dark});

  final String label;
  final StylePalette light;
  final StylePalette dark;

  StylePalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 實際套用的配色：主色換成強調色在這個深淺的顏色（[AppAccent.theme]
  /// 照風格），深色且 [pureBlack] 時底色換成純黑（[StylePalette.toPureBlack]）。
  StylePalette paletteFor(
    Brightness brightness,
    AppAccent accent, {
    bool pureBlack = false,
  }) {
    var palette = of(brightness);
    if (pureBlack) palette = palette.toPureBlack();
    final color = accent.colorFor(brightness);
    return color == null ? palette : palette.copyWith(primary: color);
  }

  /// 讀回保存的名稱；認不得（含已經拿掉的風格）時用 [fallback]。
  static AppStyle fromStorage(String? value, {required AppStyle fallback}) =>
      AppStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => fallback,
      );
}

/// 強調色：開關、選取、勾勾、強調按鈕與純文字動作用的主色。預設跟隨風格；
/// 其他顏色各有一個淺色、一個深色版本，不分風格。
enum AppAccent {
  theme('跟隨主題'),
  cinnabar('朱紅', light: Color(0xFFA8322B), dark: Color(0xFFE8806F)),
  rouge('胭脂', light: Color(0xFFB4446C), dark: Color(0xFFF08FB0)),
  amber('琥珀', light: Color(0xFFB5530F), dark: Color(0xFFF59A4A)),
  tea('茶金', light: Color(0xFF8F6A1E), dark: Color(0xFFD9B061)),
  yellow('黃', light: Color(0xFF8A6D00), dark: Color(0xFFE8C547)),
  bamboo('竹綠', light: Color(0xFF3F7A34), dark: Color(0xFF8CC47E)),
  teal('青綠', light: Color(0xFF12796F), dark: Color(0xFF5CC6B8)),
  sky('天藍', light: Color(0xFF1F78B4), dark: Color(0xFF7CC3F0)),
  azurite('石青', light: Color(0xFF2F5F99), dark: Color(0xFF8AB4E8)),
  lotus('藕荷', light: Color(0xFF7446B8), dark: Color(0xFFBFA0F0)),
  gray('灰', light: Color(0xFF666666), dark: Color(0xFFA6A6A6)),
  ink('墨', light: Color(0xFF222222), dark: Color(0xFFE6E6E6));

  const AppAccent(this.label, {this.light, this.dark});

  final String label;
  final Color? light;
  final Color? dark;

  /// 這個深淺用的顏色；[theme] 沒有自己的顏色。
  Color? colorFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AppAccent fromStorage(String? value) => AppAccent.values.firstWhere(
    (accent) => accent.name == value,
    orElse: () => AppAccent.theme,
  );
}

/// 一個風格在某個深淺下的完整配色。
///
/// 以 [ThemeExtension] 掛在 App 主題上：閱讀器與選單一律經 [StylePalette.of]
/// 取色，因此和 App 介面永遠是同一個風格、同一個深淺。
@immutable
class StylePalette extends ThemeExtension<StylePalette> {
  const StylePalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.bar,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.readerBackground,
    required this.readerMenu,
    required this.readerText,
    required this.readerInfo,
    required this.highlight,
  });

  final Brightness brightness;

  /// App 頁面底色、卡片與面板底色、頁首與浮動分頁列等玻璃列的色調，照
  /// [AppLayers] 的分層規則算好：淺色頁面比卡片暗、玻璃與卡片同色；深色
  /// 卡片比頁面亮、玻璃再亮一階。
  final Color background;
  final Color surface;
  final Color bar;
  final Color text;
  final Color textMuted;
  final Color border;

  /// 主色：選取狀態、開關、強調按鈕。
  final Color primary;

  /// 點綴色。
  final Color secondary;

  /// 閱讀正文的紙張與文字。
  final Color readerBackground;
  final Color readerText;

  /// 閱讀選單與閱讀器內面板的底色：閱讀底色往閱讀文字色移（[AppLayers]），
  /// 淺色、深色都和紙分得開。
  final Color readerMenu;

  /// 閱讀器頁首／頁尾資訊列的文字與圖示。
  final Color readerInfo;

  /// 朗讀高亮與選字反白選「跟隨主題」時的顏色（實際以設定的深淺疊上）。
  final Color highlight;

  /// 疊在主色上的勾勾與文字：紙白、墨色中對主色對比較高的一個。
  Color get onPrimary =>
      _contrast(AppPalette.paper50, primary) >=
          _contrast(AppPalette.ink700, primary)
      ? AppPalette.paper50
      : AppPalette.ink700;

  /// 「深色用純黑」：App 頁面與閱讀紙換成純黑，卡片、玻璃列、分隔線與閱讀
  /// 選單照 [AppLayers] 從純黑往各自的字色重算，字色與主色不變，所以每個
  /// 風格在純黑上仍帶著自己的字色與卡片色調。淺色、或底色本來就是純黑的
  /// 深色原樣回傳。
  StylePalette toPureBlack() {
    if (brightness == Brightness.light ||
        (background == _black && readerBackground == _black)) {
      return this;
    }
    final card = AppLayers.step(_black, text, AppLayers.cardGapDark);
    final borderGap =
        AppLayers.lightness(border) - AppLayers.lightness(surface);
    return copyWith(
      background: _black,
      surface: card,
      bar: AppLayers.step(card, text, AppLayers.floatGapDark),
      textMuted: AppLayers.keepGap(textMuted, text, from: surface, to: card),
      border: AppLayers.step(card, text, borderGap.abs()),
      readerBackground: _black,
      readerMenu: AppLayers.step(_black, readerText, AppLayers.cardGapDark),
    );
  }

  /// 目前主題的配色；主題沒有掛擴充時以預設風格補上。
  static StylePalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StylePalette>() ??
        AppStyle.paper.of(theme.brightness);
  }

  @override
  StylePalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? bar,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? primary,
    Color? secondary,
    Color? readerBackground,
    Color? readerMenu,
    Color? readerText,
    Color? readerInfo,
    Color? highlight,
  }) {
    return StylePalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      bar: bar ?? this.bar,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      readerBackground: readerBackground ?? this.readerBackground,
      readerMenu: readerMenu ?? this.readerMenu,
      readerText: readerText ?? this.readerText,
      readerInfo: readerInfo ?? this.readerInfo,
      highlight: highlight ?? this.highlight,
    );
  }

  // 強調色會讓 [AppStyle.paletteFor] 每次 copyWith 出新物件；照值比較才能
  // 讓相同設定產生相等的 ThemeData，避免全 App 跟著重建（ADR 0029）。
  @override
  bool operator ==(Object other) =>
      other is StylePalette &&
      other.brightness == brightness &&
      other.background == background &&
      other.surface == surface &&
      other.bar == bar &&
      other.text == text &&
      other.textMuted == textMuted &&
      other.border == border &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.readerBackground == readerBackground &&
      other.readerMenu == readerMenu &&
      other.readerText == readerText &&
      other.readerInfo == readerInfo &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    surface,
    bar,
    text,
    textMuted,
    border,
    primary,
    secondary,
    readerBackground,
    readerMenu,
    readerText,
    readerInfo,
    highlight,
  );

  /// 換風格或深淺時不做漸變，在動畫中點一次切換：正文段落快取以文字色
  /// 為鍵，逐幀漸變會讓每一幀都重排正文。
  @override
  StylePalette lerp(ThemeExtension<StylePalette>? other, double t) {
    if (other is! StylePalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// WCAG 2.x 對比度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
