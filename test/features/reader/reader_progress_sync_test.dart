import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_progress_sync.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';

class _BookDao extends Fake implements BookDao {
  Book? stored;
  int reads = 0;
  int writes = 0;

  /// 存進度失敗（磁碟滿了）。
  bool failWrites = false;

  @override
  Future<Book?> getByUrl(String url) async {
    reads++;
    return stored;
  }

  @override
  Future<int?> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    if (failWrites) throw StateError('存不進去');
    writes++;
    return null;
  }

  /// 跳到雲端進度後記下的時間（[markProgressSynced] 的 syncedTime）。
  final List<int> synced = [];

  @override
  Future<int?> markProgressSynced(
    String bookUrl, {
    required int syncedTime,
  }) async {
    synced.add(syncedTime);
    return syncedTime;
  }
}

class _ChapterDao extends Fake implements ChapterDao {
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => const [];

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

class _SourceDao extends Fake implements BookSourceDao {}

class _Sync extends Fake implements SyncService {
  final List<String> opened = [];

  /// 閱讀器開書、回到前景時抓到的雲端進度；null 是沒有比較新的。
  PulledProgress? pulled;

  /// 抓雲端進度要等外面放行（網路慢）。
  Completer<void>? pullGate;

  /// 抓了幾次雲端進度。
  int pulls = 0;

  @override
  Future<PulledProgress?> pullProgress(String bookUrl) async {
    pulls++;
    await pullGate?.future;
    return pulled;
  }

  /// 登記成退到背景時自己送進度的閱讀器。
  final Set<Object> hideUploaders = {};

  @override
  void uploadsOnHide(Object owner, bool on) =>
      on ? hideUploaders.add(owner) : hideUploaders.remove(owner);

  @override
  void openBook(Book book) => opened.add(book.bookUrl);

  @override
  void closeBook(Book book) {}

  /// 離開閱讀器、退到背景時要求進度優先同步的次數。
  int progressFirstRequests = 0;

  @override
  void requestSyncProgressFirst() => progressFirstRequests++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final chapters = [
    for (var i = 0; i < 5; i++)
      BookChapter(
        url: 'chapter_$i',
        title: '第 $i 章',
        bookUrl: 'http://book.test',
        index: i,
        content: '第 $i 章內容。' * 80,
      ),
  ];

  late _BookDao bookDao;
  late _Sync sync;
  late Book book;
  late ReaderRuntime runtime;

  /// 視窗把位置排好的動作；測試換掉它來控制跳轉什麼時候完成。
  late Future<bool> Function(ReaderLocation location) restore;

  /// 取不到內容的章節。
  late Set<int> unavailable;

  setUp(() {
    // 前面有測試停在背景（hidden），先回到前景，免得回到前景的流程多跑一次。
    final binding = TestWidgetsFlutterBinding.instance;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    restore = (_) async => true;
    unavailable = {};
    bookDao = _BookDao();
    sync = _Sync();
    book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      chapterIndex: 1,
      charOffset: 10,
    );
    bookDao.stored = book;
    final repository = ReaderChapterRepository(
      book: book,
      initialChapters: chapters,
      contentLoader: (index, chapter) async {
        if (unavailable.contains(index)) {
          throw const ReaderContentUnavailableException('這一章暫時取不到');
        }
        return chapter.content;
      },
      bookDao: bookDao,
      chapterDao: _ChapterDao(),
      sourceDao: _SourceDao(),
    );
    runtime = ReaderRuntime(
      book: book,
      repository: repository,
      progressController: ReaderProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderLayoutSpec.fromViewport(
        viewportSize: const Size(220, 180),
        style: const ReaderLayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
          textIndent: 2,
        ),
      ),
      initialLocation: const ReaderLocation(chapterIndex: 1, charOffset: 10),
    );
    runtime.registerViewportRestore(Object(), (location) => restore(location));
    addTearDown(runtime.dispose);
  });

  ReaderProgressSync start({
    ReaderOpenTarget? openTarget,
    List<Future<void> Function()>? suggestions,
  }) {
    final progressSync = ReaderProgressSync(
      book: book,
      runtime: () => runtime,
      onProgressSuggestion: (jump) {
        if (suggestions == null) fail('沒有要問要不要跳');
        suggestions.add(jump);
      },
      bookDao: bookDao,
      openTarget: openTarget,
      sync: sync,
    )..start();
    addTearDown(progressSync.dispose);
    return progressSync;
  }

  /// 另一台在第 [chapter] 章第 [offset] 個字；[stored] 給了的話，開書前
  /// 接上時寫進這台的資料庫。
  PulledProgress pulledAt(
    int chapter,
    int offset, {
    void Function()? onCommit,
    bool stores = false,
  }) => PulledProgress(
    SyncedProgress(
      chapterIndex: chapter,
      charOffset: offset,
      chapterTitle: '第 $chapter 章',
      time: 7,
    ),
    (_) async => onCommit?.call(),
    applyStored: stores
        ? () async {
            bookDao.stored = book.copyWith(
              chapterIndex: chapter,
              charOffset: offset,
              progressTime: 7,
            );
            return ProgressSync.recordOf(bookDao.stored!);
          }
        : null,
  );

  test('resuming pulls the cloud progress first and opens where the other '
      'phone was', () async {
    var commits = 0;
    sync.pulled = pulledAt(3, 40, stores: true, onCommit: () => commits++);
    final progressSync = start();

    final at = await progressSync.openLocation(runtime);
    await runtime.openBook(at: at);
    await pumpEventQueue();

    expect(sync.opened, [book.bookUrl], reason: '先記成開著，背景的同步不改這本');
    expect(sync.pulls, 1);
    expect(runtime.state.visibleLocation.chapterIndex, 3);
    expect(runtime.state.visibleLocation.charOffset, 40);
    expect(book.progressTime, 7);
    expect(commits, 1);
  });

  test('pulling starts as the reader opens and the wait reuses it', () async {
    sync.pullGate = Completer();
    final progressSync = start();

    expect(sync.pulls, 1, reason: '點書當下就開始抓，不等換頁動畫');

    final opening = progressSync.openLocation(runtime);
    expect(sync.pulls, 1, reason: '動畫播完沿用同一次抓取，不再另發');

    sync.pullGate!.complete();
    await opening;
  });

  test('cloud progress later than the grace: opens at this phone\'s position, '
      'marked open so the sync leaves it alone', () async {
    sync.pullGate = Completer();
    final progressSync = start();

    final at = await progressSync.openLocation(runtime);

    expect(at, isNull);
    expect(sync.opened, [book.bookUrl]);
  });

  test('no sync running: opens without waiting, at the position saved on '
      'this phone even when the shelf handed over an older one', () async {
    bookDao.stored = book.copyWith(chapterIndex: 2, charOffset: 5);
    final progressSync = start();

    final at = await progressSync
        .openLocation(runtime)
        .timeout(const Duration(milliseconds: 100));

    expect(at?.chapterIndex, 2);
    expect(at?.charOffset, 5);
  });

  test('closing before positioning preserves saved progress', () async {
    bookDao.stored = book.copyWith(chapterIndex: 3, charOffset: 40);
    expect(await runtime.flushProgress(), isNull);
    expect(bookDao.writes, 0);
  });

  test('opening uses the latest visual offset', () async {
    bookDao.stored = book.copyWith(visualOffsetPx: 24);
    final at = await start().openLocation(runtime);
    expect(at?.visualOffsetPx, 24);
  });

  test('opening a chapter picked from the table of contents does not pull, '
      'wait or read the saved position', () async {
    sync.pullGate = Completer();
    final progressSync = start(openTarget: ReaderOpenTarget.chapterStart(4));

    expect(sync.opened, [book.bookUrl]);
    expect(await progressSync.openLocation(runtime), isNull);
    expect(sync.pulls, 0);
    expect(bookDao.reads, 0);
  });

  test('closing the reader while waiting ends the wait at once', () async {
    sync.pullGate = Completer();
    final progressSync = ReaderProgressSync(
      book: book,
      runtime: () => runtime,
      onProgressSuggestion: (_) {},
      bookDao: bookDao,
      sync: sync,
    )..start();

    final opening = progressSync.openLocation(runtime);
    progressSync.dispose();

    expect(await opening.timeout(const Duration(milliseconds: 100)), isNull);
    expect(bookDao.reads, 0);
  });

  test('a chapter picked before the book opened is where it opens', () async {
    unawaited(runtime.jumpToChapter(4));
    await runtime.openBook(
      at: const ReaderLocation(chapterIndex: 2, charOffset: 0),
    );

    expect(runtime.state.visibleLocation.chapterIndex, 4);
  });

  group('uploading while reading', () {
    test('an opened reader watches the saved position and leaves the '
        'background upload to itself until it closes', () async {
      final progressSync = start()..bookOpened();
      await runtime.openBook();

      expect(sync.hideUploaders, contains(progressSync));
      expect(runtime.progressController.onMoved, isNotNull);
      expect(runtime.progressController.onActivity, isNotNull);

      progressSync.retire();
      expect(sync.hideUploaders, isEmpty, reason: '換目錄時不上傳，交給主畫面');
      progressSync.resume();
      expect(sync.hideUploaders, contains(progressSync));

      progressSync.dispose();
      expect(sync.hideUploaders, isEmpty);
      expect(runtime.progressController.onMoved, isNull);
    });
  });

  testWidgets('a saved move followed by 8 still seconds asks for the '
      'progress to go up', (tester) async {
    final progressSync = ReaderProgressSync(
      book: book,
      runtime: () => runtime,
      onProgressSuggestion: (_) {},
      bookDao: bookDao,
      sync: sync,
    )..start();
    progressSync.bookOpened();
    await tester.runAsync(runtime.openBook);

    runtime.progressController.onMoved!();
    await tester.pump(const Duration(seconds: 7));
    expect(sync.progressFirstRequests, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(sync.progressFirstRequests, 1);
    progressSync.dispose();
  });

  group('leaving the reader', () {
    test('closing it asks for the progress to go up first', () async {
      final progressSync = ReaderProgressSync(
        book: book,
        runtime: () => runtime,
        onProgressSuggestion: (_) {},
        bookDao: bookDao,
        sync: sync,
      )..start();
      progressSync.bookOpened();
      await runtime.openBook();

      progressSync.dispose();
      await pumpEventQueue();

      expect(sync.progressFirstRequests, 1);
    });

    test(
      'going to the background asks for the progress to go up first',
      () async {
        start().bookOpened();
        await runtime.openBook();

        final binding = TestWidgetsFlutterBinding.instance;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await pumpEventQueue();

        expect(sync.progressFirstRequests, 1);
      },
    );
  });

  group('progress that arrives after the book opened', () {
    var commits = 0;
    final suggestions = <Future<void> Function()>[];

    PulledProgress cloudAt(int chapter, int offset) => PulledProgress(
      SyncedProgress(
        chapterIndex: chapter,
        charOffset: offset,
        chapterTitle: '第 $chapter 章',
        time: 1,
      ),
      (_) async => commits++,
    );

    /// 開書時雲端進度還沒抓到，等滿 [ReaderProgressSync.openGrace] 照這台
    /// 的位置開了。
    Future<ReaderProgressSync> openWhileSyncing() async {
      commits = 0;
      suggestions.clear();
      sync.pullGate = Completer();
      final progressSync = start(suggestions: suggestions);
      final at = await progressSync.openLocation(runtime);
      expect(at, isNull);
      await runtime.openBook(at: at);
      return progressSync;
    }

    test('the reader has not moved: it asks before jumping', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();
      expect(runtime.state.visibleLocation.chapterIndex, 1);

      // 進度晚到（超過等待的 0.5 秒）：另一台讀到第 3 章。
      sync.pulled = cloudAt(3, 40);
      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(runtime.state.visibleLocation.charOffset, 10);
      expect(suggestions, hasLength(1), reason: '正文已經在畫面上，先問');
      expect(commits, 0);
      expect(bookDao.synced, isEmpty);

      await suggestions.single();

      expect(runtime.state.visibleLocation.chapterIndex, 3);
      expect(runtime.state.visibleLocation.charOffset, 40);
      expect(commits, 1);
      expect(bookDao.synced, [1], reason: '時間記成不比雲端那一筆早');
    });

    test('the pull finished before the book was positioned: still asks '
        'after the book shows', () async {
      sync.pullGate = Completer();
      commits = 0;
      suggestions.clear();
      final progressSync = start(suggestions: suggestions);
      await progressSync.openLocation(runtime);
      sync.pulled = cloudAt(3, 40);
      sync.pullGate!.complete();
      await runtime.openBook();
      progressSync.bookOpened();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(suggestions, hasLength(1));
      await suggestions.single();
      expect(runtime.state.visibleLocation.chapterIndex, 3);
      expect(commits, 1);
    });

    test('the reader already moved: this phone\'s position is newer, nothing '
        'is overwritten', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();
      runtime.updateVisibleLocation(
        const ReaderLocation(chapterIndex: 1, charOffset: 300),
      );

      sync.pulled = cloudAt(3, 40);
      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(runtime.state.visibleLocation.charOffset, 300);
      expect(suggestions, isEmpty);
      expect(commits, 0);
    });

    test('the pull ended without anything newer: nothing happens', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();

      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(suggestions, isEmpty);
      expect(commits, 0);
    });

    test('the same position is recorded without asking', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();

      sync.pulled = cloudAt(1, 10);
      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.charOffset, 10);
      expect(suggestions, isEmpty);
      expect(commits, 1);
    });

    test('progress that came in time needs no catching up', () async {
      sync.pullGate = Completer();
      sync.pulled = pulledAt(3, 40, stores: true);
      suggestions.clear();
      final progressSync = start(suggestions: suggestions);
      final opening = progressSync.openLocation(runtime);
      sync.pullGate!.complete();
      await runtime.openBook(at: await opening);
      sync.pulled = cloudAt(4, 0);
      progressSync.bookOpened();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 3);
      expect(suggestions, isEmpty);
    });
  });

  group('catching up with a newer progress while reading', () {
    var commits = 0;
    final suggestions = <Future<void> Function()>[];

    /// 另一台讀到第 [chapter] 章第 [offset] 個字。
    PulledProgress cloudAt(int chapter, int offset) => PulledProgress(
      SyncedProgress(
        chapterIndex: chapter,
        charOffset: offset,
        chapterTitle: '第 $chapter 章',
        time: 1,
      ),
      (_) async => commits++,
    );

    /// App 退到背景再回到前景。
    Future<void> backToForeground() async {
      final binding = TestWidgetsFlutterBinding.instance;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      await pumpEventQueue();
    }

    Future<void> openReader() async {
      commits = 0;
      suggestions.clear();
      start(suggestions: suggestions).bookOpened();
      await runtime.openBook();
    }

    test('a newer progress asks before jumping', () async {
      await openReader();
      sync.pulled = cloudAt(1, 400);

      await backToForeground();

      expect(runtime.state.visibleLocation.charOffset, 10);
      expect(suggestions, hasLength(1));
      expect(commits, 0);
    });

    test('pressing the question jumps there and records the sync', () async {
      await openReader();
      sync.pulled = cloudAt(1, 400);

      await backToForeground();
      await suggestions.single();

      expect(runtime.state.visibleLocation.charOffset, 400);
      expect(commits, 1);
      expect(bookDao.synced, [1]);
    });

    test(
      'a position only a few characters away still asks and jumps there',
      () async {
        await openReader();
        sync.pulled = cloudAt(1, 50);

        await backToForeground();
        expect(suggestions, hasLength(1));
        await suggestions.single();

        expect(runtime.state.visibleLocation.charOffset, 50);
        expect(commits, 1);
      },
    );

    test('the very same position does not ask but is recorded', () async {
      await openReader();
      sync.pulled = cloudAt(1, 10);

      await backToForeground();

      expect(suggestions, isEmpty);
      expect(commits, 1);
    });

    test('moving after the question: pressing it does nothing', () async {
      await openReader();
      sync.pulled = cloudAt(1, 400);

      await backToForeground();
      runtime.updateVisibleLocation(
        const ReaderLocation(chapterIndex: 1, charOffset: 200),
      );
      await suggestions.single();

      expect(runtime.state.visibleLocation.charOffset, 200);
      expect(commits, 0);
    });

    test('scrolling in the same chapter while the jump is loading cancels '
        'it: not recorded as synced', () async {
      await openReader();
      sync.pulled = cloudAt(1, 400);
      final entered = Completer<void>();
      final gate = Completer<void>();
      restore = (_) async {
        entered.complete();
        await gate.future;
        return true;
      };

      await backToForeground();
      final jumping = suggestions.single();
      await entered.future;
      runtime.cancelJumpForUserScroll();
      runtime.updateVisibleLocation(
        const ReaderLocation(chapterIndex: 1, charOffset: 200),
      );
      gate.complete();
      await jumping;
      await pumpEventQueue();

      expect(commits, 0, reason: '沒記成同步過，下次回到前景還會再抓到雲端的位置');
      expect(runtime.state.visibleLocation.charOffset, 200);
    });

    test('a jump whose position cannot be saved is not recorded', () async {
      await openReader();
      sync.pulled = cloudAt(3, 5);
      bookDao.failWrites = true;

      await backToForeground();
      await suggestions.single();

      expect(commits, 0);
      expect(bookDao.synced, isEmpty);
    });

    test('a chapter that cannot be loaded does not jump or record', () async {
      await openReader();
      unavailable = {3};
      sync.pulled = cloudAt(3, 5);

      await backToForeground();
      await suggestions.single();

      expect(commits, 0);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
    });

    test('a jump replaced by a newer one does not record', () async {
      await openReader();
      sync.pulled = cloudAt(1, 400);
      final entered = Completer<void>();
      final gate = Completer<void>();
      var calls = 0;
      restore = (_) async {
        if (calls++ > 0) return true;
        entered.complete();
        await gate.future;
        return true;
      };

      await backToForeground();
      final jumping = suggestions.single();
      await entered.future;
      final newer = runtime.jumpToLocation(
        const ReaderLocation(chapterIndex: 2, charOffset: 0),
      );
      await newer;
      gate.complete();
      await jumping;
      await pumpEventQueue();

      expect(commits, 0);
      expect(runtime.state.visibleLocation.chapterIndex, 2);
    });
  });
}
