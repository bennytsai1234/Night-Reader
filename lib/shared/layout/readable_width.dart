import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// 平板上清單頁的內容欄：畫面比 [maxWidth] 寬時，內容置中、兩側留底色。
///
/// 和底部面板同寬（Material 3 底部面板預設最寬 640），打開面板時上下對齊；
/// 手機比它窄，版面不變。頁首按鈕的位置見 [headerInsetOf]；底部的浮動
/// 膠囊與工具列和卡片左右切齊（[cardInsetOf]）。
abstract final class ReadableWidth {
  /// 內容欄最寬的寬度，含分組卡片兩側的外距。
  static const double maxWidth = 640;

  /// 畫面寬 [width] 時內容欄兩側各讓出的寬度。
  static double sideOf(double width) => math.max(0.0, (width - maxWidth) / 2);

  /// 目前畫面內容欄兩側的內距。
  static EdgeInsets insetOf(BuildContext context) => EdgeInsets.symmetric(
    horizontal: sideOf(MediaQuery.sizeOf(context).width),
  );

  /// 卡片邊離螢幕邊的距離：內容欄邊再往內分組卡片的外距。底部的浮動膠囊
  /// 與工具列照這個寬度，和卡片左右切齊。
  static EdgeInsets cardInsetOf(BuildContext context) => EdgeInsets.symmetric(
    horizontal: sideOf(MediaQuery.sizeOf(context).width) + AppGrouped.margin,
  );

  /// 頁首按鈕外緣離螢幕邊的距離（畫面大小 [size]）。橫拿和卡片左右切齊；
  /// 直拿兩側留白窄，按鈕置中在留白裡，留白放不下時（手機）照卡片外距。
  static double headerInsetOf(Size size) {
    final side = sideOf(size.width);
    if (size.width >= size.height) return side + AppGrouped.margin;
    return math.max(AppGrouped.margin, side / 2 - AppGlass.buttonSize / 2);
  }
}
