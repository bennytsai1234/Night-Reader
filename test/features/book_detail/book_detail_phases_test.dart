import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/download/book_update_service.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';

/// 書籍詳情讀者看得到的階段：載入中（骨架）、載入失敗（「重試」）、可以
/// 操作；書源問題那一列寫什麼、有沒有「登入」；檢查更新、加入或移出書架、
/// 換源進行中再按一次會怎樣。

enum _Toc { ok, empty, fails, needsLogin }

class _Source extends BookSourceService {
  bool infoFails = false;
  _Toc toc = _Toc.ok;
  int chapterListCalls = 0;

  /// 給了就等它才回目錄（照開始抓時的 [toc]）。
  Completer<void>? tocGate;

  /// 給了就等它才回詳情；回的是照手上的書填上詳情頁簡介的那一份。
  Completer<void>? infoGate;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    if (infoFails) throw Exception('連不上');
    final gate = infoGate;
    if (gate == null) return book;
    await gate.future;
    return book.copyWith()..intro = '詳情頁的簡介';
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
    chapterListCalls++;
    final mode = toc;
    await tocGate?.future;
    return switch (mode) {
      _Toc.ok => chaptersOf(book.bookUrl, 3),
      _Toc.empty => <BookChapter>[],
      _Toc.fails => throw Exception('目錄連不上'),
      _Toc.needsLogin => throw LoginCheckException('目錄需要登入後閱讀'),
    };
  }
}

/// 檢查更新：照書架的檢查把目錄寫進資料庫；[gate] 給了就等它才回。
class _Updates extends BookUpdateService {
  _Updates(this.db) : super(keepDownloaded: _noDownload, bookDao: db.bookDao);

  final AppDatabase db;
  Completer<void>? gate;
  int checks = 0;

  static Future<void> _noDownload(
    String bookUrl, {
    bool hasNewChapters = false,
  }) async {}

  @override
  Future<BookUpdateCheckResult> check(Book book) async {
    checks++;
    await gate?.future;
    await db.chapterDao.insertChapters(chaptersOf(book.bookUrl, 4));
    return BookUpdateCheckResult(bookUrl: book.bookUrl, newChapterCount: 4);
  }
}

/// 換源到 [_newOrigin]：照換源服務寫進資料庫的結果，換源事件也照發；
/// [gate] 給了就等它才寫。
class _Switch implements SourceSwitchService {
  _Switch(this.db);

  final AppDatabase db;
  Completer<void>? gate;

  @override
  Future<PreparedSourceSwitch> prepareSwitch(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
    SourceToc? toc,
  }) async {
    await gate?.future;
    final chapters = chaptersOf(_newUrl, 5);
    return PreparedSourceSwitch(
      searchBook: candidate,
      source: BookSource(bookSourceUrl: _newOrigin, bookSourceName: '新書源'),
      migratedBook: currentBook.copyWith(
        bookUrl: _newUrl,
        origin: _newOrigin,
        originName: '新書源',
      ),
      chapters: chapters,
      targetChapterIndex: 0,
      validatedContent: '這一章的正文。' * 20,
    );
  }

  @override
  Future<bool> commitSwitch(
    Book oldBook,
    PreparedSourceSwitch prepared, {
    dynamic bookDao,
    dynamic chapterDao,
    dynamic refresh,
  }) async {
    await db.bookDao.deleteByUrl(oldBook.bookUrl);
    await db.bookDao.upsert(prepared.migratedBook);
    await db.chapterDao.insertChapters(prepared.chapters);
    AppEventBus().fire(
      AppEventBus.bookSwitched,
      data: BookSwitchedEvent(
        fromBookUrl: oldBook.bookUrl,
        toBookUrl: prepared.migratedBook.bookUrl,
      ),
    );
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 讀目錄第一次出錯（例如資料庫忙），之後照常。
class _FlakyChapters extends ChapterDao {
  _FlakyChapters(super.db);

  bool failNext = false;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) {
    if (failNext) {
      failNext = false;
      return Future.error(Exception('讀不到目錄'));
    }
    return super.getByBook(bookUrl);
  }
}

class _Downloads implements DownloadService {
  @override
  Future<void> keepShelfBookDownloaded(
    String bookUrl, {
    bool hasNewChapters = false,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _origin = 'https://source.example';
const _bookUrl = 'https://source.example/book/1';
const _newOrigin = 'https://new.example';
const _newUrl = 'https://new.example/book/9';

List<BookChapter> chaptersOf(String bookUrl, int count) => [
  for (var i = 0; i < count; i++)
    BookChapter(
      url: '$bookUrl/c$i',
      title: '第${i + 1}章',
      bookUrl: bookUrl,
      index: i,
    ),
];

const _staleInfo = '書籍資訊更新失敗，目前顯示已儲存內容';
const _tocFailed = '目前來源目錄載入失敗，建議換源後再試';
const _tocNeedsLogin = '目錄需要登入後閱讀';

void main() {
  late AppDatabase db;
  late _Source service;
  late _FlakyChapters chapterDao;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = _Source();
    chapterDao = _FlakyChapters(db);
  });
  tearDown(() => db.close());

  Future<void> storeSource({
    bool login = false,
    String? group,
    bool enabled = true,
  }) => db.bookSourceDao.upsert(
    BookSource(
      bookSourceUrl: _origin,
      bookSourceName: '書源',
      loginUrl: login ? 'https://source.example/login' : null,
      bookSourceGroup: group,
      enabled: enabled,
    ),
  );

  Book searchResult() => Book(
    bookUrl: _bookUrl,
    origin: _origin,
    originName: '書源',
    name: '測試書',
    author: '作者',
  );

  /// 等到 [condition] 成立；兩秒還不成立就算失敗。
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('等不到預期的狀態');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<BookDetailProvider> open({
    _Updates? updates,
    SourceSwitchService? switcher,
    bool waitReady = true,
  }) async {
    final provider = BookDetailProvider(
      AggregatedSearchBook(book: searchResult(), sources: []),
      entrance: Future<void>.value(),
      bookDao: db.bookDao,
      chapterDao: chapterDao,
      sourceDao: db.bookSourceDao,
      chapterContentDao: db.readerChapterContentDao,
      service: service,
      updates: updates,
      sourceSwitchService: switcher,
      downloadService: _Downloads(),
    );
    addTearDown(provider.dispose);
    if (waitReady) await until(() => !provider.isLoading);
    return provider;
  }

  /// 書源問題那一列：寫的字、有沒有「登入」。沒有這一列是 (null, false)。
  (String?, bool) row(BookDetailProvider provider) {
    final message = provider.sourceIssueMessage;
    if (message == null || message.isEmpty) return (null, false);
    return (message, provider.loginRequired);
  }

  test('fetching the book info keeps what an update check and sync wrote '
      'meanwhile', () async {
    await storeSource();
    // 書架上的書、手機裡還沒有目錄（例如剛還原備份）：詳情向書源重抓資訊。
    await db.bookDao.upsert(searchResult()..isInBookshelf = true);
    service.infoGate = Completer<void>();
    final provider = await open(waitReady: false);
    await until(() => provider.isLoading);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 抓詳情的這段時間，書架的檢查更新寫了章數、同步套用了另一台的進度。
    final meanwhile = (await db.bookDao.getByUrl(_bookUrl))!
      ..totalChapterNum = 12
      ..lastCheckCount = 2
      ..latestChapterTitle = '第十二章'
      ..chapterIndex = 5
      ..durChapterTitle = '第6章';
    await db.bookDao.upsert(meanwhile);
    service.infoGate!.complete();
    await until(() => !provider.isLoading);

    final stored = (await db.bookDao.getByUrl(_bookUrl))!;
    expect(stored.intro, '詳情頁的簡介');
    expect(stored.totalChapterNum, 12);
    expect(stored.lastCheckCount, 2);
    // 詳情頁沒給最新章節：留著檢查更新剛寫的。
    expect(stored.latestChapterTitle, '第十二章');
    expect(stored.chapterIndex, 5);
    expect(stored.durChapterTitle, '第6章');
  });

  group('書源問題那一列', () {
    test('nothing wrong shows no row', () async {
      await storeSource();
      final provider = await open();
      expect(row(provider), (null, false));
      expect(provider.totalChapterCount, 3);
    });

    test('a source that cannot be read shows its health', () async {
      await storeSource(group: paidSourceGroupTag);
      final provider = await open();
      expect(row(provider), (paidSourceHealth.description, false));
      expect(service.chapterListCalls, 0);
    });

    test('book info that fails to refresh says the stored one shows', () async {
      await storeSource();
      service.infoFails = true;
      final provider = await open();
      expect(row(provider), (_staleInfo, false));
      expect(provider.totalChapterCount, 3);
    });

    test('a TOC that fails suggests switching source', () async {
      await storeSource();
      service.toc = _Toc.fails;
      final provider = await open();
      expect(row(provider), (_tocFailed, false));
    });

    test('a TOC behind a login offers to log in', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();
      expect(row(provider), (_tocNeedsLogin, true));
    });

    test(
      'a login wall on a source without login is just a failed TOC',
      () async {
        await storeSource();
        service.toc = _Toc.needsLogin;
        final provider = await open();
        expect(row(provider), (_tocFailed, false));
      },
    );

    test('a failed TOC also overrides stale book info', () async {
      await storeSource(login: true);
      service
        ..infoFails = true
        ..toc = _Toc.needsLogin;
      final provider = await open();
      expect(row(provider), (_tocNeedsLogin, true));
    });

    test('logging in and reloading clears the row', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      service.toc = _Toc.ok;
      await provider.retryInitialization();
      expect(row(provider), (null, false));
      expect(provider.totalChapterCount, 3);
    });

    test('a successful update check clears stale book info', () async {
      await storeSource();
      service.infoFails = true;
      final provider = await open(updates: _Updates(db));

      final result = await provider.checkForUpdates();
      expect(result.success, isTrue);
      expect(row(provider), (null, false));
    });

    test(
      'adding to the shelf with a TOC in hand keeps stale book info',
      () async {
        await storeSource();
        service.infoFails = true;
        final provider = await open();

        final result = await provider.setInBookshelf(true);
        expect(result.success, isTrue);
        expect(row(provider), (_staleInfo, false));
      },
    );

    test('switching source clears the row', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open(switcher: _Switch(db));

      final result = await provider.changeSource(
        SearchBook(bookUrl: _newUrl, origin: _newOrigin, name: '測試書'),
      );
      expect(result.success, isTrue);
      expect(provider.book.bookUrl, _newUrl);
      expect(row(provider), (null, false));
    });

    test('a source switched in the reader clears the row', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      await db.bookDao.deleteByUrl(_bookUrl);
      await db.bookDao.upsert(
        searchResult().copyWith(bookUrl: _newUrl, origin: _newOrigin),
      );
      await db.chapterDao.insertChapters(chaptersOf(_newUrl, 5));
      AppEventBus().fire(
        AppEventBus.bookSwitched,
        data: const BookSwitchedEvent(
          fromBookUrl: _bookUrl,
          toBookUrl: _newUrl,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await provider.reloadAfterReading();

      expect(provider.book.bookUrl, _newUrl);
      expect(provider.totalChapterCount, 5);
      expect(row(provider), (null, false));
    });
  });

  group('目錄後來抓到了', () {
    for (final (name, toc, login) in [
      ('failed', _Toc.fails, false),
      ('was behind a login', _Toc.needsLogin, true),
    ]) {
      test('a TOC that $name and comes in when adding to the shelf clears '
          'the row', () async {
        await storeSource(login: login);
        service.toc = toc;
        final provider = await open();

        service.toc = _Toc.ok;
        final result = await provider.setInBookshelf(true);
        expect(result.success, isTrue);
        expect(provider.totalChapterCount, 3);
        expect(row(provider), (null, false));
      });
    }

    test('a refetch that finds no chapters keeps the row', () async {
      await storeSource();
      service.toc = _Toc.fails;
      final provider = await open();

      service.toc = _Toc.empty;
      await provider.setInBookshelf(true);
      expect(provider.totalChapterCount, 0);
      expect(row(provider), (_tocFailed, false));
    });

    test('a TOC another page stored clears the row when adding to the '
        'shelf', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      await db.chapterDao.insertChapters(chaptersOf(_bookUrl, 3));
      await provider.setInBookshelf(true);
      expect(provider.totalChapterCount, 3);
      expect(row(provider), (null, false));
    });

    test('a refetch that fails after an update check brought the TOC keeps '
        'the row clear', () async {
      await storeSource();
      service.toc = _Toc.fails;
      final provider = await open(updates: _Updates(db));

      service.tocGate = Completer<void>();
      final adding = provider.setInBookshelf(true);
      await until(() => service.chapterListCalls == 2);
      expect((await provider.checkForUpdates()).success, isTrue);
      service.tocGate!.complete();
      await adding;
      expect(provider.totalChapterCount, 4);
      expect(row(provider), (null, false));
    });

    test('a TOC that failed and comes in with an update check clears the '
        'row', () async {
      await storeSource();
      service.toc = _Toc.fails;
      final provider = await open(updates: _Updates(db));

      final result = await provider.checkForUpdates();
      expect(result.success, isTrue);
      expect(provider.totalChapterCount, 4);
      expect(row(provider), (null, false));
    });
  });

  group('從書源編輯或除錯頁回來', () {
    test('a TOC behind a login still offers to log in', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      await provider.reloadSource();
      expect(provider.totalChapterCount, 0);
      expect(row(provider), (_tocNeedsLogin, true));
    });

    test('a TOC behind a login on a source whose login was removed is just '
        'a failed TOC', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      await storeSource();
      await provider.reloadSource();
      expect(row(provider), (_tocFailed, false));
    });

    test('a TOC behind a login on a source that was deleted is just a failed '
        'TOC', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      await db.bookSourceDao.deleteByUrl(_origin);
      await provider.reloadSource();
      expect(row(provider), (_tocFailed, false));
    });

    test('stale book info still says so', () async {
      await storeSource();
      service.infoFails = true;
      final provider = await open();

      await provider.reloadSource();
      expect(row(provider), (_staleInfo, false));
    });

    test('a source that can no longer be read shows its health without '
        'login', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open();

      await storeSource(login: true, group: paidSourceGroupTag);
      await provider.reloadSource();
      expect(row(provider), (paidSourceHealth.description, false));
    });
  });

  group('書源停用之後', () {
    test('downloading and checking for updates say the source cannot be '
        'read, not the old TOC problem', () async {
      await storeSource(login: true);
      service.toc = _Toc.needsLogin;
      final provider = await open(updates: _Updates(db));

      await storeSource(login: true, enabled: false);
      await provider.reloadSource();
      final download = await provider.queueDownloadAll();
      expect(download.message, '目前來源無法提供正文，請先換源後再試。');
      final update = await provider.checkForUpdates();
      expect(update.success, isFalse);
      expect(update.message, '檢查更新失敗：找不到可閱讀書源');
    });
  });

  group('載入', () {
    test('a load that fails shows the error, and retry loads it', () async {
      await storeSource();
      chapterDao.failNext = true;
      final provider = await open();

      expect(provider.worldState, BookDetailWorldState.unavailable);
      expect(provider.loadErrorMessage, '書籍詳情載入失敗，請重試');
      expect(provider.hasReadyWorld, isFalse);

      final retry = provider.retryInitialization();
      expect(provider.isLoading, isTrue);
      expect(provider.loadErrorMessage, isNull);
      await retry;
      expect(provider.worldState, BookDetailWorldState.ready);
      expect(provider.totalChapterCount, 3);
    });

    test('the first load tells the page once when it is ready', () async {
      await storeSource();
      final provider = await open(waitReady: false);
      final states = <BookDetailWorldState>[];
      provider.addListener(() => states.add(provider.worldState));
      await until(() => states.length >= 3);
      // 再等一下，確認沒有第四次。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 進場後開始載入不通知（ADR 0018）；排好目錄時骨架還在，換成內容
      // 只有一次，之後是存好封面的那一次。
      expect(states, [
        BookDetailWorldState.initializing,
        BookDetailWorldState.ready,
        BookDetailWorldState.ready,
      ]);
    });
  });

  group('進行中再按一次', () {
    test('checking for updates twice runs one check', () async {
      await storeSource();
      final updates = _Updates(db)..gate = Completer<void>();
      final provider = await open(updates: updates);

      final first = provider.checkForUpdates();
      expect(provider.isRunning(BookDetailAction.checkUpdate), isTrue);
      final second = await provider.checkForUpdates();
      expect(second.success, isFalse);
      expect(second.message, '正在檢查更新');

      updates.gate!.complete();
      expect((await first).message, '發現 4 個新章節');
      expect(provider.isRunning(BookDetailAction.checkUpdate), isFalse);
      expect(updates.checks, 1);
    });

    test('the shelf button waits for the last add or remove', () async {
      await storeSource();
      service.toc = _Toc.fails;
      final provider = await open();
      // 目錄還沒有：加入書架要先抓，抓的時候停住。
      service
        ..toc = _Toc.ok
        ..tocGate = Completer<void>();

      final adding = provider.setInBookshelf(true);
      await until(() => service.chapterListCalls == 2);
      expect(provider.isRunning(BookDetailAction.updateBookshelf), isTrue);
      final second = await provider.setInBookshelf(false);
      expect(second.success, isFalse);
      expect(second.message, '正在更新書架，請稍候');

      service.tocGate!.complete();
      expect((await adding).message, '已加入書架');
      expect(provider.isRunning(BookDetailAction.updateBookshelf), isFalse);
      expect(provider.isInBookshelf, isTrue);
    });

    test('switching source twice switches once, and the page keeps its own '
        'switch', () async {
      await storeSource();
      final switcher = _Switch(db)..gate = Completer<void>();
      final provider = await open(switcher: switcher);
      final candidate = SearchBook(
        bookUrl: _newUrl,
        origin: _newOrigin,
        name: '測試書',
      );

      final first = provider.changeSource(candidate);
      final second = await provider.changeSource(candidate);
      expect(second.success, isFalse);
      expect(second.message, '正在換源，請稍候');

      // 換源進行中收到的換源事件不記：這頁自己換好的書為準。
      const otherUrl = 'https://other.example/book/3';
      await db.bookDao.upsert(
        searchResult().copyWith(
          bookUrl: otherUrl,
          origin: 'https://other.example',
        ),
      );
      await db.chapterDao.insertChapters(chaptersOf(otherUrl, 7));
      AppEventBus().fire(
        AppEventBus.bookSwitched,
        data: const BookSwitchedEvent(
          fromBookUrl: _bookUrl,
          toBookUrl: otherUrl,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      switcher.gate!.complete();
      expect((await first).success, isTrue);
      await provider.reloadAfterReading();
      expect(provider.book.bookUrl, _newUrl);
      expect(provider.totalChapterCount, 5);
    });
  });
}
