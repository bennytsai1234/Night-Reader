import 'package:drift/drift.dart';
import '../../models/keyboard_assist.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'keyboard_assist_dao.g.dart';

@DriftAccessor(tables: [KeyboardAssists])
class KeyboardAssistDao extends DatabaseAccessor<AppDatabase>
    with _$KeyboardAssistDaoMixin {
  KeyboardAssistDao(super.db);

  Future<List<KeyboardAssist>> getAll() {
    return (select(keyboardAssists)
      ..orderBy([(t) => OrderingTerm(expression: t.serialNo)])).get();
  }

  Stream<List<KeyboardAssist>> watchAll() {
    return (select(keyboardAssists)
      ..orderBy([(t) => OrderingTerm(expression: t.serialNo)])).watch();
  }

  Future<void> upsert(KeyboardAssist assist) => into(
    keyboardAssists,
  ).insertOnConflictUpdate(KeyboardAssistToInsertable(assist).toInsertable());

  Future<void> deleteByKey(String key) =>
      (delete(keyboardAssists)..where((t) => t.key.equals(key))).go();
}
