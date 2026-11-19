// 試用開關（DESIGN.md 設計原則 6）：書架列表與分頁列的兩種版面，使用者日常用過再選；
// 選定後拿掉這個檔案、兩個開關與書架「整理」選單裡的兩項，只留選中的做法。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ShelfTrial {
  /// 書架列表併成一個面：書與書之間不留縫，只有第一本上緣、最後一本下緣是圓角。
  static final ValueNotifier<bool> mergedList = ValueNotifier<bool>(false);

  /// 分頁列置中縮小：每個分頁 72 寬，連同搜尋鈕置中，不再和卡片左右切齊。
  static final ValueNotifier<bool> compactTabBar = ValueNotifier<bool>(false);

  static const String mergedListKey = 'trial_shelf_merged_list';
  static const String compactTabBarKey = 'trial_compact_tab_bar';

  /// 開 App 時在第一幀前讀回來：分頁列在書架頁之前就畫了，不能等書架讀設定。
  static void restore(SharedPreferences prefs) {
    mergedList.value = prefs.getBool(mergedListKey) ?? false;
    compactTabBar.value = prefs.getBool(compactTabBarKey) ?? false;
  }

  /// 置中縮小時每個分頁的寬度。
  static const double compactTabWidth = 72;

  /// 書架上由上到下的位置，鍵是畫面上顯示的書名（繁簡轉換後）；預設封面照它排顏色。
  static Map<String, int> _order = const {};
  static int _total = 0;

  static void setShelfOrder(List<String> shownNames) {
    _order = {for (var i = 0; i < shownNames.length; i++) shownNames[i]: i};
    _total = shownNames.length;
  }

  /// 這本書在書架上的位置，0 是最上面、1 是最下面；不在書架上時是 null。
  static double? positionOf(String shownName) {
    final index = _order[shownName];
    if (index == null) return null;
    return _total <= 1 ? 0 : index / (_total - 1);
  }
}
