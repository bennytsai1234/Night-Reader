import 'package:drift/drift.dart';

import '../../models/read_record.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'read_record_dao.g.dart';

@DriftAccessor(tables: [ReadRecords, ReadDays])
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
    return (select(
      readRecords,
    )..where((t) => t.bookName.equals(bookName))).getSingleOrNull();
  }

  /// 記下從 [startedAt] 讀到 [stoppedAt]：累計加上這段秒數，跨過午夜的
  /// 部分分記到各自那一天。
  Future<void> recordReadActivity({
    required String bookName,
    required DateTime startedAt,
    required DateTime stoppedAt,
    String deviceId = '',
  }) {
    return transaction(() async {
      await _addToTotal(
        bookName: bookName,
        seconds: stoppedAt.difference(startedAt).inSeconds,
        lastRead: stoppedAt.millisecondsSinceEpoch,
        deviceId: deviceId,
      );
      for (final MapEntry(key: day, value: seconds) in secondsByDay(
        startedAt,
        stoppedAt,
      ).entries) {
        await into(readDays).insert(
          ReadDaysCompanion.insert(
            bookName: bookName,
            day: day,
            seconds: Value(seconds),
          ),
          onConflict: DoUpdate(
            (old) => ReadDaysCompanion.custom(
              seconds: old.seconds + Constant(seconds),
            ),
          ),
        );
      }
    });
  }

  /// 裝置當地日期 `yyyy-MM-dd`。
  static String dayKey(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final year = time.year.toString().padLeft(4, '0');
    return '$year-${two(time.month)}-${two(time.day)}';
  }

  /// 把一段閱讀時間依當地午夜切開，算出每天的秒數。
  static Map<String, int> secondsByDay(DateTime start, DateTime end) {
    final result = <String, int>{};
    var cursor = start;
    while (cursor.isBefore(end)) {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segmentEnd = midnight.isBefore(end) ? midnight : end;
      final seconds = segmentEnd.difference(cursor).inSeconds;
      if (seconds > 0) {
        result.update(
          dayKey(cursor),
          (value) => value + seconds,
          ifAbsent: () => seconds,
        );
      }
      cursor = segmentEnd;
    }
    return result;
  }

  /// 今天與本週（週一起算）讀了幾秒，所有書加總。
  Future<({int today, int week})> recentTotals(DateTime now) async {
    final today = dayKey(now);
    final weekStart = dayKey(
      DateTime(now.year, now.month, now.day - (now.weekday - 1)),
    );
    Future<int> sumBetween(String from, String to) async {
      final total = readDays.seconds.sum();
      final query = selectOnly(readDays)
        ..addColumns([total])
        ..where(readDays.day.isBetweenValues(from, to));
      return (await query.getSingle()).read(total) ?? 0;
    }

    return (
      today: await sumBetween(today, today),
      week: await sumBetween(weekStart, today),
    );
  }

  Future<List<ReadDay>> getAllDays() => select(readDays).get();

  /// 還原備份：同一本書同一天以備份的秒數為準。
  Future<void> restoreDay(ReadDay day) {
    return into(readDays).insertOnConflictUpdate(day);
  }

  Future<void> _addToTotal({
    required String bookName,
    required int seconds,
    required int lastRead,
    required String deviceId,
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

  Future<void> restoreByBookName(ReadRecord record) async {
    final existing = await getByBookName(record.bookName);
    if (existing == null) {
      await into(readRecords).insert(
        ReadRecordsCompanion.insert(
          bookName: record.bookName,
          deviceId: record.deviceId,
          readTime: Value(record.readTime < 0 ? 0 : record.readTime),
          lastRead: Value(record.lastRead),
        ),
      );
      return;
    }

    await (update(readRecords)..where((t) => t.id.equals(existing.id))).write(
      ReadRecordsCompanion(
        deviceId: Value(record.deviceId),
        readTime: Value(record.readTime < 0 ? 0 : record.readTime),
        lastRead: Value(record.lastRead),
      ),
    );
  }

  Future<void> clearAll() async {
    await delete(readRecords).go();
    await delete(readDays).go();
  }

  Future<List<ReadRecord>> getAllShow() {
    return (select(readRecords)..orderBy([
          (t) => OrderingTerm(expression: t.lastRead, mode: OrderingMode.desc),
        ]))
        .get();
  }
}
