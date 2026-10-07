import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Primitive color palette — 夜讀 (Yè Dú) Design Tokens
class AppPalette {
  AppPalette._();

  // Pigments
  static const Color cinnabar = Color(0xFF7E2E2A); // primary light
  static const Color cinnabarDark = Color(0xFFD67B6E); // primary dark
  static const Color tea = Color(0xFF8A6F3A); // warning light
  static const Color teaDark = Color(0xFFC7A867); // warning dark
  static const Color azurite = Color(0xFF4B6E8C); // info light
  static const Color azuriteDark = Color(0xFF8FB0C9); // info dark
  static const Color rust = Color(0xFFB0463A); // danger light
  static const Color rustDark = Color(0xFFD98B7E); // danger dark
  static const Color moss = Color(0xFF5F7355); // success light
  static const Color mossDark = Color(0xFF9DB38F); // success dark
  static const Color gold = Color(0xFFB6914A); // highlight
  static const Color aubergine = Color(0xFF6B5570); // cover pigment

  // Paper (Light mode surfaces)
  static const Color paper50  = Color(0xFFFFFBF2);
  static const Color paper100 = Color(0xFFFAF5E9);
  static const Color paper200 = Color(0xFFF4EFE3);
  static const Color paper300 = Color(0xFFECE5D4);
  static const Color paper400 = Color(0xFFDCD2BD);

  // Ink (Dark mode surfaces & text)
  static const Color ink50  = Color(0xFFF4EDD7);
  static const Color ink100 = Color(0xFFC8C0AC);
  static const Color ink200 = Color(0xFF8A8473);
  static const Color ink300 = Color(0xFF5F5A4D);
  static const Color ink400 = Color(0xFF3D392F);
  static const Color ink500 = Color(0xFF2A271E);
  static const Color ink600 = Color(0xFF1A1612);
  static const Color ink700 = Color(0xFF100D0A);
  static const Color ink900 = Color(0xFF060403);
}

/// Spacing scale (logical pixels).
class AppSpacing {
  AppSpacing._();
  static const double xs   = 4.0;
  static const double sm   = 6.0;
  static const double md   = 10.0;
  static const double lg   = 14.0;
  static const double xl   = 20.0;
  static const double xxl  = 28.0;
  static const double xxxl = 40.0;
}

/// Border-radius tokens.
class AppRadius {
  AppRadius._();
  static const double xs   = 4.0;
  static const double sm   = 6.0;
  static const double md   = 10.0;
  static const double lg   = 14.0;
  static const double xl   = 20.0;
  static const double pill = 999.0;

  static const BorderRadius cardXs    = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius cardSm    = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius cardMd    = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cardLg    = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardXl    = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillShape = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius topSheetLg =
      BorderRadius.vertical(top: Radius.circular(lg));
  static const BorderRadius topSheetXl =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// 分組清單幾何（Telegram iOS inset-grouped 清單的紙墨版本）。
class AppGrouped {
  AppGrouped._();

  /// 分組卡片與螢幕左右的距離；組標題、說明文字與列內文字也以此對齊。
  static const double margin = 16.0;

  /// 列內左右內距。
  static const double rowPadding = 16.0;

  /// 單行列最小高度（iOS 觸控目標）。
  static const double rowMinHeight = 44.0;

  /// 帶副標的列最小高度。
  static const double rowTallMinHeight = 60.0;

  /// 分組之間的垂直間距。
  static const double sectionGap = AppSpacing.xxl;

  /// 分組卡片圓角。
  static const double radius = AppRadius.lg;
  static const BorderRadius cardRadius = AppRadius.cardLg;

  /// 列首上色圖示方塊。
  static const double iconTile = 29.0;
  static const double iconTileRadius = 7.0;
  static const double iconGap = 14.0;

  /// 有列首圖示時分隔線從文字起點開始。
  static const double separatorIndentWithIcon = rowPadding + iconTile + iconGap;
}

/// 浮動玻璃元件（分頁列、圓形按鈕、選單）的幾何與材質參數。
class AppGlass {
  AppGlass._();

  /// 浮動分頁列：56 高的分頁項，加上下各 4 的內距。
  static const double tabItemHeight = 56.0;
  static const double tabInnerInset = 4.0;
  static const double tabBarHeight = tabItemHeight + tabInnerInset * 2;
  static const double tabBarMaxWidth = 500.0;
  static const double tabBarGap = 8.0;

  /// 分頁列與螢幕底部系統區之間的距離。
  static const double tabBarBottomGap = 8.0;

  /// 浮動分頁列在內容底部需要讓出的總高度（不含系統區）。
  static const double tabBarOccupiedHeight =
      tabBarHeight + tabBarBottomGap + AppSpacing.md;

  /// 圓形玻璃按鈕。
  static const double buttonSize = 44.0;

  /// 導航頁首工具列高度與下緣漸隱高度。
  static const double headerToolbarHeight = 52.0;
  static const double headerFadeHeight = 14.0;

  /// 模糊與色調透明度由使用者選擇的 `GlassStrength`（app_chrome.dart）決定。
  static const double hairline = 0.5;

  /// 情境選單寬度與列高。
  static const double menuWidth = 250.0;
  static const double menuRowHeight = 44.0;
}

/// 動態參數。
class AppMotion {
  AppMotion._();

  /// 淡入淡出（Telegram 0.25s easeInOut）。
  static const Duration fade = Duration(milliseconds: 250);
  static const Curve fadeCurve = Curves.easeInOut;

  /// 選單、面板滑入。
  static const Duration menu = Duration(milliseconds: 200);
  static const Curve menuCurve = Curves.easeOutCubic;

  /// 分頁選取指示、按壓回彈等彈簧動畫（Telegram spring 0.4s）。
  static const Duration spring = Duration(milliseconds: 400);
  static const Curve springCurve = AppSpringCurve();
}

/// 以臨界阻尼附近的彈簧模擬產生的曲線；用於 [AnimationController] 等只接受
/// [Curve] 的位置，讓位移帶一點自然的收尾回彈。
class AppSpringCurve extends Curve {
  const AppSpringCurve({this.bounce = 0.12});

  /// 0 為無回彈；Telegram 的選取指示大約有輕微回彈。
  final double bounce;

  @override
  double transformInternal(double t) {
    // 阻尼振盪：x(t) = 1 - e^(-ζωt) * (cos(ωd t) + ζω/ωd sin(ωd t))
    const omega = 9.0;
    final zeta = 1.0 - bounce;
    final omegaD = omega * math.sqrt(1 - zeta * zeta + 1e-9);
    final decay = math.exp(-zeta * omega * t);
    final value =
        1 -
        decay *
            (math.cos(omegaD * t) + (zeta * omega / omegaD) * math.sin(omegaD * t));
    // 在 t = 1 精確收斂到 1。
    final end =
        1 -
        math.exp(-zeta * omega) *
            (math.cos(omegaD) + (zeta * omega / omegaD) * math.sin(omegaD));
    return value / end;
  }
}
