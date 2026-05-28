import 'package:drift/drift.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'search_history_dao.g.dart';

@DriftAccessor(tables: [SearchHistoryTable])
class SearchHistoryDao extends DatabaseAccessor<AppDatabase>
    with _$SearchHistoryDaoMixin {
  SearchHistoryDao(super.db);

  Future<List<SearchHistoryRow>> getAll() {
    return (select(searchHistoryTable)..orderBy([
      (t) => OrderingTerm(expression: t.searchTime, mode: OrderingMode.desc),
    ])).get();
  }

  Future<void> add(String keyword) {
    return into(searchHistoryTable).insertOnConflictUpdate(
      SearchHistoryTableCompanion.insert(
        keyword: keyword,
        searchTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> deleteById(int id) =>
      (delete(searchHistoryTable)..where((t) => t.id.equals(id))).go();

  Future<void> clearAll() => delete(searchHistoryTable).go();

  Future<int> countAll() async {
    final row =
        await customSelect(
          'SELECT COUNT(*) AS total FROM search_history_table',
          readsFrom: {searchHistoryTable},
        ).getSingle();
    return row.read<int>('total');
  }

  /// 取得最近的搜尋記錄 (最多 50 筆)
  Future<List<SearchHistoryRow>> getRecent() {
    return (select(searchHistoryTable)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.searchTime, mode: OrderingMode.desc),
          ])
          ..limit(50))
        .get();
  }

  /// 清除 beforeTime 之前的舊搜尋紀錄
  Future<void> clearOld(int beforeTime) {
    return (delete(searchHistoryTable)
      ..where((t) => t.searchTime.isSmallerThanValue(beforeTime))).go();
  }
}
