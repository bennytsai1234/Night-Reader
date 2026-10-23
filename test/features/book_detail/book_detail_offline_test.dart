import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';

/// 網路差時書源一直不回：書架上的書照手機裡存的資料打開，不等書源。
class _StalledSourceService extends BookSourceService {
  int bookInfoCalls = 0;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) {
    bookInfoCalls++;
    return Completer<Book>().future;
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  const origin = 'https://source.example';
  const bookUrl = 'https://source.example/book/1';

  Book bookOf({required bool inShelf}) => Book(
    bookUrl: bookUrl,
    origin: origin,
    originName: '書源',
    name: '測試書',
    author: '作者',
  )..isInBookshelf = inShelf;

  BookDetailProvider open(Book book, _StalledSourceService service) {
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

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  setUp(() async {
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: origin, bookSourceName: '書源'),
    );
  });

  test(
    'a shelf book with a stored TOC opens without asking the source',
    () async {
      final book = bookOf(inShelf: true);
      await db.bookDao.upsert(book);
      await db.chapterDao.insertChapters([
        for (var i = 0; i < 3; i++)
          BookChapter(
            url: '$bookUrl/c$i',
            title: '第${i + 1}章',
            bookUrl: bookUrl,
            index: i,
          ),
      ]);
      final service = _StalledSourceService();

      final provider = open(book, service);
      await settle();

      expect(provider.hasReadyWorld, isTrue);
      expect(provider.totalChapterCount, 3);
      expect(service.bookInfoCalls, 0);
    },
  );

  test('a book off the shelf still asks the source', () async {
    final service = _StalledSourceService();

    final provider = open(bookOf(inShelf: false), service);
    await settle();

    expect(service.bookInfoCalls, 1);
    expect(provider.isLoading, isTrue);
  });
}
