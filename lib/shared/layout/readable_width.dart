import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// 平板上清單頁的內容欄：畫面比 [maxWidth] 寬時，內容置中、兩側留底色。
///
/// 和底部面板同寬（Material 3 底部面板預設最寬 640），打開面板時上下對齊；
/// 手機比它窄，版面不變。頁首按鈕放在兩側留白的正中間（[headerInsetOf]）。
abstract final class ReadableWidth {
  /// 內容欄最寬的寬度，含分組卡片兩側的外距。
  static const double maxWidth = 640;

  /// 畫面寬 [width] 時內容欄兩側各讓出的寬度。
  static double sideOf(double width) => math.max(0.0, (width - maxWidth) / 2);

  /// 目前畫面內容欄兩側的內距。
  static EdgeInsets insetOf(BuildContext context) => EdgeInsets.symmetric(
    horizontal: sideOf(MediaQuery.sizeOf(context).width),
  );

  /// 頁首按鈕離螢幕邊的距離：按鈕置中在內容欄與螢幕邊之間的留白裡，留白
  /// 放不下時照分組卡片的外距（手機）。
  static double headerInsetOf(double width) =>
      math.max(AppGrouped.margin, sideOf(width) / 2 - AppGlass.buttonSize / 2);
}
