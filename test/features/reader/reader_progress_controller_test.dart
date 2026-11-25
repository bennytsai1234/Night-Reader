import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/book_toc_replacer.dart';
import 'package:night_reader/core/storage/moved_chapters.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';

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

  final controllers = <ReaderProgressController>[];
  tearDown(() async {
    // 換目錄的對應是全 App 共用的：閱讀器關掉才不再收。排著與寫到一半的
    // 進度（例如收到對應後的重存）先寫完，才關資料庫。
    for (final controller in controllers) {
      await controller.flush();
      controller.dispose();
    }
    controllers.clear();
    await db.close();
  });

  ReaderProgressController controllerReading(List<BookChapter> opened) {
    final repository = ReaderChapterRepository(
      book: book,
      initialChapters: opened,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: BookSourceDao(db),
    );
    final controller = ReaderProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    );
    controllers.add(controller);
    return controller;
  }

  test('progress saved after a background check renumbered the TOC points '
      'at the same chapter', () async {
    // 開書時的目錄；閱讀中檢查更新在前面插了一章，資料庫已是新目錄。
    final opened = toc(['/c/1', '/c/3']);
    await chapterDao.replaceByBook(book.bookUrl, toc(['/c/1', '/c/2', '/c/3']));
    final controller = controllerReading(opened);

    await controller.saveImmediately(
      const ReaderLocation(chapterIndex: 1, charOffset: 30),
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
    final repository = ReaderChapterRepository(
      book: book,
      initialChapters: opened,
      bookDao: bookDao,
      chapterDao: racingDao,
      sourceDao: BookSourceDao(db),
    );
    final controller = ReaderProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    );
    controllers.add(controller);

    await controller.saveImmediately(
      const ReaderLocation(chapterIndex: 1, charOffset: 30),
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
      const ReaderLocation(chapterIndex: 1, charOffset: 5),
    );

    final saved = (await bookDao.getByUrl(book.bookUrl))!;
    expect(saved.chapterIndex, 1);
    expect(jsonDecode(saved.readerAnchorJson!)['chapterIndex'], 1);
  });

  group('閱讀中檢查更新、書源換了網址（反轉目錄）', () {
    tearDown(MovedChapters.clear);

    // 新到舊的目錄（反轉過存著）：舊目錄 60 章；檢查更新多了兩章新的，
    // 前 25 章換了網址。
    List<BookChapter> newestFirst({required bool moved}) => [
      for (final (i, n) in [
        for (var n = moved ? 62 : 60; n >= 1; n--) n,
      ].indexed)
        BookChapter(
          url: moved && n <= 25
              ? 'https://new.example/c/$n'
              : 'https://s.example/c/$n',
          title: '第$n章 名$n',
          bookUrl: book.bookUrl,
          index: i,
        ),
    ];

    /// 開書後檢查更新換了目錄（同 `BookUpdateService`）：照資料庫裡的書換，
    /// 換了網址的章交給 [MovedChapters]；[record] 是 false 時還沒傳回來。
    Future<List<BookChapter>> checkUpdate({bool record = true}) async {
      final stored = (await bookDao.getByUrl(book.bookUrl))!;
      final result = await BookTocReplacer(chapterDao: chapterDao)
          .replace(stored, newestFirst(moved: true));
      await bookDao.upsert(stored);
      if (record) MovedChapters.record(book.bookUrl, result.moved);
      return result.chapters;
    }

    int indexOfUrl(List<BookChapter> toc, String url) =>
        toc.indexWhere((c) => c.url == url);

    test('存進度照換目錄時記下的新網址，落在同一章', () async {
      final opened = newestFirst(moved: false);
      await chapterDao.replaceByBook(book.bookUrl, opened);
      final controller = controllerReading(opened);
      final toc = await checkUpdate();

      // 閱讀器照開書時的目錄讀到「第24章」，網址已經換了。
      final at = indexOfUrl(opened, 'https://s.example/c/24');
      await controller.saveImmediately(
        ReaderLocation(chapterIndex: at, charOffset: 30),
      );

      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, indexOfUrl(toc, 'https://new.example/c/24'));
      expect(saved.chapterIndex, isNot(at));
      expect(saved.charOffset, 30);
    });

    test('對應還沒傳回來時存的進度，傳回來後重存成同一章', () async {
      final opened = newestFirst(moved: false);
      await chapterDao.replaceByBook(book.bookUrl, opened);
      final controller = controllerReading(opened);
      final at = indexOfUrl(opened, 'https://s.example/c/24');
      await controller.saveImmediately(
        ReaderLocation(chapterIndex: at, charOffset: 30),
      );
      final toc = await checkUpdate(record: false);
      await controller.saveImmediately(
        ReaderLocation(chapterIndex: at, charOffset: 40),
      );
      expect((await bookDao.getByUrl(book.bookUrl))!.chapterIndex, at);

      final moved = {
        for (var n = 1; n <= 25; n++)
          'https://s.example/c/$n': 'https://new.example/c/$n',
      };
      MovedChapters.record(book.bookUrl, moved);
      await pumpEventQueue();
      await controller.flush();

      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, indexOfUrl(toc, 'https://new.example/c/24'));
      expect(saved.charOffset, 40);
    });
  });
}
