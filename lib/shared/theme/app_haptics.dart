import 'package:flutter/services.dart';

/// App 介面（閱讀器以外）的觸感回饋，依時機命名，不直接呼叫 [HapticFeedback]。
///
/// 三種強度對應三種時機，同類操作在各處感覺一致：
/// - [select]：選項或數值改變（開關、分段、多選勾選、數值步進）。
/// - [snap]：越過門檻或放到定位（左右滑動作到達觸發距離、拖曳排序放下）。
/// - [lift]：長按拿起項目（情境預覽選單、拖曳排序開始）。
abstract final class AppHaptics {
  /// 選項或數值改變時的輕微「喀」一聲。
  static void select() => HapticFeedback.selectionClick();

  /// 越過門檻或放到定位時的輕震。
  static void snap() => HapticFeedback.lightImpact();

  /// 長按拿起項目時的中等震動，比點擊更明確地表示「已進入另一種操作」。
  static void lift() => HapticFeedback.mediumImpact();
}
