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
    return (select(replaceRules)
      ..orderBy([(t) => OrderingTerm(expression: t.order)])).get();
  }

  Stream<List<ReplaceRule>> watchAll() {
    return (select(replaceRules)
      ..orderBy([(t) => OrderingTerm(expression: t.order)])).watch();
  }

  Future<void> upsert(ReplaceRule rule) =>
      into(replaceRules).insertOnConflictUpdate(_toInsertable(rule));

  Future<void> upsertAll(List<ReplaceRule> rules) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        replaceRules,
        rules.map(_toInsertable).toList(),
      ),
    );
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
    return (update(replaceRules)..where(
      (t) => t.id.equals(id),
    )).write(ReplaceRulesCompanion(isEnabled: Value(enabled)));
  }

  Future<void> updateOrder(int id, int order) {
    return (update(replaceRules)..where(
      (t) => t.id.equals(id),
    )).write(ReplaceRulesCompanion(order: Value(order)));
  }

  Future<List<ReplaceRule>> _getEnabledScoped({
    required String name,
    required String origin,
    required String scopePredicateSql,
  }) async {
    final rows =
        await customSelect(
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
