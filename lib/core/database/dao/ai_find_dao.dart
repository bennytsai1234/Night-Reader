import 'package:drift/drift.dart';

import '../../diagnostics/app_log_service.dart';
import '../../models/search/ai_find_record.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'ai_find_dao.g.dart';

/// 過去的找書（ADR 0060）：搜尋頁「過去的找書」列它，點了看那次的報告。
@DriftAccessor(tables: [AiFindRecords])
class AiFindDao extends DatabaseAccessor<AppDatabase> with _$AiFindDaoMixin {
  AiFindDao(super.db) {
    // 交易裡的寫入在提交後才通知、整個交易只通知一次，撤銷的不通知。
    attachedDatabase
        .tableUpdates(TableUpdateQuery.onTable(aiFindRecords))
        .listen((_) => _refreshLatest());
  }

  Future<List<AiFindRecord>> getAll() => select(aiFindRecords).get();

  /// 最近一次 [getNewestFirst] 讀到的清單，還沒讀過是 null；讀過之後資料表
  /// 每次提交寫入都跟著重讀。搜尋頁推入的第一幀照它畫「過去的找書」：找書
  /// 多半在搜尋頁關著時存下（背景的找書、同步、還原），寫入時清掉就又要等
  /// 頁面讀。
  List<AiFindRecord>? get latestNewestFirst => _latestNewestFirst;
  List<AiFindRecord>? _latestNewestFirst;

  /// 讀的順序號：較早開始的讀較晚回來時，不蓋掉較新的結果。
  int _reads = 0;
  int _applied = 0;

  /// 新找的在前。
  Future<List<AiFindRecord>> getNewestFirst() async {
    final read = ++_reads;
    final result = await (select(
      aiFindRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    if (read > _applied) {
      _applied = read;
      _latestNewestFirst = List.unmodifiable(result);
    }
    return result;
  }

  Future<void> _refreshLatest() async {
    if (_latestNewestFirst == null) return;
    try {
      await getNewestFirst();
    } catch (error, stackTrace) {
      // 讀不到就不留舊的：下次搜尋頁照沒讀過的樣子，等頁面自己讀。
      _latestNewestFirst = null;
      AppLog.e('重讀過去的找書失敗: $error', error: error, stackTrace: stackTrace);
    }
  }

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
