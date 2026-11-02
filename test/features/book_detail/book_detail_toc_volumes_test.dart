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

/// 書架上、手機裡有目錄的書不向書源要；這裡只讓它永遠不回。
class _SilentSourceService extends BookSourceService {
  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) => Completer<Book>().future;
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

  // 0 第一卷（1–2）、3 第二卷（4–5）；讀到第 4 個（第二卷第一章）。
  final titles = ['第一卷', '第1章', '第2章', '第二卷', '第3章', '第4章'];
  final chapters = [
    for (var i = 0; i < titles.length; i++)
      BookChapter(
        url: '$bookUrl/c$i',
        title: titles[i],
        bookUrl: bookUrl,
        index: i,
        isVolume: titles[i].endsWith('卷'),
      ),
  ];

  Future<BookDetailProvider> open() async {
    final book = Book(
      bookUrl: bookUrl,
      origin: origin,
      originName: '書源',
      name: '測試書',
      author: '作者',
      chapterIndex: 4,
    )..isInBookshelf = true;
    await db.bookDao.upsert(book);
    await db.chapterDao.insertChapters(chapters);
    final provider = BookDetailProvider(
      AggregatedSearchBook(book: book, sources: []),
      entrance: Future<void>.value(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      chapterContentDao: db.readerChapterContentDao,
      service: _SilentSourceService(),
    );
    addTearDown(provider.dispose);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!provider.hasReadyWorld) {
      if (DateTime.now().isAfter(deadline)) fail('等不到詳情載入完');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  List<String> shown(BookDetailProvider provider) => [
    for (final chapter in provider.filteredChapters) chapter.title,
  ];

  test('volumes read before the current chapter open collapsed and can be '
      'expanded; locating the current chapter expands its volume', () async {
    final provider = await open();
    expect(provider.groupsVolumes, isTrue);
    expect(provider.tocVolumes.chapterCount, 4);
    expect(shown(provider), ['第一卷', '第二卷', '第3章', '第4章']);
    expect(provider.displayPositionAt(1), 3);

    provider.toggleVolume(0);
    expect(shown(provider), titles);

    provider.toggleVolume(3);
    expect(shown(provider), ['第一卷', '第1章', '第2章', '第二卷']);
    provider.resetTocViewForCurrentChapter();
    expect(shown(provider), titles);
  });

  test('searching or reversing lists every match without grouping, and the '
      'rows still know where they are in the full list', () async {
    final provider = await open();

    provider.toggleSort();
    expect(provider.groupsVolumes, isFalse);
    expect(shown(provider), titles.reversed.toList());
    expect(provider.displayPositionAt(0), 5);

    provider.toggleSort();
    provider.setSearchQuery('第1');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(provider.groupsVolumes, isFalse);
    expect(shown(provider), ['第1章']);
    expect(provider.displayPositionAt(0), 1);

    provider.clearTocSearch();
    expect(shown(provider), ['第一卷', '第二卷', '第3章', '第4章']);
  });
}
