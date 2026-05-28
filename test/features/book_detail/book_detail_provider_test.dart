import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/reader_chapter_content.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/services/book_source_service.dart';
import 'package:reader/core/services/download_service.dart';
import 'package:reader/features/book_detail/book_detail_provider.dart';

// ---------------------------------------------------------------------------
// Fake DAOs
// ---------------------------------------------------------------------------

class _FakeBookDao extends Fake implements BookDao {
  final Map<String, Book> _store = {};

  @override
  Future<Book?> getByUrl(String url) async => _store[url];

  @override
  Future<void> upsert(Book book) async => _store[book.bookUrl] = book;

  @override
  Future<void> deleteByUrl(String url) async => _store.remove(url);
}

class _FakeChapterDao extends Fake implements ChapterDao {
  final Map<String, List<BookChapter>> _store = {};

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async =>
      _store[bookUrl] ?? [];

  @override
  Future<void> insertChapters(List<BookChapter> chapters) async {
    if (chapters.isEmpty) return;
    _store[chapters.first.bookUrl] = chapters;
  }

  @override
  Future<void> deleteByBook(String bookUrl) async {
    _store.remove(bookUrl);
  }
}

class _FakeChapterContentDao extends Fake implements ReaderChapterContentDao {
  _FakeChapterContentDao({Set<int> storedIndices = const <int>{}})
    : _storedIndices = Set<int>.from(storedIndices);

  final Set<int> _storedIndices;

  @override
  Future<String?> getContent({required String contentKey}) async {
    return null;
  }

  @override
  Future<ReaderChapterContentEntry?> getEntry({
    required String contentKey,
  }) async {
    return null;
  }

  @override
  Future<List<ReaderChapterContentEntry>> getEntriesByBookUrls(
    Iterable<String> bookUrls,
  ) async {
    final urls = bookUrls.toSet();
    return _storedIndices
        .map(
          (index) => ReaderChapterContentEntry(
            contentKey: 'content_$index',
            origin: 'origin',
            bookUrl: urls.isEmpty ? 'http://book.com' : urls.first,
            chapterUrl: 'chapter_$index',
            chapterIndex: index,
            status: ReaderChapterContentStatus.ready,
            content: 'content $index',
            updatedAt: 1000 + index,
          ),
        )
        .toList();
  }

  @override
  Future<void> saveContent({
    required String contentKey,
    required String origin,
    required String bookUrl,
    required String chapterUrl,
    required int chapterIndex,
    required String content,
    required int updatedAt,
    ReaderChapterContentStatus status = ReaderChapterContentStatus.ready,
    String? failureMessage,
  }) async {
    _storedIndices.add(chapterIndex);
  }

  @override
  Future<Set<int>> getStoredChapterIndices({
    required String origin,
    required String bookUrl,
  }) async {
    return Set<int>.from(_storedIndices);
  }

  @override
  Future<void> deleteByBook(String origin, String bookUrl) async {
    _storedIndices.clear();
  }
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  _FakeSourceDao([this.source]);

  final BookSource? source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

class _FakeBookSourceService extends Fake implements BookSourceService {
  _FakeBookSourceService({this.chapterList = const <BookChapter>[]});

  final List<BookChapter> chapterList;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    dynamic cancelToken,
  }) async => book;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    dynamic cancelToken,
  }) async {
    return chapterList;
  }
}

class _FakeDownloadService extends Fake implements DownloadService {
  Book? queuedBook;
  List<BookChapter> queuedChapters = <BookChapter>[];
  int addDownloadTaskCallCount = 0;

  @override
  Future<void> addDownloadTask(Book book, List<BookChapter> chapters) async {
    addDownloadTaskCallCount++;
    queuedBook = book;
    queuedChapters = List<BookChapter>.from(chapters);
  }
}

// ---------------------------------------------------------------------------
// 測試輔助
// ---------------------------------------------------------------------------

AggregatedSearchBook _makeSearchBook({
  String url = 'http://book.com',
  String origin = 'origin',
  String originName = '書源',
}) {
  final sb = SearchBook(
    bookUrl: url,
    name: '測試書',
    author: '作者',
    origin: origin,
    originName: originName,
  );
  return AggregatedSearchBook(book: sb, sources: ['書源']);
}

List<BookChapter> _makeChapters(int n) => List.generate(
  n,
  (i) => BookChapter(
    url: 'chapter_$i',
    title: '第 $i 章',
    bookUrl: 'http://book.com',
    index: i,
  ),
);

// ---------------------------------------------------------------------------
// 測試
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GetIt.instance.registerLazySingleton<BookDao>(() => _FakeBookDao());
    GetIt.instance.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());
    GetIt.instance.registerLazySingleton<ReaderChapterContentDao>(
      () => _FakeChapterContentDao(),
    );
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());
  });

  tearDown(() async => GetIt.instance.reset());

  Future<BookDetailProvider> makeProvider({
    String url = 'http://book.com',
    String origin = 'origin',
    List<BookChapter> chapters = const [],
    BookSource? source,
    BookSourceService? service,
    DownloadService? downloadService,
    Set<int> storedIndices = const <int>{},
  }) async {
    final chapterDao = GetIt.instance<ChapterDao>() as _FakeChapterDao;
    if (chapters.isNotEmpty) {
      await chapterDao.insertChapters(chapters);
    }
    final p = BookDetailProvider(
      _makeSearchBook(url: url, origin: origin),
      sourceDao: _FakeSourceDao(source),
      chapterContentDao: _FakeChapterContentDao(storedIndices: storedIndices),
      service: service ?? _FakeBookSourceService(chapterList: chapters),
      downloadService: downloadService ?? _FakeDownloadService(),
    );
    for (var i = 0; i < 20 && p.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return p;
  }

  group('BookDetailProvider - 初始狀態', () {
    test('未在書架時 isInBookshelf 為 false', () async {
      final p = await makeProvider();
      expect(p.isInBookshelf, isFalse);
      expect(p.isLoading, isFalse);
    });

    test('DAO 中已有該書時 isInBookshelf 為 true', () async {
      final bookDao = GetIt.instance<BookDao>() as _FakeBookDao;
      final book = Book(
        bookUrl: 'http://book.com',
        name: '存在的書',
        author: '作者',
        origin: 'o',
        originName: 'on',
        isInBookshelf: true,
      );
      await bookDao.upsert(book);

      final p = await makeProvider();
      expect(p.isInBookshelf, isTrue);
    });
  });

  group('BookDetailProvider - 書架操作', () {
    test('加入書架期間不切換成全頁載入狀態', () async {
      final p = await makeProvider();

      final resultFuture = p.setInBookshelf(true);

      expect(p.isInBookshelf, isTrue);
      expect(p.isLoading, isFalse);

      final result = await resultFuture;
      expect(result.success, isTrue);
      expect(p.isLoading, isFalse);
    });

    test('加入書架會用第一章初始化目前章節', () async {
      final chapters = _makeChapters(3);
      final p = await makeProvider(chapters: chapters);

      final result = await p.setInBookshelf(true);

      expect(result.success, isTrue);
      expect(p.book.chapterIndex, 0);
      expect(p.book.charOffset, 0);
      expect(p.book.durChapterTitle, '第 0 章');
      final stored = await (GetIt.instance<BookDao>() as _FakeBookDao).getByUrl(
        'http://book.com',
      );
      expect(stored?.chapterIndex, 0);
      expect(stored?.durChapterTitle, '第 0 章');
    });

    test('加入書架不會覆蓋既有閱讀進度', () async {
      final chapters = _makeChapters(3);
      final bookDao = GetIt.instance<BookDao>() as _FakeBookDao;
      await bookDao.upsert(
        Book(
          bookUrl: 'http://book.com',
          name: '測試書',
          author: '作者',
          origin: 'origin',
          originName: '書源',
          chapterIndex: 2,
          charOffset: 15,
          durChapterTitle: '既有章節',
        ),
      );
      final p = await makeProvider(chapters: chapters);

      final result = await p.setInBookshelf(true);

      expect(result.success, isTrue);
      expect(p.book.chapterIndex, 2);
      expect(p.book.charOffset, 15);
      expect(p.book.durChapterTitle, '既有章節');
      final stored = await bookDao.getByUrl('http://book.com');
      expect(stored?.chapterIndex, 2);
      expect(stored?.charOffset, 15);
      expect(stored?.durChapterTitle, '既有章節');
    });
  });

  group('BookDetailProvider - 章節篩選', () {
    test('setSearchQuery 篩選章節', () async {
      final chapters = _makeChapters(5);
      chapters[2] = BookChapter(
        url: 'chapter_2',
        title: '特殊章節',
        bookUrl: 'http://book.com',
        index: 2,
      );
      final p = await makeProvider(chapters: chapters);

      p.setSearchQuery('特殊');
      await Future.delayed(const Duration(milliseconds: 350)); // debounce
      expect(p.filteredChapters, hasLength(1));
      expect(p.filteredChapters.first.title, '特殊章節');
    });

    test('清空 searchQuery 恢復全部章節', () async {
      final p = await makeProvider(chapters: _makeChapters(5));

      p.setSearchQuery('不存在');
      await Future.delayed(const Duration(milliseconds: 350));
      expect(p.filteredChapters, isEmpty);

      p.setSearchQuery('');
      await Future.delayed(const Duration(milliseconds: 350));
      expect(p.filteredChapters, hasLength(5));
    });

    test('toggleSort 反轉章節順序', () async {
      final p = await makeProvider(chapters: _makeChapters(3));
      expect(p.filteredChapters.first.index, 0);

      p.toggleSort();
      expect(p.isReversed, isTrue);
      expect(p.filteredChapters.first.index, 2);

      p.toggleSort();
      expect(p.filteredChapters.first.index, 0);
    });

    test('totalChapterCount 正確回傳數量', () async {
      final p = await makeProvider(chapters: _makeChapters(7));
      expect(p.totalChapterCount, 7);
    });
  });

  group('BookDetailProvider - 背景下載佇列', () {
    test('queueDownloadAll 會保留未入書架狀態並加入背景下載', () async {
      final downloadService = _FakeDownloadService();
      final chapters = _makeChapters(3);
      final provider = await makeProvider(
        chapters: chapters,
        source: BookSource(bookSourceUrl: 'origin', bookSourceName: '測試書源'),
        downloadService: downloadService,
      );

      final result = await provider.queueDownloadAll();

      expect(result.queuedChapterCount, 3);
      expect(result.message, '已加入背景下載佇列，共 3 章');
      expect(downloadService.addDownloadTaskCallCount, 1);
      expect(downloadService.queuedChapters, hasLength(3));
      expect(provider.isInBookshelf, isFalse);
      expect(
        await (GetIt.instance<BookDao>() as _FakeBookDao).getByUrl(
          'http://book.com',
        ),
        isNotNull,
      );
    });

    test('queueDownloadMissing 只會加入未下載章節', () async {
      final downloadService = _FakeDownloadService();
      final provider = await makeProvider(
        chapters: _makeChapters(5),
        storedIndices: <int>{1, 3},
        source: BookSource(bookSourceUrl: 'origin', bookSourceName: '測試書源'),
        downloadService: downloadService,
      );

      final result = await provider.queueDownloadMissing();

      expect(result.queuedChapterCount, 3);
      expect(
        downloadService.queuedChapters.map((chapter) => chapter.index).toList(),
        <int>[0, 2, 4],
      );
    });

    test('queueDownloadFromCurrent 會從目前章節下載到結尾', () async {
      final downloadService = _FakeDownloadService();
      final provider = await makeProvider(
        chapters: _makeChapters(5),
        source: BookSource(bookSourceUrl: 'origin', bookSourceName: '測試書源'),
        downloadService: downloadService,
      );
      provider.book.chapterIndex = 2;

      final result = await provider.queueDownloadFromCurrent();

      expect(result.queuedChapterCount, 3);
      expect(
        downloadService.queuedChapters.map((chapter) => chapter.index).toList(),
        <int>[2, 3, 4],
      );
    });

    test('queueDownloadRange 會加入指定章節範圍', () async {
      final downloadService = _FakeDownloadService();
      final provider = await makeProvider(
        chapters: _makeChapters(5),
        source: BookSource(bookSourceUrl: 'origin', bookSourceName: '測試書源'),
        downloadService: downloadService,
      );

      final result = await provider.queueDownloadRange(1, 3);

      expect(result.queuedChapterCount, 3);
      expect(
        downloadService.queuedChapters.map((chapter) => chapter.index).toList(),
        <int>[1, 2, 3],
      );
    });

    test('queueDownloadAll 會在缺少書源時阻擋背景下載', () async {
      final downloadService = _FakeDownloadService();
      final provider = await makeProvider(
        chapters: _makeChapters(2),
        downloadService: downloadService,
      );

      final result = await provider.queueDownloadAll();

      expect(result.queuedChapterCount, 0);
      expect(result.message, '目前找不到書源，請先換源後再試。');
      expect(downloadService.addDownloadTaskCallCount, 0);
      expect(provider.isInBookshelf, isFalse);
    });

    test('queueDownloadAll 會略過本地書籍的背景下載任務', () async {
      final downloadService = _FakeDownloadService();
      final provider = await makeProvider(
        origin: 'local',
        chapters: _makeChapters(2),
        downloadService: downloadService,
      );

      final result = await provider.queueDownloadAll();

      expect(result.queuedChapterCount, 0);
      expect(result.message, '這本書已經在裝置內，不需要背景下載。');
      expect(downloadService.addDownloadTaskCallCount, 0);
    });

    test('queueDownloadNext 會從目前章節起加入指定數量章節', () async {
      final downloadService = _FakeDownloadService();
      final provider = await makeProvider(
        chapters: _makeChapters(8),
        source: BookSource(bookSourceUrl: 'origin', bookSourceName: '測試書源'),
        downloadService: downloadService,
      );
      provider.book.chapterIndex = 3;

      final result = await provider.queueDownloadNext(2);

      expect(result.queuedChapterCount, 2);
      expect(
        downloadService.queuedChapters.map((chapter) => chapter.index),
        <int>[3, 4],
      );
    });
  });

  group('BookDetailProvider - 快取與更新', () {
    test('cacheStatus 會統計已快取章節，清正文後歸零', () async {
      final provider = await makeProvider(
        chapters: _makeChapters(5),
        storedIndices: <int>{1, 3},
      );

      await provider.refreshCacheStatus();
      expect(provider.cacheStatus.storedChapterCount, 2);
      expect(provider.cacheStatus.totalChapterCount, 5);

      final result = await provider.clearBookCache(
        BookDetailCacheClearTarget.content,
      );

      expect(result.success, isTrue);
      expect(provider.cacheStatus.storedChapterCount, 0);
    });

    test('checkForUpdates 會更新章節列表並回報新增章節數', () async {
      final provider = await makeProvider(
        chapters: _makeChapters(2),
        source: BookSource(bookSourceUrl: 'origin', bookSourceName: '測試書源'),
        service: _FakeBookSourceService(chapterList: _makeChapters(4)),
      );

      final result = await provider.checkForUpdates();

      expect(result.success, isTrue);
      expect(result.newChapterCount, 2);
      expect(provider.totalChapterCount, 4);
      expect(provider.book.latestChapterTitle, '第 3 章');
    });
  });
}
