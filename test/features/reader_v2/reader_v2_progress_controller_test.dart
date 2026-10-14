import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_toc_replacer.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';

import '../../test_helper.dart';

/// 查完章節序號之後呼叫 [afterLookup]，用來在那一刻插進別的寫入。
class _RacingChapterDao extends ChapterDao {
  _RacingChapterDao(super.db, this.afterLookup);

  final void Function() afterLookup;

  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async {
    final index = await super.indexOfUrl(bookUrl, url);
    afterLookup();
    // 讓另一邊有機會先跑；沒有交易保護時它會在這裡把目錄換掉。
    await pumpEventQueue();
    return index;
  }
}

void main() {
  late AppDatabase db;
  late BookDao bookDao;
  late ChapterDao chapterDao;

  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );

  List<BookChapter> toc(List<String> paths) => [
    for (final (i, path) in paths.indexed)
      BookChapter(
        url: 'https://s.example$path',
        title: path,
        bookUrl: book.bookUrl,
        index: i,
      ),
  ];

  setUpAll(setupTestDI);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    chapterDao = ChapterDao(db);
    await bookDao.upsert(book);
  });

  tearDown(() => db.close());

  ReaderV2ProgressController controllerReading(List<BookChapter> opened) {
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: opened,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: BookSourceDao(db),
    );
    return ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    );
  }

  test('progress saved after a background check renumbered the TOC points '
      'at the same chapter', () async {
    // 開書時的目錄；閱讀中檢查更新在前面插了一章，資料庫已是新目錄。
    final opened = toc(['/c/1', '/c/3']);
    await chapterDao.replaceByBook(book.bookUrl, toc(['/c/1', '/c/2', '/c/3']));
    final controller = controllerReading(opened);

    await controller.saveImmediately(
      const ReaderV2Location(chapterIndex: 1, charOffset: 30),
    );

    final saved = (await bookDao.getByUrl(book.bookUrl))!;
    expect(saved.chapterIndex, 2);
    expect(saved.charOffset, 30);
    expect(jsonDecode(saved.readerAnchorJson!)['chapterIndex'], 2);
    // 閱讀器自己仍照開書時的目錄。
    expect(book.chapterIndex, 1);
  });

  test('a TOC replaced between looking up the chapter and saving still ends '
      'on the same chapter', () async {
    final opened = toc(['/c/1', '/c/3']);
    final renumbered = toc(['/c/1', '/c/2', '/c/3']);
    await chapterDao.replaceByBook(book.bookUrl, opened);
    late Future<void> replacing;
    // 剛查完序號，檢查更新就開始換目錄（不在閱讀器的交易裡）。
    final racingDao = _RacingChapterDao(db, () {
      replacing = Zone.root.run(
        () => bookDao.transaction(() async {
          final stored = (await bookDao.getByUrl(book.bookUrl))!;
          final result = await BookTocReplacer(chapterDao: chapterDao)
              .replace(stored, renumbered.map((c) => c.copyWith()).toList());
          if (result.progressMoved) await bookDao.upsert(stored);
        }),
      );
    });
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: opened,
      bookDao: bookDao,
      chapterDao: racingDao,
      sourceDao: BookSourceDao(db),
    );
    final controller = ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    );

    await controller.saveImmediately(
      const ReaderV2Location(chapterIndex: 1, charOffset: 30),
    );
    await replacing;

    final saved = (await bookDao.getByUrl(book.bookUrl))!;
    expect(saved.chapterIndex, 2);
    expect(saved.charOffset, 30);
  });

  test('progress in an unchanged TOC is saved as is', () async {
    final opened = toc(['/c/1', '/c/2']);
    await chapterDao.replaceByBook(book.bookUrl, opened);
    final controller = controllerReading(opened);

    await controller.saveImmediately(
      const ReaderV2Location(chapterIndex: 1, charOffset: 5),
    );

    final saved = (await bookDao.getByUrl(book.bookUrl))!;
    expect(saved.chapterIndex, 1);
    expect(jsonDecode(saved.readerAnchorJson!)['chapterIndex'], 1);
  });
}
