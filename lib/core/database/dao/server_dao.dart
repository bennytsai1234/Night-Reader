import 'package:drift/drift.dart';
import '../../models/server.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'server_dao.g.dart';

@DriftAccessor(tables: [Servers])
class ServerDao extends DatabaseAccessor<AppDatabase> with _$ServerDaoMixin {
  ServerDao(super.db);

  Future<List<Server>> getAll() {
    return (select(servers)
      ..orderBy([(t) => OrderingTerm(expression: t.sortNumber)])).get();
  }

  Future<void> upsert(Server server) => into(
    servers,
  ).insertOnConflictUpdate(ServerToInsertable(server).toInsertable());

  Future<void> deleteById(int id) =>
      (delete(servers)..where((t) => t.id.equals(id))).go();
}
