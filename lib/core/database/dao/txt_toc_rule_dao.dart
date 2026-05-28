import 'package:drift/drift.dart';
import '../../models/txt_toc_rule.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'txt_toc_rule_dao.g.dart';

@DriftAccessor(tables: [TxtTocRules])
class TxtTocRuleDao extends DatabaseAccessor<AppDatabase>
    with _$TxtTocRuleDaoMixin {
  TxtTocRuleDao(super.db);

  Future<List<TxtTocRule>> getAll() {
    return (select(txtTocRules)
      ..orderBy([(t) => OrderingTerm(expression: t.serialNumber)])).get();
  }

  Stream<List<TxtTocRule>> watchEnabled() {
    return (select(txtTocRules)
          ..where((t) => t.enable.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.serialNumber)]))
        .watch();
  }

  Future<void> upsert(TxtTocRule rule) => into(
    txtTocRules,
  ).insertOnConflictUpdate(TxtTocRuleToInsertable(rule).toInsertable());

  Future<void> deleteById(int id) =>
      (delete(txtTocRules)..where((t) => t.id.equals(id))).go();

  Future<void> insertOrUpdateAll(List<TxtTocRule> rules) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        txtTocRules,
        rules.map((e) => TxtTocRuleToInsertable(e).toInsertable()).toList(),
      ),
    );
  }
}
