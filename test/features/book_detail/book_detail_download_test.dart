import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';

class _Source extends BookSourceService {
  _Source(this.toc);

  final List<BookChapter> toc;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async => book;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async => toc;
}

/// 只記下排了哪本書的下載。
class _Downloads implements DownloadService {
  final List<String> queued = [];

  final List<String> kept = [];

  @override
  Future<void> keepShelfBookDownloaded(
    String bookUrl, {
    bool hasNewChapters = false,
  }) async => kept.add(bookUrl);

  @override
  Future<void> addDownloadTask(
    Book book,
    List<BookChapter> chapters, {
    BookChapter? from,
    BookChapter? to,
  }) async => queued.add(book.bookUrl);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const origin = 'https://source.example';
const bookUrl = 'https://source.example/book/1';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: origin, bookSourceName: '書源'),
    );
  });
  tearDown(() => db.close());

  final chapters = [
    for (var i = 0; i < 3; i++)
      BookChapter(
        url: '$bookUrl/c$i',
        title: '第${i + 1}章',
        bookUrl: bookUrl,
        index: i,
      ),
  ];

  group('清除已下載的正文', clearContentTests);

  test('downloading a book off the shelf adds it to the shelf, so the '
      'download is kept', () async {
    final downloads = _Downloads();
    final provider = BookDetailProvider(
      AggregatedSearchBook(
        book: Book(
          bookUrl: bookUrl,
          origin: origin,
          originName: '書源',
          name: '測試書',
          author: '作者',
        ),
        sources: [],
      ),
      entrance: Future<void>.value(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      chapterContentDao: db.readerChapterContentDao,
      service: _Source(chapters),
      downloadService: downloads,
    );
    addTearDown(provider.dispose);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!provider.hasReadyWorld) {
      if (DateTime.now().isAfter(deadline)) fail('詳情頁沒載入完');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(provider.isInBookshelf, isFalse);

    final result = await provider.queueDownloadRange(0, 1);

    expect(result.message, '已加入書架與背景下載佇列，共 2 章');
    expect(downloads.queued, [bookUrl]);
    expect(provider.isInBookshelf, isTrue);
    expect((await db.bookDao.getByUrl(bookUrl))!.isInBookshelf, isTrue);
    expect(await db.chapterDao.getByBook(bookUrl), hasLength(3));
  });
}

void clearContentTests() {
  late AppDatabase db;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('book_detail_clear');
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: origin, bookSourceName: '書源'),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('清除已下載的正文：正文與插圖都刪掉，書架自動下載重抓', () async {
    final book = Book(
      bookUrl: bookUrl,
      origin: origin,
      originName: '書源',
      name: '測試書',
      author: '作者',
      isInBookshelf: true,
    );
    final chapter = BookChapter(
      url: '$bookUrl/c0',
      title: '第1章',
      bookUrl: bookUrl,
      index: 0,
    );
    await db.bookDao.upsert(book);
    await db.chapterDao.insertChapters([chapter]);
    await ReaderChapterContentStore(
      chapterDao: db.chapterDao,
      contentDao: db.readerChapterContentDao,
    ).saveRawContent(
      book: book,
      chapter: chapter,
      content: '前文\n<img src="https://source.example/1.png">\n後文',
    );
    final image = File(
      BookIllustrationStorage.pathFor(
        await BookIllustrationStorage.dirFor(book),
        'https://source.example/1.png',
      ),
    );
    await image.create(recursive: true);

    final downloads = _Downloads();
    final provider = BookDetailProvider(
      AggregatedSearchBook(book: book, sources: []),
      entrance: Future<void>.value(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      chapterContentDao: db.readerChapterContentDao,
      service: _Source([chapter]),
      downloadService: downloads,
    );
    addTearDown(provider.dispose);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!provider.hasReadyWorld) {
      if (DateTime.now().isAfter(deadline)) fail('詳情頁沒載入完');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final result = await provider.clearStoredContent();

    expect(result.success, isTrue);
    expect(
      await db.readerChapterContentDao.getStoredChapterUrls(
        origin: origin,
        bookUrl: bookUrl,
      ),
      isEmpty,
    );
    expect(image.existsSync(), isFalse);
    expect(provider.cacheStatus.hasContentCache, isFalse);
    expect(downloads.kept, [bookUrl]);
  });
}
