import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/comic_reader/comic_progress_sync.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';

import '../audiobook/audiobook_test_doubles.dart';

class _BookDao extends Fake implements BookDao {
  Book? stored;

  @override
  Future<Book?> getByUrl(String url) async => stored;

  /// 跳到雲端進度後記下的時間。
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

/// 另一台在第 [chapter] 話第 [page] 張；記成同步過時 [commits] 加一。
PulledProgress _cloudAt(int chapter, int page, void Function() onCommit) =>
    PulledProgress(
      SyncedProgress(
        chapterIndex: chapter,
        charOffset: page,
        chapterTitle: '第${chapter + 1}話',
        time: 9,
      ),
      (_) async => onCommit(),
    );

/// App 退到背景再回到前景。
void _backToForeground() => TestWidgetsFlutterBinding.instance
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 回到前景抓另一台的進度；抓的途中讀者在同一張長圖裡往下讀了，另一台的
  // 位置就不再問（同一張的幾成也算動過）。
  for (final (moved, label) in [
    (const ComicLocation(0, 0, fraction: 0.6), '同一張往下讀'),
    (null, '沒動'),
  ]) {
    test('回到前景接另一台的進度：抓的途中$label', () async {
      final sync = FakeSync()
        ..pullGate = Completer<void>()
        ..pulled = PulledProgress(
          const SyncedProgress(
            chapterIndex: 0,
            charOffset: 4,
            chapterTitle: '第1話',
            time: 1,
          ),
          (_) async {},
        );
      var here = const ComicLocation(0, 0, fraction: 0.1);
      final jumps = <(int, int)>[];
      final suggestions = <Future<void> Function()>[];
      final progress = ComicProgressSync(
        book: Book(bookUrl: 'https://comic.test/b', name: '長圖', origin: 'x'),
        bookDao: _BookDao(),
        current: () => here,
        flush: () async {},
        titles: () => const ['第1話', '第2話'],
        ids: () => const ['c1', 'c2'],
        jumpTo: (chapter, page) async {
          jumps.add((chapter, page));
          return true;
        },
        onProgressSuggestion: suggestions.add,
        resumes: false,
        sync: sync,
      )..start();
      addTearDown(progress.dispose);
      progress.bookOpened();

      TestWidgetsFlutterBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      if (moved != null) here = moved;
      sync.pullGate!.complete();
      await pumpEventQueue();

      if (moved == null) {
        expect(jumps, isEmpty, reason: '正文已經在畫面上，先問');
        expect(suggestions, hasLength(1));
        await suggestions.single();
      } else {
        expect(suggestions, isEmpty);
      }
      expect(jumps, moved == null ? [(0, 4)] : isEmpty);
    });
  }

  test('另一台不在同一張就跳，同一張不跳', () {
    const here = ComicLocation(3, 10, fraction: 0.4);
    expect(ComicProgressSync.shouldJump(here, 3, 10), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 11), isTrue);
    expect(ComicProgressSync.shouldJump(here, 3, 9), isTrue);
    expect(ComicProgressSync.shouldJump(here, 4, 10), isTrue);
  });

  group('接另一台的進度', () {
    late _BookDao bookDao;
    late FakeSync sync;
    late ComicLocation here;
    late List<(int, int)> jumps;
    late List<Future<void> Function()> suggestions;
    late bool lands;
    var commits = 0;

    setUp(() {
      bookDao = _BookDao();
      sync = FakeSync();
      here = const ComicLocation(0, 0, fraction: 0.1);
      jumps = [];
      suggestions = [];
      lands = true;
      commits = 0;
    });

    ComicProgressSync open({bool resumes = false}) {
      final book = Book(
        bookUrl: 'https://comic.test/b',
        name: '長圖',
        origin: 'x',
      );
      bookDao.stored = book;
      final progress = ComicProgressSync(
        book: book,
        bookDao: bookDao,
        current: () => here,
        flush: () async {},
        titles: () => const ['第1話', '第2話'],
        ids: () => const ['c1', 'c2'],
        jumpTo: (chapter, page) async {
          jumps.add((chapter, page));
          if (lands) here = ComicLocation(chapter, page);
          return lands;
        },
        onProgressSuggestion: suggestions.add,
        resumes: resumes,
        sync: sync,
      )..start();
      addTearDown(progress.dispose);
      return progress;
    }

    test('跳到了那一話那一張：先問，按了才跳、記成同步過，時間不比那一筆早', () async {
      open().bookOpened();
      sync.pulled = _cloudAt(1, 3, () => commits++);
      _backToForeground();
      await pumpEventQueue();

      expect(jumps, isEmpty);
      expect(suggestions, hasLength(1));
      await suggestions.single();

      expect(jumps, [(1, 3)]);
      expect(commits, 1);
      expect(bookDao.synced, [9]);
    });

    test('那一話載不下來、落到別話：按了也不記成同步過', () async {
      lands = false;
      open().bookOpened();
      sync.pulled = _cloudAt(1, 3, () => commits++);
      _backToForeground();
      await pumpEventQueue();

      expect(suggestions, hasLength(1));
      await suggestions.single();

      expect(jumps, [(1, 3)]);
      expect(commits, 0);
      expect(bookDao.synced, isEmpty);
    });

    test('位置完全一樣：不出提示，照舊記成同步過', () async {
      open().bookOpened();
      sync.pulled = _cloudAt(0, 0, () => commits++);
      _backToForeground();
      await pumpEventQueue();

      expect(suggestions, isEmpty);
      expect(jumps, isEmpty);
      expect(commits, 1);
    });

    test('點書當下就開始抓，換頁動畫播完沿用同一次', () async {
      sync.pullGate = Completer<void>();
      final progress = open(resumes: true);

      expect(sync.pulls, 1, reason: '點書當下就開始抓，不等換頁動畫');

      final opening = progress.openLocation();
      expect(sync.pulls, 1, reason: '動畫播完沿用同一次抓取，不再另發');

      sync.pullGate!.complete();
      await opening;
    });

    test('開書時雲端進度晚到：先照這台的位置開，讀者沒捲就出提示，按了才跳', () async {
      sync
        ..pullGate = Completer<void>()
        ..pulled = _cloudAt(1, 2, () => commits++);
      final progress = open(resumes: true);
      final at = await progress.openLocation();
      expect(at?.chapterIndex, 0);
      expect(sync.opened, ['https://comic.test/b']);
      progress.bookOpened();

      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(jumps, isEmpty, reason: '正文已經在畫面上，先問');
      expect(suggestions, hasLength(1));
      await suggestions.single();

      expect(jumps, [(1, 2)]);
      expect(commits, 1);
    });

    test('開書時雲端進度晚到、讀者已經捲過：不出提示、不跳', () async {
      sync
        ..pullGate = Completer<void>()
        ..pulled = _cloudAt(1, 2, () => commits++);
      final progress = open(resumes: true);
      await progress.openLocation();
      progress.bookOpened();
      here = const ComicLocation(0, 1);

      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(suggestions, isEmpty);
      expect(jumps, isEmpty);
      expect(commits, 0);
    });

    test('開書前就抓到：直接開在雲端的位置，不出提示', () async {
      sync
        ..pullGate = Completer<void>()
        ..pulled = PulledProgress(
          const SyncedProgress(
            chapterIndex: 1,
            charOffset: 3,
            chapterTitle: '第2話',
            time: 9,
          ),
          (_) async => commits++,
          applyStored: () async {
            bookDao.stored = bookDao.stored!.copyWith(
              chapterIndex: 1,
              charOffset: 3,
              progressTime: 9,
            );
            return ProgressSync.recordOf(bookDao.stored!);
          },
        );
      final progress = open(resumes: true);
      final opening = progress.openLocation();
      sync.pullGate!.complete();
      final at = await opening;

      expect(at?.chapterIndex, 1);
      expect(at?.pageIndex, 3);
      expect(suggestions, isEmpty);
    });

    testWidgets('讀書途中位置變了、畫面停住 8 秒才送；一直在捲就不送', (tester) async {
      final progress = open()..bookOpened();
      progress.moved();
      for (var i = 0; i < 10; i++) {
        progress.located();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(sync.progressFirstRequests, 0);

      // 最後一次捲動之後至少停住 8 秒才送（最晚 16 秒）。
      await tester.pump(const Duration(seconds: 8));
      expect(sync.progressFirstRequests, 0);
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(sync.progressFirstRequests, 1);
      progress.dispose();
    });

    test('從目錄點某一話開書：不抓', () async {
      final progress = open();
      expect(await progress.openLocation(), isNull);
      expect(sync.pulls, 0);
    });
  });
}
