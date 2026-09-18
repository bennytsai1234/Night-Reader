import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';

class _FakeBookSourceService extends BookSourceService {
  _FakeBookSourceService({
    required this.chapters,
    this.content = '這是一段足夠長的章節正文內容，用來通過可讀性檢查。',
    this.throwOnChapterList = false,
  });

  final List<BookChapter> chapters;
  final String content;
  final bool throwOnChapterList;

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
    if (throwOnChapterList) return const <BookChapter>[];
    return chapters;
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
    return content;
  }
}

class _SearchTrackingBookSourceService extends BookSourceService {
  int preciseSearchCalls = 0;
  int nameOnlySearchCalls = 0;

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author,
  ) async {
    preciseSearchCalls++;
    return const <SearchBook>[];
  }

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    nameOnlySearchCalls++;
    final candidate = SearchBook(
      bookUrl: '${source.bookSourceUrl}/book/1',
      name: key,
      author: '不同作者',
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
    );
    return filter?.call(candidate.name, candidate.author ?? '') == false
        ? const <SearchBook>[]
        : <SearchBook>[candidate];
  }
}

class _EnabledBookSourceDao extends Fake implements BookSourceDao {
  _EnabledBookSourceDao(this.sources);

  final List<BookSource> sources;

  @override
  Future<List<BookSource>> getEnabled() async => sources;
}

BookSource _source(String url, String name) {
  return BookSource(bookSourceUrl: url, bookSourceName: name);
}

SearchBook _candidate(String origin) {
  return SearchBook(
    bookUrl: '$origin/book/1',
    name: '測試書',
    author: '作者',
    origin: origin,
    originName: '新源',
    tocUrl: '$origin/toc/1',
  );
}

Book _currentBook({
  int chapterIndex = 5,
  String? durChapterTitle = '第6章',
  int totalChapterNum = 100,
}) {
  return Book(
    bookUrl: 'old-origin/book/1',
    origin: 'old-origin',
    originName: '舊源',
    name: '測試書',
    author: '作者',
    chapterIndex: chapterIndex,
    durChapterTitle: durChapterTitle,
    totalChapterNum: totalChapterNum,
    isInBookshelf: true,
  );
}

List<BookChapter> _chapters(String bookUrl, int count) {
  return List<BookChapter>.generate(
    count,
    (i) => BookChapter(
      url: '$bookUrl/c$i',
      title: '第${i + 1}章',
      bookUrl: bookUrl,
      index: i,
    ),
  );
}

Future<void> _seedOldContent(AppDatabase db, Book oldBook) async {
  final chapterUrl = '${oldBook.bookUrl}/cached/0';
  await db.readerChapterContentDao.saveContent(
    contentKey: ReaderChapterContentDao.contentKey(
      origin: oldBook.origin,
      bookUrl: oldBook.bookUrl,
      chapterUrl: chapterUrl,
    ),
    origin: oldBook.origin,
    bookUrl: oldBook.bookUrl,
    chapterUrl: chapterUrl,
    chapterIndex: 0,
    content: '舊來源已下載的完整正文內容',
    updatedAt: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourceSwitchService.searchAlternatives', () {
    test('停用作者比對時以書名搜尋，不會要求候選作者為空字串', () async {
      final source = _source('new-origin', '新源');
      final sourceService = _SearchTrackingBookSourceService();
      final service = SourceSwitchService(
        service: sourceService,
        sourceDao: _EnabledBookSourceDao(<BookSource>[source]),
      );

      final results = await service.searchAlternatives(
        _currentBook(),
        checkAuthor: false,
      );

      expect(results, hasLength(1));
      expect(results.single.author, '不同作者');
      expect(sourceService.nameOnlySearchCalls, 1);
      expect(sourceService.preciseSearchCalls, 0);
    });

    test('原書沒有作者時自動退化為書名搜尋', () async {
      final source = _source('new-origin', '新源');
      final sourceService = _SearchTrackingBookSourceService();
      final service = SourceSwitchService(
        service: sourceService,
        sourceDao: _EnabledBookSourceDao(<BookSource>[source]),
      );

      final results = await service.searchAlternatives(
        _currentBook().copyWith(author: '   '),
      );

      expect(results, hasLength(1));
      expect(sourceService.nameOnlySearchCalls, 1);
      expect(sourceService.preciseSearchCalls, 0);
    });
  });

  group('SourceSwitchService.resolveSwitch', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.bookSourceDao.upsert(_source('new-origin', '新源'));
    });

    tearDown(() async {
      await db.close();
    });

    test('按標題對齊到目標章節索引', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.resolveSwitch(
        _currentBook(chapterIndex: 5, durChapterTitle: '第6章'),
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
        validateTargetContent: true,
      );

      expect(resolution.targetChapterIndex, 5);
      expect(resolution.chapters.length, 100);
      expect(resolution.migratedBook.origin, 'new-origin');
      expect(resolution.validatedContent, isNotNull);
    });

    test('新源章節數較少時 clamp 不越界', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 10);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.resolveSwitch(
        _currentBook(
          chapterIndex: 50,
          durChapterTitle: '不存在的章節',
          totalChapterNum: 100,
        ),
        candidate,
        targetChapterIndex: 50,
        targetChapterTitle: '不存在的章節',
        validateTargetContent: true,
      );

      expect(resolution.targetChapterIndex, inInclusiveRange(0, 9));
    });

    test('目標章節內容不可讀時丟 StateError', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters, content: '加載章節失敗'),
        sourceDao: db.bookSourceDao,
      );

      expect(
        () => service.resolveSwitch(
          _currentBook(),
          candidate,
          targetChapterIndex: 5,
          targetChapterTitle: '第6章',
          validateTargetContent: true,
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', '目標章節內容不可讀'),
        ),
      );
    });

    test('新源沒有目錄時丟 StateError', () async {
      final candidate = _candidate('new-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: const <BookChapter>[],
          throwOnChapterList: true,
        ),
        sourceDao: db.bookSourceDao,
      );

      expect(
        () => service.resolveSwitch(
          _currentBook(),
          candidate,
          targetChapterIndex: 5,
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', '新來源沒有可用目錄'),
        ),
      );
    });

    test('找不到對應書源時丟 StateError', () async {
      final candidate = _candidate('missing-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: _chapters('x', 3)),
        sourceDao: db.bookSourceDao,
      );

      expect(
        () => service.resolveSwitch(_currentBook(), candidate),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', '找不到對應書源'),
        ),
      );
    });
  });

  group('SourceSwitchService.persistSwitch', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.bookSourceDao.upsert(_source('new-origin', '新源'));
    });

    tearDown(() async {
      await db.close();
    });

    test('遷移到不同 bookUrl 時刪除舊書、章節與全部正文', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await _seedOldContent(db, oldBook);

      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.resolveSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
        validateTargetContent: true,
      );

      await service.persistSwitch(
        oldBook,
        resolution,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      expect(await db.bookDao.getByUrl(oldBook.bookUrl), isNull);
      expect(await db.chapterDao.getByBook(oldBook.bookUrl), isEmpty);
      expect(
        await db.readerChapterContentDao.getEntriesByBookUrls(<String>[
          oldBook.bookUrl,
        ]),
        isEmpty,
      );

      final migrated = await db.bookDao.getByUrl(
        resolution.migratedBook.bookUrl,
      );
      expect(migrated, isNotNull);
      expect(migrated!.origin, 'new-origin');
      expect(migrated.isInBookshelf, isTrue);
      final newChapters = await db.chapterDao.getByBook(
        resolution.migratedBook.bookUrl,
      );
      expect(newChapters.length, 100);
    });

    test('新來源資料寫入失敗時 transaction 回滾並完整保留舊資料', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await _seedOldContent(db, oldBook);

      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 4);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );
      final resolution = await service.resolveSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 1,
        targetChapterTitle: '第2章',
        validateTargetContent: true,
      );

      await db.customStatement('''
        CREATE TRIGGER fail_new_source_chapters
        BEFORE INSERT ON chapters
        WHEN NEW.bookUrl = '${candidate.bookUrl}'
        BEGIN
          SELECT RAISE(ABORT, 'forced source switch failure');
        END;
      ''');

      expect(
        () => service.persistSwitch(
          oldBook,
          resolution,
          bookDao: db.bookDao,
          chapterDao: db.chapterDao,
        ),
        throwsA(anything),
      );

      expect(await db.bookDao.getByUrl(oldBook.bookUrl), isNotNull);
      expect(await db.chapterDao.getByBook(oldBook.bookUrl), hasLength(3));
      expect(
        await db.readerChapterContentDao.getEntriesByBookUrls(<String>[
          oldBook.bookUrl,
        ]),
        hasLength(1),
      );
      expect(await db.bookDao.getByUrl(candidate.bookUrl), isNull);
      expect(await db.chapterDao.getByBook(candidate.bookUrl), isEmpty);
    });
  });
}
