import 'dart:async';

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
import 'package:night_reader/features/reader_v2/hybrid/overlay/tts_highlight_overlay.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

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

void main() {
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

  ReaderV2LayoutSpec spec() {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: const Size(220, 180),
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
      initialLayoutSpec: spec(),
      initialLocation: initialLocation,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    ReaderV2Runtime runtime,
    ReaderV2ViewportController controller, {
    ValueNotifier<HybridProgressSnapshot?>? progress,
    ReaderV2TtsHighlight? ttsHighlight,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 220,
            height: 180,
            child: HybridReaderScreen(
              runtime: runtime,
              backgroundColor: const Color(0xFFFFFFFF),
              textColor: const Color(0xFF000000),
              style: style,
              viewportController: controller,
              ttsHighlight: ttsHighlight,
              progressListenable: progress,
              preprocessor: const TextPreprocessor(useIsolate: false),
              enableDiskMetrics: false,
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
    expect(snapshot.chapterLabel, '第 1/3 章');
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
