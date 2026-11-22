import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 頁面、卡片與浮動元件的分層規則，所有風格、淺色與深色共用。
///
/// 差距以 CIELAB 明度差（ΔL*，人眼感受到的明暗差）表示。淺色卡片多已近白，
/// 頁面以卡片為準：明度低 [cardGapLight]、彩度乘 [pageChromaLight]、色相不變；
/// 深色頁面已近黑，卡片由頁面往文字色提亮。`StylePalette` 的底色照這組數字
/// 算好寫死，`app_style_test` 檢查每個風格都符合。
class AppLayers {
  AppLayers._();

  /// 頁面到卡片。原本淺色 3.9–5.5、深色 5.4–8.1，看久了分不出卡片；iOS 分組
  /// 清單淺色 4.4、深色 10.3。卡片與玻璃沒有框線（2026-10-21 使用者拿掉），
  /// 只靠底色分開，所以比加框時的 9／12 再拉開。深色同樣的差距看起來比較
  /// 小，多拉一些。
  static const double cardGapLight = 12;
  static const double cardGapDark = 15;

  /// 深色的玻璃列（頁首、分頁列）比卡片再亮一階；淺色玻璃與卡片同色，
  /// 靠貼邊陰影浮起來。
  static const double floatGapDark = 6;

  /// 深色的閱讀選單比紙亮多少；淺色比紙暗 [cardGapLight]。使用者
  /// 2026-11-22 在候選圖上選：「選單要和紙分得出來，對比要夠。淺色就選
  /// 比較暗的，深色就選比較亮的。」原本深色同頁面到卡片的 15，選單看起來
  /// 比 App 的彈出選單還暗。
  static const double readerMenuGapDark = 27;

  /// 對比調高時字色不動，底色往字的方向移；選單與面板卡片的底和選單上的
  /// 字至少留這麼多明度差，到了就停（[StylePalette.withContrast]）。
  static const double minTextGap = 45;

  static double cardGap(Brightness brightness) =>
      brightness == Brightness.dark ? cardGapDark : cardGapLight;

  /// 閱讀選單和紙的明度差（[readerMenuGapDark]）。
  static double readerMenuGap(Brightness brightness) =>
      brightness == Brightness.dark ? readerMenuGapDark : cardGapLight;

  /// 淺色頁面的彩度是卡片的幾倍，色相同卡片。卡片色往字色混出來的頁面
  /// 彩度和卡片差不多，但暗了 12 就顯得灰褐；拉高彩度，頁面才像比卡片深
  /// 一點的同一張紙（2026-11-18 使用者在候選圖上選）。素色沒有色調，不變。
  static const double pageChromaLight = 1.6;

  /// CIELAB 的明度、彩度與色相（度）。
  static ({double l, double c, double h}) lch(Color color) {
    double lin(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final r = lin(color.r), g = lin(color.g), b = lin(color.b);
    final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    final a = 500 * (f(x) - f(y)), bb = 200 * (f(y) - f(z));
    return (
      l: 116 * f(y) - 16,
      c: math.sqrt(a * a + bb * bb),
      h: (math.atan2(bb, a) * 180 / math.pi) % 360,
    );
  }

  /// 色調（彩度、色相）照 [tone]、明度是 [l] 的顏色。超出 sRGB 時降彩度，
  /// 明度維持 [l]。
  static Color withLightness(Color tone, double l) {
    final source = lch(tone);
    var chroma = source.c;
    for (var i = 0; i < 24; i++) {
      final color = _fromLch(l, chroma, source.h);
      if ((lightness(color) - l).abs() < 0.3 || chroma < 0.5) return color;
      chroma *= 0.85;
    }
    return _fromLch(l, 0, source.h);
  }

  /// [lch] 的反函數，超出 sRGB 的分量截到 0–1。
  static Color _fromLch(double l, double c, double h) {
    final a = c * math.cos(h * math.pi / 180);
    final b = c * math.sin(h * math.pi / 180);
    final fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
    double inv(double t) =>
        t * t * t > 0.008856 ? t * t * t : (t - 16 / 116) / 7.787;
    final x = inv(fx) * 0.95047, y = inv(fy), z = inv(fz) * 1.08883;
    int channel(double v) {
      final c = v.clamp(0.0, 1.0);
      final s = c <= 0.0031308
          ? 12.92 * c
          : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
      return (s * 255).round().clamp(0, 255);
    }

    return Color.fromARGB(
      255,
      channel(3.2406 * x - 1.5372 * y - 0.4986 * z),
      channel(-0.9689 * x + 1.8758 * y + 0.0415 * z),
      channel(0.0557 * x - 0.2040 * y + 1.0570 * z),
    );
  }

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

  /// 底色從 [from] 換成 [to] 而離 [color] 更近時，把 [color] 往 [toward] 移，
  /// 保持原本和底色的明度差；離得更遠就不動。用在次要文字換到另一層底上。
  static Color keepGap(
    Color color,
    Color toward, {
    required Color from,
    required Color to,
  }) {
    final l = lightness(color);
    final lost = (l - lightness(from)).abs() - (l - lightness(to)).abs();
    return lost > 0 ? step(color, toward, lost) : color;
  }

  /// 浮動玻璃貼著邊的那一圈陰影，補上散開的漫射陰影畫不出的邊界；深色
  /// 同樣的透明度看不出來，疊多一些。[shown] 0→1 是玻璃進出場的程度。
  static BoxShadow contactShadow({required bool dark, double shown = 1}) =>
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, (dark ? 0.5 : 0.12) * shown),
        blurRadius: 3,
        offset: const Offset(0, 1),
      );
}
