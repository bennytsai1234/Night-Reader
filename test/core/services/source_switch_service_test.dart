import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_storage.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/core/services/source_switch_handoff.dart';

class _RecordingSourceSwitchLease implements SourceSwitchOperationLease {
  _RecordingSourceSwitchLease(this.bookUrl);

  final String bookUrl;
  bool retiredInTransaction = false;
  bool committedCalled = false;
  bool rolledBackCalled = false;

  @override
  Future<void> retireInTransaction(AppDatabase db) async {
    retiredInTransaction = true;
    await DownloadDao(db).deleteByUrl(bookUrl);
  }

  @override
  void committed() {
    committedCalled = true;
  }

  @override
  void rolledBack() {
    rolledBackCalled = true;
  }
}

class _FakeBookSourceService extends BookSourceService {
  _FakeBookSourceService({
    required this.chapters,
    this.content = '這是一段足夠長的章節正文內容，用來通過可讀性檢查。',
    this.throwOnChapterList = false,
  });

  final List<BookChapter> chapters;
  final String content;
  final bool throwOnChapterList;
  int contentCalls = 0;

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
    contentCalls++;
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

class _ThrowingSearchBookSourceService extends BookSourceService {
  _ThrowingSearchBookSourceService(this.error);

  final Object error;

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author,
  ) async {
    throw error;
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
    throw error;
  }
}

class _AutoPrepareFailureBookSourceService extends BookSourceService {
  _AutoPrepareFailureBookSourceService(this.error);

  final Object error;

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author,
  ) async {
    return <SearchBook>[_candidate(source.bookSourceUrl)];
  }

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    throw error;
  }
}

class _EnabledBookSourceDao extends Fake implements BookSourceDao {
  _EnabledBookSourceDao(this.sources);

  final List<BookSource> sources;

  @override
  Future<List<BookSource>> getEnabled() async => sources;

  @override
  Future<BookSource?> getByUrl(String url) async {
    for (final source in sources) {
      if (source.bookSourceUrl == url) return source;
    }
    return null;
  }
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

    test('已知書源失敗只淘汰該搜尋候選', () async {
      final source = _source('new-origin', '新源');
      final service = SourceSwitchService(
        service: _ThrowingSearchBookSourceService(
          SourceException('書源搜尋不可用', sourceUrl: source.bookSourceUrl),
        ),
        sourceDao: _EnabledBookSourceDao(<BookSource>[source]),
      );

      expect(await service.searchAlternatives(_currentBook()), isEmpty);
    });

    test('未知搜尋程式錯誤不得被當成空候選', () async {
      final source = _source('new-origin', '新源');
      final error = StateError('search invariant broke');
      final service = SourceSwitchService(
        service: _ThrowingSearchBookSourceService(error),
        sourceDao: _EnabledBookSourceDao(<BookSource>[source]),
      );

      await expectLater(
        service.searchAlternatives(_currentBook()),
        throwsA(same(error)),
      );
    });

    test('auto prepare 只跳過已知候選 unavailable', () async {
      final source = _source('new-origin', '新源');
      final service = SourceSwitchService(
        service: _AutoPrepareFailureBookSourceService(
          SourceException('候選不可用', sourceUrl: source.bookSourceUrl),
        ),
        sourceDao: _EnabledBookSourceDao(<BookSource>[source]),
      );

      expect(await service.autoPrepareSwitch(_currentBook()), isNull);
    });

    test('auto prepare 不吞未知 prepare 錯誤', () async {
      final source = _source('new-origin', '新源');
      final error = StateError('prepare invariant broke');
      final service = SourceSwitchService(
        service: _AutoPrepareFailureBookSourceService(error),
        sourceDao: _EnabledBookSourceDao(<BookSource>[source]),
      );

      await expectLater(
        service.autoPrepareSwitch(_currentBook()),
        throwsA(same(error)),
      );
    });
  });

  group('SourceSwitchService.prepareSwitch', () {
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

      final resolution = await service.prepareSwitch(
        _currentBook(chapterIndex: 5, durChapterTitle: '第6章'),
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
      );

      expect(resolution.targetChapterIndex, 5);
      expect(resolution.chapters.length, 100);
      expect(resolution.migratedBook.origin, 'new-origin');
      expect(resolution.validatedContent, isNotEmpty);
    });

    test('新源章節數較少時 clamp 不越界', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 10);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.prepareSwitch(
        _currentBook(
          chapterIndex: 50,
          durChapterTitle: '不存在的章節',
          totalChapterNum: 100,
        ),
        candidate,
        targetChapterIndex: 50,
        targetChapterTitle: '不存在的章節',
      );

      expect(resolution.targetChapterIndex, inInclusiveRange(0, 9));
    });

    test('目標章節內容不可讀時回報 source unavailable', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters, content: '加載章節失敗'),
        sourceDao: db.bookSourceDao,
      );

      await expectLater(
        service.prepareSwitch(
          _currentBook(),
          candidate,
          targetChapterIndex: 5,
          targetChapterTitle: '第6章',
        ),
        throwsA(
          isA<SourceException>().having((e) => e.message, 'message', '目標章節內容不可讀'),
        ),
      );
    });

    test('新源沒有目錄時回報 source unavailable', () async {
      final candidate = _candidate('new-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: const <BookChapter>[],
          throwOnChapterList: true,
        ),
        sourceDao: db.bookSourceDao,
      );

      await expectLater(
        service.prepareSwitch(
          _currentBook(),
          candidate,
          targetChapterIndex: 5,
        ),
        throwsA(
          isA<SourceException>().having((e) => e.message, 'message', '新來源沒有可用目錄'),
        ),
      );
    });

    test('找不到對應書源時回報 source unavailable', () async {
      final candidate = _candidate('missing-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: _chapters('x', 3)),
        sourceDao: db.bookSourceDao,
      );

      await expectLater(
        service.prepareSwitch(_currentBook(), candidate),
        throwsA(
          isA<SourceException>().having((e) => e.message, 'message', '找不到對應書源'),
        ),
      );
    });
  });

  group('SourceSwitchService.commitSwitch', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.bookSourceDao.upsert(_source('new-origin', '新源'));
    });

    tearDown(() async {
      await db.close();
    });

    test('遷移到不同 bookUrl 時原子寫入目標正文並刪除舊來源資料', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await _seedOldContent(db, oldBook);

      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final sourceService = _FakeBookSourceService(chapters: chapters);
      final service = SourceSwitchService(
        service: sourceService,
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.prepareSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
      );

      await service.commitSwitch(
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

      final targetChapter = newChapters[resolution.targetChapterIndex];
      final targetEntry = await db.readerChapterContentDao.getEntry(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: migrated.origin,
          bookUrl: migrated.bookUrl,
          chapterUrl: targetChapter.url,
        ),
      );
      expect(targetEntry, isNotNull);
      expect(targetEntry!.isReady, isTrue);
      expect(targetEntry.content, resolution.validatedContent);

      final storage = ReaderChapterContentStorage.withMaterializer(
        book: migrated,
        contentStore: ReaderChapterContentStore(
          chapterDao: db.chapterDao,
          contentDao: db.readerChapterContentDao,
        ),
        sourceDao: db.bookSourceDao,
        service: sourceService,
      );
      final prepared = await storage.read(
        chapterIndex: resolution.targetChapterIndex,
        chapter: targetChapter,
      );
      expect(prepared.isReady, isTrue);
      expect(prepared.content, resolution.validatedContent);
      expect(
        sourceService.contentCalls,
        1,
        reason: 'handoff 後 Reader 必須直接命中已驗證正文，不得第二次抓網路',
      );
    });

    test('書籤跟 logical book 原子移交，舊正文 scalar offset 不跨來源沿用', () async {
      final oldBook = _currentBook(
        chapterIndex: 1,
        durChapterTitle: '第2章',
        totalChapterNum: 3,
      );
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await db.bookmarkDao.upsert(
        Bookmark(
          id: 41,
          time: 1,
          bookName: oldBook.name,
          bookAuthor: oldBook.author,
          chapterIndex: 1,
          chapterPos: 77,
          chapterName: '第2章',
          bookUrl: oldBook.bookUrl,
          bookText: '使用者當時看到的原文',
          content: '使用者筆記',
        ),
      );

      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 5);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );
      final prepared = await service.prepareSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 1,
        targetChapterTitle: '第2章',
      );

      await service.commitSwitch(
        oldBook,
        prepared,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      expect(await db.bookmarkDao.getByBook(oldBook.bookUrl), isEmpty);
      final migratedBookmarks = await db.bookmarkDao.getByBook(
        prepared.migratedBook.bookUrl,
      );
      expect(migratedBookmarks, hasLength(1));
      final bookmark = migratedBookmarks.single;
      expect(bookmark.id, 41);
      expect(bookmark.chapterIndex, 1);
      expect(bookmark.chapterName, '第2章');
      expect(bookmark.chapterPos, 0);
      expect(bookmark.bookText, '使用者當時看到的原文');
      expect(bookmark.content, '使用者筆記');
    });

    test('operation owner 在 commit transaction 內退休，成功後才 finalize', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await db.downloadDao.upsert(
        DownloadTask(
          bookUrl: oldBook.bookUrl,
          bookName: oldBook.name,
          startChapterIndex: 0,
          endChapterIndex: 2,
          status: DownloadTask.statusWaiting,
        ),
      );

      final lease = _RecordingSourceSwitchLease(oldBook.bookUrl);
      final candidate = _candidate('new-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: _chapters(candidate.bookUrl, 4),
        ),
        sourceDao: db.bookSourceDao,
        operationQuiescer: (_) async => lease,
      );
      final prepared = await service.prepareSwitch(oldBook, candidate);

      await service.commitSwitch(
        oldBook,
        prepared,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      expect(lease.retiredInTransaction, isTrue);
      expect(lease.committedCalled, isTrue);
      expect(lease.rolledBackCalled, isFalse);
      expect(
        (await db.downloadDao.getAll())
            .where((task) => task.bookUrl == oldBook.bookUrl),
        isEmpty,
      );
    });

    test('PreparedSourceSwitch 不接受不可讀正文', () {
      final migratedBook = _currentBook().copyWith(
        bookUrl: 'new-origin/book/1',
        origin: 'new-origin',
        originName: '新源',
      );
      final chapters = _chapters(migratedBook.bookUrl, 3);

      expect(
        () => PreparedSourceSwitch(
          searchBook: _candidate('new-origin'),
          source: _source('new-origin', '新源'),
          migratedBook: migratedBook,
          chapters: chapters,
          targetChapterIndex: 1,
          validatedContent: '加載章節失敗',
        ),
        throwsArgumentError,
      );
    });

    test('bookUrl 相同但 origin 改變時清除舊 source identity 正文', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await _seedOldContent(db, oldBook);

      final candidate = SearchBook(
        bookUrl: oldBook.bookUrl,
        name: oldBook.name,
        author: oldBook.author,
        origin: 'new-origin',
        originName: '新源',
        tocUrl: 'new-origin/toc/1',
      );
      final chapters = _chapters(oldBook.bookUrl, 3);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );
      final resolution = await service.prepareSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 1,
        targetChapterTitle: '第2章',
      );

      await service.commitSwitch(
        oldBook,
        resolution,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      final migrated = await db.bookDao.getByUrl(oldBook.bookUrl);
      expect(migrated, isNotNull);
      expect(migrated!.origin, 'new-origin');
      final entries = await db.readerChapterContentDao.getEntriesByBookUrls(
        <String>[oldBook.bookUrl],
      );
      expect(entries, hasLength(1));
      expect(entries.single.origin, 'new-origin');
      expect(entries.single.chapterUrl, chapters[1].url);
      expect(entries.single.content, resolution.validatedContent);
    });

    test('commit 失敗時 operation retirement 與書籤 migration 一起回滾', () async {
      final oldBook = _currentBook(
        chapterIndex: 1,
        durChapterTitle: '第2章',
        totalChapterNum: 3,
      );
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await db.bookmarkDao.upsert(
        Bookmark(
          id: 42,
          time: 1,
          chapterIndex: 1,
          chapterPos: 33,
          chapterName: '第2章',
          bookUrl: oldBook.bookUrl,
          content: '保留的筆記',
        ),
      );
      await db.downloadDao.upsert(
        DownloadTask(
          bookUrl: oldBook.bookUrl,
          bookName: oldBook.name,
          startChapterIndex: 0,
          endChapterIndex: 2,
          status: DownloadTask.statusWaiting,
        ),
      );

      final lease = _RecordingSourceSwitchLease(oldBook.bookUrl);
      final candidate = _candidate('new-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: _chapters(candidate.bookUrl, 4),
        ),
        sourceDao: db.bookSourceDao,
        operationQuiescer: (_) async => lease,
      );
      final prepared = await service.prepareSwitch(oldBook, candidate);

      await db.customStatement('''
        CREATE TRIGGER fail_source_switch_bookmark_handoff
        BEFORE INSERT ON reader_chapter_contents
        WHEN NEW.origin = 'new-origin'
        BEGIN
          SELECT RAISE(ABORT, 'forced rollback after handoff staging');
        END;
      ''');

      await expectLater(
        service.commitSwitch(
          oldBook,
          prepared,
          bookDao: db.bookDao,
          chapterDao: db.chapterDao,
        ),
        throwsA(anything),
      );

      expect(lease.retiredInTransaction, isTrue);
      expect(lease.committedCalled, isFalse);
      expect(lease.rolledBackCalled, isTrue);
      final oldBookmarks = await db.bookmarkDao.getByBook(oldBook.bookUrl);
      expect(oldBookmarks, hasLength(1));
      expect(oldBookmarks.single.chapterPos, 33);
      expect(
        (await db.downloadDao.getAll())
            .where((task) => task.bookUrl == oldBook.bookUrl),
        hasLength(1),
      );
    });

    test('目標正文 handoff 寫入失敗時整個 commit 回滾', () async {
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
      final resolution = await service.prepareSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 1,
        targetChapterTitle: '第2章',
      );

      await db.customStatement('''
        CREATE TRIGGER fail_source_switch_handoff_content
        BEFORE INSERT ON reader_chapter_contents
        WHEN NEW.origin = 'new-origin'
        BEGIN
          SELECT RAISE(ABORT, 'forced handoff content failure');
        END;
      ''');

      await expectLater(
        service.commitSwitch(
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
      expect(
        await db.readerChapterContentDao.getEntriesByBookUrls(<String>[
          candidate.bookUrl,
        ]),
        isEmpty,
      );
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
      final resolution = await service.prepareSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 1,
        targetChapterTitle: '第2章',
      );

      await db.customStatement('''
        CREATE TRIGGER fail_new_source_chapters
        BEFORE INSERT ON chapters
        WHEN NEW.bookUrl = '${candidate.bookUrl}'
        BEGIN
          SELECT RAISE(ABORT, 'forced source switch failure');
        END;
      ''');

      await expectLater(
        service.commitSwitch(
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
      expect(
        await db.readerChapterContentDao.getEntriesByBookUrls(<String>[
          candidate.bookUrl,
        ]),
        isEmpty,
      );
    });
  });
}
