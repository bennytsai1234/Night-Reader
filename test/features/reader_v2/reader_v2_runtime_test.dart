import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:reader/features/reader_v2/content/reader_v2_content.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_chapter_view.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_performance_metrics.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_preload_scheduler.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_progress_controller.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_resolver.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderV2Resolver', () {
    test('reuses cached layouts and invalidates them by generation', () async {
      final engine = _CountingLayoutEngine();
      final resolver = ReaderV2Resolver(
        repository: _repository(),
        layoutEngine: engine,
        layoutSpec: _spec(fontSize: 18),
      );

      final first = await resolver.ensureLayout(0);
      final second = await resolver.ensureLayout(0);
      expect(identical(first, second), isTrue);
      expect(engine.layoutCount, 1);

      resolver.updateLayoutSpec(_spec(fontSize: 22));
      final third = await resolver.ensureLayout(0);
      expect(identical(first, third), isFalse);
      expect(engine.layoutCount, 2);

      resolver.clearCachedLayouts();
      await resolver.ensureLayout(0);
      expect(engine.layoutCount, 3);
    });
  });

  group('ReaderV2PreloadScheduler', () {
    test('promotes an already queued priority layout preload', () async {
      final repository = _ControlledContentRepository(chapterCount: 4);
      final scheduler = ReaderV2PreloadScheduler(
        resolver: ReaderV2Resolver(
          repository: repository,
          layoutEngine: ReaderV2LayoutEngine(),
          layoutSpec: _spec(),
        ),
      );

      final active = scheduler.scheduleLayout(0);
      final queuedPriority = scheduler.scheduleLayout(2);
      final queuedNormal = scheduler.scheduleLayout(3);
      final promoted = scheduler.scheduleLayout(2, priority: true);

      try {
        expect(
          await repository
              .waitForStartCount(1)
              .timeout(const Duration(seconds: 1)),
          0,
        );

        repository.completeLoad(0);
        final secondStarted = await repository
            .waitForStartCount(2)
            .timeout(const Duration(seconds: 1));
        expect(secondStarted, 2);

        repository.completeLoad(2);
        final thirdStarted = await repository
            .waitForStartCount(3)
            .timeout(const Duration(seconds: 1));
        expect(thirdStarted, 3);

        repository.completeLoad(3);
        await Future.wait(<Future<void>>[
          active,
          queuedPriority,
          queuedNormal,
          promoted,
        ]).timeout(const Duration(seconds: 1));
      } finally {
        repository.completeAllLoads();
        scheduler.dispose();
      }
    });

    test(
      'defers layout while interactive but still preloads content',
      () async {
        final repository = _ControlledContentRepository(chapterCount: 3);
        final engine = _CountingLayoutEngine();
        final scheduler = ReaderV2PreloadScheduler(
          resolver: ReaderV2Resolver(
            repository: repository,
            layoutEngine: engine,
            layoutSpec: _spec(),
          ),
        );

        scheduler.beginInteractive();
        final preload = scheduler.scheduleLayout(1, priority: true);

        try {
          final started = await repository
              .waitForStartCount(1)
              .timeout(const Duration(seconds: 1));
          expect(started, 1);
          expect(engine.layoutCount, 0);

          repository.completeLoad(1);
          await Future<void>.delayed(Duration.zero);
          expect(engine.layoutCount, 0);

          scheduler.endInteractive();
          await preload.timeout(const Duration(seconds: 1));
          expect(engine.layoutCount, 1);
        } finally {
          repository.completeAllLoads();
          scheduler.dispose();
        }
      },
    );

    test('interactive layout pause is depth balanced', () async {
      final repository = _ControlledContentRepository(chapterCount: 2);
      final engine = _CountingLayoutEngine();
      final scheduler = ReaderV2PreloadScheduler(
        resolver: ReaderV2Resolver(
          repository: repository,
          layoutEngine: engine,
          layoutSpec: _spec(),
        ),
      );

      scheduler.beginInteractive();
      scheduler.beginInteractive();
      final preload = scheduler.scheduleLayout(1, priority: true);

      try {
        await repository
            .waitForStartCount(1)
            .timeout(const Duration(seconds: 1));
        repository.completeLoad(1);
        await Future<void>.delayed(Duration.zero);

        scheduler.endInteractive();
        await Future<void>.delayed(Duration.zero);
        expect(engine.layoutCount, 0);

        scheduler.endInteractive();
        await preload.timeout(const Duration(seconds: 1));
        expect(engine.layoutCount, 1);
      } finally {
        repository.completeAllLoads();
        scheduler.dispose();
      }
    });
  });

  group('ReaderV2Runtime', () {
    test('saving progress updates book position', () async {
      final book = _book();
      final repository = _repository(book: book);
      final controller = ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: _FakeBookDao(),
      );

      await controller.saveImmediately(
        const ReaderV2Location(chapterIndex: 1, charOffset: 12),
      );

      expect(book.chapterIndex, 1);
      expect(book.charOffset, 12);
      controller.dispose();
    });

    test(
      'jumpToLocation resolves a page window and visible location',
      () async {
        final runtime = _runtime(initialMode: ReaderV2Mode.slide);

        await runtime.jumpToLocation(
          const ReaderV2Location(chapterIndex: 1, charOffset: 12),
          immediateSave: false,
        );

        expect(runtime.state.phase, ReaderV2Phase.ready);
        expect(runtime.state.visibleLocation.chapterIndex, 1);
        expect(runtime.state.pageWindow, isNotNull);
        expect(runtime.state.pageWindow!.current.chapterIndex, 1);
        expect(runtime.state.currentSlidePage?.chapterIndex, 1);

        runtime.dispose();
      },
    );

    test('captureVisibleLocation can update state silently', () async {
      final runtime = _runtime(initialMode: ReaderV2Mode.scroll);
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );

      var notifyCount = 0;
      runtime.addListener(() => notifyCount += 1);
      final captureOwner = Object();
      var nextOffset = 6;
      runtime.registerVisibleLocationCapture(captureOwner, () {
        return ReaderV2Location(chapterIndex: 0, charOffset: nextOffset);
      });

      final silent = runtime.captureVisibleLocation(notifyIfChanged: false);
      expect(silent, isNotNull);
      expect(silent!.charOffset, 6);
      expect(runtime.state.visibleLocation.charOffset, 6);
      expect(notifyCount, 0);

      nextOffset = 9;
      final notified = runtime.captureVisibleLocation();
      expect(notified, isNotNull);
      expect(notified!.charOffset, 9);
      expect(runtime.state.visibleLocation.charOffset, 9);
      expect(notifyCount, 1);

      runtime.unregisterVisibleLocationCapture(captureOwner);
      runtime.dispose();
    });

    test('applyPresentation keeps location while changing mode/spec', () async {
      final runtime = _runtime(initialMode: ReaderV2Mode.slide);
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 20),
        immediateSave: false,
      );
      final before = runtime.state.visibleLocation;
      final beforeGeneration = runtime.state.layoutGeneration;

      await runtime.applyPresentation(
        spec: _spec(fontSize: 22),
        mode: ReaderV2Mode.scroll,
      );

      expect(runtime.state.phase, ReaderV2Phase.ready);
      expect(runtime.state.mode, ReaderV2Mode.scroll);
      expect(runtime.state.visibleLocation.chapterIndex, before.chapterIndex);
      expect(runtime.state.visibleLocation.charOffset, before.charOffset);
      expect(runtime.state.layoutGeneration, greaterThan(beforeGeneration));

      runtime.dispose();
    });

    test(
      'reloadContentPreservingLocation clears caches and restores anchor',
      () async {
        final runtime = _runtime(initialMode: ReaderV2Mode.scroll);
        await runtime.jumpToLocation(
          const ReaderV2Location(chapterIndex: 1, charOffset: 18),
          immediateSave: false,
        );
        final before = runtime.state.visibleLocation;
        final beforeGeneration = runtime.state.layoutGeneration;

        await runtime.reloadContentPreservingLocation();

        expect(runtime.state.phase, ReaderV2Phase.ready);
        expect(runtime.state.visibleLocation.chapterIndex, before.chapterIndex);
        expect(runtime.state.visibleLocation.charOffset, before.charOffset);
        expect(runtime.state.layoutGeneration, greaterThan(beforeGeneration));

        runtime.dispose();
      },
    );

    test(
      'preloadDirectionalForVelocity widens preload span for fast fling',
      () async {
        final runtime = _runtime(
          initialMode: ReaderV2Mode.scroll,
          chapterCount: 7,
        );
        await runtime.jumpToLocation(
          const ReaderV2Location(chapterIndex: 3, charOffset: 0),
          immediateSave: false,
        );

        await runtime.preloadDirectionalForVelocity(
          chapterIndex: 3,
          forward: true,
          velocity: 4200,
        );

        expect(runtime.debugResolver.cachedLayout(4), isNotNull);
        expect(runtime.debugResolver.cachedLayout(5), isNotNull);
        expect(runtime.debugResolver.cachedLayout(6), isNotNull);

        runtime.dispose();
      },
    );

    test(
      'cache manager keeps recent chapter across one window shift',
      () async {
        final runtime = _runtime(
          initialMode: ReaderV2Mode.scroll,
          chapterCount: 8,
        );
        await runtime.jumpToLocation(
          const ReaderV2Location(chapterIndex: 2, charOffset: 0),
          immediateSave: false,
        );

        final manager = ReaderV2ChapterPageCacheManager(
          runtime: runtime,
          pageExtent: (page) => page.height,
        );
        await manager.ensureWindowAround(
          centerChapterIndex: 2,
          backwardExtent: 1,
          forwardExtent: 1,
        );
        expect(manager.containsChapter(1), isTrue);

        await manager.ensureWindowAround(
          centerChapterIndex: 3,
          backwardExtent: 1,
          forwardExtent: 1,
        );
        expect(manager.containsChapter(1), isTrue);

        await manager.ensureWindowAround(
          centerChapterIndex: 5,
          backwardExtent: 1,
          forwardExtent: 1,
        );
        expect(manager.containsChapter(1), isFalse);

        runtime.dispose();
      },
    );

    test('chapter view binary lookups match reference scan logic', () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 1,
        paragraphsPerChapter: 36,
      );
      final view = await runtime.debugResolver.ensureLayout(0);
      final textLength = view.displayText.length;
      final offsets = <int>{
        0,
        1,
        2,
        textLength ~/ 4,
        textLength ~/ 2,
        (textLength * 3) ~/ 4,
        textLength,
        textLength + 7,
      };

      for (final offset in offsets) {
        final actual = view.lineForCharOffset(offset);
        final expected = _referenceLineForCharOffset(view, offset);
        expect(actual, expected, reason: 'offset=$offset');
      }

      final ranges = <({int start, int end})>[
        (start: 0, end: 6),
        (start: textLength ~/ 3, end: textLength ~/ 3 + 24),
        (start: textLength ~/ 2, end: textLength ~/ 2),
        (start: textLength - 12, end: textLength + 4),
      ];
      for (final range in ranges) {
        final actual = view.linesForRange(range.start, range.end);
        final expected = _referenceLinesForRange(view, range.start, range.end);
        expect(
          actual.map((line) => line.lineIndex).toList(growable: false),
          expected.map((line) => line.lineIndex).toList(growable: false),
          reason: 'range=${range.start}-${range.end}',
        );
      }

      final maxY = view.contentHeight + 48;
      for (var step = 0; step <= 12; step++) {
        final localY = (maxY / 12) * step;
        expect(
          view.pageForLocalY(localY),
          _referencePageForLocalY(view, localY),
          reason: 'page y=$localY',
        );
        expect(
          view.lineAtOrNearLocalY(localY),
          _referenceLineAtOrNearLocalY(view, localY),
          reason: 'line y=$localY',
        );
      }

      runtime.dispose();
    });

    test(
      'jumpToChapter survives concurrent applyPresentation (race guard)',
      () async {
        // Simulate the race where applyPresentation fires (e.g., from an
        // initial loadSettings completion) while jumpToChapter is blocked
        // waiting for chapter content to load.  Without the fix, applyPresentation
        // would capture the *old* visibleLocation (chapter 0) and navigate there,
        // leaving the user at the wrong chapter after the drawer tap.
        final repository = _ControlledContentRepository(chapterCount: 3);
        final book = _book();
        final runtime = ReaderV2Runtime(
          book: book,
          repository: repository,
          layoutEngine: ReaderV2LayoutEngine(),
          progressController: ReaderV2ProgressController(
            book: book,
            repository: repository,
            bookDao: _FakeBookDao(),
          ),
          initialLayoutSpec: _spec(),
          initialMode: ReaderV2Mode.slide,
          initialLocation: const ReaderV2Location(
            chapterIndex: 0,
            charOffset: 0,
          ),
        );

        // Establish a known starting position at chapter 0.
        repository.completeLoad(0);
        await runtime.jumpToLocation(
          const ReaderV2Location(chapterIndex: 0, charOffset: 0),
          immediateSave: false,
        );
        expect(runtime.state.visibleLocation.chapterIndex, 0);

        // Start jumping to chapter 2.  The repository will block until we
        // release it, creating the async gap where the race can occur.
        final jumpFuture = runtime.jumpToChapter(2);

        // While jumpToChapter is suspended (chapter 2 not yet loaded),
        // applyPresentation fires — as happens when loadSettings() completes
        // shortly after the reader opens.  Previously, applyPresentation would
        // grab state.visibleLocation = chapter 0 and navigate there, cancelling
        // the jumpToChapter.
        final presentFuture = runtime.applyPresentation(
          spec: _spec(fontSize: 22),
          mode: ReaderV2Mode.slide,
        );

        // Unblock chapter 2 so both futures can complete.
        repository.completeLoad(2);
        await Future.wait(<Future<void>>[jumpFuture, presentFuture]);

        // The user must end up at chapter 2, not chapter 0.
        expect(runtime.state.phase, ReaderV2Phase.ready);
        expect(runtime.state.visibleLocation.chapterIndex, 2);

        runtime.dispose();
      },
    );

    test('collects and clears performance metrics snapshot', () async {
      final runtime = _runtime(initialMode: ReaderV2Mode.scroll);
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );

      runtime.debugRecordFrameSample(totalMs: 18, buildMs: 7, rasterMs: 6);
      runtime.debugRecordFrameSample(totalMs: 12, buildMs: 5, rasterMs: 4);
      runtime.recordFullScreenLoadingSample();
      runtime.recordOverlayLoadingSample();
      runtime.recordSlidePlaceholderExposure(2);
      runtime.recordSlidePlaceholderExposure(1);

      final snapshot = runtime.performanceSnapshot;
      expect(snapshot, isA<ReaderV2PerformanceSnapshot>());
      expect(snapshot.layoutSampleCount, greaterThan(0));
      expect(snapshot.frameSampleCount, 2);
      expect(snapshot.worstFrameTotalMs, closeTo(18, 0.001));
      expect(snapshot.jankyFrameCount, 1);
      expect(snapshot.fullScreenLoadingSampleCount, 1);
      expect(snapshot.overlayLoadingSampleCount, 1);
      expect(snapshot.slidePlaceholderSampleCount, 2);
      expect(snapshot.slidePlaceholderExposureCount, 3);
      expect(runtime.performanceProfilingSignal, contains('frame('));

      runtime.clearPerformanceMetrics();
      final cleared = runtime.performanceSnapshot;
      expect(cleared.frameSampleCount, 0);
      expect(cleared.layoutSampleCount, 0);
      expect(cleared.fullScreenLoadingSampleCount, 0);
      expect(cleared.overlayLoadingSampleCount, 0);
      expect(cleared.slidePlaceholderSampleCount, 0);
      expect(cleared.slidePlaceholderExposureCount, 0);

      runtime.dispose();
    });
  });
}

ReaderV2Runtime _runtime({
  required ReaderV2Mode initialMode,
  int chapterCount = 3,
  int paragraphsPerChapter = 12,
}) {
  final book = _book();
  final repository = _repository(
    book: book,
    chapterCount: chapterCount,
    paragraphsPerChapter: paragraphsPerChapter,
  );
  return ReaderV2Runtime(
    book: book,
    repository: repository,
    layoutEngine: ReaderV2LayoutEngine(),
    progressController: ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: _FakeBookDao(),
    ),
    initialLayoutSpec: _spec(),
    initialMode: initialMode,
    initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
  );
}

ReaderV2ChapterRepository _repository({
  Book? book,
  int chapterCount = 3,
  int paragraphsPerChapter = 12,
}) {
  final targetBook = book ?? _book();
  final chapters = _chapters(
    targetBook.bookUrl,
    count: chapterCount,
    paragraphsPerChapter: paragraphsPerChapter,
  );
  return ReaderV2ChapterRepository(
    book: targetBook,
    initialChapters: chapters,
    bookDao: _FakeBookDao(),
    chapterDao: _FakeChapterDao(chapters),
    sourceDao: _FakeSourceDao(),
    contentDao: null,
  );
}

Book _book() {
  return Book(
    bookUrl: 'test://book',
    origin: 'local',
    originName: 'fixture',
    name: '測試書',
  );
}

List<BookChapter> _chapters(
  String bookUrl, {
  int count = 3,
  int paragraphsPerChapter = 12,
}) {
  return List<BookChapter>.generate(count, (index) {
    return BookChapter(
      index: index,
      bookUrl: bookUrl,
      title: '第${index + 1}章',
      content: List<String>.filled(
        paragraphsPerChapter,
        '這是第${index + 1}章的測試內容，用於建立足夠多的排版行與頁面。',
      ).join('\n\n'),
    );
  });
}

ReaderV2RenderLine? _referenceLineForCharOffset(
  ReaderV2ChapterView view,
  int charOffset,
) {
  final queryLines = view.lines;
  if (queryLines.isEmpty) return null;
  ReaderV2RenderLine? previous;
  for (var index = 0; index < queryLines.length; index++) {
    final line = queryLines[index];
    if (line.text.isEmpty) continue;
    final effectiveEnd = _referenceEffectiveLineEnd(queryLines, index);
    if (charOffset >= line.startCharOffset && charOffset < effectiveEnd) {
      return line;
    }
    if (charOffset < line.startCharOffset) return line;
    previous = line;
  }
  return previous;
}

ReaderV2RenderLine? _referenceLineAtOrNearLocalY(
  ReaderV2ChapterView view,
  double localY,
) {
  ReaderV2RenderLine? nearest;
  var nearestDistance = double.infinity;
  for (final line in view.lines) {
    if (line.text.isEmpty) continue;
    if (localY >= line.top && localY <= line.bottom) return line;
    final distance =
        localY < line.top ? line.top - localY : localY - line.bottom;
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = line;
    }
  }
  return nearest;
}

ReaderV2RenderPage? _referencePageForLocalY(
  ReaderV2ChapterView view,
  double localY,
) {
  if (view.pages.isEmpty) return null;
  if (localY <= view.pages.first.localStartY) return view.pages.first;
  var best = view.pages.first;
  for (final page in view.pages) {
    if (page.localStartY <= localY) {
      best = page;
    } else {
      break;
    }
  }
  return best;
}

List<ReaderV2RenderLine> _referenceLinesForRange(
  ReaderV2ChapterView view,
  int startCharOffset,
  int endCharOffset,
) {
  final start =
      startCharOffset <= endCharOffset ? startCharOffset : endCharOffset;
  final end =
      startCharOffset <= endCharOffset ? endCharOffset : startCharOffset;
  if (start == end) {
    final line = _referenceLineForCharOffset(view, start);
    return line == null
        ? const <ReaderV2RenderLine>[]
        : <ReaderV2RenderLine>[line];
  }
  final queryLines = view.lines;
  return queryLines
      .asMap()
      .entries
      .where((entry) {
        final line = entry.value;
        if (line.text.isEmpty) return false;
        return _referenceEffectiveLineEnd(queryLines, entry.key) > start &&
            line.startCharOffset < end;
      })
      .map((entry) => entry.value)
      .toList(growable: false);
}

int _referenceEffectiveLineEnd(List<ReaderV2RenderLine> lines, int index) {
  final line = lines[index];
  for (var nextIndex = index + 1; nextIndex < lines.length; nextIndex++) {
    final next = lines[nextIndex];
    if (next.text.isEmpty) continue;
    if (next.startCharOffset > line.endCharOffset) {
      return next.startCharOffset;
    }
    break;
  }
  return line.endCharOffset;
}

ReaderV2LayoutSpec _spec({double fontSize = 18}) {
  return ReaderV2LayoutSpec.fromViewport(
    viewportSize: const Size(240, 220),
    style: ReaderV2LayoutStyle(
      fontSize: fontSize,
      lineHeight: 1.5,
      letterSpacing: 0,
      paragraphSpacing: 0.8,
      paddingTop: 12,
      paddingBottom: 12,
      paddingLeft: 12,
      paddingRight: 12,
      textIndent: 2,
    ),
  );
}

class _ControlledContentRepository extends ReaderV2ChapterRepository {
  _ControlledContentRepository({required int chapterCount})
    : _storedChapters = _chapters(
        'test://book',
        count: chapterCount,
        paragraphsPerChapter: 2,
      ),
      super(
        book: _book(),
        initialChapters: _chapters(
          'test://book',
          count: chapterCount,
          paragraphsPerChapter: 2,
        ),
        bookDao: _FakeBookDao(),
        chapterDao: _FakeChapterDao(
          _chapters(
            'test://book',
            count: chapterCount,
            paragraphsPerChapter: 2,
          ),
        ),
        sourceDao: _FakeSourceDao(),
        contentDao: null,
      );

  final List<BookChapter> _storedChapters;
  final List<int> startedLoads = <int>[];
  final Map<int, Completer<void>> _pendingLoads = <int, Completer<void>>{};
  final Map<int, ReaderV2Content> _cached = <int, ReaderV2Content>{};
  final List<Completer<void>> _startWaiters = <Completer<void>>[];

  @override
  int get chapterCount => _storedChapters.length;

  @override
  List<BookChapter> get chapters =>
      List<BookChapter>.unmodifiable(_storedChapters);

  @override
  Future<List<BookChapter>> ensureChapters() async => chapters;

  @override
  BookChapter? chapterAt(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _storedChapters.length) {
      return null;
    }
    return _storedChapters[chapterIndex];
  }

  @override
  String titleFor(int chapterIndex) => chapterAt(chapterIndex)?.title ?? '';

  @override
  ReaderV2Content? cachedContent(int chapterIndex) => _cached[chapterIndex];

  @override
  Future<ReaderV2Content> loadContent(int chapterIndex) async {
    final cached = _cached[chapterIndex];
    if (cached != null) return cached;
    startedLoads.add(chapterIndex);
    _notifyStartWaiters();
    final blocker = _pendingLoads.putIfAbsent(
      chapterIndex,
      () => Completer<void>(),
    );
    await blocker.future;
    final chapter = chapterAt(chapterIndex)!;
    final content = ReaderV2Content.fromRaw(
      chapterIndex: chapterIndex,
      title: chapter.title,
      rawText: chapter.content ?? '',
    );
    _cached[chapterIndex] = content;
    return content;
  }

  Future<int> waitForStartCount(int count) async {
    while (startedLoads.length < count) {
      final waiter = Completer<void>();
      _startWaiters.add(waiter);
      await waiter.future;
    }
    return startedLoads[count - 1];
  }

  void completeLoad(int chapterIndex) {
    final blocker = _pendingLoads.putIfAbsent(
      chapterIndex,
      () => Completer<void>(),
    );
    if (!blocker.isCompleted) blocker.complete();
  }

  void completeAllLoads() {
    for (final blocker in _pendingLoads.values) {
      if (!blocker.isCompleted) blocker.complete();
    }
    _notifyStartWaiters();
  }

  void _notifyStartWaiters() {
    final waiters = _startWaiters.toList(growable: false);
    _startWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}

class _CountingLayoutEngine extends ReaderV2LayoutEngine {
  int layoutCount = 0;

  @override
  ReaderV2ChapterLayout layout(
    ReaderV2Content content,
    ReaderV2LayoutSpec spec,
  ) {
    layoutCount += 1;
    return super.layout(content, spec);
  }
}

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {}
}

class _FakeChapterDao extends Fake implements ChapterDao {
  _FakeChapterDao(this.storedChapters);

  final List<BookChapter> storedChapters;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => storedChapters;
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async => null;
}
