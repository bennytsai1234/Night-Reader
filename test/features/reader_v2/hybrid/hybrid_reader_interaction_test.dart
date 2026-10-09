import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

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

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

const Size _viewport = Size(400, 600);

const ReaderV2Style _style = ReaderV2Style(
  fontSize: 18,
  lineHeight: 1.5,
  letterSpacing: 0,
  paragraphSpacing: 0.8,
  paddingTop: 12,
  paddingBottom: 12,
  paddingLeft: 12,
  paddingRight: 12,
  textIndent: 2,
);

BookChapter _chapter(int index) => BookChapter(
  url: 'chapter_$index',
  title: '第 $index 章',
  bookUrl: 'http://interaction.test',
  index: index,
  content: List<String>.generate(
    80,
    (paragraph) => '第 $index 章第 $paragraph 段，夜深人靜時翻開書頁，字句在燈下慢慢展開。',
  ).join('\n'),
);

ReaderV2Runtime _makeRuntime({
  int chapterCount = 3,
  ReaderV2TestContentLoader? contentLoader,
}) {
  final book = Book(
    bookUrl: 'http://interaction.test',
    name: '互動測試書',
    author: '作者',
    origin: 'local',
    originName: '本地',
  );
  final bookDao = _FakeBookDao();
  final repository = ReaderV2ChapterRepository(
    book: book,
    initialChapters: List<BookChapter>.generate(chapterCount, _chapter),
    contentLoader:
        contentLoader ?? (_, chapter) => Future<String?>.value(chapter.content),
    bookDao: bookDao,
    chapterDao: _FakeChapterDao(),
    sourceDao: _FakeSourceDao(),
  );
  return ReaderV2Runtime(
    book: book,
    repository: repository,
    progressController: ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    ),
    initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
      viewportSize: _viewport,
      style: ReaderV2LayoutStyle(
        fontSize: _style.fontSize,
        lineHeight: _style.lineHeight,
        letterSpacing: _style.letterSpacing,
        paragraphSpacing: _style.paragraphSpacing,
        paddingTop: _style.paddingTop,
        paddingBottom: _style.paddingBottom,
        paddingLeft: _style.paddingLeft,
        paddingRight: _style.paddingRight,
        textIndent: _style.textIndent,
      ),
    ),
    initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
  );
}

void main() {
  late ReaderV2Runtime runtime;
  late ReaderV2ViewportController viewport;
  late List<TapUpDetails> taps;
  GestureTapUpCallback? onTap;

  Future<void> pumpReader(
    WidgetTester tester, {
    ReaderV2Runtime? customRuntime,
  }) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    runtime = customRuntime ?? _makeRuntime();
    addTearDown(runtime.dispose);
    viewport = ReaderV2ViewportController();
    taps = <TapUpDetails>[];
    onTap = null;
    await tester.pumpWidget(
      MaterialApp(
        home: HybridReaderScreen(
          runtime: runtime,
          backgroundColor: Colors.white,
          textColor: Colors.black,
          style: _style,
          viewportController: viewport,
          enableDiskMetrics: false,
          preprocessor: const TextPreprocessor(useIsolate: false),
          onContentTapUp: (details) {
            taps.add(details);
            onTap?.call(details);
          },
        ),
      ),
    );
    unawaited(runtime.openBook());
    for (
      var frame = 0;
      frame < 2000 &&
          !(runtime.state.hasStableWorld &&
              find.byType(CustomScrollView).evaluate().isNotEmpty);
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(runtime.state.hasStableWorld, isTrue);
    expect(find.byType(CustomScrollView), findsOneWidget);
  }

  ScrollPosition scrollPosition(WidgetTester tester) {
    return tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
  }

  testWidgets('tapping to stop a fling only stops it', (tester) async {
    await pumpReader(tester);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -300),
      3000,
    );
    await tester.pump(const Duration(milliseconds: 50));
    final position = scrollPosition(tester);
    expect(position.isScrollingNotifier.value, isTrue);

    await tester.tapAt(const Offset(200, 300));
    final stoppedAt = position.pixels;
    await tester.pump(const Duration(milliseconds: 200));

    expect(position.pixels, stoppedAt);
    expect(taps, isEmpty);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, hasLength(1), reason: '停住之後的下一次點擊照常生效');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a tap during a page turn finishes the page and still counts', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);

    final before = position.pixels;
    final plainTurn = viewport.moveToNextPage!();
    await settle(tester);
    expect(await plainTurn, isTrue);
    final pageDistance = position.pixels - before;
    expect(pageDistance, greaterThan(0));

    final start = position.pixels;
    final interruptedTurn = viewport.moveToNextPage!();
    for (var frame = 0; frame < 30 && position.pixels == start; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, greaterThan(start));
    expect(position.pixels, lessThan(start + pageDistance));
    await tester.tapAt(const Offset(200, 300));
    await settle(tester);
    await interruptedTurn;

    expect(position.pixels - start, closeTo(pageDistance, 0.5));
    expect(taps, hasLength(1), reason: '翻頁動畫不是使用者甩動，點擊照常生效');
  });

  testWidgets('a tap-zone page turn works while text selection is off', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);
    final start = position.pixels;
    Future<bool>? turn;
    onTap = (_) => turn = viewport.moveToNextPage!();

    await tester.tapAt(const Offset(200, 300));
    await settle(tester);

    expect(turn, isNotNull);
    expect(await turn, isTrue);
    expect(position.pixels, greaterThan(start));
  });

  testWidgets('dragging while a jump is loading cancels the jump cleanly', (
    tester,
  ) async {
    final target = Completer<String?>();
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(
        chapterCount: 8,
        contentLoader: (index, chapter) =>
            index == 7 ? target.future : Future.value(chapter.content),
      ),
    );
    final position = scrollPosition(tester);

    final jump = runtime.jumpToChapter(7);
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pump();
    final draggedTo = position.pixels;
    expect(runtime.stateMachine.currentOperation, isNull);

    target.complete(_chapter(7).content);
    await jump;
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(runtime.state.visibleLocation.chapterIndex, 0);
    expect(position.pixels, draggedTo);
  });

  testWidgets('stopping auto-scroll does not cancel the finger on the text', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();

    await viewport.settleScroll!();
    final afterSettle = position.pixels;
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();

    expect(position.pixels, closeTo(afterSettle + 60, 0.5));
    await gesture.up();
    await settle(tester);
  });
}
