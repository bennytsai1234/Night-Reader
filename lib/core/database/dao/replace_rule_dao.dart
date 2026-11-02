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
  /// 編輯畫面開著時規則被同步換了編號，照新編號存（[_current]）。
  Future<void> upsert(ReplaceRule rule) => transaction(() async {
    if (rule.id > 0) rule.id = await _current(rule.id);
    await _assignIds([rule]);
    await into(replaceRules).insertOnConflictUpdate(_toInsertable(rule));
  });

  /// 新增一條規則，回傳它的 id。
  Future<int> insert(ReplaceRule rule) => transaction(() async {
    await _assignIds([rule]);
    return into(replaceRules).insert(_toInsertable(rule));
  });

  /// 照每條自己的編號存（匯入、還原、同步）；沒有編號的配新的。
  Future<void> upsertAll(List<ReplaceRule> rules) => transaction(() async {
    await _assignIds(rules);
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        replaceRules,
        rules.map(_toInsertable).toList(),
      ),
    );
  });

  /// 照編號刪，不追換過的編號（同步套用別台的刪除用）。
  Future<void> deleteByIds(Iterable<int> ids) =>
      (delete(replaceRules)..where((t) => t.id.isIn(ids))).go();

  /// 同步對齊編號：[mapping] 的每條規則從鍵的編號換到值的編號，值是 null
  /// 的配一個新編號；傳回每條實際換到的編號。兩條互換編號也行。換過的
  /// 舊編號記下來，畫面上拿舊編號做的事（選字隱藏的復原、開著的編輯畫面）
  /// 照樣找得到那條規則（[_current]）。
  ///
  /// 新編號避開 [avoid]（例如雲端已經用掉的編號）。
  Future<Map<int, int>> changeIds(
    Map<int, int?> mapping, {
    Set<int> avoid = const {},
  }) {
    if (mapping.isEmpty) return Future.value(const {});
    return transaction(() async {
      final taken = {...avoid, ...mapping.values.whereType<int>()};
      var candidate = (await _newIds(1)).single;
      int fresh() {
        while (taken.contains(candidate)) {
          candidate++;
        }
        taken.add(candidate);
        return candidate;
      }

      final targets = <int, int>{
        for (final MapEntry(:key, :value) in mapping.entries)
          key: value ?? fresh(),
      };
      // 先全部搬到暫時的編號，互換時不會撞到還沒搬走的。
      final temps = <int, int>{};
      for (final from in targets.keys) {
        temps[from] = fresh();
        await _moveRow(from, temps[from]!);
      }
      final moved = _movedIds[attachedDatabase] ??= {};
      for (final MapEntry(key: from, value: to) in targets.entries) {
        await _moveRow(temps[from]!, to);
        for (final entry in moved.entries.toList()) {
          if (entry.value == from) moved[entry.key] = to;
        }
        moved[from] = to;
      }
      return targets;
    });
  }

  Future<void> _moveRow(int from, int to) =>
      (update(replaceRules)..where((t) => t.id.equals(from))).write(
        ReplaceRulesCompanion(id: Value(to)),
      );

  /// 每個資料庫被同步換掉的編號：舊編號 → 現在的編號。
  static final Expando<Map<int, int>> _movedIds = Expando();

  /// [id] 現在的編號：還在就是它，被同步換掉了就是換到的那個。
  Future<int> _current(int id) async {
    final exists = await (select(
      replaceRules,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (exists != null) return id;
    return _movedIds[attachedDatabase]?[id] ?? id;
  }

  /// 新規則的編號用建立的時間（毫秒，同 Legado）：兩台手機各自新增的規則
  /// 不會撞號，同步時分得開（ADR 0039）。直接寫進 [rules]，呼叫端拿得到。
  /// 呼叫端在同一個交易裡寫入，兩個同時新增的不會拿到同一個編號。
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

  /// 刪一條規則；被同步換過編號的照新編號刪（[_current]）。
  Future<void> deleteById(int id) => transaction(() async {
    final current = await _current(id);
    await (delete(replaceRules)..where((t) => t.id.equals(current))).go();
  });

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

  Future<void> updateEnabled(int id, bool enabled) => transaction(() async {
    final current = await _current(id);
    await (update(replaceRules)..where((t) => t.id.equals(current))).write(
      ReplaceRulesCompanion(isEnabled: Value(enabled)),
    );
  });

  Future<void> updateOrder(int id, int order) => transaction(() async {
    final current = await _current(id);
    await (update(replaceRules)..where((t) => t.id.equals(current))).write(
      ReplaceRulesCompanion(order: Value(order)),
    );
  });

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
