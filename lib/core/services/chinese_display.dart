import 'package:flutter/widgets.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';

/// 書籍資訊的顯示時繁簡轉換：書名、作者、簡介、分類與章節標題。
///
/// 繁簡轉換只改「顯示」，不改資料：資料庫、搜尋比對、書源請求與閱讀
/// 紀錄一律使用原文，否則換源、搜尋與進度對應都會失準。
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
    return _converter.convert(text, convertType: convertType ?? mode.value);
  }
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
