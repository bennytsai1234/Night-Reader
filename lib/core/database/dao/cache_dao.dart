import 'package:drift/drift.dart';
import '../../models/cache.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'cache_dao.g.dart';

@DriftAccessor(tables: [CacheTable])
class CacheDao extends DatabaseAccessor<AppDatabase> with _$CacheDaoMixin {
  CacheDao(super.db);

  Future<Cache?> get(String key) {
    return (select(cacheTable)
      ..where((t) => t.key.equals(key))).getSingleOrNull();
  }

  Future<void> upsert(Cache cache) => into(
    cacheTable,
  ).insertOnConflictUpdate(CacheToInsertable(cache).toInsertable());

  Future<void> deleteKey(String key) =>
      (delete(cacheTable)..where((t) => t.key.equals(key))).go();

  Future<void> clearAll() => delete(cacheTable).go();

  Future<void> deleteByKey(String key) => deleteKey(key);

  Future<void> clearDeadline(int now) {
    return (delete(cacheTable)..where(
      (t) =>
          t.deadline.isSmallerThanValue(now) & t.deadline.isBiggerThanValue(0),
    )).go();
  }
}
