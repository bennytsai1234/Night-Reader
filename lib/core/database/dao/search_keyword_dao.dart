import 'package:drift/drift.dart';
import '../../models/search_keyword.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'search_keyword_dao.g.dart';

@DriftAccessor(tables: [SearchKeywords])
class SearchKeywordDao extends DatabaseAccessor<AppDatabase>
    with _$SearchKeywordDaoMixin {
  SearchKeywordDao(super.db);

  /// 按使用頻率降序取得全部 (對標 Legado flowByUsage)
  Future<List<SearchKeyword>> getAll() {
    return (select(searchKeywords)..orderBy([
      (t) => OrderingTerm(expression: t.usage, mode: OrderingMode.desc),
    ])).get();
  }

  /// 按最後使用時間降序取得全部 (對標 Legado flowByTime)
  Future<List<SearchKeyword>> getByTime() {
    return (select(searchKeywords)
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.lastUseTime,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(50))
        .get();
  }

  /// 搜尋包含關鍵字的歷史記錄 (對標 Legado flowSearch)
  Future<List<SearchKeyword>> search(String key) {
    return (select(searchKeywords)
          ..where((t) => t.word.like('%$key%'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.usage, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// 取得單一關鍵字 (對標 Legado get)
  Future<SearchKeyword?> getByWord(String word) {
    return (select(searchKeywords)
      ..where((t) => t.word.equals(word))).getSingleOrNull();
  }

  /// 儲存搜尋關鍵字：存在則 +1 usage 並更新時間，不存在則新增
  /// (對標 Legado SearchViewModel.saveSearchKey)
  Future<void> saveKeyword(String word) async {
    final existing = await getByWord(word);
    if (existing != null) {
      existing.usage += 1;
      existing.lastUseTime = DateTime.now().millisecondsSinceEpoch;
      await upsert(existing);
    } else {
      await upsert(
        SearchKeyword(
          word: word,
          usage: 1,
          lastUseTime: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> upsert(SearchKeyword keyword) => into(
    searchKeywords,
  ).insertOnConflictUpdate(SearchKeywordToInsertable(keyword).toInsertable());

  Future<void> deleteByWord(String word) =>
      (delete(searchKeywords)..where((t) => t.word.equals(word))).go();

  Future<void> clearAll() => delete(searchKeywords).go();
}
