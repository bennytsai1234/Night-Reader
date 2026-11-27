import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_progress_sync.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';

/// 開書時抓到的雲端進度；開書前就抓到時照真的同步寫進這台的資料庫。
class _Sync extends Fake implements SyncService {
  PulledProgress? pulled;

  @override
  Future<PulledProgress?> pullProgress(String bookUrl) async => pulled;

  @override
  void uploadsOnHide(Object owner, bool on) {}

  @override
  void openBook(Book book) {}

  @override
  void closeBook(Book book) {}

  @override
  void requestSyncProgressFirst() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dir;
  late BookDao bookDao;
  late ChapterDao chapterDao;
  late BookmarkDao bookmarkDao;

  String body(String marker) => '　　$marker${'正文內容。' * 60}\n';
  final text = '第１章 開始\n${body('甲')}第２章 中間\n${body('乙')}第３章 結尾\n${body('丙')}';

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    chapterDao = ChapterDao(db);
    bookmarkDao = BookmarkDao(db);
    GetIt.instance
      ..registerSingleton<BookDao>(bookDao)
      ..registerSingleton<ChapterDao>(chapterDao)
      ..registerSingleton<BookmarkDao>(bookmarkDao)
      ..registerSingleton<HighlightDao>(HighlightDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db));
    dir = await Directory.systemTemp.createTemp('reader_txt_toc');
  });

  tearDown(() async {
    await LocalBookService().closeOpenFile();
    await db.close();
    await GetIt.instance.reset();
    await dir.delete(recursive: true);
  });

  /// 舊版匯入的書：分章規則還不認全形數字，整本只切成一章，也沒有記下
  /// 分章版本的檔。
  Future<Book> seedOldBook({int chapterIndex = 0, int charOffset = 10}) async {
    final file = File('${dir.path}/全形.txt');
    await file.writeAsString(text);
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      originName: '本地',
      name: '全形',
      author: '本地',
      isInBookshelf: true,
      chapterIndex: chapterIndex,
      charOffset: charOffset,
      durChapterTitle: '正文',
    );
    await bookDao.upsert(book);
    await chapterDao.insertChapters([
      BookChapter(
        url: '${book.bookUrl}#0',
        title: '正文',
        bookUrl: book.bookUrl,
        index: 0,
        start: 0,
        end: utf8.encode(text).length,
      ),
    ]);
    return book;
  }

  ReaderRuntime runtimeFor(Book book, {ReaderOpenTarget? openTarget}) {
    final repository = ReaderChapterRepository(
      book: book,
      bookDao: bookDao,
      chapterDao: chapterDao,
    );
    final runtime = ReaderRuntime(
      book: book,
      repository: repository,
      progressController: ReaderProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderLayoutSpec.fromViewport(
        viewportSize: const Size(220, 180),
        style: const ReaderLayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
          textIndent: 2,
        ),
      ),
      initialLocation: openTarget?.location,
    );
    runtime.registerViewportRestore(Object(), (_) async => true);
    addTearDown(runtime.dispose);
    return runtime;
  }

  test(
    'a TXT split by the old rules is re-split on opening, and the other '
    'phone\'s progress in the new contents opens in the same chapter',
    () async {
      final book = await seedOldBook();
      await bookmarkDao.upsertAll([
        Bookmark(
          id: 1,
          bookName: book.name,
          bookAuthor: book.author,
          chapterTitle: '正文',
          charOffset: text.indexOf('乙'),
        ),
      ]);
      final sync = _Sync();
      // 另一台用新版下載同一個檔，切成三章，讀到「第３章」第 50 個字。
      final theirs = SyncRecord(
        time: 7,
        data: const {
          'chapterIndex': 2,
          'charOffset': 50,
          'chapterTitle': '第３章 結尾',
        },
      );
      sync.pulled = PulledProgress(
        SyncedProgress.fromRecord(theirs),
        (_) async {},
        applyStored: () async {
          final current = await bookDao.getByUrl(book.bookUrl);
          final progress = ProgressSync(
            bookDao: bookDao,
            chapterDao: chapterDao,
          );
          if (!await progress.isAheadOn(current!, theirs)) return null;
          return progress.applyTo(current, theirs);
        },
      );
      final runtime = runtimeFor(book);
      final progressSync = ReaderProgressSync(
        book: book,
        runtime: () => runtime,
        onProgressSuggestion: (_) => fail('開書前就抓到了，不用問'),
        bookDao: bookDao,
        sync: sync,
      )..start();
      addTearDown(progressSync.dispose);

      // 同閱讀器開書：進場播完先對好目錄，再問要不要改停在別處、開書。
      await runtime.ensureChapters();
      final at = await progressSync.openLocation(runtime);
      await runtime.openBook(at: at);

      expect(runtime.chapters, hasLength(3));
      expect(runtime.chapters[2].title, '第３章 結尾');
      expect(runtime.state.visibleLocation.chapterIndex, 2);
      expect(runtime.state.visibleLocation.charOffset, 50);
      // 先開始重新分章的是開書時抓雲端進度的那一頭，書籤一樣跟著換。
      final mark =
          (await bookmarkDao.watchByBook(book.name, book.author).first).single;
      expect(mark.chapterIndex, 1);
      expect(mark.chapterTitle, '第２章 中間');
    },
  );

  test('the reader aligns the contents before asking where to open: the '
      'position it holds is already in the new contents', () async {
    final book = await seedOldBook(charOffset: text.indexOf('乙'));
    final runtime = runtimeFor(book);

    await runtime.alignChaptersBeforeOpen();

    expect(runtime.state.visibleLocation.chapterIndex, 1);
    await runtime.openBook();
    expect(runtime.state.visibleLocation.chapterIndex, 1);
  });

  test('reopening the re-split TXT in the same run does not convert the '
      'new position a second time', () async {
    final book = await seedOldBook();
    final first = runtimeFor(book);
    await first.alignChaptersBeforeOpen();
    await first.openBook();

    // 從目錄點「第３章」重開：位置已經是新目錄的座標。
    final runtime = runtimeFor(
      book,
      openTarget: ReaderOpenTarget.chapterStart(2),
    );
    await runtime.alignChaptersBeforeOpen();
    await runtime.openBook();

    expect(runtime.state.visibleLocation.chapterIndex, 2);
    expect(runtime.state.visibleLocation.charOffset, 0);
  });

  test('opening an old TXT from a bookmark lands in the re-split chapter, '
      'not back in the old chapter title', () async {
    final book = await seedOldBook();
    final start = text.indexOf('丙');
    await bookmarkDao.upsertAll([
      Bookmark(
        id: 1,
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: 0,
        chapterTitle: '正文',
        charOffset: start,
      ),
    ]);
    final target = ReaderOpenTarget.location(
      ReaderLocation(chapterIndex: 0, charOffset: start),
      chapterTitle: '正文',
    );
    final runtime = runtimeFor(book, openTarget: target);

    await runtime.ensureChapters();
    await runtime.openBook(chapterTitle: target.chapterTitle);

    final third = text.substring(text.indexOf('第３章'));
    final visible = runtime.state.visibleLocation;
    expect(visible.chapterIndex, 2);
    // 「丙」在第３章裡的位置（章名一行之後），換算照位元組比例，差一兩個字。
    expect(visible.charOffset, closeTo(third.indexOf('丙'), 2));
  });
}
