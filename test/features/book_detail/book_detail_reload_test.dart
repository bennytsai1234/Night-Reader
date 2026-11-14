import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
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

  test(
    'editing book info and cover refreshes the bookshelf once per save',
    () async {
      var refreshes = 0;
      final subscription = AppEventBus()
          .onName(AppEventBus.upBookshelf)
          .listen((_) => refreshes++);
      addTearDown(subscription.cancel);
      final provider = await openDetail();

      // 沒有成功儲存時，不要求書架重讀。
      final rejected = await provider.updateBookInfo('  ', '作者', '', '');
      expect(rejected.success, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 0);

      final edited = await provider.updateBookInfo('新書名', '新作者', '新簡介', '');
      expect(edited.success, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 1);
      expect((await db.bookDao.getByUrl(oldUrl))?.name, '新書名');
      expect((await db.bookDao.getByUrl(oldUrl))?.author, '新作者');

      final covered = await provider.updateCover('');
      expect(covered.success, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 2);

      // 原本就會通知書架的自動檢查更新開關仍然照常運作。
      final updateCheck = await provider.setCanUpdate(false);
      expect(updateCheck.success, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 3);
    },
  );

  test('a source edited elsewhere is read again on return', () async {
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: 'https://old.example', bookSourceName: '舊名字'),
    );
    final provider = await openDetail();
    expect(provider.currentSource?.bookSourceName, '舊名字');

    // 書源編輯頁存檔只寫進資料庫。
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: 'https://old.example', bookSourceName: '新名字'),
    );
    await provider.reloadSource();

    // 下次開編輯頁拿到的是存過的規則，不會蓋掉剛才的修改。
    expect(provider.currentSource?.bookSourceName, '新名字');
  });
}
