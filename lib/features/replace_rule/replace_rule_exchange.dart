import 'dart:convert';

import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';

// 替換規則的匯入、匯出與複製貼上用的 JSON（同 Legado 的 `ReplaceRule`）。
// 匯出、複製寫 Legado 讀得懂的樣子（[ReplaceRule.toLegadoJson]）；讀的時候
// 開關寫 `1`／`0` 或 `true`／`false` 都認得。

/// 匯出一批規則：一個陣列，順序照傳進來的（套用的順序）。
String encodeReplaceRules(Iterable<ReplaceRule> rules) =>
    jsonEncode([for (final rule in rules) rule.toLegadoJson()]);

/// 複製一條規則：一個物件（同 Legado 編輯頁的「複製規則」）。
String encodeReplaceRule(ReplaceRule rule) => jsonEncode(rule.toLegadoJson());

/// 讀匯入的規則：一個陣列，或只有一條的物件。不是 JSON、不是物件或陣列
/// 時丟出 [FormatException]；陣列裡不是物件的跳過。
List<ReplaceRule> decodeReplaceRules(String text) {
  final decoded = jsonDecode(text.trim());
  final items = switch (decoded) {
    Map() => [decoded],
    List() => decoded,
    _ => throw const FormatException('替換規則格式不正確'),
  };
  return [
    for (final item in items)
      if (item is Map) ReplaceRule.fromJson(Map<String, dynamic>.from(item)),
  ];
}

/// 從剪貼簿貼上一條規則：一個物件，或只有一條的陣列。不是規則（讀不成
/// JSON、沒有「替換內容」、不只一條）時回傳 null。
ReplaceRule? decodeOneReplaceRule(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final List<ReplaceRule> rules;
  try {
    rules = decodeReplaceRules(text);
  } on FormatException {
    return null;
  }
  if (rules.length != 1 || rules.single.pattern.isEmpty) return null;
  return rules.single;
}

/// 匯入預覽裡一條規則和這台的關係（同 Legado 匯入規則的「新增」「更新」
/// 「已有」）：用編號對。
enum ReplaceRuleImportState {
  /// 這台沒有這個編號。
  added('新增'),

  /// 這台有同一個編號，內容不一樣：匯入會蓋掉這台的。
  updated('更新'),

  /// 這台有同一條，內容一樣（順序不算）。
  unchanged('已有');

  const ReplaceRuleImportState(this.label);

  final String label;
}

class ReplaceRuleImportItem {
  const ReplaceRuleImportItem(this.rule, this.state);

  final ReplaceRule rule;
  final ReplaceRuleImportState state;

  /// 預設只勾新的；這台已有的多半是改過的，不預設蓋掉（同 Legado）。
  bool get selectedByDefault => state == ReplaceRuleImportState.added;
}

class ReplaceRuleImportPreview {
  const ReplaceRuleImportPreview({
    required this.items,
    required this.invalidCount,
  });

  /// 檔案裡每一條能用的規則，照檔案的順序。
  final List<ReplaceRuleImportItem> items;

  /// 空的或正則寫錯的規則（`ReplaceRule.isValid`），不列、不匯入。
  final int invalidCount;

  List<ReplaceRule> get defaultSelection => [
    for (final item in items)
      if (item.selectedByDefault) item.rule,
  ];
}

/// 解析 [text]、和這台的規則對編號，給匯入預覽用。格式不對時丟出
/// [FormatException]。
Future<ReplaceRuleImportPreview> previewReplaceRuleImport(
  String text,
  ReplaceRuleDao dao,
) async {
  final rules = decodeReplaceRules(text);
  final valid = [
    for (final rule in rules)
      if (rule.isValid()) rule,
  ];
  final local = {for (final rule in await dao.getAll()) rule.id: rule};
  return ReplaceRuleImportPreview(
    items: [
      for (final rule in valid)
        ReplaceRuleImportItem(rule, switch (local[rule.id]) {
          null => ReplaceRuleImportState.added,
          final mine when _sameContent(mine, rule) =>
            ReplaceRuleImportState.unchanged,
          _ => ReplaceRuleImportState.updated,
        }),
    ],
    invalidCount: rules.length - valid.length,
  );
}

/// 寫入勾選的規則：照各自的編號存，已有的蓋掉，沒有編號的配新的；回傳
/// 寫了幾條。
Future<int> importReplaceRules(
  List<ReplaceRule> rules,
  ReplaceRuleDao dao,
) async {
  if (rules.isEmpty) return 0;
  await dao.upsertAll(rules);
  return rules.length;
}

bool _sameContent(ReplaceRule a, ReplaceRule b) {
  Map<String, dynamic> content(ReplaceRule rule) =>
      rule.toJson()..remove('order');
  final left = content(a);
  final right = content(b);
  return left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}
