import 'package:drift/drift.dart';
import '../../models/rule_sub.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'rule_sub_dao.g.dart';

@DriftAccessor(tables: [RuleSubs])
class RuleSubDao extends DatabaseAccessor<AppDatabase> with _$RuleSubDaoMixin {
  RuleSubDao(super.db);

  Future<List<RuleSub>> getAll() => select(ruleSubs).get();

  Stream<List<RuleSub>> watchAll() => select(ruleSubs).watch();

  Future<void> upsert(RuleSub sub) => into(
    ruleSubs,
  ).insertOnConflictUpdate(RuleSubToInsertable(sub).toInsertable());

  Future<void> deleteById(int id) =>
      (delete(ruleSubs)..where((t) => t.id.equals(id))).go();
}
