import 'package:flutter/widgets.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/services/chinese_utils.dart';

/// 書籍資訊的顯示時繁簡轉換：書名、作者、簡介、分類與章節標題。
///
/// 繁簡轉換只改「顯示」，不改資料：資料庫、書源回傳的書與閱讀紀錄一律
/// 保留原文，否則換源與進度對應都會失準。搜尋另外處理：關鍵字原文之外
/// 也送另一種寫法，比對時繁簡視為相同（`normalizeSearchText`），與這裡的
/// 顯示模式無關。
///
/// 轉換模式與閱讀設定的「繁簡轉換」為同一個值
/// （0：不轉換、1：簡轉繁、2：繁轉簡），由 ReaderV2SettingsController
/// 在載入與變更時同步；App 啟動時由 [dictionaryReady] 載入。
abstract final class ChineseDisplay {
  static final ChineseDisplayMode mode = ChineseDisplayMode();
  static const ChineseTextConverter _converter = ChineseTextConverter();

  /// 字典在背景載入；載入完成前轉換會原樣返回，完成後要讓已顯示的
  /// 文字重建一次。
  static void dictionaryReady(int? storedMode) {
    mode.value = storedMode ?? mode.value;
    mode.refresh();
  }

  static String convert(String text, {int? convertType}) {
    final type = convertType ?? mode.value;
    if (text.isEmpty || type == 0) return text;
    // 字典還沒載入時原樣返回，這時的結果不記。
    if (!ChineseUtils.isInitialized || text.length > _cacheMaxLength) {
      return _converter.convert(text, convertType: type);
    }
    final cache = _cache.putIfAbsent(type, () => <String, String>{});
    final cached = cache.remove(text);
    if (cached != null) return cache[text] = cached;
    final converted = _converter.convert(text, convertType: type);
    cache[text] = converted;
    if (cache.length > _cacheMaxEntries) cache.remove(cache.keys.first);
    return converted;
  }

  /// 書名、作者、簡介這類顯示文字在每次重建時都會再轉一次（搜尋結果串流
  /// 進來時一秒重建好幾次），所以記下最近轉過的。依轉換方向分開，各留
  /// 最近用到的 [_cacheMaxEntries] 筆；超過 [_cacheMaxLength] 字的（例如
  /// 整段簡介以外的長文）不記。上限約幾 MB。
  static final Map<int, Map<String, String>> _cache = {};
  static const int _cacheMaxEntries = 2000;
  static const int _cacheMaxLength = 512;
}

final class ChineseDisplayMode extends ValueNotifier<int> {
  ChineseDisplayMode() : super(0);

  void refresh() => notifyListeners();
}

/// 讓畫面在轉換模式變更時自動重建；掛在 MaterialApp.builder 之下，
/// 所有頁面都在其範圍內。
class ChineseDisplayScope extends InheritedNotifier<ValueNotifier<int>> {
  ChineseDisplayScope({super.key, required super.child})
    : super(notifier: ChineseDisplay.mode);
}

extension ChineseDisplayContext on BuildContext {
  /// 以目前的繁簡轉換模式顯示書籍資訊文字，並登記模式變更時重建。
  String zh(String text) {
    final notifier =
        dependOnInheritedWidgetOfExactType<ChineseDisplayScope>()?.notifier;
    return ChineseDisplay.convert(
      text,
      convertType: notifier?.value ?? ChineseDisplay.mode.value,
    );
  }
}
