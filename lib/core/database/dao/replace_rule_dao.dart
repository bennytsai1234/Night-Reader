import 'package:drift/drift.dart';

import '../../models/replace_rule.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'replace_rule_dao.g.dart';

@DriftAccessor(tables: [ReplaceRules])
class ReplaceRuleDao extends DatabaseAccessor<AppDatabase>
    with _$ReplaceRuleDaoMixin {
  ReplaceRuleDao(super.db);

  Future<List<ReplaceRule>> getAll() {
    return (select(
      replaceRules,
    )..orderBy([(t) => OrderingTerm(expression: t.order)])).get();
  }

  Stream<List<ReplaceRule>> watchAll() {
    return (select(
      replaceRules,
    )..orderBy([(t) => OrderingTerm(expression: t.order)])).watch();
  }

  /// 存一條規則；還沒有編號（id 為 0）的是新規則，配一個編號（[_assignIds]）。
  Future<void> upsert(ReplaceRule rule) async {
    await _assignIds([rule]);
    await into(replaceRules).insertOnConflictUpdate(_toInsertable(rule));
  }

  /// 新增一條規則，回傳它的 id。
  Future<int> insert(ReplaceRule rule) async {
    await _assignIds([rule]);
    return into(replaceRules).insert(_toInsertable(rule));
  }

  Future<void> upsertAll(List<ReplaceRule> rules) async {
    await _assignIds(rules);
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        replaceRules,
        rules.map(_toInsertable).toList(),
      ),
    );
  }

  /// 規則換編號（同步時兩台的舊規則同號不同內容，把這台的換開）。
  Future<void> changeId(int from, int to) =>
      (update(replaceRules)..where((t) => t.id.equals(from))).write(
        ReplaceRulesCompanion(id: Value(to)),
      );

  /// 一個沒用過的新編號，用法同 [_assignIds]。
  Future<int> newId() async => (await _newIds(1)).single;

  /// 新規則的編號用建立的時間（毫秒，同 Legado）：兩台手機各自新增的規則
  /// 不會撞號，同步時分得開（ADR 0039）。直接寫進 [rules]，呼叫端拿得到。
  Future<void> _assignIds(List<ReplaceRule> rules) async {
    final missing = [
      for (final rule in rules)
        if (rule.id <= 0) rule,
    ];
    if (missing.isEmpty) return;
    final ids = await _newIds(missing.length);
    for (var i = 0; i < missing.length; i++) {
      missing[i].id = ids[i];
    }
  }

  /// 同一毫秒要好幾個、或現在的時間比已有的編號小時，接在最大的後面。
  Future<List<int>> _newIds(int count) async {
    final maxId = replaceRules.id.max();
    final largest =
        await (selectOnly(
          replaceRules,
        )..addColumns([maxId])).map((row) => row.read(maxId)).getSingle() ??
        0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now > largest ? now : largest + 1;
    return [for (var i = 0; i < count; i++) start + i];
  }

  Future<void> deleteById(int id) =>
      (delete(replaceRules)..where((t) => t.id.equals(id))).go();

  Future<List<ReplaceRule>> getEnabled() {
    return (select(replaceRules)
          ..where((t) => t.isEnabled.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.order)]))
        .get();
  }

  Future<List<ReplaceRule>> getEnabledForBook(String name, String origin) {
    return _getEnabledScoped(
      name: name,
      origin: origin,
      scopePredicateSql: '(scopeContent = 1 OR scopeTitle = 1)',
    );
  }

  Future<List<ReplaceRule>> getEnabledContentForBook(
    String name,
    String origin,
  ) {
    return _getEnabledScoped(
      name: name,
      origin: origin,
      scopePredicateSql: 'scopeContent = 1',
    );
  }

  Future<void> updateEnabled(int id, bool enabled) {
    return (update(replaceRules)..where((t) => t.id.equals(id))).write(
      ReplaceRulesCompanion(isEnabled: Value(enabled)),
    );
  }

  Future<void> updateOrder(int id, int order) {
    return (update(replaceRules)..where((t) => t.id.equals(id))).write(
      ReplaceRulesCompanion(order: Value(order)),
    );
  }

  Future<List<ReplaceRule>> _getEnabledScoped({
    required String name,
    required String origin,
    required String scopePredicateSql,
  }) async {
    final rows = await customSelect(
      '''
      SELECT * FROM replace_rules
      WHERE isEnabled = 1
        AND $scopePredicateSql
        AND (
          scope IS NULL
          OR scope = ''
          OR (? <> '' AND instr(scope, ?) > 0)
          OR (? <> '' AND instr(scope, ?) > 0)
        )
        AND (
          excludeScope IS NULL
          OR (
            (? = '' OR instr(excludeScope, ?) = 0)
            AND (? = '' OR instr(excludeScope, ?) = 0)
          )
        )
      ORDER BY "order" ASC
      ''',
      variables: [
        Variable.withString(name),
        Variable.withString(name),
        Variable.withString(origin),
        Variable.withString(origin),
        Variable.withString(name),
        Variable.withString(name),
        Variable.withString(origin),
        Variable.withString(origin),
      ],
      readsFrom: {replaceRules},
    ).get();
    return Future.wait(rows.map((row) => replaceRules.mapFromRow(row)));
  }

  Insertable<ReplaceRule> _toInsertable(ReplaceRule rule) {
    return ReplaceRulesCompanion(
      id: rule.id > 0 ? Value(rule.id) : const Value.absent(),
      name: Value(rule.name),
      pattern: Value(rule.pattern),
      replacement: Value(rule.replacement),
      scope: Value(rule.scope),
      scopeTitle: Value(rule.scopeTitle),
      scopeContent: Value(rule.scopeContent),
      excludeScope: Value(rule.excludeScope),
      isEnabled: Value(rule.isEnabled),
      isRegex: Value(rule.isRegex),
      timeoutMillisecond: Value(rule.timeoutMillisecond),
      group: Value(rule.group),
      order: Value(rule.order),
    );
  }
}
