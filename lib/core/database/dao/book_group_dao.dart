import 'package:drift/drift.dart';
import '../../models/book_group.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'book_group_dao.g.dart';

@DriftAccessor(tables: [BookGroups])
class BookGroupDao extends DatabaseAccessor<AppDatabase>
    with _$BookGroupDaoMixin {
  BookGroupDao(super.db);

  Future<List<BookGroup>> getAll() {
    return (select(bookGroups)
      ..orderBy([(t) => OrderingTerm(expression: t.order)])).get();
  }

  Stream<List<BookGroup>> watchAll() => select(bookGroups).watch();

  Future<void> upsert(BookGroup group) => into(
    bookGroups,
  ).insertOnConflictUpdate(BookGroupToInsertable(group).toInsertable());

  Future<void> deleteById(int id) =>
      (delete(bookGroups)..where((t) => t.groupId.equals(id))).go();

  Future<void> updateOrder(List<BookGroup> groups) async {
    for (var i = 0; i < groups.length; i++) {
      await (update(bookGroups)..where(
        (t) => t.groupId.equals(groups[i].groupId),
      )).write(BookGroupsCompanion(order: Value(i)));
    }
  }
}
