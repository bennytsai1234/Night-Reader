import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_tokens.dart';

/// 主頁底部分頁列（島）與右邊搜尋鈕的樣子，使用者在「外觀與主題」選
/// （DESIGN.md 設計原則 6 的例外，ADR 0074）。分頁列、搜尋鈕、疊在搜尋鈕
/// 上方的收聽圓鈕與書架編輯工具列都照它畫。
enum TabBarLook {
  /// 分頁列和卡片左右切齊，52 高；搜尋鈕一樣高。
  full('撐滿', tabItemHeight: 44, searchSize: 52, isCentered: false),

  /// 每個分頁 [centeredTabWidth] 寬，連同搜尋鈕置中。
  centered('置中', tabItemHeight: 44, searchSize: 52, isCentered: true),

  /// 同 [centered]，搜尋鈕放大成 64。
  centeredLargeSearch(
    '置中，搜尋鈕大',
    tabItemHeight: 44,
    searchSize: 64,
    isCentered: true,
  ),

  /// 和卡片左右切齊，64 高（預設；2026-11-19 改矮之前的樣子）。
  tall('撐滿，加高', tabItemHeight: 56, searchSize: 64, isCentered: false);

  const TabBarLook(
    this.label, {
    required this.tabItemHeight,
    required this.searchSize,
    required this.isCentered,
  });

  /// 選單上的名稱。
  final String label;

  /// 一個分頁（圖示加字）的高度；分頁列再加上下各 [AppGlass.tabInnerInset]。
  final double tabItemHeight;

  /// 搜尋鈕（與收聽圓鈕）的直徑。
  final double searchSize;

  /// 分頁的圖示：分頁 56 高時 24，44 高時 22。
  double get tabIconSize => tabItemHeight >= 56 ? 24 : 22;

  /// 搜尋鈕裡的圖示：鈕 64 時 26，52 時 24。
  double get searchIconSize => searchSize >= 64 ? 26 : 24;

  /// 分頁列連同搜尋鈕置中，每個分頁 [centeredTabWidth] 寬。
  final bool isCentered;

  /// 置中時每個分頁的寬度。
  static const double centeredTabWidth = 72;

  /// 分頁列的高度。
  double get barHeight => tabItemHeight + AppGlass.tabInnerInset * 2;

  /// 分頁列加搜尋鈕那一列的高度：兩者垂直置中，取高的那個。
  double get rowHeight => math.max(barHeight, searchSize);

  static const TabBarLook defaultLook = tall;

  /// 目前的樣子。開 App 時在第一幀前讀（[restore]）：分頁列在任何頁面之前
  /// 就畫了。
  static final ValueNotifier<TabBarLook> current = ValueNotifier(defaultLook);

  /// 2026-11-20 前「分頁列置中」是書架「整理」選單裡的試用開關；開著的
  /// 換成 [centered]，讀完就刪。
  static const String _trialKey = 'trial_compact_tab_bar';

  /// 從偏好設定讀回來（開 App 時、同步套用了另一台的設定時）。
  static void restore(SharedPreferences prefs) {
    if (prefs.getBool(_trialKey) case final trial?) {
      if (prefs.getString(PreferKey.tabBarLook) == null) {
        prefs.setString(PreferKey.tabBarLook, _ofTrial(trial: trial).name);
      }
      prefs.remove(_trialKey);
    }
    current.value = fromStorage(prefs.getString(PreferKey.tabBarLook));
  }

  /// 還原的備份裡的偏好設定：只有 2026-11-20 前的試用開關、沒有這個設定時，
  /// 照備份當時的開關換成對應的樣子（開著是置中、關著是撐滿），不讓手機上
  /// 現在選的蓋過備份；試用的鍵不寫回去。
  static Map<String, dynamic> migrateBackup(Map<String, dynamic> values) {
    final trial = values[_trialKey];
    if (trial is! bool) return values;
    return {
      for (final entry in values.entries)
        if (entry.key != _trialKey) entry.key: entry.value,
      PreferKey.tabBarLook:
          values[PreferKey.tabBarLook] ?? _ofTrial(trial: trial).name,
    };
  }

  /// 試用開關關著時看到的是當時的預設撐滿，不是現在的預設。
  static TabBarLook _ofTrial({required bool trial}) => trial ? centered : full;

  static TabBarLook fromStorage(String? name) =>
      values.firstWhere((look) => look.name == name, orElse: () => defaultLook);
}
