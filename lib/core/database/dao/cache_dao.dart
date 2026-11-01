import 'package:drift/drift.dart';

import '../../models/cache.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'cache_dao.g.dart';

@DriftAccessor(tables: [CacheTable])
class CacheDao extends DatabaseAccessor<AppDatabase> with _$CacheDaoMixin {
  CacheDao(super.db);

  Future<Cache?> get(String key) {
    return (select(
      cacheTable,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
  }

  /// 以 [prefix] 開頭的鍵（逐字比對，[prefix] 裡的 `%`、`_` 不當萬用字元）。
  Future<List<String>> keysStartingWith(String prefix) {
    return customSelect(
      'SELECT "key" FROM cache_table WHERE substr("key", 1, ?) = ?',
      variables: [Variable.withInt(prefix.length), Variable.withString(prefix)],
      readsFrom: {cacheTable},
    ).map((row) => row.read<String>('key')).get();
  }

  /// 在 [now]（毫秒）還沒過期的全部內容。
  Future<List<Cache>> getLive(int now) {
    return (select(cacheTable)..where(
          (t) => t.deadline.equals(0) | t.deadline.isBiggerThanValue(now),
        ))
        .get();
  }

  Future<void> upsert(Cache cache) =>
      into(cacheTable)
          .insertOnConflictUpdate(CacheToInsertable(cache).toInsertable());

  Future<void> deleteKey(String key) =>
      (delete(cacheTable)..where((t) => t.key.equals(key))).go();

  Future<void> clearAll() => delete(cacheTable).go();

  Future<void> deleteByKey(String key) => deleteKey(key);

  Future<void> clearDeadline(int now) {
    return (delete(cacheTable)..where(
          (t) =>
              t.deadline.isSmallerOrEqualValue(now) &
              t.deadline.isBiggerThanValue(0),
        ))
        .go();
  }
}
