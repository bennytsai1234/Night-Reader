import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/read_record.dart';

void main() {
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

    test('recordReadActivity accumulates time by book name', () async {
      await db.readRecordDao.recordReadActivity(
        bookName: '書 A',
        seconds: 4,
        lastRead: 1000,
      );
      await db.readRecordDao.recordReadActivity(
        bookName: '書 A',
        seconds: 6,
        lastRead: 2000,
      );

      final record = await db.readRecordDao.getByBookName('書 A');

      expect(record, isNotNull);
      expect(record!.readTime, 10);
      expect(record.lastRead, 2000);
    });

    test('restoreByBookName replaces existing totals without doubling', () async {
      await db.readRecordDao.recordReadActivity(
        bookName: '書 A',
        seconds: 10,
        lastRead: 1000,
      );

      final backupRecord = ReadRecord(
        bookName: '書 A',
        readTime: 25,
        lastRead: 3000,
      );
      await db.readRecordDao.restoreByBookName(backupRecord);
      await db.readRecordDao.restoreByBookName(backupRecord);

      final records = await db.readRecordDao.getAll();
      final record = await db.readRecordDao.getByBookName('書 A');

      expect(records, hasLength(1));
      expect(record, isNotNull);
      expect(record!.readTime, 25);
      expect(record.lastRead, 3000);
    });

    test('deleting a book keeps its reading record', () async {
      await db.bookDao.upsert(
        Book(bookUrl: 'book://a', name: '書 A', isInBookshelf: true),
      );
      await db.readRecordDao.recordReadActivity(
        bookName: '書 A',
        seconds: 10,
        lastRead: 1000,
      );

      await db.bookDao.deleteByUrl('book://a');

      expect(await db.bookDao.getByUrl('book://a'), isNull);
      final record = await db.readRecordDao.getByBookName('書 A');
      expect(record, isNotNull);
      expect(record!.readTime, 10);
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
