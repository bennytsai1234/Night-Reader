import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/reader_skeleton_page.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/tts_highlight_overlay.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

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

BookChapter _chapter(int index, {int paragraphs = 80}) => BookChapter(
  url: 'chapter_$index',
  title: '第 $index 章',
  bookUrl: 'http://interaction.test',
  index: index,
  content: List<String>.generate(
    paragraphs,
    (paragraph) => '第 $index 章第 $paragraph 段，夜深人靜時翻開書頁，字句在燈下慢慢展開。',
  ).join('\n'),
);

ReaderV2Runtime _makeRuntime({
  int chapterCount = 3,
  int paragraphs = 80,
  ReaderV2Location initialLocation = const ReaderV2Location(
    chapterIndex: 0,
    charOffset: 0,
  ),
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
    initialChapters: List<BookChapter>.generate(
      chapterCount,
      (index) => _chapter(index, paragraphs: paragraphs),
    ),
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
    initialLocation: initialLocation,
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
    bool waitForOpen = true,
    ReaderV2TtsHighlight? ttsHighlight,
    ReaderSkeletonPageStore? skeletonPages,
    ValueNotifier<HybridProgressSnapshot?>? progress,
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
          ttsHighlight: ttsHighlight,
          bookUrl: skeletonPages == null ? null : 'http://interaction.test',
          skeletonPages: skeletonPages,
          progressListenable: progress,
          enableDiskCache: false,
          preprocessor: const TextPreprocessor(useIsolate: false),
          onContentTapUp: (details) {
            taps.add(details);
            onTap?.call(details);
          },
        ),
      ),
    );
    unawaited(runtime.openBook());
    if (!waitForOpen) return;
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

  group('開書骨架照上次那一頁畫', () {
    late ReaderSkeletonPageStore store;
    late ValueNotifier<HybridProgressSnapshot?> progress;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = ReaderSkeletonPageStore(await SharedPreferences.getInstance());
      progress = ValueNotifier(null);
    });

    /// 紀錄存到小數一位，兩次記下的同一行最多差 0.1。
    void expectSameLines(List<Rect> actual, List<Rect> expected) {
      expect(actual.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        for (final (a, e) in [
          (actual[i].left, expected[i].left),
          (actual[i].top, expected[i].top),
          (actual[i].right, expected[i].right),
          (actual[i].bottom, expected[i].bottom),
        ]) {
          expect(a, closeTo(e, 0.11), reason: '第 $i 行');
        }
      }
    }

    /// 推進到骨架換場播完（同 [settle]，它定義在後面）。
    Future<void> settleReveal(WidgetTester tester) async {
      final frames = SkeletonReveal.defaultDuration.inMilliseconds ~/ 16 + 8;
      for (var frame = 0; frame < frames; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<ReaderSkeletonPage> leaveMidChapter(WidgetTester tester) async {
      await pumpReader(tester, skeletonPages: store, progress: progress);
      await settleReveal(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -437));
      await settleReveal(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      return store.read('http://interaction.test')!;
    }

    ReaderV2Runtime reopenAt(ReaderSkeletonPage page) => _makeRuntime(
      initialLocation: ReaderV2Location(
        chapterIndex: page.chapterIndex,
        charOffset: page.charOffset,
        visualOffsetPx: page.visualOffsetPx,
      ),
    );

    testWidgets('leaving remembers every line on screen', (tester) async {
      final page = await leaveMidChapter(tester);
      expect(page.lines.length, greaterThan(10));
      for (final line in page.lines) {
        expect(line.bottom, greaterThan(0));
        expect(line.top, lessThan(_viewport.height));
        expect(line.left, greaterThanOrEqualTo(_style.paddingLeft));
      }
      expect(page.progress, isNotNull);
    });

    testWidgets('reopening there draws those lines, where the text lands', (
      tester,
    ) async {
      final page = await leaveMidChapter(tester);

      progress.value = null;
      await pumpReader(
        tester,
        customRuntime: reopenAt(page),
        skeletonPages: store,
        progress: progress,
        waitForOpen: false,
      );
      expect(
        tester.widget<LoadingVeil>(find.byType(LoadingVeil)).lines,
        page.lines,
        reason: '第一幀的紙就照記下的行畫',
      );
      await tester.pump();
      expect(
        progress.value?.chapterPercent,
        page.progress!.chapterPercent,
        reason: '頁尾的進度骨架照當時的字樣量寬度',
      );

      // 排好之後再記一次：正文的每一行就落在骨架的那一行上。
      for (
        var frame = 0;
        frame < 2000 && find.byType(LoadingVeil).evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expectSameLines(store.read('http://interaction.test')!.lines, page.lines);
    });

    testWidgets('opening somewhere else does not use the record', (
      tester,
    ) async {
      final page = await leaveMidChapter(tester);
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          initialLocation: ReaderV2Location(
            chapterIndex: page.chapterIndex,
            charOffset: page.charOffset + 40,
          ),
        ),
        skeletonPages: store,
        waitForOpen: false,
      );
      expect(
        tester.widget<LoadingVeil>(find.byType(LoadingVeil)).lines,
        isNull,
      );
    });
  });

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

  /// 推進到骨架換場（預設時長）播完再多幾幀。
  Future<void> settle(WidgetTester tester) async {
    final frames = SkeletonReveal.defaultDuration.inMilliseconds ~/ 16 + 8;
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<double> plainPageDistance(WidgetTester tester) async {
    final position = scrollPosition(tester);
    final before = position.pixels;
    final turn = viewport.moveToNextPage!();
    await settle(tester);
    expect(await turn, isTrue);
    final distance = position.pixels - before;
    expect(distance, greaterThan(0));
    return distance;
  }

  testWidgets('a tap during a page turn does not stop it and still counts', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);
    final pageDistance = await plainPageDistance(tester);

    final start = position.pixels;
    final turn = viewport.moveToNextPage!();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final beforeTap = position.pixels;
    expect(beforeTap, greaterThan(start));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, greaterThan(beforeTap), reason: '按下不會停住翻頁動畫');
    await settle(tester);

    expect(await turn, isTrue);
    expect(position.pixels - start, closeTo(pageDistance, 0.5));
    expect(taps, hasLength(1), reason: '翻頁動畫不是使用者甩動，點擊照常生效');
  });

  testWidgets('rapid page taps keep scrolling instead of snapping', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);
    final pageDistance = await plainPageDistance(tester);

    final start = position.pixels;
    final turns = <Future<bool>>[];
    onTap = (_) => turns.add(viewport.moveToNextPage!());
    final samples = <double>[start];
    Future<void> frame() async {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(position.pixels);
    }

    await tester.tapAt(const Offset(200, 300));
    await frame();
    await frame();
    await tester.tapAt(const Offset(200, 300));
    for (var i = 0; i < 30; i++) {
      await frame();
    }

    expect(turns, hasLength(2));
    expect(await Future.wait(turns), [isTrue, isTrue]);
    expect(position.pixels - start, closeTo(pageDistance * 2, 0.5));
    for (var i = 1; i < samples.length; i++) {
      final step = samples[i] - samples[i - 1];
      expect(step, greaterThanOrEqualTo(0), reason: '第 $i 幀倒退');
      expect(
        step,
        lessThan(pageDistance * 0.5),
        reason: '第 $i 幀一次跳了 $step px，翻頁應連續捲動',
      );
    }
  });

  testWidgets('a reverse tap queued behind a turn keeps the tap order', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);
    final pageDistance = await plainPageDistance(tester);

    final start = position.pixels;
    final finished = <String>[];
    final a = viewport.moveToNextPage!().then((_) => finished.add('A'));
    await tester.pump(const Duration(milliseconds: 16));
    final b = viewport.moveToPrevPage!().then((_) => finished.add('B'));
    final c = viewport.moveToNextPage!().then((_) => finished.add('C'));
    var highest = position.pixels;
    for (var frame = 0; frame < 90; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (position.pixels > highest) highest = position.pixels;
    }
    await Future.wait([a, b, c]);

    expect(finished, ['A', 'B', 'C']);
    expect(
      highest,
      lessThanOrEqualTo(start + pageDistance + 0.5),
      reason: '第三下不能先把第一下延長成兩頁',
    );
    expect(position.pixels - start, closeTo(pageDistance, 0.5));
  });

  testWidgets('dragging during a page turn hands the text to the finger', (
    tester,
  ) async {
    await pumpReader(tester);
    final position = scrollPosition(tester);
    await plainPageDistance(tester);

    final turn = viewport.moveToNextPage!();
    await tester.pump(const Duration(milliseconds: 16));
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    final held = position.pixels;
    await tester.pump(const Duration(milliseconds: 100));

    expect(position.pixels, held, reason: '手指拖動後翻頁動畫不再推動正文');
    expect(await turn, isFalse);
    await gesture.up();
    await settle(tester);
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

  testWidgets('a jump covers the text with paper until its chapter arrives', (
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
    final start = position.pixels;

    final jump = runtime.jumpToChapter(7);
    await tester.pump();
    expect(find.byType(LoadingVeil), findsOneWidget, reason: '正文還在取得就蓋紙');
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -120),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(position.pixels, start, reason: '紙蓋著時不能捲動');
    expect(runtime.stateMachine.currentOperation, isNotNull);

    target.complete(_chapter(7).content);
    for (
      var frame = 0;
      frame < 2000 && runtime.stateMachine.currentOperation != null;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await jump;
    await settle(tester);
    await tester.pump(SkeletonReveal.defaultDuration);

    expect(tester.takeException(), isNull);
    expect(runtime.state.visibleLocation.chapterIndex, 7);
    expect(find.byType(LoadingVeil), findsNothing);
  });

  testWidgets('a jump that cannot load lifts the paper off the old text', (
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await settle(tester);
    final start = position.pixels;

    final jump = runtime.jumpToChapter(7);
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoadingVeil), findsOneWidget);

    target.completeError(
      const ReaderV2ContentUnavailableException('第 7 章暫時取不到'),
    );
    await jump;
    await settle(tester);

    expect(runtime.takeUserNotice(), '第 7 章暫時取不到');
    expect(find.byType(LoadingVeil), findsNothing);
    expect(identical(scrollPosition(tester), position), isTrue);
    expect(position.pixels, start);
    expect(runtime.state.visibleLocation.chapterIndex, 0);
  });

  /// 第 7 章的正文等 [target] 才到，其餘章節立刻到。
  Future<void> pumpReaderWaitingForChapter7(
    WidgetTester tester,
    Completer<String?> target,
  ) => pumpReader(
    tester,
    customRuntime: _makeRuntime(
      chapterCount: 8,
      contentLoader: (index, chapter) =>
          index == 7 ? target.future : Future.value(chapter.content),
    ),
  );

  /// 等跳章的紙蓋上（紙比 runtime 通知晚一幀）。
  Future<void> paperFalls(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoadingVeil), findsOneWidget);
  }

  /// 正文到了之後排版要等下一幀，邊推幀邊等跳章結束。
  Future<void> finishJump(WidgetTester tester, Future<void> jump) async {
    for (
      var frame = 0;
      frame < 2000 && runtime.stateMachine.currentOperation != null;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await jump;
    await settle(tester);
    await tester.pump(SkeletonReveal.defaultDuration);
  }

  testWidgets('the jump paper stops a fling and still lets taps through', (
    tester,
  ) async {
    final target = Completer<String?>();
    await pumpReaderWaitingForChapter7(tester, target);
    final position = scrollPosition(tester);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -300),
      3000,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(position.isScrollingNotifier.value, isTrue);

    final jump = runtime.jumpToChapter(7);
    await paperFalls(tester);
    final coveredAt = position.pixels;
    await tester.pump(const Duration(milliseconds: 200));
    expect(position.pixels, coveredAt, reason: '甩動的慣性不在紙下繼續跑');
    final operation = runtime.stateMachine.currentOperation;
    expect(operation, isNotNull);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, hasLength(1), reason: '點紙不會被當成停住甩動而吞掉');
    expect(identical(runtime.stateMachine.currentOperation, operation), isTrue);

    target.completeError(
      const ReaderV2ContentUnavailableException('第 7 章暫時取不到'),
    );
    await jump;
    await settle(tester);

    expect(runtime.takeUserNotice(), '第 7 章暫時取不到');
    expect(find.byType(LoadingVeil), findsNothing);
    expect(position.pixels, coveredAt, reason: '掀紙回到蓋紙那一刻的位置');
    expect(runtime.state.visibleLocation.chapterIndex, 0);
  });

  testWidgets('a finger down before the paper falls cannot drag under it', (
    tester,
  ) async {
    final target = Completer<String?>();
    await pumpReaderWaitingForChapter7(tester, target);
    final position = scrollPosition(tester);
    final start = position.pixels;
    final gesture = await tester.startGesture(const Offset(200, 300));

    final jump = runtime.jumpToChapter(7);
    await paperFalls(tester);
    final operation = runtime.stateMachine.currentOperation;
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(position.pixels, start, reason: '紙下的拖動作廢');
    expect(
      identical(runtime.stateMachine.currentOperation, operation),
      isTrue,
      reason: '拖動不取消跳章',
    );

    target.complete(_chapter(7).content);
    await finishJump(tester, jump);
    expect(tester.takeException(), isNull);
    expect(runtime.state.visibleLocation.chapterIndex, 7);
    expect(find.byType(LoadingVeil), findsNothing);
  });

  testWidgets('nothing moves the text under the jump paper', (tester) async {
    final target = Completer<String?>();
    await pumpReaderWaitingForChapter7(tester, target);
    final position = scrollPosition(tester);
    final start = position.pixels;
    final jump = runtime.jumpToChapter(7);
    await paperFalls(tester);
    final operation = runtime.stateMachine.currentOperation;

    final scrolled = viewport.continuousScrollBy!(60);
    await tester.pump();
    expect(await scrolled, isFalse, reason: '自動捲動不推動紙下的正文');
    final turned = viewport.moveToNextPage!();
    await settle(tester);
    expect(await turned, isFalse, reason: '翻頁不推動紙下的正文');
    final followed = viewport.ensureCharRangeVisible!(
      chapterIndex: 3,
      startCharOffset: 0,
      endCharOffset: 4,
    );
    await settle(tester);
    expect(await followed, isFalse, reason: '朗讀跟隨等跳章結束');

    expect(position.pixels, start);
    expect(find.byType(LoadingVeil), findsOneWidget, reason: '紙不會被提早掀開');
    expect(identical(runtime.stateMachine.currentOperation, operation), isTrue);

    target.complete(_chapter(7).content);
    await finishJump(tester, jump);
    expect(runtime.state.visibleLocation.chapterIndex, 7);
    expect(find.byType(LoadingVeil), findsNothing);
  });

  testWidgets('opening fades the text in from paper without a spinner', (
    tester,
  ) async {
    await pumpReader(tester, waitForOpen: false);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('正在準備閱讀內容'), findsNothing);

    for (
      var frame = 0;
      frame < 2000 && find.byType(CustomScrollView).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(LoadingVeil), findsOneWidget, reason: '紙還在正文上淡出');

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, hasLength(1), reason: '淡出中的紙不攔點擊');

    await tester.pump(SkeletonReveal.defaultDuration);
    expect(find.byType(LoadingVeil), findsNothing);
  });

  testWidgets('opening mid-chapter does not wait for adjacent chapters', (
    tester,
  ) async {
    final neverLoaded = Completer<String?>();
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(
        // Long enough that both 3000px leads stay inside chapter 1.
        paragraphs: 400,
        initialLocation: const ReaderV2Location(
          chapterIndex: 1,
          charOffset: 6000,
        ),
        contentLoader: (index, chapter) =>
            index == 1 ? Future.value(chapter.content) : neverLoaded.future,
      ),
    );

    expect(runtime.state.visibleLocation.chapterIndex, 1);
    expect(runtime.pendingLocation, isNull);
  });

  testWidgets('opening at a chapter start still waits for the previous one', (
    tester,
  ) async {
    final previous = Completer<String?>();
    final neverLoaded = Completer<String?>();
    await pumpReader(
      tester,
      waitForOpen: false,
      customRuntime: _makeRuntime(
        paragraphs: 400,
        initialLocation: const ReaderV2Location(chapterIndex: 1, charOffset: 0),
        contentLoader: (index, chapter) => switch (index) {
          0 => previous.future,
          1 => Future.value(chapter.content),
          _ => neverLoaded.future,
        },
      ),
    );
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      runtime.state.hasStableWorld,
      isFalse,
      reason: 'The backward lead crosses into chapter 0.',
    );

    previous.complete(_chapter(0, paragraphs: 400).content);
    for (
      var frame = 0;
      frame < 2000 &&
          !(runtime.state.hasStableWorld &&
              find.byType(CustomScrollView).evaluate().isNotEmpty);
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.state.visibleLocation.chapterIndex, 1);
    final position = scrollPosition(tester);
    expect(
      position.pixels - position.minScrollExtent,
      greaterThanOrEqualTo(3000),
      reason: 'The backward lead exists before the reader is interactive.',
    );
  });

  testWidgets('an unavailable next chapter is reported at the edge, not '
      'requested every frame', (tester) async {
    var requests = 0;
    var available = false;
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(
        chapterCount: 2,
        paragraphs: 20,
        contentLoader: (index, chapter) async {
          if (index != 1) return chapter.content;
          requests += 1;
          if (!available) {
            throw const ReaderV2ContentUnavailableException('第 1 章暫時取不到');
          }
          return chapter.content;
        },
      ),
    );
    final position = scrollPosition(tester);
    final afterOpen = requests;
    expect(afterOpen, greaterThan(0));

    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var step = 0; step < 40; step++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(requests, afterOpen, reason: '捲動中不重複向書源要取不到的章節');
    await gesture.up();
    await settle(tester);

    final edge = position.maxScrollExtent;
    expect(position.pixels, closeTo(edge, 0.5));
    expect(runtime.takeUserNotice(), '第 1 章暫時取不到');
    expect(requests, afterOpen + 1, reason: '停在邊緣時重試一次');

    available = true;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await settle(tester);
    expect(requests, afterOpen + 2);
    for (var frame = 0; frame < 200; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.maxScrollExtent, greaterThan(edge), reason: '重試成功後正文接上');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await settle(tester);
    expect(runtime.state.visibleLocation.chapterIndex, 1);
  });

  testWidgets('the speech highlight follows the text while scrolling', (
    tester,
  ) async {
    await pumpReader(
      tester,
      ttsHighlight: const ReaderV2TtsHighlight(
        chapterIndex: 0,
        sentenceStart: 10,
        sentenceEnd: 40,
      ),
    );
    List<HybridLineBox> boxes() => tester
        .widget<HybridTtsHighlightOverlay>(
          find.byType(HybridTtsHighlightOverlay),
        )
        .sentence;
    final before = boxes();
    expect(before, isNotEmpty);

    final position = scrollPosition(tester);
    for (final step in [50.0, 30.0]) {
      final previous = boxes();
      position.jumpTo(position.pixels + step);
      await tester.pump();
      final after = boxes();
      expect(after, hasLength(previous.length));
      for (var i = 0; i < after.length; i++) {
        expect(after[i].top, closeTo(previous[i].top - step, 0.01));
        expect(after[i].bottom, closeTo(previous[i].bottom - step, 0.01));
        expect(after[i].left, previous[i].left);
        expect(after[i].right, previous[i].right);
      }
    }
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

  group('沒有可用的紀錄時，骨架照排好的第一頁畫', () {
    const bookUrl = 'http://interaction.test';
    late ReaderSkeletonPageStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = ReaderSkeletonPageStore(await SharedPreferences.getInstance());
    });

    List<Rect>? veilLines(WidgetTester tester) {
      final veil = find.byType(LoadingVeil);
      return veil.evaluate().isEmpty
          ? null
          : tester.widget<LoadingVeil>(veil).lines;
    }

    /// 一幀一幀推進，直到紙上的骨架照 [accept] 認可的行畫；回傳那張紙。
    Future<LoadingVeil> untilVeilLines(
      WidgetTester tester, {
      bool Function(List<Rect> lines)? accept,
    }) async {
      for (var frame = 0; frame < 2000; frame++) {
        final lines = veilLines(tester);
        if (lines != null && (accept?.call(lines) ?? true)) {
          return tester.widget<LoadingVeil>(find.byType(LoadingVeil));
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      fail('紙上一直沒有畫出骨架');
    }

    Future<void> untilVeilGone(WidgetTester tester) async {
      for (
        var frame = 0;
        frame < 2000 && find.byType(LoadingVeil).evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(LoadingVeil), findsNothing);
    }

    /// 離開閱讀器，回傳記下的那一頁每一行字的位置。
    Future<List<Rect>> linesOnLeaving(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      return store.read(bookUrl)!.lines;
    }

    /// 紀錄存到小數一位，同一行最多差 0.1。
    void expectSameLines(List<Rect> actual, List<Rect> expected) {
      expect(actual.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        for (final (a, e) in [
          (actual[i].left, expected[i].left),
          (actual[i].top, expected[i].top),
          (actual[i].right, expected[i].right),
          (actual[i].bottom, expected[i].bottom),
        ]) {
          expect(a, closeTo(e, 0.11), reason: '第 $i 行');
        }
      }
    }

    testWidgets('a jump leaves the middle empty until its first page is laid '
        'out, then the bars become the text', (tester) async {
      final target = Completer<String?>();
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          chapterCount: 8,
          contentLoader: (index, chapter) =>
              index == 7 ? target.future : Future.value(chapter.content),
        ),
        skeletonPages: store,
      );
      await untilVeilGone(tester);

      final jump = runtime.jumpToChapter(7);
      await paperFalls(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(veilLines(tester), isNull, reason: '正文還沒到，中間空著');

      target.complete(_chapter(7).content);
      final veil = await untilVeilLines(tester);
      expect(veil.titleLines, contains(0), reason: '跳到章首，第一行是章名');
      await finishJump(tester, jump);
      expect(runtime.state.visibleLocation.chapterIndex, 7);
      expectSameLines(await linesOnLeaving(tester), veil.lines!);
    });

    testWidgets('opening without a record waits for the first page too', (
      tester,
    ) async {
      await pumpReader(tester, skeletonPages: store, waitForOpen: false);
      expect(veilLines(tester), isNull);
      final veil = await untilVeilLines(tester);
      await untilVeilGone(tester);
      expectSameLines(await linesOnLeaving(tester), veil.lines!);
    });

    testWidgets('a record of different text is dropped for the first page', (
      tester,
    ) async {
      final custom = _makeRuntime();
      const stale = [Rect.fromLTRB(12, 10, 200, 28)];
      await store.write(
        bookUrl,
        ReaderSkeletonPage(
          chapterIndex: 0,
          charOffset: 0,
          visualOffsetPx: 0,
          layout: ReaderSkeletonPage.layoutKeyOf(custom.state.layoutSpec),
          contentHash: '替換規則改過之前的正文',
          lines: stale,
        ),
      );
      await pumpReader(
        tester,
        customRuntime: custom,
        skeletonPages: store,
        waitForOpen: false,
      );
      expect(veilLines(tester), stale, reason: '開書時還不知道正文換過');

      final veil = await untilVeilLines(
        tester,
        accept: (lines) => !listEquals(lines, stale),
      );
      await untilVeilGone(tester);
      expectSameLines(await linesOnLeaving(tester), veil.lines!);
    });

    testWidgets('jumping while the opening reveal plays drops the record', (
      tester,
    ) async {
      final custom = _makeRuntime();
      const remembered = [Rect.fromLTRB(12, 10, 200, 28)];
      await pumpReader(tester, customRuntime: custom);
      final contentHash = (await custom.repository.loadContent(0)).contentHash;
      await tester.pumpWidget(const SizedBox.shrink());
      await store.write(
        bookUrl,
        ReaderSkeletonPage(
          chapterIndex: 0,
          charOffset: 0,
          visualOffsetPx: 0,
          layout: ReaderSkeletonPage.layoutKeyOf(
            _makeRuntime().state.layoutSpec,
          ),
          contentHash: contentHash,
          lines: remembered,
        ),
      );

      await pumpReader(tester, skeletonPages: store);
      expect(veilLines(tester), remembered, reason: '開書換場還在播，照紀錄畫');
      final jump = runtime.jumpToChapter(1);
      final veil = await untilVeilLines(
        tester,
        accept: (lines) => !listEquals(lines, remembered),
      );
      await finishJump(tester, jump);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expectSameLines(await linesOnLeaving(tester), veil.lines!);
    });

    /// 一幀一幀推進到紙掀完，回傳紙上最後畫的那組行。
    Future<List<Rect>> lastLinesUntilVeilGone(WidgetTester tester) async {
      List<Rect>? last;
      for (
        var frame = 0;
        frame < 2000 && find.byType(LoadingVeil).evaluate().isNotEmpty;
        frame++
      ) {
        last = veilLines(tester) ?? last;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(LoadingVeil), findsNothing);
      return last!;
    }

    testWidgets('a jump during the first-page fade-in gets its own page', (
      tester,
    ) async {
      await pumpReader(tester, skeletonPages: store, waitForOpen: false);
      await untilVeilLines(tester);
      unawaited(runtime.jumpToChapter(1));
      final last = await lastLinesUntilVeilGone(tester);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expectSameLines(await linesOnLeaving(tester), last);
    });

    testWidgets('a layout change during the fade-in measures the page again', (
      tester,
    ) async {
      await pumpReader(tester, skeletonPages: store, waitForOpen: false);
      final first = (await untilVeilLines(tester)).lines!;
      final larger = ReaderV2LayoutSpec.fromViewport(
        viewportSize: _viewport,
        style: ReaderV2LayoutStyle(
          fontSize: 26,
          lineHeight: _style.lineHeight,
          letterSpacing: _style.letterSpacing,
          paragraphSpacing: _style.paragraphSpacing,
          paddingTop: _style.paddingTop,
          paddingBottom: _style.paddingBottom,
          paddingLeft: _style.paddingLeft,
          paddingRight: _style.paddingRight,
          textIndent: _style.textIndent,
        ),
      );
      unawaited(runtime.applyPresentation(spec: larger));
      final last = await lastLinesUntilVeilGone(tester);
      expect(last, isNot(first));
      expectSameLines(await linesOnLeaving(tester), last);
    });

    testWidgets('an old skeleton fades out completely before it is replaced', (
      tester,
    ) async {
      // 舊骨架完整淡入後正文才到；正文很短，第一頁比舊骨架淡完還快排好。
      final text = Completer<String?>();
      final custom = _makeRuntime(
        paragraphs: 1,
        contentLoader: (index, chapter) =>
            index == 0 ? text.future : Future.value(chapter.content),
      );
      const stale = [Rect.fromLTRB(12, 10, 200, 28)];
      await store.write(
        bookUrl,
        ReaderSkeletonPage(
          chapterIndex: 0,
          charOffset: 0,
          visualOffsetPx: 0,
          layout: ReaderSkeletonPage.layoutKeyOf(custom.state.layoutSpec),
          contentHash: '替換規則改過之前的正文',
          lines: stale,
        ),
      );
      await pumpReader(
        tester,
        customRuntime: custom,
        skeletonPages: store,
        waitForOpen: false,
      );
      await tester.pump(SkeletonReveal.defaultDuration);
      text.complete(_chapter(0, paragraphs: 1).content);
      final noBars = paintsExactlyCountTimes(#drawRRect, 0);
      var paintedBars = true;
      for (
        var frame = 0;
        frame < 2000 && listEquals(veilLines(tester), stale);
        frame++
      ) {
        paintedBars = !noBars.matches(find.byType(LoadingVeil), {});
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(veilLines(tester), isNot(stale));
      expect(paintedBars, isFalse, reason: '換成新的行之前，舊骨架已經淡完');
      await untilVeilGone(tester);
    });

    testWidgets('at a short last chapter the skeleton sits where it stops', (
      tester,
    ) async {
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          paragraphs: 1,
          initialLocation: const ReaderV2Location(
            chapterIndex: 2,
            charOffset: 0,
          ),
        ),
        skeletonPages: store,
        waitForOpen: false,
      );
      final last = await lastLinesUntilVeilGone(tester);
      expectSameLines(await linesOnLeaving(tester), last);
    });

    testWidgets('with the previous chapter unavailable the skeleton sits '
        'where the scroll stops', (tester) async {
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          initialLocation: const ReaderV2Location(
            chapterIndex: 1,
            charOffset: 0,
          ),
          contentLoader: (index, chapter) => index == 0
              ? Future.error(
                  const ReaderV2ContentUnavailableException('第 0 章暫時取不到'),
                )
              : Future.value(chapter.content),
        ),
        skeletonPages: store,
        waitForOpen: false,
      );
      final last = await lastLinesUntilVeilGone(tester);
      expectSameLines(await linesOnLeaving(tester), last);
    });
  });
}
