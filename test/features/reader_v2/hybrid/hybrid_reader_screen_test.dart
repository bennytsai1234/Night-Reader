import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/tts_highlight_overlay.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/cached_block_widget.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

import '../../../reader_correctness/reader_correctness_operations.dart';

class _FakeBookDao extends Fake implements BookDao {
  int progressWrites = 0;

  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    progressWrites += 1;
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

final class _DeferredChapterLoader {
  bool holdChapter3 = false;
  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};

  Future<String?> load(int chapterIndex, BookChapter chapter) {
    if (!holdChapter3 || chapterIndex != 3) {
      return Future<String?>.value(chapter.content);
    }
    final completer = _pending.putIfAbsent(
      chapterIndex,
      Completer<String?>.new,
    );
    return completer.future;
  }

  bool get chapter3Pending => _pending[3] != null;

  void releaseChapter3(BookChapter chapter) {
    final completer = _pending.remove(3);
    if (completer == null || completer.isCompleted) return;
    completer.complete(chapter.content);
  }
}

final class _OrdinaryPrefetchDrainObservation {
  const _OrdinaryPrefetchDrainObservation({
    required this.snapshot,
    required this.maxEnqueuedCount,
    required this.maxQueueDepth,
    required this.postDrainRefills,
  });

  final Map<String, Object?> snapshot;
  final int maxEnqueuedCount;
  final int maxQueueDepth;
  final int postDrainRefills;
}

void main() {
  setUp(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
  });
  tearDown(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
  });

  HybridFrameInvariantRecord invariantRecord({
    required List<BlockKey> visibleKeys,
    int timestampMicros = 1,
    double scrollOffset = 0,
    bool isScrolling = false,
    String? scrollActivity,
    double? scrollVelocity,
    int? operationTokenId = 1,
    bool operationIsCurrent = true,
    int chapterCount = 2,
    bool errorPresent = false,
    double scrollPixels = 0,
    double minScrollExtent = 0,
    double maxScrollExtent = 1000,
    int pumpQueueDepth = 0,
    int epoch = 1,
    int layoutGeneration = 1,
    int resetGeneration = 3,
  }) {
    return HybridFrameInvariantRecord(
      timestampMicros: timestampMicros,
      phase: 'ready',
      scrollOffset: scrollOffset,
      viewportHeight: 180,
      dragging: false,
      isScrolling: isScrolling,
      restoreLocked: false,
      initialRestoreCompleted: true,
      pendingChapterJumpTarget: null,
      epoch: epoch,
      layoutGeneration: layoutGeneration,
      documentIndexRevision: 1,
      resetGeneration: resetGeneration,
      indexBindingResetGeneration: resetGeneration,
      indexCenter: const BlockKey(chapterIndex: 0, blockIndex: 0),
      visibleKeys: visibleKeys,
      visibleChapters: const <int>[0],
      missingParagraphCount: 0,
      unloadedChapterCount: 0,
      dominantVisibleChapter: 0,
      displayedProgressChapter: 0,
      pumpQueueDepth: pumpQueueDepth,
      scrollPixels: scrollPixels,
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
      scrollActivity: scrollActivity ?? (isScrolling ? 'ballistic' : 'idle'),
      scrollVelocity: scrollVelocity ?? (isScrolling ? 100.0 : 0.0),
      operationTokenId: operationTokenId,
      operationIsCurrent: operationIsCurrent,
      chapterCount: chapterCount,
      errorPresent: errorPresent,
    );
  }

  test('逐幀 evaluator 會捕捉明確的 I1 visible key 缺口', () {
    final violations = evaluateHybridFrameInvariants(
      current: invariantRecord(
        visibleKeys: const <BlockKey>[
          BlockKey(chapterIndex: 0, blockIndex: 0),
          BlockKey(chapterIndex: 0, blockIndex: 2),
        ],
      ),
    );
    expect(violations.map((violation) => violation.invariant), contains('I1'));
  });

  test('I8 不把跨 epoch 的 reload restore 誤判成同一 ballistic stream', () {
    final previousPrevious = invariantRecord(
      visibleKeys: const <BlockKey>[BlockKey(chapterIndex: 0, blockIndex: 0)],
      timestampMicros: 1,
      isScrolling: true,
      scrollOffset: 0,
    );
    final previous = invariantRecord(
      visibleKeys: const <BlockKey>[BlockKey(chapterIndex: 0, blockIndex: 0)],
      timestampMicros: 2,
      isScrolling: true,
      scrollOffset: 0,
    );
    final current = invariantRecord(
      visibleKeys: const <BlockKey>[BlockKey(chapterIndex: 0, blockIndex: 0)],
      timestampMicros: 3,
      isScrolling: true,
      scrollOffset: -10,
      epoch: 2,
      layoutGeneration: 2,
      resetGeneration: 4,
    );
    final violations = evaluateHybridFrameInvariants(
      current: current,
      previous: previous,
      previousPrevious: previousPrevious,
    );
    expect(
      violations.map((violation) => violation.invariant),
      isNot(contains('I8')),
    );
  });

  group('hybrid page completion', () {
    test('lazy edge partial movement is not a completed page', () {
      expect(
        isHybridPageMoveComplete(
          requestedDistance: 145,
          actualDistance: 100,
          atBookBoundary: false,
        ),
        isFalse,
      );
    });

    test('full requested movement is a completed page', () {
      expect(
        isHybridPageMoveComplete(
          requestedDistance: 145,
          actualDistance: 145,
          atBookBoundary: false,
        ),
        isTrue,
      );
    });

    test('short final page is valid at a confirmed book boundary', () {
      expect(
        isHybridPageMoveComplete(
          requestedDistance: 145,
          actualDistance: 100,
          atBookBoundary: true,
        ),
        isTrue,
      );
    });

    test('no movement is never a completed page', () {
      expect(
        isHybridPageMoveComplete(
          requestedDistance: 145,
          actualDistance: 0,
          atBookBoundary: true,
        ),
        isFalse,
      );
    });
  });

  const style = ReaderV2Style(
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 0.8,
    paddingTop: 12,
    paddingBottom: 0,
    paddingLeft: 12,
    paddingRight: 12,
    textIndent: 2,
  );

  ReaderV2LayoutSpec spec({Size viewportSize = const Size(220, 180)}) {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: viewportSize,
      style: const ReaderV2LayoutStyle(
        fontSize: 18,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 0.8,
        paddingTop: 12,
        paddingBottom: 0,
        paddingLeft: 12,
        paddingRight: 12,
        textIndent: 2,
      ),
    );
  }

  BookChapter chapter(int index, {int paragraphCount = 8}) {
    final body = List<String>.generate(
      paragraphCount,
      (p) => '第 $index 章第 $p 段：這是一段供混合引擎整合測試使用的中文內容，帶有標點並且長度足以跨越多行呈現。',
    ).join('\n\n');
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: body,
    );
  }

  ReaderV2Runtime makeRuntime(
    List<BookChapter> chapters, {
    _FakeBookDao? bookDao,
    ReaderV2TestContentLoader? contentLoader,
    Size viewportSize = const Size(220, 180),
    ReaderV2Location initialLocation = const ReaderV2Location(
      chapterIndex: 0,
      charOffset: 0,
    ),
  }) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final dao = bookDao ?? _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: dao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
      contentLoader: contentLoader,
    );
    return ReaderV2Runtime(
      book: book,
      repository: repository,
      layoutEngine: ReaderV2LayoutEngine(),
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: dao,
      ),
      initialLayoutSpec: spec(viewportSize: viewportSize),
      initialLocation: initialLocation,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    ReaderV2Runtime runtime,
    ReaderV2ViewportController controller, {
    ValueNotifier<HybridProgressSnapshot?>? progress,
    ReaderV2TtsHighlight? ttsHighlight,
    GestureTapUpCallback? onContentTapUp,
    int paragraphCacheCapacity = 512,
    Size viewportSize = const Size(220, 180),
    Color backgroundColor = const Color(0xFFFFFFFF),
    Color textColor = const Color(0xFF000000),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: viewportSize.width,
            height: viewportSize.height,
            child: HybridReaderScreen(
              runtime: runtime,
              backgroundColor: backgroundColor,
              textColor: textColor,
              style: style,
              viewportController: controller,
              ttsHighlight: ttsHighlight,
              onContentTapUp: onContentTapUp,
              progressListenable: progress,
              preprocessor: const TextPreprocessor(useIsolate: false),
              enableDiskMetrics: false,
              paragraphCacheCapacity: paragraphCacheCapacity,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openAndSettle(
    WidgetTester tester,
    ReaderV2Runtime runtime,
  ) async {
    unawaited(runtime.openBook());
    await tester.pumpAndSettle();
  }

  Future<_OrdinaryPrefetchDrainObservation>
  pumpUntilOrdinaryPrefetchStable(
    WidgetTester tester,
    dynamic state, {
    String reason = 'ordinary prefetch',
    int maxBatchBlocks = 32,
    Map<String, Object?>? initialSample,
  }) async {
    var consecutiveSettledFrames = 0;
    var sawWork = initialSample != null &&
        ((initialSample['pumpQueueDepth'] as int) > 0 ||
            (initialSample['enqueuedCount'] as int) > 0);
    var zeroAfterWork = initialSample != null && sawWork;
    var postDrainRefills = 0;
    var maxEnqueuedCount = initialSample?['enqueuedCount'] as int? ?? 0;
    var maxQueueDepth = initialSample?['pumpQueueDepth'] as int? ?? 0;
    Map<String, Object?>? lastSample = initialSample;

    for (var frame = 0; frame < 240; frame += 1) {
      await tester.pump(const Duration(milliseconds: 8));
      final sample = Map<String, Object?>.from(
        (state as dynamic).debugSnapshot() as Map,
      );
      lastSample = sample;
      final queueDepth = sample['pumpQueueDepth'] as int;
      final enqueuedCount = sample['enqueuedCount'] as int;
      maxEnqueuedCount = math.max(maxEnqueuedCount, enqueuedCount);
      maxQueueDepth = math.max(maxQueueDepth, queueDepth);

      if (queueDepth > 0) {
        if (zeroAfterWork) postDrainRefills += 1;
        sawWork = true;
        zeroAfterWork = false;
      } else if (sawWork) {
        zeroAfterWork = true;
      }
      if (enqueuedCount > 0) sawWork = true;

      final visibleKeys = sample['visibleKeys'] as List;
      final missingParagraphKeys = sample['missingParagraphKeys'] as List;
      final readyFrame =
          sample['phase'] == 'ready' &&
          sample['initialRestoreCompleted'] == true &&
          sample['dragging'] == false &&
          sample['isScrolling'] == false &&
          sample['restorePrefetchBarrierActive'] == false &&
          sample['pendingChapterJumpTarget'] == null;
      if (readyFrame && visibleKeys.isNotEmpty) {
        expect(sample['visibleKeysContiguous'], true, reason: reason);
        expect(missingParagraphKeys, isEmpty, reason: reason);
      }

      final semanticallySettled =
          readyFrame &&
          queueDepth == 0 &&
          enqueuedCount == 0 &&
          visibleKeys.isNotEmpty &&
          sample['visibleKeysContiguous'] == true &&
          missingParagraphKeys.isEmpty;
      if (semanticallySettled) {
        consecutiveSettledFrames += 1;
      } else {
        consecutiveSettledFrames = 0;
      }

      if (consecutiveSettledFrames >= 4) {
        expect(sawWork, true, reason: '$reason must admit a bounded batch');
        expect(
          maxEnqueuedCount,
          lessThanOrEqualTo(maxBatchBlocks),
          reason: '$reason must keep enqueued work bounded',
        );
        expect(
          maxQueueDepth,
          lessThanOrEqualTo(maxBatchBlocks),
          reason: '$reason must keep pump queue bounded',
        );
        expect(
          postDrainRefills,
          0,
          reason:
              '$reason must stay settled after its first queue drain; '
              'a zero-to-positive transition means _pumpOnce re-admitted '
              'the remaining lead deficit',
        );
        return _OrdinaryPrefetchDrainObservation(
          snapshot: sample,
          maxEnqueuedCount: maxEnqueuedCount,
          maxQueueDepth: maxQueueDepth,
          postDrainRefills: postDrainRefills,
        );
      }
    }

    fail(
      '$reason did not reach four consecutive semantic settled frames; '
      'lastSnapshot=$lastSample',
    );
  }

  testWidgets('hook 開啟時可執行逐幀路徑，關閉時沒有記錄', (tester) async {
    final runtime = makeRuntime(List.generate(2, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    final state = tester.state(find.byType(HybridReaderScreen));
    expect((state as dynamic).debugFrameInvariantViolations(), isEmpty);
    final disabledSummary =
        (state as dynamic).debugPerformanceSummary() as Map<String, Object?>;
    expect(disabledSummary['invariantHookEnabled'], false);

    await openAndSettle(tester, runtime);
    expect((state as dynamic).debugFrameInvariantViolations(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    HybridReaderScreen.debugFrameInvariantsEnabled = true;
    final enabledRuntime = makeRuntime(List.generate(2, chapter));
    final enabledController = ReaderV2ViewportController();
    addTearDown(enabledRuntime.dispose);
    await pumpScreen(tester, enabledRuntime, enabledController);
    final enabledState = tester.state(find.byType(HybridReaderScreen));
    final enabledSummary =
        (enabledState as dynamic).debugPerformanceSummary()
            as Map<String, Object?>;
    expect(enabledSummary['invariantHookEnabled'], true);
    await openAndSettle(tester, enabledRuntime);
    expect((enabledState as dynamic).debugFrameInvariantViolations(), isEmpty);
  });

  testWidgets('textColor 變更先隔離舊 ParagraphCache 再 restore', (tester) async {
    final runtime = makeRuntime(List.generate(2, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    final state = tester.state(find.byType(HybridReaderScreen));
    final before = (state as dynamic).debugSnapshot() as Map<String, Object?>;
    expect(before['initialRestoreCompleted'], true);
    expect(before['missingParagraphKeys'], isEmpty);

    HybridReaderScreen.debugFrameInvariantsEnabled = true;
    await pumpScreen(
      tester,
      runtime,
      controller,
      textColor: const Color(0xFF244739),
    );
    final duringState = tester.state(find.byType(HybridReaderScreen));
    // This is the regression assertion: before the fix didUpdateWidget kept
    // the old ready flag while the new text color made visible cache entries
    // stale, so the P3 hook recorded I2 during the transition.
    expect((duringState as dynamic).debugFrameInvariantViolations(), isEmpty);

    await tester.pumpAndSettle();
    final after =
        (tester.state(find.byType(HybridReaderScreen)) as dynamic)
                .debugSnapshot()
            as Map<String, Object?>;
    expect(after['phase'], 'ready');
    expect(after['initialRestoreCompleted'], true);
    expect(after['missingParagraphKeys'], isEmpty);
  });

  testWidgets('開書後掛載 hybrid 滾動骨架並落實 D5 七閉包 attach', (tester) async {
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    expect(controller.scrollBy, isNotNull);
    expect(controller.continuousScrollBy, isNotNull);
    expect(controller.animateBy, isNotNull);
    expect(controller.moveToNextPage, isNotNull);
    expect(controller.moveToPrevPage, isNotNull);
    expect(controller.settleScroll, isNotNull);
    expect(controller.ensureCharRangeVisible, isNotNull);

    await openAndSettle(tester, runtime);
    expect(runtime.state.phase, ReaderV2Phase.ready);
    expect(find.byType(HybridScrollView), findsOneWidget);

    // capture 契約：可從畫面反推出合法的 ReaderV2Location。
    final captured = runtime.captureVisibleLocation(notifyIfChanged: false);
    expect(captured, isNotNull);
    expect(captured!.chapterIndex, 0);
    expect(
      captured.visualOffsetPx,
      inInclusiveRange(
        ReaderV2Location.minVisualOffsetPx,
        ReaderV2Location.maxVisualOffsetPx,
      ),
    );
  });

  testWidgets('開書建置量超過 ParagraphCache 容量時，首屏 block 不空白', (tester) async {
    // 回歸守門員：容量遠小於初始視窗所需 block 數時，修復前 restore 期間
    // 無 pin 保護，LRU 會把錨點周圍（首屏可見）的段落逐出——開書只剩
    // 錨點一行、其餘佔位空白，滑動後才恢復。
    final runtime = makeRuntime(
      List.generate(3, (i) => chapter(i, paragraphCount: 12)),
    );
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller, paragraphCacheCapacity: 4);
    await openAndSettle(tester, runtime);
    expect(runtime.state.phase, ReaderV2Phase.ready);

    final elements = find.byType(CachedBlockWidget).evaluate().toList();
    expect(elements, isNotEmpty);
    for (final element in elements) {
      final widget = element.widget as CachedBlockWidget;
      expect(
        element.renderObject,
        paints..paragraph(),
        reason: '${widget.blockKey} 已 materialize，必須畫得出段落而非佔位空白',
      );
    }
  });

  testWidgets('多章開書只需完成可呈現首屏，不等待完整 lead window', (tester) async {
    // The restore path intentionally loads only the bounded nearby chapter
    // window.  A large book must still open once the target viewport is
    // presentable; waiting for the normal 3000/6000px lead would report a
    // false restore failure before ordinary scrolling can extend it.
    final runtime = makeRuntime(
      List.generate(
        121,
        (index) => chapter(index, paragraphCount: index == 0 ? 1 : 5),
      ),
    );
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    final snapshot =
        (tester.state(find.byType(HybridReaderScreen)) as dynamic)
                .debugSnapshot()
            as Map<String, Object?>;
    expect(snapshot['phase'], 'ready');
    expect(snapshot['initialRestoreCompleted'], true);
    expect(snapshot['pumpQueueDepth'], 0);
    expect(snapshot['visibleKeys'], isNotEmpty);
    expect(snapshot['missingParagraphKeys'], isEmpty);
  });

  testWidgets('scrollBy 前進、settle 落盤並更新 D6 進度', (tester) async {
    final dao = _FakeBookDao();
    final runtime = makeRuntime(List.generate(3, chapter), bookDao: dao);
    final controller = ReaderV2ViewportController();
    final progress = ValueNotifier<HybridProgressSnapshot?>(null);
    addTearDown(runtime.dispose);
    addTearDown(progress.dispose);

    await pumpScreen(tester, runtime, controller, progress: progress);
    await openAndSettle(tester, runtime);

    final before = runtime.state.visibleLocation;
    final moved = controller.scrollBy!(600);
    await tester.pumpAndSettle();
    expect(await moved, isTrue);

    final after = runtime.state.visibleLocation;
    expect(after.charOffset, greaterThan(before.charOffset));
    expect(dao.progressWrites, greaterThan(0));

    final snapshot = progress.value;
    expect(snapshot, isNotNull);
    expect(snapshot!.chapterIndex, 0);
    expect(snapshot.chapterCount, 3);
    expect(snapshot.chapterPercent, greaterThan(0));
    expect(snapshot.chapterPercent, lessThanOrEqualTo(99.9));
    expect(snapshot.chapterLabel, startsWith('第 1/3 章 · 本章 '));
    expect(snapshot.chapterSegment, inInclusiveRange(0, 9));
  });

  testWidgets('首次 restore 後非 ready 狀態以不攔截 overlay 回饋', (tester) async {
    final runtime = makeRuntime(List.generate(2, chapter));
    final controller = ReaderV2ViewportController();
    var contentTaps = 0;
    final logMessages = <String?>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logMessages.add(message);
    addTearDown(() => debugPrint = previousDebugPrint);
    addTearDown(runtime.dispose);

    await pumpScreen(
      tester,
      runtime,
      controller,
      onContentTapUp: (_) => contentTaps += 1,
    );
    await openAndSettle(tester, runtime);
    final viewportSize = tester.getSize(find.byType(HybridScrollView));

    final token = runtime.beginJumpOperation();
    await tester.pump();
    await tester.pump();

    expect(find.text('正在整理版面'), findsOneWidget);
    expect(find.byType(HybridScrollView), findsOneWidget);
    expect(tester.getSize(find.byType(HybridScrollView)), viewportSize);
    final ignorePointer = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.text('正在整理版面'),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignorePointer.ignoring, isTrue);
    await tester.tapAt(tester.getCenter(find.byType(HybridScrollView)));
    await tester.pump();
    expect(contentTaps, 1);

    runtime.failOperation(token, StateError('internal restore details'));
    await tester.pump();
    await tester.pump();

    expect(find.text('閱讀內容暫時無法顯示，請稍後再試'), findsOneWidget);
    expect(find.textContaining('internal restore details'), findsNothing);
    expect(find.byType(HybridScrollView), findsOneWidget);
    int matchingErrorLogs() => logMessages
        .whereType<String>()
        .where((message) => message.contains('internal restore details'))
        .length;
    expect(matchingErrorLogs(), 1);

    runtime.failOperation(token, StateError('internal restore details'));
    await tester.pump();
    await tester.pump();
    expect(matchingErrorLogs(), 1);

    final nextToken = runtime.beginJumpOperation();
    await tester.pump();
    await tester.pump();
    runtime.failOperation(nextToken, StateError('internal restore details'));
    await tester.pump();
    await tester.pump();
    expect(matchingErrorLogs(), 2, reason: '新的 operation 進入 error 時仍須留下技術診斷');
    debugPrint = previousDebugPrint;
  });

  testWidgets('hybrid 只在已確認書首書尾時發出邊界通知', (tester) async {
    final runtime = makeRuntime(<BookChapter>[
      BookChapter(
        url: 'chapter_0',
        title: '短章',
        bookUrl: 'http://book.test',
        index: 0,
        content: '短文。',
      ),
    ]);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    expect(await controller.moveToPrevPage!(), isFalse);
    expect(runtime.takeUserNotice(), '已到書首');
    expect(runtime.takeUserNotice(), isNull);

    expect(await controller.moveToNextPage!(), isFalse);
    expect(runtime.takeUserNotice(), '已到書尾');
    expect(runtime.takeUserNotice(), isNull);
  });

  testWidgets('關閉重開後 capture/restore 幾何誤差不超過 0.01 logical px', (tester) async {
    final chapters = List.generate(3, chapter);
    final firstRuntime = makeRuntime(chapters);
    final firstController = ReaderV2ViewportController();
    addTearDown(firstRuntime.dispose);

    await pumpScreen(tester, firstRuntime, firstController);
    await openAndSettle(tester, firstRuntime);
    expect(await firstController.scrollBy!(650), isTrue);
    await tester.pumpAndSettle();

    final beforeClose = firstRuntime.captureVisibleLocation(
      notifyIfChanged: false,
    );
    expect(beforeClose, isNotNull);
    expect(beforeClose!.charOffset, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    final reopenedRuntime = makeRuntime(chapters, initialLocation: beforeClose);
    final reopenedController = ReaderV2ViewportController();
    addTearDown(reopenedRuntime.dispose);

    await pumpScreen(tester, reopenedRuntime, reopenedController);
    await openAndSettle(tester, reopenedRuntime);

    final afterReopen = reopenedRuntime.captureVisibleLocation(
      notifyIfChanged: false,
    );
    expect(afterReopen, isNotNull);
    expect(afterReopen!.chapterIndex, beforeClose.chapterIndex);
    expect(afterReopen.charOffset, beforeClose.charOffset);
    expect(
      (afterReopen.visualOffsetPx - beforeClose.visualOffsetPx).abs(),
      lessThanOrEqualTo(0.01),
    );
  });

  testWidgets('runtime.jumpToChapter 後 viewport 跟隨到新章', (tester) async {
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();

    expect(runtime.state.visibleLocation.chapterIndex, 1);
    final captured = runtime.captureVisibleLocation(notifyIfChanged: false);
    expect(captured, isNotNull);
    expect(captured!.chapterIndex, 1);
  });

  testWidgets('pending jump-owned settle 不會解除 restore prefetch barrier', (
    tester,
  ) async {
    final runtime = makeRuntime([
      chapter(0, paragraphCount: 4),
      chapter(1, paragraphCount: 240),
      chapter(2, paragraphCount: 4),
    ]);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    await runtime.jumpToChapter(1);
    await tester.pump();

    final state = tester.state(find.byType(HybridReaderScreen));
    final before = (state as dynamic).debugSnapshot() as Map<String, Object?>;
    expect(before['restorePrefetchBarrierActive'], true);

    // Reproduce the delayed ScrollEnd ownership window without relying on a
    // wall-clock race: the runtime exposes the same pending target while its
    // explicit jump is still the viewport owner. settleScroll must keep this
    // restore-owned boundary bounded instead of reopening every long-chapter
    // group.
    runtime.pendingChapterJumpTarget = const ReaderV2Location(
      chapterIndex: 1,
      charOffset: 0,
    );
    await controller.settleScroll!();
    final pending = (state as dynamic).debugSnapshot() as Map<String, Object?>;
    expect(pending['pendingChapterJumpTarget'], isNotNull);
    expect(pending['restorePrefetchBarrierActive'], true);
    expect(pending['restoreUserScrollObserved'], false);

    runtime.pendingChapterJumpTarget = null;
    await tester.pump();
    final after = (state as dynamic).debugSnapshot() as Map<String, Object?>;
    expect(after['restorePrefetchBarrierActive'], true);
  });

  testWidgets('long chapter restore drains only the bounded viewport batches', (
    tester,
  ) async {
    final runtime = makeRuntime([
      chapter(0, paragraphCount: 4),
      chapter(1, paragraphCount: 240),
      chapter(2, paragraphCount: 4),
    ]);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    // A long chapter is deliberately used here so the old restore path would
    // leave a large non-visible prefetch tail in LayoutPump after the anchor
    // became ready. The regression contract is queue drain at restore return,
    // not a relaxed settle timeout.
    await runtime.jumpToChapter(1);
    // Give repository loaded events and their post-frame callbacks one chance
    // to run. A late event must stay on the bounded restore path instead of
    // re-enqueuing the whole long chapter after restore returns.
    await tester.pump();
    final state = tester.state(find.byType(HybridReaderScreen));
    final firstJump =
        (state as dynamic).debugSnapshot() as Map<String, Object?>;
    expect(firstJump['phase'], 'ready');
    expect(firstJump['initialRestoreCompleted'], true);
    expect(firstJump['pumpQueueDepth'], 0);
    expect(firstJump['missingParagraphKeys'], isEmpty);

    // Repeating the same chapter-start navigation is the C6 failure shape.
    // It must remain bounded even when the long chapter has already been
    // warmed by the first jump.
    await runtime.jumpToChapter(1);
    await tester.pump();
    final repeatedJump =
        (tester.state(find.byType(HybridReaderScreen)) as dynamic)
                .debugSnapshot()
            as Map<String, Object?>;
    expect(repeatedJump['phase'], 'ready');
    expect(repeatedJump['initialRestoreCompleted'], true);
    expect(repeatedJump['pumpQueueDepth'], 0);
    expect(repeatedJump['missingParagraphKeys'], isEmpty);
  });

  testWidgets('user settle uses progressive prefetch for a long chapter', (
    tester,
  ) async {
    const longChapterParagraphs = 240;
    final runtime = makeRuntime([
      chapter(0, paragraphCount: 4),
      chapter(1, paragraphCount: longChapterParagraphs),
      chapter(2, paragraphCount: 4),
    ]);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(HybridReaderScreen));
    final beforeUserSettle =
        (state as dynamic).debugSnapshot() as Map<String, Object?>;
    final reader = find.byType(HybridScrollView);
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, -40),
      duration: const Duration(milliseconds: 64),
    );
    expect(
      (state as dynamic).debugSnapshot()['dragging'],
      true,
      reason: 'the regression must observe an actual user drag before settle',
    );
    await gesture.up();
    // Let ScrollEnd schedule the ordinary settled prefetch, but inspect before
    // the bounded batch has drained.  The save performed by settle yields, so
    // allow a bounded number of real frames for that hand-off instead of
    // making the assertion depend on one particular async turn.
    const maxOrdinaryPrefetchBlocks = 32;
    final ordinarySamples = <Map<String, Object?>>[];
    for (var i = 0; i < 16; i += 1) {
      final sample = Map<String, Object?>.from(
        (state as dynamic).debugSnapshot() as Map,
      );
      ordinarySamples.add(sample);
      if ((sample['enqueuedCount'] as int) > 0 ||
          (sample['pumpQueueDepth'] as int) > 0) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 8));
    }
    final afterUserSettle = ordinarySamples.last;
    expect(afterUserSettle['phase'], 'ready');
    expect(afterUserSettle['restorePrefetchBarrierActive'], false);
    expect(
      afterUserSettle['enqueuedCount'] as int,
      greaterThan(0),
      reason: 'ordinary user settle must enqueue a non-empty progressive batch',
    );
    expect(
      afterUserSettle['enqueuedCount'] as int,
      lessThanOrEqualTo(maxOrdinaryPrefetchBlocks),
      reason: 'user settle 不得一次排入整個長章節的 layout groups',
    );
    expect(
      afterUserSettle['pumpQueueDepth'] as int,
      lessThanOrEqualTo(maxOrdinaryPrefetchBlocks),
      reason: 'ordinary prefetch queue 必須維持 bounded frontier',
    );

    final drainObservation = await pumpUntilOrdinaryPrefetchStable(
      tester,
      state,
      reason: 'long-chapter ordinary settle',
      maxBatchBlocks: maxOrdinaryPrefetchBlocks,
      initialSample: afterUserSettle,
    );
    final drained = drainObservation.snapshot;
    expect(drained['phase'], 'ready');
    expect(drained['initialRestoreCompleted'], true);
    expect(drained['pumpQueueDepth'], 0);
    expect(
      drained['forwardEdge'],
      isNot(equals(beforeUserSettle['forwardEdge'])),
      reason: 'the ordinary frontier must advance before the queue drains',
    );
    expect(drained['visibleKeys'], isNotEmpty);
    expect(drained['visibleKeysContiguous'], true);
    expect(drained['missingParagraphKeys'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('遠距離跳章會撤銷舊中心的排版工作，而不是照樣把它排完', (tester) async {
    // 失效鍵是 (epoch, fingerprint, windowCenter)。跳章不改變 epoch，所以在
    // 加入 center 之前，投放時屬於舊中心的 LayoutTask 仍會被完整排版，其
    // metrics 再也接不上重定中心後的 DocumentIndex（I3 連續性），等於整段
    // 排版時間白費並讓 restore 的 settle 契約等在後面。
    final runtime = makeRuntime(<BookChapter>[
      chapter(0, paragraphCount: 240),
      for (var i = 1; i <= 11; i += 1) chapter(i, paragraphCount: 8),
    ]);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    final state = tester.state(find.byType(HybridReaderScreen));

    // 先用一次真實的 user settle，在舊中心（第 0 章）留下尚未 drain 的
    // progressive batch；這是跳章當下佇列裡真的有舊工作的唯一自然來源。
    final reader = find.byType(HybridScrollView);
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, -40),
      duration: const Duration(milliseconds: 64),
    );
    await gesture.up();

    Map<String, Object?> snapshot() => Map<String, Object?>.from(
      (state as dynamic).debugSnapshot() as Map,
    );

    var beforeJump = snapshot();
    for (var i = 0; i < 16; i += 1) {
      beforeJump = snapshot();
      if ((beforeJump['pumpQueueDepth'] as int) > 0) break;
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(
      beforeJump['pumpQueueDepth'] as int,
      greaterThan(0),
      reason: '這個回歸需要跳章當下佇列裡真的有屬於舊中心的工作',
    );
    expect(beforeJump['discardedLayoutTasks'], 0);

    // 跳到遠離舊中心超過需求半徑的章節。
    await runtime.jumpToChapter(9);
    await tester.pump();
    final afterJump = snapshot();

    expect(afterJump['phase'], 'ready');
    expect(afterJump['initialRestoreCompleted'], true);
    expect(
      afterJump['discardedLayoutTasks'] as int,
      greaterThan(0),
      reason: '舊中心的工作必須被撤銷，而不是照樣排完',
    );
    // restore 返回後可以有屬於「新中心」的少量後續需求；要保證的是佇列
    // 只反映當前需求視窗，不是舊中心留下的長尾（C6 觀察到的是 931）。
    expect(
      afterJump['pumpQueueDepth'] as int,
      lessThanOrEqualTo(32),
      reason: 'restore 返回時佇列必須是當前需求的有界 frontier',
    );
    expect(afterJump['visibleKeys'], isNotEmpty);
    expect(afterJump['visibleKeysContiguous'], true);
    expect(afterJump['missingParagraphKeys'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary prefetch drops a chapter load that completes during a drag',
    (tester) async {
      const maxOrdinaryPrefetchBlocks = 32;
      final chapters = [
        chapter(0, paragraphCount: 1),
        chapter(1, paragraphCount: 1),
        chapter(2, paragraphCount: 1),
        chapter(3, paragraphCount: 96),
      ];
      final loader = _DeferredChapterLoader()..holdChapter3 = true;
      final runtime = makeRuntime(chapters, contentLoader: loader.load);
      final controller = ReaderV2ViewportController();
      addTearDown(runtime.dispose);

      await pumpScreen(tester, runtime, controller);
      await openAndSettle(tester, runtime);

      // Open restore owns the prefetch barrier. Release it with a genuine
      // user-owned settle before creating the ordinary async request.
      final reader = find.byType(HybridScrollView);
      final releaseBarrier = await tester.startGesture(
        tester.getCenter(reader),
      );
      await moveVsyncPaced(
        tester,
        releaseBarrier,
        const Offset(0, -16),
        duration: const Duration(milliseconds: 64),
      );
      await releaseBarrier.up();
      await tester.pumpAndSettle();
      final afterBarrierRelease =
          (tester.state(find.byType(HybridReaderScreen)) as dynamic)
                  .debugSnapshot()
              as Map<String, Object?>;
      expect(afterBarrierRelease['restorePrefetchBarrierActive'], false);

      // The short first chapters make this controlled drag cross into chapter
      // 1. setPrefetchCenter starts chapter 3's ordinary load while the
      // pointer is still down; holding that future gives the test a stable
      // race window instead of relying on scheduler luck.
      final crossChapterDrag = await tester.startGesture(
        tester.getCenter(reader),
      );
      await moveVsyncPaced(
        tester,
        crossChapterDrag,
        const Offset(0, -900),
        duration: const Duration(milliseconds: 480),
      );
      final state = tester.state(find.byType(HybridReaderScreen));
      expect((state as dynamic).debugSnapshot()['dragging'], true);

      var chapter3Pending = loader.chapter3Pending;
      for (var i = 0; i < 20 && !chapter3Pending; i += 1) {
        await tester.pump();
        chapter3Pending = loader.chapter3Pending;
      }
      expect(
        chapter3Pending,
        true,
        reason:
            'the cross-chapter drag must create an ordinary async load; '
            'snapshot=${(state as dynamic).debugSnapshot()}',
      );

      final beforeResolve =
          (state as dynamic).debugSnapshot() as Map<String, Object?>;
      final enqueuedBeforeResolve = beforeResolve['enqueuedCount'] as int;
      final queueBeforeResolve = beforeResolve['pumpQueueDepth'] as int;

      // Resolve the ordinary load while the user still owns the gesture. A
      // stale completion may populate its cache, but it must not enqueue
      // layout work until the user-owned settle has completed.
      loader.releaseChapter3(chapters[3]);
      await tester.pump();
      await tester.pump();
      final whileDragging =
          (state as dynamic).debugSnapshot() as Map<String, Object?>;
      expect(whileDragging['dragging'], true);
      expect(whileDragging['enqueuedCount'], enqueuedBeforeResolve);
      expect(whileDragging['pumpQueueDepth'], queueBeforeResolve);

      await crossChapterDrag.up();
      final afterDragRelease = Map<String, Object?>.from(
        (state as dynamic).debugSnapshot() as Map,
      );
      final drainObservation = await pumpUntilOrdinaryPrefetchStable(
        tester,
        state,
        reason: 'stale chapter completion after drag',
        maxBatchBlocks: maxOrdinaryPrefetchBlocks,
        initialSample: afterDragRelease,
      );
      final drained = drainObservation.snapshot;
      expect(
        drainObservation.maxEnqueuedCount,
        greaterThan(0),
        reason: 'the post-drag ordinary settle must enqueue work',
      );
      expect(
        drainObservation.maxEnqueuedCount,
        lessThanOrEqualTo(maxOrdinaryPrefetchBlocks),
        reason: 'ordinary refill must stay within the progressive frontier',
      );
      expect(drained['phase'], 'ready');
      expect(drained['initialRestoreCompleted'], true);
      expect(drained['pumpQueueDepth'], 0);
      expect(drained['visibleKeys'], isNotEmpty);
      expect(drained['visibleKeysContiguous'], true);
      expect(drained['missingParagraphKeys'], isEmpty);
      expect(
        drained['documentIndexRevision'] as int,
        greaterThan(beforeResolve['documentIndexRevision'] as int),
        reason: 'the admitted frontier must advance before the queue drains',
      );
      expect(drained['forwardEdge'], isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ballistic 尾端的明確 jump 不會被 dragging 旗標拒絕', (tester) async {
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    final reader = find.byType(HybridReaderScreen).first;
    await tester.fling(reader, const Offset(0, -1600), 3800);
    await tester.pump(const Duration(milliseconds: 90));
    final jump = runtime.jumpToChapter(1);
    await tester.pump(const Duration(milliseconds: 55));
    await tester.pump(const Duration(milliseconds: 125));
    await jump;
    await tester.pumpAndSettle();

    expect(runtime.state.phase, ReaderV2Phase.ready);
    expect(runtime.state.visibleLocation.chapterIndex, 1);
  });

  testWidgets('runtime.jumpToChapter 後窄通道進度不會沿用上一章', (tester) async {
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    final progress = ValueNotifier<HybridProgressSnapshot?>(null);
    addTearDown(runtime.dispose);
    addTearDown(progress.dispose);

    await pumpScreen(tester, runtime, controller, progress: progress);
    await openAndSettle(tester, runtime);
    expect(progress.value, isNotNull);
    expect(progress.value!.chapterIndex, 0);

    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();

    expect(runtime.state.visibleLocation.chapterIndex, 1);
    expect(
      progress.value?.chapterIndex,
      1,
      reason: '章節內容已切換時，底部資訊列不能保留上一章的進度 label',
    );
  });

  testWidgets('短章節回跳完成後窄通道進度跟隨 runtime 目前章節', (tester) async {
    final shortChapter = BookChapter(
      url: 'chapter_0',
      title: '前言',
      bookUrl: 'http://book.test',
      index: 0,
      content: '短前言',
    );
    final progress = ValueNotifier<HybridProgressSnapshot?>(null);
    final runtime = makeRuntime([
      shortChapter,
      chapter(1, paragraphCount: 40),
    ], viewportSize: const Size(432, 824));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);
    addTearDown(progress.dispose);

    await pumpScreen(
      tester,
      runtime,
      controller,
      progress: progress,
      viewportSize: const Size(432, 824),
    );
    await openAndSettle(tester, runtime);
    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();
    expect(progress.value?.chapterIndex, 1);

    await runtime.jumpToChapter(0);
    await tester.pumpAndSettle();

    expect(runtime.state.visibleLocation.chapterIndex, 0);
    expect(
      progress.value?.chapterIndex,
      0,
      reason: '短章節回跳完成後，進度不能由 anchor 線誤判為下一章',
    );
  });

  testWidgets('runtime 從後一章回跳到前一章後 viewport 跟隨', (tester) async {
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();
    expect(runtime.state.visibleLocation.chapterIndex, 1);

    await runtime.jumpToChapter(0);
    await tester.pumpAndSettle();

    expect(runtime.state.phase, ReaderV2Phase.ready);
    expect(runtime.state.visibleLocation.chapterIndex, 0);
    final captured = runtime.captureVisibleLocation(notifyIfChanged: false);
    expect(captured, isNotNull);
    expect(captured!.chapterIndex, 0);
  });

  testWidgets('短章節位於 anchor 線前時，回跳仍保留目標章節', (tester) async {
    final shortChapter = BookChapter(
      url: 'chapter_0',
      title: '前言',
      bookUrl: 'http://book.test',
      index: 0,
      content: '短前言',
    );
    final viewportSize = const Size(432, 824);
    final runtime = makeRuntime([
      shortChapter,
      chapter(1, paragraphCount: 40),
    ], viewportSize: viewportSize);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller, viewportSize: viewportSize);
    await openAndSettle(tester, runtime);
    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();

    await runtime.jumpToChapter(0);
    await tester.pumpAndSettle();

    expect(runtime.state.phase, ReaderV2Phase.ready);
    expect(
      runtime.state.visibleLocation.chapterIndex,
      0,
      reason: '短章節在 anchor 線前時，不應被 motion capture 改成下一章',
    );
  });

  testWidgets('開書初始定位在短章節時，不被 anchor 線改成下一章', (tester) async {
    final shortChapter = BookChapter(
      url: 'chapter_0',
      title: '前言',
      bookUrl: 'http://book.test',
      index: 0,
      content: '短前言',
    );
    final viewportSize = const Size(432, 824);
    final runtime = makeRuntime([
      shortChapter,
      chapter(1, paragraphCount: 40),
    ], viewportSize: viewportSize);
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller, viewportSize: viewportSize);
    await openAndSettle(tester, runtime);

    expect(
      runtime.state.visibleLocation.chapterIndex,
      0,
      reason: '開書要求前言章首時，短前言不能因 anchor 線落到下一章而改變目前章節',
    );
    final captured = runtime.captureVisibleLocation(notifyIfChanged: false);
    expect(captured, isNotNull);
    expect(captured!.chapterIndex, 0);
  });

  testWidgets('短章節初始定位的公開進度不會被 anchor 線改成下一章', (tester) async {
    final shortChapter = BookChapter(
      url: 'chapter_0',
      title: '前言',
      bookUrl: 'http://book.test',
      index: 0,
      content: '短前言',
    );
    final progress = ValueNotifier<HybridProgressSnapshot?>(null);
    final runtime = makeRuntime([
      shortChapter,
      chapter(1, paragraphCount: 40),
    ], viewportSize: const Size(432, 824));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);
    addTearDown(progress.dispose);

    await pumpScreen(
      tester,
      runtime,
      controller,
      progress: progress,
      viewportSize: const Size(432, 824),
    );
    await openAndSettle(tester, runtime);

    expect(progress.value, isNotNull);
    expect(progress.value!.chapterIndex, 0);
    expect(progress.value!.chapterPercent, inInclusiveRange(0, 100));
  });

  testWidgets('ensureCharRangeVisible 已可見不動、離屏會捲動', (tester) async {
    final dao = _FakeBookDao();
    final runtime = makeRuntime(
      List.generate(2, chapter, growable: false),
      bookDao: dao,
    );
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    final visibleNow = controller.ensureCharRangeVisible!(
      chapterIndex: 0,
      startCharOffset: 0,
      endCharOffset: 4,
    );
    await tester.pumpAndSettle();
    expect(await visibleNow, isTrue);

    final content = await runtime.loadContentAt(0);
    final farOffset = content.displayText.length - 20;
    dao.progressWrites = 0;
    final scrolled = controller.ensureCharRangeVisible!(
      chapterIndex: 0,
      startCharOffset: farOffset,
      endCharOffset: farOffset + 10,
    );
    await tester.pumpAndSettle();
    expect(await scrolled, isTrue);
    expect(dao.progressWrites, greaterThan(0));
    final captured = runtime.captureVisibleLocation(notifyIfChanged: false);
    expect(captured, isNotNull);
    expect(captured!.charOffset, greaterThan(0));
  });

  testWidgets('TTS 高亮 overlay 掛載且不攔截指標', (tester) async {
    final runtime = makeRuntime(List.generate(2, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    await pumpScreen(
      tester,
      runtime,
      controller,
      ttsHighlight: const ReaderV2TtsHighlight(
        chapterIndex: 0,
        highlightStart: 0,
        highlightEnd: 12,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HybridTtsHighlightOverlay), findsOneWidget);
  });

  testWidgets('dispose 時 detach 全部閉包並解除 capture/restore', (tester) async {
    final runtime = makeRuntime(List.generate(2, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.scrollBy, isNull);
    expect(controller.continuousScrollBy, isNull);
    expect(controller.animateBy, isNull);
    expect(controller.moveToNextPage, isNull);
    expect(controller.moveToPrevPage, isNull);
    expect(controller.settleScroll, isNull);
    expect(controller.ensureCharRangeVisible, isNull);
    expect(runtime.captureVisibleLocation(notifyIfChanged: false), isNull);
  });

  testWidgets('runtime 熱替換後改讀新 repository 並維持 bridge', (tester) async {
    final first = makeRuntime(<BookChapter>[chapter(0, paragraphCount: 1)]);
    final second = makeRuntime(<BookChapter>[chapter(0, paragraphCount: 20)]);
    final controller = ReaderV2ViewportController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await pumpScreen(tester, first, controller);
    await openAndSettle(tester, first);
    await pumpScreen(tester, second, controller);
    await openAndSettle(tester, second);

    final content = await second.loadContentAt(0);
    final moved = controller.ensureCharRangeVisible!(
      chapterIndex: 0,
      startCharOffset: content.displayText.length - 20,
      endCharOffset: content.displayText.length - 10,
    );
    await tester.pumpAndSettle();

    expect(await moved, isTrue);
    expect(second.captureVisibleLocation(notifyIfChanged: false), isNotNull);
  });

  testWidgets('舊 viewport dispose 不會清掉新 owner 的 controller 閉包', (tester) async {
    final runtime = makeRuntime(List.generate(2, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    Widget screen(Key key) {
      return HybridReaderScreen(
        key: key,
        runtime: runtime,
        backgroundColor: const Color(0xFFFFFFFF),
        textColor: const Color(0xFF000000),
        style: style,
        viewportController: controller,
        preprocessor: const TextPreprocessor(useIsolate: false),
        enableDiskMetrics: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 220,
          height: 180,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: screen(const ValueKey('old'))),
            ],
          ),
        ),
      ),
    );
    await openAndSettle(tester, runtime);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 220,
          height: 180,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: screen(const ValueKey('old'))),
              Positioned.fill(child: screen(const ValueKey('new'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 220,
          height: 180,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: screen(const ValueKey('new'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.scrollBy, isNotNull);
    expect(controller.ensureCharRangeVisible, isNotNull);
    expect(runtime.captureVisibleLocation(notifyIfChanged: false), isNotNull);
  });

  testWidgets('拖曳期間排定的 pump 會硬停而不觸發 assertion', (tester) async {
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    await tester.drag(find.byType(HybridScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('拖曳期間 TTS ensure 會延後到手勢結束後執行', (tester) async {
    final runtime = makeRuntime(
      List.generate(3, (i) => chapter(i, paragraphCount: 18)),
    );
    final controller = ReaderV2ViewportController();
    addTearDown(runtime.dispose);

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    final content = await runtime.loadContentAt(0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HybridScrollView)),
    );
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();

    var completed = false;
    final ensure = controller.ensureCharRangeVisible!(
      chapterIndex: 0,
      startCharOffset: content.displayText.length - 40,
      endCharOffset: content.displayText.length - 20,
    );
    ensure.whenComplete(() => completed = true);
    await tester.pump(const Duration(milliseconds: 500));

    expect(completed, isFalse);
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(await ensure, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hybrid 開書與跳章不會再觸發舊分頁排版引擎', (tester) async {
    final previousObserver = ReaderV2LayoutEngine.debugOnStats;
    var oldLayoutRuns = 0;
    ReaderV2LayoutEngine.debugOnStats = (_) => oldLayoutRuns += 1;
    final runtime = makeRuntime(List.generate(3, chapter));
    final controller = ReaderV2ViewportController();
    addTearDown(() {
      runtime.dispose();
      ReaderV2LayoutEngine.debugOnStats = previousObserver;
    });

    await pumpScreen(tester, runtime, controller);
    await openAndSettle(tester, runtime);
    await runtime.jumpToChapter(1);
    await tester.pumpAndSettle();
    await runtime.applyPresentation(
      spec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(220, 180),
        style: const ReaderV2LayoutStyle(
          fontSize: 20,
          lineHeight: 1.6,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 0,
          paddingLeft: 12,
          paddingRight: 12,
          textIndent: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await runtime.reloadContentPreservingLocation();
    await tester.pumpAndSettle();

    expect(oldLayoutRuns, 0);
    expect(runtime.state.pageWindow, isNull);
    expect(runtime.state.phase, ReaderV2Phase.ready);
  });
}
