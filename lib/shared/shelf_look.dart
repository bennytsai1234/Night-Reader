// 書架列表的樣子：「整理」選單的「列表併成一面」（ADR 0079），跟著多台手機同步。
// 書架順序（預設封面的天空顏色）也記在這裡。
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ShelfLook {
  /// 書架列表併成一個面：書與書之間不留縫，只有第一本上緣、最後一本下緣是圓角。
  static final ValueNotifier<bool> mergedList = ValueNotifier<bool>(false);

  /// 開 App 時在第一幀前讀回來：書架骨架第一幀就照它排。書架順序同時清空，
  /// 測試之間不帶著上一個測試的書架。
  static void restore(SharedPreferences prefs) {
    readMergedList(prefs);
    setShelfOrder(const []);
  }

  /// 讀回「列表併成一面」；同步套用了另一台的設定時書架也照它重讀。
  static void readMergedList(SharedPreferences prefs) {
    mergedList.value = prefs.getBool(PreferKey.shelfMergedList) ?? false;
  }

  /// 書架上由上到下的位置，鍵是書的網址（`Book.bookUrl`）：同名的書，不論
  /// 作者、書源或類別，各自是一本、各有位置；預設封面照它排顏色。
  static Map<String, int> _order = const {};
  static int _total = 0;

  static void setShelfOrder(List<String> shown) {
    _order = {for (var i = 0; i < shown.length; i++) shown[i]: i};
    _total = shown.length;
  }

  /// 書換了書源、網址跟著換了（[BookSwitchedEvent]）：書架被蓋著時要露出來
  /// 才重讀，這之前新網址先沿用舊網址的位置，換源後重開的播放器封面才不會
  /// 變成中間的顏色。
  static void bookSwitched(BookSwitchedEvent event) {
    final index = _order[event.fromBookUrl];
    if (index == null) return;
    final order = Map.of(_order)..remove(event.fromBookUrl);
    order[event.toBookUrl] = index;
    _order = order;
  }

  /// 這本書在書架上的位置，0 是最上面、1 是最下面；不在書架上時是 null。
  static double? positionOf(String? bookUrl) {
    final index = bookUrl == null ? null : _order[bookUrl];
    if (index == null) return null;
    return _total <= 1 ? 0 : index / (_total - 1);
  }
}
