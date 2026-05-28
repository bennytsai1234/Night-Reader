import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:sqlite3/open.dart';

void main() {
  setUpAll(() {
    const linuxSqlite = '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0';
    if (Platform.isLinux && File(linuxSqlite).existsSync()) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open(linuxSqlite),
      );
    }
  });

  group('ReadRecordDao', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('recordReadActivity lets new records receive generated ids', () async {
      await db.readRecordDao.recordReadActivity(
        bookName: '書 A',
        seconds: 4,
        lastRead: 1000,
      );
      await db.readRecordDao.recordReadActivity(
        bookName: '書 B',
        seconds: 5,
        lastRead: 2000,
      );

      final records = await db.readRecordDao.getAllShow();

      expect(records.map((record) => record.bookName), ['書 B', '書 A']);
      expect(records.map((record) => record.id), everyElement(greaterThan(0)));
    });

    test('upsert omits default model id for new records', () async {
      await db.readRecordDao.upsert(ReadRecord(bookName: '書 A'));
      await db.readRecordDao.upsert(ReadRecord(bookName: '書 B'));

      final records = await db.readRecordDao.getAll();

      expect(records.map((record) => record.bookName), ['書 A', '書 B']);
      expect(records.map((record) => record.id), everyElement(greaterThan(0)));
    });
  });
}
