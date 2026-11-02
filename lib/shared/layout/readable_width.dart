import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 平板上清單頁的內容欄：畫面比 [maxWidth] 寬時，內容置中、兩側留底色。
///
/// 原型：候選圖用 [maxWidth] 與 [headerFollows] 切換，使用者選定後定成常數。
abstract final class ReadableWidth {
  /// 內容欄最寬的寬度（含分組卡片兩側的外距）；無限大表示不設上限。
  static double maxWidth = double.infinity;

  /// 頁首的返回鈕與右側按鈕跟著內容欄，不貼螢幕兩邊。
  static bool headerFollows = false;

  /// 寬度為 [width] 時內容欄兩側各要讓出的寬度。
  static double sideOf(double width) =>
      maxWidth.isFinite ? math.max(0.0, (width - maxWidth) / 2) : 0.0;

  /// 目前畫面內容欄兩側的內距。
  static EdgeInsets insetOf(BuildContext context) {
    final side = sideOf(MediaQuery.sizeOf(context).width);
    return EdgeInsets.symmetric(horizontal: side);
  }
}
