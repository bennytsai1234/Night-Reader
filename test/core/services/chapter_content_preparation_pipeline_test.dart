import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/engine/web_book/illustration_fetcher.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';

import '../../test_helper.dart';

/// 網站把這本書改成付費：正文頁只回付費提示。
class _PaywalledSite extends BookSourceService {
  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => '本章為付費章節，請訂閱後閱讀';
}

/// 插圖在這裡直接抓（不經書源 isolate），記下被叫了幾次。
class _IllustratedSite extends BookSourceService {
  int fetches = 0;

  @override
  Future<int> fetchIllustrations(
    BookSource source,
    Book book,
    String content, {
    required String dir,
    bool retryMissing = true,
    CancelToken? cancelToken,
  }) {
    fetches += 1;
    return IllustrationFetcher.fetch(
      source,
      book,
      content,
      dir,
      retryMissing: retryMissing,
      cancelToken: cancelToken,
    );
  }
}

/// 正文抓得到，裡面的圖連不上。
class _UnreachableImages extends BookSourceService {
  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => '前文\n<img src="https://s.example/1.png">\n後文';

  @override
  Future<int> fetchIllustrations(
    BookSource source,
    Book book,
    String content, {
    required String dir,
    bool retryMissing = true,
    CancelToken? cancelToken,
  }) async => 1;
}

/// 只有開頭的 PNG（寬 300、高 200），夠讀出寬高。
final _png = Uint8List(24)
  ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  ..setAll(16, [0, 0, 0x01, 0x2C, 0, 0, 0, 0xC8]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  late AppDatabase db;
  late ReaderChapterContentStore store;
  late ChapterContentPreparationPipeline pipeline;

  final source = BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'https://s.example',
  });
  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );
  BookChapter lockedChapter() => BookChapter(
    url: 'https://s.example/c/1.html',
    title: '第一章',
    bookUrl: book.bookUrl,
    isVip: true,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = ReaderChapterContentStore(
      chapterDao: ChapterDao(db),
      contentDao: ReaderChapterContentDao(db),
    );
    pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: store,
      sourceDao: BookSourceDao(db),
      service: _PaywalledSite(),
      getSource: () => source,
    );
  });

  tearDown(() => db.close());

  test('a paid chapter not bought yet is shown but not stored', () async {
    final result = await pipeline.prepare(
      chapterIndex: 0,
      chapter: lockedChapter(),
    );

    expect(result.content, '本章為付費章節，請訂閱後閱讀');
    expect(
      await store.getContentEntry(book: book, chapter: lockedChapter()),
      isNull,
    );
  });

  test('a snapshot from before the chapter turned paid neither stores the '
      'notice nor unlocks the chapter', () async {
    // 閱讀器或下載拿到的是免費時的快照；之後檢查更新把它標成付費。
    final snapshot = lockedChapter()..isVip = false;
    final chapterDao = ChapterDao(db);
    await chapterDao.insertChapters([snapshot.copyWith()]);
    await store.saveRawContent(
      book: book,
      chapter: snapshot,
      content: '免費時的正文',
    );
    await chapterDao.insertChapters([lockedChapter()]);

    final result = await pipeline.prepare(
      chapterIndex: 0,
      chapter: snapshot,
      forceRefresh: true,
    );

    expect(result.content, '本章為付費章節，請訂閱後閱讀');
    expect(
      (await store.getContentEntry(book: book, chapter: snapshot))!.content,
      '免費時的正文',
    );
    expect(
      (await chapterDao.getByUrl(snapshot.bookUrl, snapshot.url))!.isLocked,
      isTrue,
    );
  });

  test('a fresh chapter whose illustrations could not be reached is ready, '
      'and the book is marked for the shelf download to fetch them', () async {
    final root = await Directory.systemTemp.createTemp('pipeline_unreachable');
    addTearDown(() => root.delete(recursive: true));
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
    final offline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: store,
      sourceDao: BookSourceDao(db),
      service: _UnreachableImages(),
      getSource: () => source,
    );
    final chapter = BookChapter(
      url: 'https://s.example/c/3.html',
      title: '第三章',
      bookUrl: book.bookUrl,
    );

    final result = await offline.prepare(chapterIndex: 0, chapter: chapter);

    expect(result.isReady, isTrue);
    expect(await BookIllustrationStorage.isUnfetched(book), isTrue);
    expect(await offline.illustrationsSettled(result.content), isFalse);
  });

  test('stored text whose illustrations are not on this phone (restored from '
      'a backup) fetches them once before it is ready', () async {
    final root = await Directory.systemTemp.createTemp('pipeline_images');
    addTearDown(() => root.delete(recursive: true));
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
    final site = _IllustratedSite();
    final illustrated = ChapterContentPreparationPipeline(
      book: book,
      contentStore: store,
      sourceDao: BookSourceDao(db),
      service: site,
      getSource: () => source,
    );
    final good = 'data:image/png;base64,${base64Encode(_png)}';
    final bad = 'data:image/png;base64,${base64Encode(utf8.encode('404'))}';
    final chapter = BookChapter(
      url: 'https://s.example/c/2.html',
      title: '第二章',
      bookUrl: book.bookUrl,
    );
    await store.saveRawContent(
      book: book,
      chapter: chapter,
      content: '前文\n<img src="$good">\n<img src="$bad">\n後文',
    );

    await illustrated.prepare(chapterIndex: 0, chapter: chapter);
    final dir = await BookIllustrationStorage.dirFor(book);
    expect(
      File(BookIllustrationStorage.pathFor(dir, good)).existsSync(),
      isTrue,
    );
    expect(site.fetches, 1);

    // 都抓過了（壞的那張記成確定抓不到）：再打開不再抓。
    await illustrated.prepare(chapterIndex: 0, chapter: chapter);
    expect(site.fetches, 1);
  });

  test('content stored while the chapter was free is kept', () async {
    final chapter = lockedChapter();
    await store.saveRawContent(
      book: book,
      chapter: chapter.copyWith(isVip: false),
      content: '免費時的正文',
    );

    final reread = await pipeline.prepare(chapterIndex: 0, chapter: chapter);
    final refreshed = await pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      forceRefresh: true,
    );

    expect(reread.content, '免費時的正文');
    expect(refreshed.content, '本章為付費章節，請訂閱後閱讀');
    expect(
      (await store.getContentEntry(book: book, chapter: chapter))!.content,
      '免費時的正文',
    );
  });
}
