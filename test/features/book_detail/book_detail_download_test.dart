import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/download_service.dart';
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
