import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/session/reader_session_facade.dart';

import '../../test_helper.dart';

/// 從搜尋直接讀、讀到一半加入書架：重開時要能照前後文字找回同一句
/// （ADR 0042），不能只剩「第幾個字」。
void main() {
  late AppDatabase db;
  late BookDao bookDao;
  late ChapterDao chapterDao;

  final before = '${'甲' * 200}這裡繼續讀${'乙' * 50}';
  // 之後這一章重新取得，那一句前面少了 100 個字。
  final after = '${'甲' * 100}這裡繼續讀${'乙' * 50}';
  const reading = ReaderLocation(chapterIndex: 0, charOffset: 200);

  setUpAll(setupTestDI);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    chapterDao = ChapterDao(db);
  });

  tearDown(() => db.close());

  Book unshelvedBook() => Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );

  Future<Book> addToShelf(Book book, ReaderLocation location) async {
    await const ReaderSessionFacade().addCurrentBookToBookshelf(
      book: book,
      chapters: const [],
      location: location,
      chapterTitle: '第一章',
      bookDao: bookDao,
      chapterDao: chapterDao,
    );
    return (await bookDao.getByUrl(book.bookUrl))!;
  }

  int reopenedOffset(Book saved) {
    final target = ReaderOpenTarget.resume(saved).location;
    return ReaderContentLocationMapper.offsetIn(
      location: target,
      displayText: after,
      contentHash: 'after',
    );
  }

  test(
    'the sentence saved on exit survives adding the book to the shelf',
    () async {
      // 退出時先存進度：書上帶著這一句的前後文字。
      final book = unshelvedBook()
        ..chapterIndex = 0
        ..charOffset = 200
        ..readerAnchorJson = jsonEncode(
          reading
              .withContentIdentity(contentHash: 'before', displayText: before)
              .toJson(),
        );

      final saved = await addToShelf(book, reading);

      expect(saved.isInBookshelf, isTrue);
      expect(reopenedOffset(saved), after.indexOf('這裡繼續讀'));
    },
  );

  test('a location that carries its own sentence is saved with it', () async {
    final saved = await addToShelf(
      unshelvedBook(),
      reading.withContentIdentity(contentHash: 'before', displayText: before),
    );

    expect(reopenedOffset(saved), after.indexOf('這裡繼續讀'));
  });

  test('a saved sentence for another position is not kept', () async {
    final book = unshelvedBook()
      ..readerAnchorJson = jsonEncode(
        const ReaderLocation(chapterIndex: 0, charOffset: 10)
            .withContentIdentity(contentHash: 'before', displayText: before)
            .toJson(),
      );

    final saved = await addToShelf(book, reading);

    expect(saved.readerAnchorJson, isNull);
    expect(saved.charOffset, 200);
  });

  test('adding to the shelf keeps book info edited while reading', () async {
    final book = unshelvedBook();
    // 閱讀中從書籍詳情改了書名與封面：資料庫那一列已經是新的，閱讀器手上
    // 還是開書時那一份。
    await bookDao.upsert(
      book.copyWith()
        ..name = '新書名'
        ..customCoverUrl = 'https://s.example/cover.jpg',
    );

    final saved = await addToShelf(book, reading);

    expect(saved.isInBookshelf, isTrue);
    expect(saved.charOffset, 200);
    expect(saved.durChapterTitle, '第一章');
    expect(saved.name, '新書名');
    expect(saved.customCoverUrl, 'https://s.example/cover.jpg');
  });
}
