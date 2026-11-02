import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 設定的同步：清單裡的每個設定一筆（ADR 0039）。只同步閱讀、外觀、朗讀與
/// 書架的顯示這類兩台都該一樣的；這台手機自己的（亮度、螢幕方向、朗讀引擎與
/// 聲音、上次的骨架紀錄、更新頻道、同步空間本身）不在清單裡。設定回到預設
/// 值（從偏好設定移除）也跟著同步。
class SettingsSync extends SyncKind {
  SettingsSync({SharedPreferences? prefs})
    : _prefs = prefs ?? getIt<SharedPreferences>();

  final SharedPreferences _prefs;

  /// 套用了另一台的設定時加一：把設定讀進記憶體的地方（外觀、書架、朗讀）
  /// 聽它重讀，畫面馬上換過來。閱讀器的排版設定每次開書才讀，下次開書生效。
  static final ValueNotifier<int> applied = ValueNotifier(0);

  static const Set<String> keys = {
    // 外觀與主題
    PreferKey.themeMode,
    PreferKey.lightStyle,
    PreferKey.darkStyle,
    PreferKey.pureBlack,
    PreferKey.appAccent,
    PreferKey.glassStrength,
    PreferKey.pageTransition,
    // 書架與搜尋
    'bookshelf_is_grid',
    'bookshelf_show_last_update',
    'bookshelf_unified_covers',
    PreferKey.bookshelfSort,
    'precision_search',
    'search_blocked_words',
    PreferKey.autoRefresh,
    PreferKey.replaceEnableDefault,
    // 閱讀偏好與排版
    PreferKey.readerFontSize,
    PreferKey.readerTitleFontSize,
    PreferKey.readerLineHeight,
    PreferKey.readerParagraphSpacing,
    PreferKey.readerChapterSpacing,
    PreferKey.readerLetterSpacing,
    PreferKey.readerTextIndent,
    PreferKey.readerTitleSpacing,
    PreferKey.readerPaddingHorizontal,
    PreferKey.readerPaddingTop,
    PreferKey.readerPaddingBottom,
    PreferKey.readerFooterOffset,
    PreferKey.readerJustifyText,
    PreferKey.readerEdgeFade,
    PreferKey.readerHideStatusBar,
    PreferKey.readerHideNavigationBar,
    PreferKey.readerHeaderInfo,
    PreferKey.readerFooterInfo,
    PreferKey.readerUse24HourClock,
    PreferKey.readerProgressFractionDigits,
    PreferKey.readerChineseConvert,
    PreferKey.readerClickActions,
    PreferKey.readerVolumeKeyPage,
    PreferKey.readerVolumeKeyReversed,
    PreferKey.readerPageTurnOverlap,
    PreferKey.readerPageTurnSpeed,
    PreferKey.readerAutoPageSpeed,
    PreferKey.readerKeepScreenOn,
    PreferKey.readerMaxDim,
    PreferKey.readerHighlightColor,
    PreferKey.readerHighlightStrength,
    PreferKey.showAddToShelfAlert,
    // 朗讀
    PreferKey.readerTtsSpeedMultiplier,
    PreferKey.readerTtsPitch,
    PreferKey.readerTtsFollow,
    PreferKey.ttsTimer,
    PreferKey.ttsTimerCustomMinutes,
  };

  @override
  String get name => 'settings';

  @override
  Future<Map<String, SyncRecord>> local() async {
    final records = <String, SyncRecord>{};
    for (final key in keys) {
      final data = _encode(_prefs.get(key));
      if (data != null) records[key] = SyncRecord(time: 0, data: data);
    }
    return records;
  }

  static Map<String, Object?>? _encode(Object? value) => switch (value) {
    final bool v => {'t': 'bool', 'v': v},
    final int v => {'t': 'int', 'v': v},
    final double v => {'t': 'double', 'v': v},
    final String v => {'t': 'string', 'v': v},
    final List<String> v => {'t': 'list', 'v': v},
    _ => null,
  };

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (!keys.contains(key)) continue;
      if (record.deleted) {
        await _prefs.remove(key);
      } else if (!await _write(key, record.data)) {
        continue;
      }
      final now = _encode(_prefs.get(key));
      applied[key] = now == null
          ? const SyncRecord(time: 0, data: {}, deleted: true)
          : SyncRecord(time: 0, data: now);
    }
    if (applied.isNotEmpty) {
      if (applied.containsKey(PreferKey.readerChineseConvert)) {
        ChineseDisplay.mode.value =
            _prefs.getInt(PreferKey.readerChineseConvert) ?? 0;
      }
      SettingsSync.applied.value++;
    }
    return applied;
  }

  /// 寫一個設定；型別對不上（例如別的版本存成另一種）就不寫，留給下次。
  Future<bool> _write(String key, Map<String, Object?> data) {
    final value = data['v'];
    return switch ((data['t'], value)) {
      ('bool', final bool v) => _prefs.setBool(key, v),
      ('int', final int v) => _prefs.setInt(key, v),
      ('double', final num v) => _prefs.setDouble(key, v.toDouble()),
      ('string', final String v) => _prefs.setString(key, v),
      ('list', final List<Object?> v) when v.every((e) => e is String) =>
        _prefs.setStringList(key, v.cast<String>()),
      _ => Future.value(false),
    };
  }
}
