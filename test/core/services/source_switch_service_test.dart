import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
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
    bool requireComplete = false,
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

  @override
  Future<AudioRequest> getAudioRequest(
    BookSource source,
    Book book,
    BookChapter chapter, {
    CancelToken? cancelToken,
  }) async => AudioRequest(
    url: 'https://cdn.test/${chapter.index}.mp3',
    headers: const {},
  );
}

/// 自動換源用的網站：每個書源的目錄照 [tocs]（書源網址 → 章名），搜得到
/// 書名與作者都一樣的那本；[unreadable] 的正文抓不到，[searchErrors] 的
/// 搜尋丟出那個錯誤。
class _SitesBookSourceService extends BookSourceService {
  _SitesBookSourceService(
    this.tocs, {
    this.unreadable = const {},
    this.searchErrors = const {},
  });

  final Map<String, List<String>> tocs;
  final Set<String> unreadable;
  final Map<String, Object> searchErrors;
  final List<String> searched = [];
  final List<String> contentFetched = [];

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author, {
    CancelToken? cancelToken,
  }) async {
    final origin = source.bookSourceUrl;
    searched.add(origin);
    if (searchErrors[origin] case final error?) throw error;
    if (!tocs.containsKey(origin) || name != '測試書' || author != '作者') {
      return const [];
    }
    return [_candidate(origin)];
  }

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
  }) async => [
    for (final (i, title) in tocs[source.bookSourceUrl]!.indexed)
      BookChapter(
        url: '${book.bookUrl}/c$i',
        title: title,
        bookUrl: book.bookUrl,
        index: i,
      ),
  ];

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    contentFetched.add(source.bookSourceUrl);
    return unreadable.contains(source.bookSourceUrl)
        ? ''
        : '這是一段足夠長的章節正文內容，用來通過可讀性檢查。';
  }
}

/// 第 1 到 [count] 章的章名，[extra] 接在最後。
List<String> _titles(int count, [List<String> extra = const []]) => [
  for (var i = 1; i <= count; i++) '第$i章',
  ...extra,
];

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

  group('SourceSwitchService.prepareAutomaticSwitch（ADR 0069）', () {
    SourceSwitchService switcher(
      _SitesBookSourceService sites,
      List<BookSource> sources,
    ) => SourceSwitchService(
      service: sites,
      sourceDao: _EnabledBookSourceDao(sources),
    );

    BookSource ordered(String url, int order, {String? group}) =>
        _source(url, url)
          ..customOrder = order
          ..bookSourceGroup = group;

    test('讀到的那一章章名對不上的不換：手動換源會照位置換算，自動換源沒人看', () async {
      final sites = _SitesBookSourceService({
        'a': [for (var i = 1; i <= 30; i++) '第$i話'],
        'b': _titles(8),
      });
      final prepared = await switcher(sites, [
        ordered('a', 0),
        ordered('b', 1),
      ]).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');

      expect(prepared?.source.bookSourceUrl, 'b');
      expect(prepared?.targetChapter.title, '第6章');
      expect(sites.contentFetched, ['b'], reason: '對不上的不抓正文');

      final none = await switcher(_SitesBookSourceService({'a': _titles(5)}), [
        ordered('a', 0),
      ]).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');
      expect(none, isNull);
    });

    test('章名繁簡、空白不同也算對得上', () async {
      ChineseUtils.initializeFromDictionaryData(['', '', '', '歸\t归\n來\t来\n']);
      final prepared =
          await switcher(
            _SitesBookSourceService({
              'a': ['第一章 序', '第二章　归来'],
            }),
            [ordered('a', 0)],
          ).prepareAutomaticSwitch(
            _currentBook(chapterIndex: 1, durChapterTitle: '第二章 歸來'),
            chapterTitle: '第二章 歸來',
          );

      expect(prepared?.targetChapterIndex, 1);
    });

    test('幾個都合格時挑目錄章數最多的，一樣多照書源排序', () async {
      final sites = _SitesBookSourceService({
        'a': _titles(10),
        'b': _titles(20),
        'c': _titles(20),
      });
      final prepared = await switcher(sites, [
        ordered('a', 0),
        ordered('c', 2),
        ordered('b', 1),
      ]).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');

      expect(prepared?.source.bookSourceUrl, 'b');
      expect(sites.contentFetched, ['b']);
    });

    test('章數最多的正文抓不到時換下一個', () async {
      final sites = _SitesBookSourceService(
        {'a': _titles(10), 'b': _titles(20)},
        unreadable: {'b'},
      );
      final prepared = await switcher(sites, [
        ordered('a', 0),
        ordered('b', 1),
      ]).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');

      expect(prepared?.source.bookSourceUrl, 'a');
      expect(sites.contentFetched, ['b', 'a']);
    });

    test('只找啟用、同一類、沒有狀態標記與「AI 修不好」的書源', () async {
      final sites = _SitesBookSourceService({
        for (final url in ['ok', 'flagged', 'paid', 'unfixable', 'login'])
          url: _titles(10),
        'comic': _titles(10),
        'off': _titles(10),
      });
      final sources = [
        ordered('ok', 0),
        ordered('flagged', 1, group: '異常,正文失效'),
        ordered('paid', 2, group: '付費'),
        ordered('unfixable', 3, group: 'AI 修不好'),
        ordered('login', 4, group: '需要登入'),
        ordered('comic', 5)..bookSourceType = 2,
        ordered('off', 6)..enabled = false,
        ordered('old-origin', 7),
      ];
      final prepared = await switcher(
        sites,
        sources,
      ).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');

      expect(prepared?.source.bookSourceUrl, 'ok');
      expect(sites.searched, ['ok']);
    });

    test('某個書源出錯只跳過它，連沒預期的錯也是：背景沒人看，不讓整本書放棄', () async {
      for (final error in [
        SourceException('搜尋不可用', sourceUrl: 'a'),
        StateError('search invariant broke'),
      ]) {
        final prepared = await switcher(
          _SitesBookSourceService(
            {'a': _titles(20), 'b': _titles(10)},
            searchErrors: {'a': error},
          ),
          [ordered('a', 0), ordered('b', 1)],
        ).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');
        expect(prepared?.source.bookSourceUrl, 'b', reason: '$error');
      }
    });

    test('聚合源不當候選（ADR 0056 照 Legado 只用同一類）', () async {
      final sites = _SitesBookSourceService({
        'aggregate': _titles(20),
        'plain': _titles(10),
      });
      final aggregate = ordered('aggregate', 0)
        ..ruleBookInfo = BookInfoRule(name: '@js:book.type = 32; result');
      final prepared = await switcher(sites, [
        aggregate,
        ordered('plain', 1),
      ]).prepareAutomaticSwitch(_currentBook(), chapterTitle: '第6章');

      expect(aggregate.isAggregateSource, isTrue);
      expect(prepared?.source.bookSourceUrl, 'plain');
      expect(sites.searched, ['plain']);
    });

    test('改照最新的書寫回：搜的時候改了分組、封面也留著；讀到的那一章變了'
        '就要重新準備', () async {
      final service = switcher(_SitesBookSourceService({'a': _titles(10)}), [
        ordered('a', 0),
      ]);
      final book = _currentBook();
      final prepared = (await service.prepareAutomaticSwitch(
        book,
        chapterTitle: '第6章',
      ))!;
      final latest = book.copyWith(group: 4, customCoverUrl: 'cover.jpg');

      final rebased = service.rebase(prepared, latest)!;
      expect(rebased.migratedBook.group, 4);
      expect(rebased.migratedBook.customCoverUrl, 'cover.jpg');
      expect(rebased.migratedBook.origin, 'a');
      expect(rebased.targetChapterIndex, 5);

      expect(
        service.rebase(
          prepared,
          book.copyWith(chapterIndex: 7, durChapterTitle: '第8章'),
        ),
        isNull,
      );
    });

    test('取消時不換也不丟錯誤', () async {
      final cancel = CancelToken()..cancel();
      final sites = _SitesBookSourceService({'a': _titles(10)});
      final prepared = await switcher(sites, [ordered('a', 0)])
          .prepareAutomaticSwitch(
            _currentBook(),
            chapterTitle: '第6章',
            cancelToken: cancel,
          );

      expect(prepared, isNull);
      expect(sites.searched, isEmpty);
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

    test('有聲書照取音訊網址驗證、不跑文字正文，對到同一集接著同一秒（ADR 0055）', () async {
      final candidate = SearchBook(
        bookUrl: 'new-origin/book/1',
        name: '測試書',
        author: '作者',
        origin: 'new-origin',
        originName: '新源',
        tocUrl: 'new-origin/toc/1',
        type: 1,
      );
      final chapters = _chapters(candidate.bookUrl, 10);
      final fake = _FakeBookSourceService(chapters: chapters, content: '');
      final service = SourceSwitchService(
        service: fake,
        sourceDao: db.bookSourceDao,
      );
      final listening = _currentBook()
        ..type = 1
        ..charOffset = 95000;

      final resolution = await service.prepareSwitch(
        listening,
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
      );

      expect(fake.contentCalls, 0);
      expect(resolution.validatedContent, startsWith('http'));
      expect(resolution.migratedBook.charOffset, 95000);
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
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            '目標章節內容不可讀',
          ),
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
        service.prepareSwitch(_currentBook(), candidate, targetChapterIndex: 5),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            '新來源沒有可用目錄',
          ),
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

      final switched = AppEventBus()
          .onName(AppEventBus.bookSwitched)
          .map((event) => event.data as BookSwitchedEvent)
          .first;
      await service.commitSwitch(
        oldBook,
        resolution,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      // 從別頁開的閱讀器換源時，那一頁（例如書籍詳情）靠它找到新的書。
      final event = await switched;
      expect(event.fromBookUrl, oldBook.bookUrl);
      expect(event.toBookUrl, resolution.migratedBook.bookUrl);
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

    test('書籤與標註跟著搬到新書源：對到新目錄裡同名的那一章，章內位置照舊', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 100));
      final bookmarks = BookmarkDao(db);
      final saved = await bookmarks.add(
        Bookmark(
          id: 0,
          bookName: oldBook.name,
          bookAuthor: oldBook.author,
          chapterIndex: 5,
          chapterTitle: '第6章',
          charOffset: 42,
          excerpt: '燈下的字句',
        ),
      );
      final other = await bookmarks.add(
        Bookmark(id: 0, bookName: '別本書', chapterIndex: 5, chapterTitle: '第6章'),
      );
      final highlights = HighlightDao(db);
      final painted = await highlights.add(
        Highlight(
          id: 0,
          bookName: oldBook.name,
          bookAuthor: oldBook.author,
          chapterIndex: 5,
          chapterTitle: '第6章',
          charOffset: 30,
          quote: '燈下',
          color: HighlightColor.green,
        ),
      );

      // 新書源多一個楔子，第6章往後挪一格。
      final candidate = _candidate('new-origin');
      final chapters = [
        BookChapter(
          url: '${candidate.bookUrl}/prologue',
          title: '楔子',
          bookUrl: candidate.bookUrl,
          index: 0,
        ),
        for (final chapter in _chapters(candidate.bookUrl, 100))
          chapter.copyWith(index: chapter.index + 1),
      ];
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );
      final resolution = await service.prepareSwitch(oldBook, candidate);
      await service.commitSwitch(
        oldBook,
        resolution,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      final moved = {for (final b in await bookmarks.getAll()) b.id: b};
      expect(moved[saved.id]!.chapterIndex, 6);
      expect(moved[saved.id]!.chapterTitle, '第6章');
      expect(moved[saved.id]!.charOffset, 42);
      expect(moved[other.id]!.chapterIndex, 5, reason: '別本書的書籤不動');
      final movedHighlight = (await highlights.getAll()).single;
      expect(movedHighlight.id, painted.id);
      expect(movedHighlight.chapterIndex, 6, reason: '標註也跟著搬');
      expect(movedHighlight.charOffset, 30);
      expect(movedHighlight.color, HighlightColor.green);
    });

    test('漫畫換源：目標那一話只有圖也能換，不寫進正文快取（ADR 0052）', () async {
      final oldBook = _currentBook()..type = 2;
      await db.bookDao.upsert(oldBook);
      final candidate = _candidate('new-origin')..type = 2;
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: _chapters(candidate.bookUrl, 10),
          content: '<img src="https://a.test/1.jpg"><img src="https://a.test/2.jpg">',
        ),
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

      final migrated = await db.bookDao.getByUrl(candidate.bookUrl);
      expect(migrated?.bookKind, BookSourceKind.comic);
      expect(
        await db.readerChapterContentDao.getEntriesByBookUrls([
          candidate.bookUrl,
        ]),
        isEmpty,
      );
    });

    test('operation owner 在 commit transaction 內退休，成功後才 finalize', () async {
      final oldBook = _currentBook();
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await db.downloadDao.upsert(
        DownloadTask(
          bookUrl: oldBook.bookUrl,
          bookName: oldBook.name,
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
        (await db.downloadDao.getAll()).where(
          (task) => task.bookUrl == oldBook.bookUrl,
        ),
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

    test('commit 失敗時 operation retirement 一起回滾', () async {
      final oldBook = _currentBook(
        chapterIndex: 1,
        durChapterTitle: '第2章',
        totalChapterNum: 3,
      );
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));
      await db.downloadDao.upsert(
        DownloadTask(
          bookUrl: oldBook.bookUrl,
          bookName: oldBook.name,
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
        CREATE TRIGGER fail_source_switch_handoff
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
      expect(
        (await db.downloadDao.getAll()).where(
          (task) => task.bookUrl == oldBook.bookUrl,
        ),
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
