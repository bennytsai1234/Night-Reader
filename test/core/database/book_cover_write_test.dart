import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book/book.dart';

/// 書籍詳情在背景把封面存進手機（[BookDao.saveStoredCover]）：封面下載完才
/// 寫，這段期間讀者可能已經換了封面、或把書移出書架。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Book book() => Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
    coverUrl: 'https://s.example/cover.jpg',
  )..isInBookshelf = true;

  test('a stored cover file is written to the book', () async {
    await db.bookDao.upsert(book());

    await db.bookDao.saveStoredCover(book()..coverLocalPath = '/covers/1.jpg');

    final stored = await db.bookDao.getByUrl('https://s.example/book/1');
    expect(stored!.coverLocalPath, '/covers/1.jpg');
  });

  test(
    'a cover stored after the reader picked another one is dropped',
    () async {
      await db.bookDao.upsert(
        book()..customCoverUrl = 'https://img.example/new.jpg',
      );

      await db.bookDao.saveStoredCover(
        book()..customCoverLocalPath = '/covers/old.jpg',
      );

      final stored = await db.bookDao.getByUrl('https://s.example/book/1');
      expect(stored!.customCoverUrl, 'https://img.example/new.jpg');
      expect(stored.customCoverLocalPath, isNull);
    },
  );

  test(
    'a cover stored after the book left the shelf does not bring it back',
    () async {
      await db.bookDao.saveStoredCover(
        book()..coverLocalPath = '/covers/1.jpg',
      );

      expect(await db.bookDao.getByUrl('https://s.example/book/1'), isNull);
    },
  );
}
