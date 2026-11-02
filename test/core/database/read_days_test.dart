import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_controller.dart';

import 'legacy_books_table.dart';
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

  test('改書名：閱讀統計併到新書名，不分成兩筆', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReadRecordDao(db);
    Future<void> read(String book, DateTime start, int minutes) =>
        dao.recordReadActivity(
          bookName: book,
          startedAt: start,
          stoppedAt: start.add(Duration(minutes: minutes)),
        );
    await read('舊書名', DateTime(2026, 10, 14, 21), 10);
    await read('舊書名', DateTime(2026, 10, 15, 21), 20);
    // 新書名本來就有紀錄（例如改回以前用過的名字）：兩邊加起來。
    await read('新書名', DateTime(2026, 10, 15, 22), 5);

    await dao.renameBook(from: '舊書名', to: '新書名');

    final records = await dao.getAll();
    expect(records.map((r) => r.bookName), ['新書名']);
    expect(records.single.readTime, 35 * 60);
    expect(
      records.single.lastRead,
      DateTime(2026, 10, 15, 22, 5).millisecondsSinceEpoch,
    );
    final days = {
      for (final day in await dao.getAllDays())
        '${day.bookName} ${day.day}': day.seconds,
    };
    expect(days, {'新書名 2026-10-14': 600, '新書名 2026-10-15': 1500});

    // 沒讀過的書改名、名字沒變：什麼都不動。
    await dao.renameBook(from: '沒讀過', to: '別的名字');
    await dao.renameBook(from: '新書名', to: '新書名');
    expect((await dao.getAll()).single.readTime, 35 * 60);
  });

  test('閱讀中改書名：回去接著讀的時間記在新書名下，不再分成兩筆', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReadRecordDao(db);
    var now = DateTime(2026, 10, 15, 21);
    var currentName = '舊書名';
    final timer = ReaderV2ReadTimeController(
      bookName: () async => currentName,
      readRecordDao: dao,
      now: () => now,
    );
    timer.start();
    now = now.add(const Duration(seconds: 10));
    await timer.stop(); // 進書籍詳情
    currentName = '新書名';
    await dao.renameBook(from: '舊書名', to: '新書名');
    timer.start(); // 回到閱讀器
    now = now.add(const Duration(seconds: 20));
    await timer.stop();

    final records = await dao.getAll();
    expect(records.map((r) => (r.bookName, r.readTime)), [('新書名', 30)]);
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
          raw.execute(legacyBooksTable);
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
