import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 頁面、卡片與浮動元件的分層規則，五種風格、淺色與深色共用。
///
/// 差距以 CIELAB 明度差（ΔL*，人眼感受到的明暗差）表示。淺色卡片多已近白，
/// 由頁面往文字色退；深色頁面已近黑，由卡片往文字色提亮。`StylePalette`
/// 的底色照這組數字算好寫死，`app_style_test` 檢查每個風格都符合。
class AppLayers {
  AppLayers._();

  /// 頁面到卡片。原本淺色 3.9–5.5、深色 5.4–8.1，看久了分不出卡片；iOS 分組
  /// 清單淺色 4.4、深色 10.3。深色同樣的差距看起來比較小，多拉一些。
  static const double cardGapLight = 9;
  static const double cardGapDark = 12;

  /// 深色的玻璃列（頁首、分頁列）比卡片再亮一階；淺色玻璃與卡片同色，
  /// 靠框線與貼邊陰影浮起來。閱讀選單和閱讀底色的差距同頁面到卡片。
  static const double floatGapDark = 6;

  /// 框線和它所在的面的差距與寬度。0.5 的髮絲在 3 倍密度上只有 1.5 個
  /// 像素，淺色、深色都看不出來。
  static const double edgeGap = 24;
  static const double edgeWidth = 1;

  static double cardGap(Brightness brightness) =>
      brightness == Brightness.dark ? cardGapDark : cardGapLight;

  /// CIELAB 明度 L*（0–100）。
  static double lightness(Color color) {
    final y = color.computeLuminance();
    return y > 0.008856 ? 116 * math.pow(y, 1 / 3) - 16 : 903.3 * y;
  }

  /// 把 [from] 往 [toward] 混到明度差 [gap]；混到底還不夠就是 [toward]。
  static Color step(Color from, Color toward, double gap) {
    final base = lightness(from);
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      final mixed = Color.alphaBlend(toward.withValues(alpha: mid), from);
      if ((lightness(mixed) - base).abs() < gap) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return Color.alphaBlend(toward.withValues(alpha: hi), from);
  }

  /// 畫在 [surface] 上的框線色。
  static Color edgeOn(Color surface, Color text) =>
      step(surface, text, edgeGap);

  /// 浮動玻璃貼著邊的那一圈陰影，補上散開的漫射陰影畫不出的邊界；深色
  /// 同樣的透明度看不出來，疊多一些。[shown] 0→1 是玻璃進出場的程度。
  static BoxShadow contactShadow({required bool dark, double shown = 1}) =>
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, (dark ? 0.5 : 0.12) * shown),
        blurRadius: 3,
        offset: const Offset(0, 1),
      );
}
