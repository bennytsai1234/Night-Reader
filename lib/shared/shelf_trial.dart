// 試用開關（DESIGN.md 設計原則 6）：書架列表的版面，使用者日常用過再選；選定後拿掉
// 開關與書架「整理」選單裡的那一項，只留選中的做法。書架順序（預設封面的天空顏色）
// 也記在這裡。
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ShelfTrial {
  /// 書架列表併成一個面：書與書之間不留縫，只有第一本上緣、最後一本下緣是圓角。
  static final ValueNotifier<bool> mergedList = ValueNotifier<bool>(false);

  static const String mergedListKey = 'trial_shelf_merged_list';

  /// 開 App 時在第一幀前讀回來：書架骨架第一幀就照它排。書架順序同時清空，
  /// 測試之間不帶著上一個測試的書架。
  static void restore(SharedPreferences prefs) {
    mergedList.value = prefs.getBool(mergedListKey) ?? false;
    setShelfOrder(const []);
  }

  /// 書架上由上到下的位置，鍵是畫面上顯示的書名（繁簡轉換後）加書的類別
  /// （同名的小說、漫畫、有聲書是不同的書，ADR 0053）；預設封面照它排顏色。
  static Map<(String, BookSourceKind), int> _order = const {};
  static int _total = 0;

  static void setShelfOrder(List<(String, BookSourceKind)> shown) {
    _order = {for (var i = 0; i < shown.length; i++) shown[i]: i};
    _total = shown.length;
  }

  /// 這本書在書架上的位置，0 是最上面、1 是最下面；不在書架上時是 null。
  static double? positionOf(String shownName, BookSourceKind kind) {
    final index = _order[(shownName, kind)];
    if (index == null) return null;
    return _total <= 1 ? 0 : index / (_total - 1);
  }
}
