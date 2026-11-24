import 'dart:convert';

import 'package:night_reader/core/models/source/rule_data_interface.dart';

/// 還沒有書的規則上下文（Legado `RuleData`）：搜尋、發現網址的 JS 用
/// `java.put` 存的變數先放這裡，解析出來的每本書都帶一份（[variableJson]）。
class RuleData implements RuleDataInterface {
  @override
  final Map<String, String> variableMap = {};

  @override
  void putVariable(String key, String? value) {
    if (value == null) {
      variableMap.remove(key);
    } else {
      variableMap[key] = value;
    }
  }

  @override
  String getVariable(String key) => variableMap[key] ?? '';

  /// 存過的變數寫成書的 `variable` 欄；沒有時是 null。
  String? get variableJson =>
      variableMap.isEmpty ? null : jsonEncode(variableMap);
}
