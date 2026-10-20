import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';

/// 從詳情開的閱讀器換了源，回到詳情時（[BookDetailProvider.reloadAfterReading]）
/// 詳情改顯示換源後的書。閱讀器的部分照它寫進資料庫的結果模擬。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  const oldUrl = 'https://old.example/book/1';
  const newUrl = 'https://new.example/book/9';

  Book bookAt(String url, String origin, {required bool inShelf}) => Book(
    bookUrl: url,
    origin: origin,
    originName: origin,
    name: '測試書',
    author: '作者',
  )..isInBookshelf = inShelf;

  List<BookChapter> chaptersOf(String bookUrl, int count) => [
    for (var i = 0; i < count; i++)
      BookChapter(
        url: '$bookUrl/c$i',
        title: '第${i + 1}章',
        bookUrl: bookUrl,
        index: i,
      ),
  ];

  Future<BookDetailProvider> openDetail() async {
    final book = bookAt(oldUrl, 'https://old.example', inShelf: false);
    await db.chapterDao.insertChapters(chaptersOf(oldUrl, 3));
    final provider = BookDetailProvider(
      AggregatedSearchBook(book: book, sources: []),
      entrance: Future<void>.value(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      chapterContentDao: db.readerChapterContentDao,
    );
    addTearDown(provider.dispose);
    while (!provider.hasReadyWorld) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(provider.totalChapterCount, 3);
    return provider;
  }

  /// 閱讀器換源的寫入：舊的那筆刪掉、新的寫進去，再發出換源事件。
  Future<void> switchInReader({required bool keepNew}) async {
    await db.bookDao.deleteByUrl(oldUrl);
    await db.chapterDao.deleteByBook(oldUrl);
    if (keepNew) {
      await db.bookDao.upsert(
        bookAt(newUrl, 'https://new.example', inShelf: true),
      );
      await db.chapterDao.insertChapters(chaptersOf(newUrl, 5));
    }
    AppEventBus().fire(
      AppEventBus.bookSwitched,
      data: const BookSwitchedEvent(fromBookUrl: oldUrl, toBookUrl: newUrl),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'a source switched in the reader shows when the reader closes',
    () async {
      final provider = await openDetail();

      await switchInReader(keepNew: true);
      // 閱讀器還蓋著時不動。
      expect(provider.book.bookUrl, oldUrl);

      await provider.reloadAfterReading();
      expect(provider.book.bookUrl, newUrl);
      expect(provider.book.origin, 'https://new.example');
      expect(provider.isInBookshelf, isTrue);
      expect(provider.totalChapterCount, 5);
    },
  );

  test('a switched book the reader did not keep leaves the old one '
      'showing off the shelf', () async {
    final provider = await openDetail();

    await switchInReader(keepNew: false);
    await provider.reloadAfterReading();
    expect(provider.book.bookUrl, oldUrl);
    expect(provider.isInBookshelf, isFalse);
    expect(provider.totalChapterCount, 3);
  });

  test('a switch of another book is ignored', () async {
    final provider = await openDetail();

    AppEventBus().fire(
      AppEventBus.bookSwitched,
      data: const BookSwitchedEvent(
        fromBookUrl: 'https://other.example/book/2',
        toBookUrl: newUrl,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await provider.reloadAfterReading();
    expect(provider.book.bookUrl, oldUrl);
  });
}
