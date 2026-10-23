import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';

/// 網路差時書源一直不回：書架上、手機裡有目錄的書照存著的資料打開，不等
/// 書源；其他書照舊向書源要。
class _FakeSourceService extends BookSourceService {
  /// 給了就回這個封面，沒給就一直不回（網路差）。
  String? infoCover;

  /// 目錄：給了就回，沒給就一直不回。
  List<BookChapter>? toc;

  int bookInfoCalls = 0;
  int chapterListCalls = 0;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) {
    bookInfoCalls++;
    final cover = infoCover;
    if (cover == null) return Completer<Book>().future;
    return Future.value(book.copyWith(coverUrl: cover));
  }

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) {
    chapterListCalls++;
    final chapters = toc;
    if (chapters == null) return Completer<List<BookChapter>>().future;
    return Future.value(chapters);
  }
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

  Book bookOf({required bool inShelf}) => Book(
    bookUrl: bookUrl,
    origin: origin,
    originName: '書源',
    name: '測試書',
    author: '作者',
  )..isInBookshelf = inShelf;

  final chapters = [
    for (var i = 0; i < 3; i++)
      BookChapter(
        url: '$bookUrl/c$i',
        title: '第${i + 1}章',
        bookUrl: bookUrl,
        index: i,
      ),
  ];

  BookDetailProvider open(Book book, _FakeSourceService service) {
    final provider = BookDetailProvider(
      AggregatedSearchBook(book: book, sources: []),
      entrance: Future<void>.value(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      chapterContentDao: db.readerChapterContentDao,
      service: service,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  /// 等到 [condition] 成立；兩秒還不成立就算失敗。
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('等不到預期的狀態');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'a shelf book with a stored TOC opens without asking the source',
    () async {
      await db.bookDao.upsert(bookOf(inShelf: true));
      await db.chapterDao.insertChapters(chapters);
      final service = _FakeSourceService();

      // 從搜尋結果點進來：手上的書沒標在書架上，照資料庫裡的為準。
      final provider = open(bookOf(inShelf: false), service);
      await until(() => provider.hasReadyWorld);

      expect(provider.isInBookshelf, isTrue);
      expect(provider.totalChapterCount, 3);
      expect(service.bookInfoCalls, 0);
      expect(service.chapterListCalls, 0);
    },
  );

  test('a shelf book without a stored TOC still asks the source', () async {
    await db.bookDao.upsert(bookOf(inShelf: true));
    final service = _FakeSourceService()
      ..infoCover = 'https://source.example/cover.jpg'
      ..toc = chapters;

    final provider = open(bookOf(inShelf: true), service);
    await until(() => provider.hasReadyWorld);

    expect(service.bookInfoCalls, 1);
    expect(service.chapterListCalls, 1);
    expect(provider.totalChapterCount, 3);
    expect(await db.chapterDao.getByBook(bookUrl), hasLength(3));
  });

  test(
    'a book off the shelf with a stored TOC still asks the source',
    () async {
      await db.bookDao.upsert(bookOf(inShelf: false));
      await db.chapterDao.insertChapters(chapters);
      final service = _FakeSourceService();

      final provider = open(bookOf(inShelf: false), service);
      await until(() => service.bookInfoCalls == 1);

      expect(provider.isLoading, isTrue);
    },
  );

  test('the cover goes to the search page before the TOC comes back', () async {
    final service = _FakeSourceService()
      ..infoCover = 'https://source.example/cover.jpg';
    final covers = <BookCoverEvent>[];
    final sub = AppEventBus()
        .onName(AppEventBus.bookCover)
        .listen((event) => covers.add(event.data as BookCoverEvent));
    addTearDown(sub.cancel);

    final provider = open(bookOf(inShelf: false), service);
    await until(() => service.chapterListCalls == 1);
    await until(() => covers.isNotEmpty);

    expect(covers.single.cover, 'https://source.example/cover.jpg');
    expect(provider.isLoading, isTrue);
  });
}
