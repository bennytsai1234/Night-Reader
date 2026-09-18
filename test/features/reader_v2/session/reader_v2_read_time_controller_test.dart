import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_controller.dart';

void main() {
  group('ReaderV2ReadTimeController', () {
    late AppDatabase db;
    late DateTime now;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      now = DateTime(2026, 8, 11, 12);
    });

    tearDown(() async {
      await db.close();
    });

    test('累加多段前景閱讀時間', () async {
      final controller = ReaderV2ReadTimeController(
        bookName: '書 A',
        readRecordDao: db.readRecordDao,
        now: () => now,
      );

      controller.start();
      now = now.add(const Duration(seconds: 10));
      await controller.stop();

      now = now.add(const Duration(minutes: 5));
      controller.start();
      now = now.add(const Duration(seconds: 7));
      await controller.stop();

      final record = await db.readRecordDao.getByBookName('書 A');
      expect(record, isNotNull);
      expect(record!.readTime, 17);
      expect(record.lastRead, now.millisecondsSinceEpoch);

      await controller.close();
    });

    test('未開始計時時停止不建立紀錄', () async {
      final controller = ReaderV2ReadTimeController(
        bookName: '書 A',
        readRecordDao: db.readRecordDao,
        now: () => now,
      );

      await controller.stop();

      expect(await db.readRecordDao.getByBookName('書 A'), isNull);
      await controller.close();
    });
  });
}
