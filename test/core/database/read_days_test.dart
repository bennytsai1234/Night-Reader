import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';

import 'legacy_chapters_table.dart';

void main() {
  test('a session past midnight is split between the two days', () {
    final days = ReadRecordDao.secondsByDay(
      DateTime(2026, 10, 14, 23, 50),
      DateTime(2026, 10, 15, 0, 20),
    );
    expect(days, {'2026-10-14': 600, '2026-10-15': 1200});
  });

  test('split seconds add up to the total even with milliseconds', () {
    final start = DateTime(2026, 10, 14, 23, 59, 59, 500);
    final end = DateTime(2026, 10, 15, 0, 0, 0, 500);
    final days = ReadRecordDao.secondsByDay(start, end);
    expect(
      days.values.fold<int>(0, (sum, seconds) => sum + seconds),
      end.difference(start).inSeconds,
    );
    expect(days, {'2026-10-15': 1});
  });

  test('today and this week (from Monday) add up across books', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReadRecordDao(db);
    // 2026-10-15 是週四；週一是 10-12，上週日是 10-11。
    final now = DateTime(2026, 10, 15, 21);
    Future<void> read(String book, DateTime start, int minutes) =>
        dao.recordReadActivity(
          bookName: book,
          startedAt: start,
          stoppedAt: start.add(Duration(minutes: minutes)),
        );

    await read('甲', DateTime(2026, 10, 15, 8), 30);
    await read('乙', DateTime(2026, 10, 15, 20), 10);
    await read('甲', DateTime(2026, 10, 12, 9), 60);
    await read('甲', DateTime(2026, 10, 11, 9), 120);

    final totals = await dao.recentTotals(now);
    expect(totals.today, 40 * 60);
    expect(totals.week, 100 * 60);
    final first = await dao.getByBookName('甲');
    expect(first!.readTime, 210 * 60);
  });

  test('upgrading from schema 6 keeps the totals and adds daily records', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
            CREATE TABLE read_records (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              bookName TEXT NOT NULL,
              deviceId TEXT NOT NULL,
              readTime INTEGER NOT NULL DEFAULT 0,
              lastRead INTEGER NOT NULL DEFAULT 0
            )''');
          raw.execute(
            'INSERT INTO read_records (bookName, deviceId, readTime, lastRead) '
            "VALUES ('甲', '', 3600, 1)",
          );
          raw.execute(legacyChaptersTable);
          raw.execute('PRAGMA user_version = 6');
        },
      ),
    );
    addTearDown(db.close);
    final dao = ReadRecordDao(db);

    expect((await dao.getByBookName('甲'))!.readTime, 3600);
    final totals = await dao.recentTotals(DateTime(2026, 10, 15));
    expect(totals.today, 0);
    expect(totals.week, 0);
  });
}
