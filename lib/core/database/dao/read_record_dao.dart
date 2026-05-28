import 'package:drift/drift.dart';
import '../../models/read_record.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'read_record_dao.g.dart';

@DriftAccessor(tables: [ReadRecords])
class ReadRecordDao extends DatabaseAccessor<AppDatabase>
    with _$ReadRecordDaoMixin {
  ReadRecordDao(super.db);

  Future<List<ReadRecord>> getAll() => select(readRecords).get();

  Future<void> upsert(ReadRecord record) {
    return into(readRecords).insertOnConflictUpdate(
      ReadRecordsCompanion(
        id: record.id > 0 ? Value(record.id) : const Value.absent(),
        bookName: Value(record.bookName),
        deviceId: Value(record.deviceId),
        readTime: Value(record.readTime),
        lastRead: Value(record.lastRead),
      ),
    );
  }

  Future<ReadRecord?> getByBookName(String bookName) {
    return (select(readRecords)
      ..where((t) => t.bookName.equals(bookName))).getSingleOrNull();
  }

  Future<void> recordReadActivity({
    required String bookName,
    required int seconds,
    required int lastRead,
    String deviceId = '',
  }) async {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final existing = await getByBookName(bookName);
    if (existing == null) {
      await into(readRecords).insert(
        ReadRecordsCompanion.insert(
          bookName: bookName,
          deviceId: deviceId,
          readTime: Value(safeSeconds),
          lastRead: Value(lastRead),
        ),
      );
      return;
    }
    await (update(readRecords)..where((t) => t.id.equals(existing.id))).write(
      ReadRecordsCompanion(
        readTime: Value(existing.readTime + safeSeconds),
        lastRead: Value(lastRead),
      ),
    );
  }

  Future<void> clearAll() => delete(readRecords).go();

  Future<List<ReadRecord>> getAllShow() {
    return (select(readRecords)..orderBy([
      (t) => OrderingTerm(expression: t.lastRead, mode: OrderingMode.desc),
    ])).get();
  }
}
