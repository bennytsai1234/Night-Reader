import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_sync.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

class _BookDao extends Fake implements BookDao {
  Book? stored;
  int reads = 0;

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
  }) async => null;
}

class _ChapterDao extends Fake implements ChapterDao {
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

class _SourceDao extends Fake implements BookSourceDao {}

/// 背景同步：[progress] 是這次同步做完閱讀進度那一步的時候，null 是沒在
/// 同步。
class _Sync extends Fake implements SyncService {
  Completer<void>? progress;
  final List<String> opened = [];

  /// 閱讀器回到前景時抓到的雲端進度；null 是沒有比較新的。
  PulledProgress? pulled;

  @override
  Future<PulledProgress?> pullProgress(String bookUrl) async => pulled;

  @override
  Future<void>? get progressReady => progress?.future;

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
  late ReaderV2Runtime runtime;

  /// 視窗把位置排好的動作；測試換掉它來控制跳轉什麼時候完成。
  late Future<bool> Function(ReaderV2Location location) restore;

  /// 取不到內容的章節。
  late Set<int> unavailable;

  setUp(() {
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
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      contentLoader: (index, chapter) async {
        if (unavailable.contains(index)) {
          throw const ReaderV2ContentUnavailableException('這一章暫時取不到');
        }
        return chapter.content;
      },
      bookDao: bookDao,
      chapterDao: _ChapterDao(),
      sourceDao: _SourceDao(),
    );
    runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(220, 180),
        style: const ReaderV2LayoutStyle(
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
      initialLocation: const ReaderV2Location(chapterIndex: 1, charOffset: 10),
    );
    runtime.registerViewportRestore(Object(), (location) => restore(location));
    addTearDown(runtime.dispose);
  });

  ReaderV2ProgressSync start({
    ReaderV2OpenTarget? openTarget,
    void Function(ReaderV2Location previous)? onJumped,
  }) {
    final progressSync = ReaderV2ProgressSync(
      book: book,
      runtime: () => runtime,
      onJumped: onJumped ?? (_) => fail('開書不提示'),
      bookDao: bookDao,
      openTarget: openTarget,
      sync: sync,
    )..start();
    addTearDown(progressSync.dispose);
    return progressSync;
  }

  test('a book tapped while the sync is still on progress opens where the '
      'other phone was', () async {
    sync.progress = Completer();
    final progressSync = start();

    final opening = progressSync.openLocation(runtime);
    await pumpEventQueue();
    expect(sync.opened, isEmpty, reason: '等同步的這段時間，背景還能改這本書');

    // 同步把另一台的進度寫進資料庫。
    bookDao.stored = book.copyWith(chapterIndex: 3, charOffset: 40);
    sync.progress!.complete();
    final at = await opening;
    await runtime.openBook(at: at);

    expect(sync.opened, [book.bookUrl]);
    expect(runtime.state.visibleLocation.chapterIndex, 3);
    expect(runtime.state.visibleLocation.charOffset, 40);
  });

  test('progress later than the grace: opens at this phone\'s position, '
      'marked open so the sync leaves it alone', () async {
    sync.progress = Completer();
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

  test('opening a chapter picked from the table of contents does not wait '
      'or read the saved position', () async {
    sync.progress = Completer();
    final progressSync = start(openTarget: ReaderV2OpenTarget.chapterStart(4));

    expect(sync.opened, [book.bookUrl]);
    expect(await progressSync.openLocation(runtime), isNull);
    expect(bookDao.reads, 0);
  });

  test('closing the reader while waiting ends the wait at once', () async {
    sync.progress = Completer();
    final progressSync = ReaderV2ProgressSync(
      book: book,
      runtime: () => runtime,
      onJumped: (_) {},
      bookDao: bookDao,
      sync: sync,
    )..start();

    final opening = progressSync.openLocation(runtime);
    progressSync.dispose();

    expect(await opening.timeout(const Duration(milliseconds: 100)), isNull);
    expect(sync.opened, isEmpty);
  });

  test('a chapter picked before the book opened is where it opens', () async {
    unawaited(runtime.jumpToChapter(4));
    await runtime.openBook(
      at: const ReaderV2Location(chapterIndex: 2, charOffset: 0),
    );

    expect(runtime.state.visibleLocation.chapterIndex, 4);
  });

  group('leaving the reader', () {
    test('closing it saves the position and asks for the progress to go up '
        'first', () async {
      final progressSync = ReaderV2ProgressSync(
        book: book,
        runtime: () => runtime,
        onJumped: (_) {},
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
    final jumped = <ReaderV2Location>[];

    PulledProgress cloudAt(int chapter, int offset) => PulledProgress(
      SyncedProgress(
        chapterIndex: chapter,
        charOffset: offset,
        chapterTitle: '第 $chapter 章',
        time: 1,
      ),
      (_) async => commits++,
    );

    /// 開書時同步的進度還沒好，等滿 [ReaderV2ProgressSync.openGrace] 照這台
    /// 的位置開了。
    Future<ReaderV2ProgressSync> openWhileSyncing() async {
      commits = 0;
      jumped.clear();
      sync.progress = Completer();
      final progressSync = start(onJumped: jumped.add);
      final at = await progressSync.openLocation(runtime);
      expect(at, isNull);
      await runtime.openBook(at: at);
      return progressSync;
    }

    test('the reader has not moved: it catches up with the other phone and '
        'says so', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();
      expect(runtime.state.visibleLocation.chapterIndex, 1);

      // 進度晚到（超過等待的 0.5 秒）：另一台讀到第 3 章。
      sync.pulled = cloudAt(3, 40);
      sync.progress!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 3);
      expect(runtime.state.visibleLocation.charOffset, 40);
      expect(jumped.map((it) => it.chapterIndex), [1], reason: '提示可以回到原處');
      expect(commits, 1);
    });

    test('the sync finished before the book was positioned: still catches '
        'up', () async {
      sync.progress = Completer();
      commits = 0;
      jumped.clear();
      final progressSync = start(onJumped: jumped.add);
      await progressSync.openLocation(runtime);
      sync.pulled = cloudAt(3, 40);
      sync.progress!.complete();
      await runtime.openBook();
      progressSync.bookOpened();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 3);
      expect(commits, 1);
    });

    test('the reader already moved: this phone\'s position is newer, nothing '
        'is overwritten', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();
      runtime.updateVisibleLocation(
        const ReaderV2Location(chapterIndex: 1, charOffset: 300),
      );

      sync.pulled = cloudAt(3, 40);
      sync.progress!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(runtime.state.visibleLocation.charOffset, 300);
      expect(jumped, isEmpty);
      expect(commits, 0);
    });

    test('the sync ended without anything newer: nothing happens', () async {
      final progressSync = await openWhileSyncing();
      progressSync.bookOpened();

      sync.progress!.complete();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(jumped, isEmpty);
      expect(commits, 0);
    });

    test('progress that came in time needs no catching up', () async {
      sync.progress = Completer();
      final progressSync = start();
      final opening = progressSync.openLocation(runtime);
      bookDao.stored = book.copyWith(chapterIndex: 3, charOffset: 40);
      sync.progress!.complete();
      await runtime.openBook(at: await opening);
      sync.pulled = cloudAt(4, 0);
      progressSync.bookOpened();
      await pumpEventQueue();

      expect(runtime.state.visibleLocation.chapterIndex, 3);
    });
  });

  group('catching up with a newer progress while reading', () {
    var commits = 0;
    final jumped = <ReaderV2Location>[];

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
      jumped.clear();
      start(onJumped: jumped.add).bookOpened();
      await runtime.openBook();
    }

    test('a jump that lands shows the notice and records the sync', () async {
      await openReader();
      sync.pulled = cloudAt(1, 400);

      await backToForeground();

      expect(runtime.state.visibleLocation.charOffset, 400);
      expect(jumped.map((it) => it.charOffset), [10]);
      expect(commits, 1);
    });

    test(
      'a position within the near range does not jump but is recorded',
      () async {
        await openReader();
        sync.pulled = cloudAt(1, 50);

        await backToForeground();

        expect(jumped, isEmpty);
        expect(commits, 1);
      },
    );

    test('scrolling in the same chapter while the jump is loading cancels '
        'it: no notice, not recorded as synced', () async {
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
      await entered.future;
      runtime.cancelJumpForUserScroll();
      runtime.updateVisibleLocation(
        const ReaderV2Location(chapterIndex: 1, charOffset: 200),
      );
      gate.complete();
      await pumpEventQueue();

      expect(jumped, isEmpty);
      expect(commits, 0, reason: '沒記成同步過，下次回到前景還會再抓到雲端的位置');
      expect(runtime.state.visibleLocation.charOffset, 200);
    });

    test('a chapter that cannot be loaded does not jump or record', () async {
      await openReader();
      unavailable = {3};
      sync.pulled = cloudAt(3, 5);

      await backToForeground();

      expect(jumped, isEmpty);
      expect(commits, 0);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
    });

    test('a jump replaced by a newer one does not show the notice or '
        'record', () async {
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
      await entered.future;
      final newer = runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 2, charOffset: 0),
      );
      await newer;
      gate.complete();
      await pumpEventQueue();

      expect(jumped, isEmpty);
      expect(commits, 0);
      expect(runtime.state.visibleLocation.chapterIndex, 2);
    });
  });
}
