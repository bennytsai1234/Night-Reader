import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';

class _FakeCoverStorageService extends Fake
    implements BookCoverStorageService {
  @override
  Future<void> ensureDisplayCoverStored(Book book) async {}

  @override
  Future<int> getBookAssetSize(Book book) async => 0;
}

class _SourceAwareBookSourceService extends BookSourceService {
  _SourceAwareBookSourceService(this.chaptersByOrigin);

  final Map<String, List<BookChapter>> chaptersByOrigin;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    return book;
  }

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return List<BookChapter>.from(
      chaptersByOrigin[source.bookSourceUrl] ?? const <BookChapter>[],
    );
  }

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return '這是一段足夠長的測試正文內容，用來確認換源前會先驗證目標章節可讀。';
  }
}

List<BookChapter> _chapters(String bookUrl, int count) {
  return List<BookChapter>.generate(
    count,
    (index) => BookChapter(
      url: '$bookUrl/chapter/$index',
      title: '第${index + 1}章',
      bookUrl: bookUrl,
      index: index,
    ),
  );
}

AggregatedSearchBook _initialSearchBook() {
  final book = SearchBook(
    bookUrl: 'https://old-source.example/book/1',
    name: '測試書',
    author: '作者',
    origin: 'https://old-source.example',
    originName: '舊源',
  );
  return AggregatedSearchBook(book: book, sources: const <String>['舊源']);
}

SearchBook _newSourceCandidate() {
  return SearchBook(
    bookUrl: 'https://new-source.example/book/1',
    name: '測試書',
    author: '作者',
    origin: 'https://new-source.example',
    originName: '新源',
  );
}

Future<void> _waitForInitialization(BookDetailProvider provider) async {
  for (var i = 0; i < 100 && provider.isLoading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(provider.isLoading, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.bookSourceDao.upsert(
      BookSource(
        bookSourceUrl: 'https://old-source.example',
        bookSourceName: '舊源',
      ),
    );
    await db.bookSourceDao.upsert(
      BookSource(
        bookSourceUrl: 'https://new-source.example',
        bookSourceName: '新源',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('換源成功後才切換 provider 狀態並遷移資料庫', () async {
    final oldUrl = 'https://old-source.example/book/1';
    final newUrl = 'https://new-source.example/book/1';
    final service = _SourceAwareBookSourceService(<String, List<BookChapter>>{
      'https://old-source.example': _chapters(oldUrl, 3),
      'https://new-source.example': _chapters(newUrl, 4),
    });
    final provider = BookDetailProvider(
      _initialSearchBook(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      service: service,
      coverStorage: _FakeCoverStorageService(),
    );
    addTearDown(provider.dispose);
    await _waitForInitialization(provider);

    provider.book.chapterIndex = 1;
    provider.book.charOffset = 17;
    provider.book.visualOffsetPx = 24.5;
    provider.book.durChapterTitle = '第2章';
    await db.bookDao.upsert(provider.book);

    final result = await provider.changeSource(_newSourceCandidate());

    expect(result.success, isTrue);
    expect(provider.book.bookUrl, newUrl);
    expect(provider.book.origin, 'https://new-source.example');
    expect(provider.book.chapterIndex, 1);
    expect(provider.book.charOffset, 17);
    expect(provider.book.visualOffsetPx, 24.5);
    expect(provider.allChapters, hasLength(4));
    expect(await db.bookDao.getByUrl(oldUrl), isNull);
    expect(await db.chapterDao.getByBook(oldUrl), isEmpty);
    expect(await db.bookDao.getByUrl(newUrl), isNotNull);
    expect(await db.chapterDao.getByBook(newUrl), hasLength(4));
  });

  test('新來源沒有目錄時換源失敗且保留舊來源狀態與資料', () async {
    final oldUrl = 'https://old-source.example/book/1';
    final newUrl = 'https://new-source.example/book/1';
    final service = _SourceAwareBookSourceService(<String, List<BookChapter>>{
      'https://old-source.example': _chapters(oldUrl, 3),
      'https://new-source.example': const <BookChapter>[],
    });
    final provider = BookDetailProvider(
      _initialSearchBook(),
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      service: service,
      coverStorage: _FakeCoverStorageService(),
    );
    addTearDown(provider.dispose);
    await _waitForInitialization(provider);

    final result = await provider.changeSource(_newSourceCandidate());

    expect(result.success, isFalse);
    expect(provider.book.bookUrl, oldUrl);
    expect(provider.book.origin, 'https://old-source.example');
    expect(provider.allChapters, hasLength(3));
    expect(await db.bookDao.getByUrl(oldUrl), isNotNull);
    expect(await db.chapterDao.getByBook(oldUrl), hasLength(3));
    expect(await db.bookDao.getByUrl(newUrl), isNull);
    expect(await db.chapterDao.getByBook(newUrl), isEmpty);
  });
}
