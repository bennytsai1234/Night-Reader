import 'package:drift/drift.dart';
import '../../models/cookie.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'cookie_dao.g.dart';

@DriftAccessor(tables: [Cookies])
class CookieDao extends DatabaseAccessor<AppDatabase> with _$CookieDaoMixin {
  CookieDao(super.db);

  Future<Cookie?> getByUrl(String url) {
    return (select(cookies)..where((t) => t.url.equals(url))).getSingleOrNull();
  }

  Future<void> upsert(Cookie cookie) => into(
    cookies,
  ).insertOnConflictUpdate(CookieToInsertable(cookie).toInsertable());

  Future<void> deleteByUrl(String url) =>
      (delete(cookies)..where((t) => t.url.equals(url))).go();

  Future<void> clearAll() => delete(cookies).go();
}
