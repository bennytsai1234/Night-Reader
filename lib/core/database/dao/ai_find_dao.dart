import 'package:drift/drift.dart';

import '../../models/search/ai_find_record.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'ai_find_dao.g.dart';

/// 過去的找書（ADR 0060）：搜尋頁「過去的找書」列它，點了看那次的報告。
@DriftAccessor(tables: [AiFindRecords])
class AiFindDao extends DatabaseAccessor<AppDatabase> with _$AiFindDaoMixin {
  AiFindDao(super.db);

  Future<List<AiFindRecord>> getAll() => select(aiFindRecords).get();

  /// 最近一次 [getNewestFirst] 讀到的清單，還沒讀過是 null；讀過之後每次寫入
  /// 都跟著重讀。搜尋頁推入的第一幀照它畫「過去的找書」：找書多半在搜尋頁
  /// 關著時存下（背景的找書、同步、還原），寫入時清掉就又要等頁面讀。
  List<AiFindRecord>? get latestNewestFirst => _latestNewestFirst;
  List<AiFindRecord>? _latestNewestFirst;

  /// 新找的在前。
  Future<List<AiFindRecord>> getNewestFirst() async {
    final result = await (select(
      aiFindRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    _latestNewestFirst = List.unmodifiable(result);
    return result;
  }

  Future<AiFindRecord?> getById(String id) =>
      (select(aiFindRecords)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(AiFindRecord record) => _write(
    () => into(aiFindRecords).insertOnConflictUpdate(record.toInsertable()),
  );

  Future<void> upsertAll(List<AiFindRecord> records) => _write(
    () => batch(
      (b) => b.insertAllOnConflictUpdate(aiFindRecords, [
        for (final record in records) record.toInsertable(),
      ]),
    ),
  );

  Future<void> deleteById(String id) =>
      _write((delete(aiFindRecords)..where((t) => t.id.equals(id))).go);

  Future<void> deleteByIds(List<String> ids) =>
      _write((delete(aiFindRecords)..where((t) => t.id.isIn(ids))).go);

  Future<void> _write(Future<Object?> Function() write) async {
    await write();
    if (_latestNewestFirst != null) await getNewestFirst();
  }
}
