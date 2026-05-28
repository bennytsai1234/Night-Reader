import 'package:drift/drift.dart';
import '../../models/dict_rule.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'dict_rule_dao.g.dart';

@DriftAccessor(tables: [DictRules])
class DictRuleDao extends DatabaseAccessor<AppDatabase>
    with _$DictRuleDaoMixin {
  DictRuleDao(super.db);

  Future<List<DictRule>> getAll() {
    return (select(dictRules)
      ..orderBy([(t) => OrderingTerm(expression: t.sortNumber)])).get();
  }

  Stream<List<DictRule>> watchAll() {
    return (select(dictRules)
      ..orderBy([(t) => OrderingTerm(expression: t.sortNumber)])).watch();
  }

  Future<void> upsert(DictRule rule) => into(
    dictRules,
  ).insertOnConflictUpdate(DictRuleToInsertable(rule).toInsertable());

  Future<void> deleteById(int id) =>
      (delete(dictRules)..where((t) => t.id.equals(id))).go();

  Future<void> insertOrUpdateAll(List<DictRule> rules) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        dictRules,
        rules.map((e) => DictRuleToInsertable(e).toInsertable()).toList(),
      ),
    );
  }

  Future<void> deleteByName(String name) =>
      (delete(dictRules)..where((t) => t.name.equals(name))).go();
}
