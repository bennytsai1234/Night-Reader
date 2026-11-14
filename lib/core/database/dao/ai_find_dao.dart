import 'package:drift/drift.dart';

import '../../models/ai_find_record.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'ai_find_dao.g.dart';

/// 過去的找書（ADR 0060）：搜尋頁「過去的找書」列它，點了看那次的報告。
@DriftAccessor(tables: [AiFindRecords])
class AiFindDao extends DatabaseAccessor<AppDatabase> with _$AiFindDaoMixin {
  AiFindDao(super.db);

  Future<List<AiFindRecord>> getAll() => select(aiFindRecords).get();

  /// 新找的在前。
  Future<List<AiFindRecord>> getNewestFirst() => (select(
    aiFindRecords,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Future<AiFindRecord?> getById(String id) =>
      (select(aiFindRecords)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(AiFindRecord record) =>
      into(aiFindRecords).insertOnConflictUpdate(record.toInsertable());

  Future<void> upsertAll(List<AiFindRecord> records) => batch(
    (b) => b.insertAllOnConflictUpdate(aiFindRecords, [
      for (final record in records) record.toInsertable(),
    ]),
  );

  Future<void> deleteById(String id) =>
      (delete(aiFindRecords)..where((t) => t.id.equals(id))).go();

  Future<void> deleteByIds(List<String> ids) =>
      (delete(aiFindRecords)..where((t) => t.id.isIn(ids))).go();
}
