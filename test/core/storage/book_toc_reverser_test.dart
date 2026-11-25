import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/storage/book_toc_reverser.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/features/bookmark/reader_bookmarks.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';

import '../../test_helper.dart';

void main() {
  late AppDatabase db;
  late BookDao bookDao;
  late ChapterDao chapterDao;
  late BookmarkDao bookmarkDao;
  late HighlightDao highlightDao;
  late BookTocReverser reverser;

  const bookUrl = 'https://s.example/book/1';
  // 新到舊的目錄：第 0 章是最新的。兩個「番外」同名，只能靠序號分。
  const titles = ['第5章', '番外', '第3章', '番外', '第1章'];

  List<BookChapter> toc() => [
    for (final (i, title) in titles.indexed)
      BookChapter(
        url: 'https://s.example/c/$i',
        title: title,
        bookUrl: bookUrl,
        index: i,
      ),
  ];

  Book book() => Book(
    bookUrl: bookUrl,
    origin: 'https://s.example',
    name: '書',
    author: '作者',
    chapterIndex: 3,
    durChapterTitle: '番外',
    charOffset: 42,
    durChapterTime: 1,
    readerAnchorJson: jsonEncode({
      'chapterIndex': 3,
      'charOffset': 42,
      'contentHash': 'h',
      'contentLength': 100,
    }),
  );

  setUpAll(setupTestDI);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    chapterDao = ChapterDao(db);
    bookmarkDao = BookmarkDao(db);
    highlightDao = HighlightDao(db);
    reverser = BookTocReverser(
      bookDao: bookDao,
      chapterDao: chapterDao,
      bookmarkDao: bookmarkDao,
      highlightDao: highlightDao,
    );
    await bookDao.upsert(book());
    await chapterDao.replaceByBook(bookUrl, toc());
  });

  tearDown(() => db.close());

  test('目錄整個翻過來、重新編號，記下這本書反轉了', () async {
    final result = await reverser.setReversed(book(), true);

    final stored = await chapterDao.getByBook(bookUrl);
    expect([for (final c in stored) c.title], titles.reversed);
    expect([for (final c in stored) c.index], [0, 1, 2, 3, 4]);
    expect(result!.chapters.map((c) => c.url), stored.map((c) => c.url));
    final saved = (await bookDao.getByUrl(bookUrl))!;
    expect(saved.readConfig!.reverseToc, isTrue);
    expect(result.book.readConfig!.reverseToc, isTrue);
  });

  test('閱讀進度跟著同一章，章內位置與錨點不變', () async {
    await reverser.setReversed(book(), true);

    final saved = (await bookDao.getByUrl(bookUrl))!;
    final stored = await chapterDao.getByBook(bookUrl);
    expect(stored[saved.chapterIndex].url, 'https://s.example/c/3');
    expect(saved.chapterIndex, 1);
    expect(saved.durChapterTitle, '番外');
    expect(saved.charOffset, 42);
    expect(jsonDecode(saved.readerAnchorJson!)['chapterIndex'], 1);
  });

  test('同名的章（兩個番外）上的書籤與標註，翻過來還是同一章', () async {
    await bookmarkDao.upsertAll([
      Bookmark(
        id: 1,
        bookName: '書',
        bookAuthor: '作者',
        chapterIndex: 3,
        chapterTitle: '番外',
      ),
    ]);
    await highlightDao.upsertAll([
      Highlight(
        id: 2,
        bookName: '書',
        bookAuthor: '作者',
        chapterIndex: 1,
        chapterTitle: '番外',
      ),
    ]);

    await reverser.setReversed(book(), true);

    final stored = await chapterDao.getByBook(bookUrl);
    final bookmark = (await bookmarkDao.getAll()).single;
    final highlight = (await highlightDao.getAll()).single;
    int resolved(int index, String title) => chapterIndexByTitle(
      chapterIndex: index,
      chapterTitle: title,
      chapters: stored,
    );
    expect(
      stored[resolved(bookmark.chapterIndex, bookmark.chapterTitle)].url,
      'https://s.example/c/3',
    );
    expect(
      stored[resolved(highlight.chapterIndex, highlight.chapterTitle)].url,
      'https://s.example/c/1',
    );
  });

  test('再翻一次回到原本的順序；已經是那個順序時什麼都不動', () async {
    expect(await reverser.setReversed(book(), false), isNull);
    await reverser.setReversed(book(), true);
    expect(await reverser.setReversed(book(), true), isNull);
    await reverser.setReversed(book(), false);

    final stored = await chapterDao.getByBook(bookUrl);
    expect([for (final c in stored) c.title], titles);
    final saved = (await bookDao.getByUrl(bookUrl))!;
    expect(saved.chapterIndex, 3);
    expect(saved.readConfig!.reverseToc, isFalse);
  });

  test('翻過來之後，還照舊目錄開著的閱讀器存的進度也是同一章', () async {
    final opened = await chapterDao.getByBook(bookUrl);
    final reading = book();
    final controller = ReaderProgressController(
      book: reading,
      repository: ReaderChapterRepository(
        book: reading,
        initialChapters: opened,
        bookDao: bookDao,
        chapterDao: chapterDao,
        sourceDao: BookSourceDao(db),
      ),
      bookDao: bookDao,
    );

    await reverser.setReversed(book(), true);
    await controller.saveImmediately(
      const ReaderLocation(chapterIndex: 3, charOffset: 50),
    );

    final saved = (await bookDao.getByUrl(bookUrl))!;
    final stored = await chapterDao.getByBook(bookUrl);
    expect(stored[saved.chapterIndex].url, 'https://s.example/c/3');
    expect(saved.charOffset, 50);
  });
}
