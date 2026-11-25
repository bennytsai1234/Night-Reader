import 'dart:convert';

import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';

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

/// 匯入預覽裡一條規則和這台的關係（Legado 匯入規則的「新增」「更新」
/// 「已有」）：用編號對，舊流水號另看規則本身（[_stateOf]）。
enum ReplaceRuleImportState {
  /// 這台沒有這個編號，或舊流水號撞到這台另一條規則（會配新編號）。
  added('新增'),

  /// 這台有同一條，有任何一欄不一樣（名稱、分組、開關也算，順序不算）：
  /// 匯入會蓋掉這台的。
  updated('更新'),

  /// 這台有同一條，每一欄都一樣（順序不算）。
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
        ReplaceRuleImportItem(rule, _stateOf(rule, local[rule.id])),
    ],
    invalidCount: rules.length - valid.length,
  );
}

/// [incoming] 和這台同號的 [mine] 是什麼關係。舊流水號（1、2、3……）撞號、
/// 規則本身不同時是別條規則：當成新增，編號清成 0，寫入時配一個新的，兩條
/// 都留，不蓋掉這台的那條（同同步的做法，ADR 0039、[ReplaceRuleSync.reconcile]）。
ReplaceRuleImportState _stateOf(ReplaceRule incoming, ReplaceRule? mine) {
  if (mine == null) return ReplaceRuleImportState.added;
  if (_sameContent(mine, incoming)) return ReplaceRuleImportState.unchanged;
  if (incoming.id < ReplaceRuleSync.firstTimeId &&
      _identity(mine) != _identity(incoming)) {
    incoming.id = 0;
    return ReplaceRuleImportState.added;
  }
  return ReplaceRuleImportState.updated;
}

/// 規則本身（找什麼、換成什麼、套用在哪），同同步認同一條的方式。
String _identity(ReplaceRule rule) =>
    ReplaceRuleSync.identityOf(ReplaceRuleSync.recordOf(rule));

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
