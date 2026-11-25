import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/features/reader/text_view/overlay/highlight_marks.dart';
import 'package:night_reader/features/reader/features/auto_page/reader_auto_page_controller.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_highlight.dart';
import 'package:night_reader/features/reader/text_view/core/progress_snapshot.dart';
import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';
import 'package:night_reader/features/reader/text_view/overlay/loading_veil.dart';
import 'package:night_reader/features/reader/text_view/overlay/reader_skeleton_page.dart';
import 'package:night_reader/features/reader/text_view/overlay/reader_text_selection_layer.dart';
import 'package:night_reader/features/reader/text_view/overlay/selection_service.dart';
import 'package:night_reader/features/reader/text_view/overlay/tts_highlight_overlay.dart';
import 'package:night_reader/features/reader/text_view/text/text_preprocessor.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/layout/reader_style_preferences.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/viewport/reader_viewport_controller.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton_reveal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 正文排好到紙掀完：骨架長完後停著等正文（[LoadingVeilController
/// .restBeforeBreath]），超過才開始呼吸、收住時呼完這一口（從最深起步的
/// 第一口最多一輪半），紙底下建好、畫出正文後停 [AppMotion.stillGap]，
/// 再照骨架換場的預設時長掀紙。
final Duration _revealTime =
    LoadingVeilController.restBeforeBreath +
    Skeleton.breathCycle * 1.5 +
    SkeletonReveal.defaultDuration +
    AppMotion.stillGap;

/// 正文排好後一幀一幀推進到紙開始掀（或已經沒有紙）：呼吸收住，正文在紙
/// 底下建好、畫出，再停 [AppMotion.stillGap]。
Future<void> _pumpUntilRevealing(WidgetTester tester) async {
  for (var frame = 0; frame < 200; frame++) {
    final veil = find.byType(LoadingVeil);
    if (veil.evaluate().isEmpty ||
        tester.widget<LoadingVeil>(veil).controller.isRevealing) {
      // 開始掀的那一幀排了重建，紙上那層下一幀才不攔觸控。
      await tester.pump(const Duration(milliseconds: 16));
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 正文排好後推進到紙掀完。
Future<void> _pumpReveal(WidgetTester tester) async {
  await _pumpUntilRevealing(tester);
  await tester.pump(SkeletonReveal.defaultDuration);
  await tester.pump(const Duration(milliseconds: 16));
}

/// 最後一次寫進資料庫的閱讀進度（章、字）。
({int chapter, int pos})? _savedProgress;

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<int?> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    _savedProgress = (chapter: chapterIndex, pos: pos);
    return null;
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {
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

class _FakeSourceDao extends Fake implements BookSourceDao {}

/// 釋放 [runtime]；已經釋放過就不再釋放。
void _disposeRuntime(ReaderRuntime runtime) {
  if (!runtime.disposed) runtime.dispose();
}

/// 跟閱讀頁一樣由畫面擁有 runtime：樹拆掉時釋放，排著的進度在測試框架
/// 檢查有沒有剩下的計時器之前寫完。測試中途失敗時框架不拆樹，另外在
/// teardown 補釋放一次。
class _RuntimeOwner extends StatefulWidget {
  const _RuntimeOwner({required this.runtime, required this.child});

  final ReaderRuntime runtime;
  final Widget child;

  @override
  State<_RuntimeOwner> createState() => _RuntimeOwnerState();
}

class _RuntimeOwnerState extends State<_RuntimeOwner> {
  @override
  void dispose() {
    _disposeRuntime(widget.runtime);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const Size _viewport = Size(400, 600);

const ReaderStylePreferences _style = ReaderStylePreferences(
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

ReaderRuntime _makeRuntime({
  int chapterCount = 3,
  int paragraphs = 80,
  ReaderLocation initialLocation = const ReaderLocation(
    chapterIndex: 0,
    charOffset: 0,
  ),
  ReaderTestContentLoader? contentLoader,
  Set<int> locked = const <int>{},
}) {
  final book = Book(
    bookUrl: 'http://interaction.test',
    name: '互動測試書',
    author: '作者',
    origin: 'local',
    originName: '本地',
  );
  final bookDao = _FakeBookDao();
  final repository = ReaderChapterRepository(
    book: book,
    initialChapters: List<BookChapter>.generate(
      chapterCount,
      (index) =>
          _chapter(index, paragraphs: paragraphs)
            ..isVip = locked.contains(index),
    ),
    contentLoader:
        contentLoader ?? (_, chapter) => Future<String?>.value(chapter.content),
    bookDao: bookDao,
    chapterDao: _FakeChapterDao(),
    sourceDao: _FakeSourceDao(),
  );
  return ReaderRuntime(
    book: book,
    repository: repository,
    progressController: ReaderProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    ),
    initialLayoutSpec: ReaderLayoutSpec.fromViewport(
      viewportSize: _viewport,
      style: ReaderLayoutStyle(
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
  late ReaderRuntime runtime;
  late ReaderViewportController viewport;
  late List<TapUpDetails> taps;
  GestureTapUpCallback? onTap;

  Future<void> pumpReader(
    WidgetTester tester, {
    ReaderRuntime? customRuntime,
    bool waitForOpen = true,
    ReaderTtsHighlight? ttsHighlight,
    ReaderSkeletonPageStore? skeletonPages,
    ValueNotifier<ProgressSnapshot?>? progress,
    bool textSelectionEnabled = false,
    ValueListenable<List<ReaderHighlightMark>>? highlights,
  }) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final owned = runtime = customRuntime ?? _makeRuntime();
    addTearDown(() => _disposeRuntime(owned));
    viewport = ReaderViewportController();
    taps = <TapUpDetails>[];
    onTap = null;
    await tester.pumpWidget(
      MaterialApp(
        home: _RuntimeOwner(
          runtime: runtime,
          child: ReaderTextView(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style,
            viewportController: viewport,
            ttsHighlight: ttsHighlight,
            textSelectionEnabled: textSelectionEnabled,
            highlights: highlights,
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
    // 紙停過預留停頓、開始掀（掀開中的紙不攔觸控）。
    await _pumpUntilRevealing(tester);
  }

  ScrollPosition scrollPosition(WidgetTester tester) {
    return tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
  }

  group('開書骨架照上次那一頁畫', () {
    late ReaderSkeletonPageStore store;
    late ValueNotifier<ProgressSnapshot?> progress;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = ReaderSkeletonPageStore(await SharedPreferences.getInstance());
      progress = ValueNotifier(null);
    });

    /// 推進到骨架換場播完（同 [settle]，它定義在後面）。
    Future<void> settleReveal(WidgetTester tester) async {
      final frames = _revealTime.inMilliseconds ~/ 16 + 12;
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

    ReaderRuntime reopenAt(ReaderSkeletonPage page) => _makeRuntime(
      initialLocation: ReaderLocation(
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
      _expectSameLines(
        store.read('http://interaction.test')!.lines,
        page.lines,
      );
    });

    testWidgets('opening somewhere else does not use the record', (
      tester,
    ) async {
      final page = await leaveMidChapter(tester);
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          initialLocation: ReaderLocation(
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

    testWidgets('leaving while a font change fades the paper in records the '
        'old layout with the old lines', (tester) async {
      await pumpReader(tester, skeletonPages: store, progress: progress);
      await settleReveal(tester);
      final oldSpec = runtime.state.layoutSpec;
      final larger = ReaderLayoutSpec.fromViewport(
        viewportSize: _viewport,
        style: ReaderLayoutStyle(
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
      for (
        var frame = 0;
        frame < 200 && find.byType(LoadingVeil).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final veil = tester.widget<LoadingVeil>(find.byType(LoadingVeil));
      expect(veil.controller.isCovered, isFalse, reason: '紙還在淡入');
      expect(runtime.state.layoutSpec.style.fontSize, 26);

      await tester.pumpWidget(const SizedBox.shrink());
      final page = store.read('http://interaction.test')!;
      expect(
        page.layout,
        ReaderSkeletonPage.layoutKeyOf(oldSpec),
        reason: '畫面上還是舊字級排的行，紀錄的版面也是舊的',
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
    // 跳章時紙先淡入蓋滿。
    final frames = (_revealTime + AppMotion.fade).inMilliseconds ~/ 16 + 12;
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
    await _pumpReveal(tester);

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

    target.completeError(const ReaderContentUnavailableException('第 7 章暫時取不到'));
    await jump;
    await settle(tester);

    expect(runtime.takeUserNotice()?.message, '第 7 章暫時取不到');
    expect(find.byType(LoadingVeil), findsNothing);
    expect(identical(scrollPosition(tester), position), isTrue);
    expect(position.pixels, start);
    expect(runtime.state.visibleLocation.chapterIndex, 0);
  });

  group('the paper fades in over the old text before the relayout', () {
    LoadingVeilController? veilOf(WidgetTester tester) {
      final veil = find.byType(LoadingVeil);
      return veil.evaluate().isEmpty
          ? null
          : tester.widget<LoadingVeil>(veil).controller;
    }

    /// 一幀一幀推進，直到紙開始淡入；淡入途中每一幀舊正文都還在紙下，
    /// 紙蓋滿後才拿掉。回傳淡入了幾幀。
    Future<int> expectOldTextUntilCovered(WidgetTester tester) async {
      var frame = 0;
      while (frame < 200 && veilOf(tester) == null) {
        await tester.pump(const Duration(milliseconds: 16));
        frame++;
      }
      final veil = veilOf(tester)!;
      var fading = 0;
      while (!veil.isCovered) {
        expect(veil.isVisible, isTrue);
        expect(
          find.byType(CustomScrollView),
          findsOneWidget,
          reason: '紙還沒蓋滿，舊正文留在紙下',
        );
        await tester.pump(const Duration(milliseconds: 16));
        fading++;
        expect(fading, lessThan(100));
      }
      return fading;
    }

    testWidgets('a jump keeps the old text until the paper covers it', (
      tester,
    ) async {
      await pumpReader(tester, customRuntime: _makeRuntime(chapterCount: 8));
      await settle(tester);

      final jump = runtime.jumpToChapter(5);
      final fading = await expectOldTextUntilCovered(tester);
      expect(fading, greaterThan(5), reason: '紙是淡入的，不是一幀蓋上');

      for (
        var frame = 0;
        frame < 2000 && runtime.stateMachine.currentOperation != null;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await jump;
      await settle(tester);
      expect(runtime.state.visibleLocation.chapterIndex, 5);
      expect(find.byType(LoadingVeil), findsNothing);
    });

    testWidgets('a font size change keeps the old text until covered', (
      tester,
    ) async {
      await pumpReader(tester);
      await settle(tester);
      final larger = ReaderLayoutSpec.fromViewport(
        viewportSize: _viewport,
        style: ReaderLayoutStyle(
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

      final applied = runtime.applyPresentation(spec: larger);
      final fading = await expectOldTextUntilCovered(tester);
      expect(fading, greaterThan(5), reason: '紙是淡入的，不是一幀蓋上');

      for (
        var frame = 0;
        frame < 2000 && runtime.stateMachine.currentOperation != null;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await applied;
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(runtime.state.layoutSpec.style.fontSize, 26);
      expect(find.byType(LoadingVeil), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('scrolling back to a chapter whose text changed meanwhile '
        'lays out the new text', (tester) async {
      const chapterCount = 25;
      var rewritten = false;
      String? textOf(int index, BookChapter chapter) =>
          index == 0 && rewritten ? '改過的第 0 章。\n只剩兩段。' : chapter.content;
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          chapterCount: chapterCount,
          paragraphs: 4,
          contentLoader: (index, chapter) =>
              Future.value(textOf(index, chapter)),
        ),
      );
      await settle(tester);

      // 讀到第 22 章：第 0 章離開閱讀器常駐的範圍，也離開最近 20 章的正文
      // 快取，只剩它的換行計畫。
      for (
        var step = 0;
        step < 400 && runtime.state.visibleLocation.chapterIndex < 22;
        step++
      ) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await settle(tester);
      }
      expect(runtime.state.visibleLocation.chapterIndex, 22);
      final generation = runtime.state.contentGeneration;

      // 下載把第 0 章換成新的正文，閱讀器沒有收到重新載入。
      rewritten = true;
      for (
        var step = 0;
        step < 400 &&
            (runtime.state.visibleLocation.chapterIndex > 0 ||
                runtime.state.contentGeneration == generation);
        step++
      ) {
        if (runtime.state.hasStableWorld &&
            find.byType(CustomScrollView).evaluate().isNotEmpty) {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 500),
          );
        }
        await settle(tester);
      }
      for (
        var frame = 0;
        frame < 2000 && find.byType(LoadingVeil).evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(runtime.state.contentGeneration, greaterThan(generation));
      expect(runtime.state.visibleLocation.chapterIndex, 0);
      expect(runtime.stateMachine.currentOperation, isNull);
      expect(find.byType(LoadingVeil), findsNothing, reason: '紙掀開了');
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(
        (await runtime.repository.loadContent(0)).displayText,
        contains('改過的第 0 章'),
        reason: '排的是新的正文',
      );
    });

    testWidgets('a page turn waiting for a chapter whose text changed '
        'meanwhile is cancelled, not failed', (tester) async {
      const chapterCount = 25;
      final rewritten = Completer<String?>();
      var holdChapter1 = false;
      // 開在長長的第 0 章中間：開書不等相鄰的章，第 1 章在背景取，被擋住。
      const paragraphs = 300;
      final custom = _makeRuntime(
        chapterCount: chapterCount,
        paragraphs: paragraphs,
        initialLocation: ReaderLocation(
          chapterIndex: 0,
          charOffset: _chapter(0, paragraphs: paragraphs).content!.length ~/ 2,
        ),
        contentLoader: (index, chapter) => index == 1 && holdChapter1
            ? rewritten.future
            : Future.value(chapter.content),
      );
      // 先讀過第 1–24 章：第 1 章的正文記得是哪一份，但已經不在最近 20 章
      // 的快取裡，再取時才發現正文換了。
      for (var index = 1; index < chapterCount; index++) {
        await custom.repository.loadContent(index);
      }
      holdChapter1 = true;
      await pumpReader(tester, customRuntime: custom);
      await settle(tester);
      final generation = runtime.state.contentGeneration;

      // 捲到已經排好的盡頭（第 0 章結尾），再翻下一頁就要等第 1 章。
      final position = scrollPosition(tester);
      for (var step = 0; step < 40; step++) {
        final before = position.pixels;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await settle(tester);
        if (position.pixels == before) break;
      }
      expect(position.pixels, position.maxScrollExtent);
      final turn = viewport.moveToNextPage!();
      await settle(tester);
      rewritten.complete('改過的第 1 章。\n只剩兩段。');
      var turned = false;
      var failed = false;
      unawaited(
        turn.then((_) => turned = true, onError: (Object _) => failed = true),
      );
      for (
        var frame = 0;
        frame < 2000 &&
            (!turned ||
                runtime.stateMachine.currentOperation != null ||
                find.byType(LoadingVeil).evaluate().isNotEmpty);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(failed, isFalse, reason: '翻頁作廢，不丟出錯誤');
      expect(turned, isTrue);
      expect(tester.takeException(), isNull);
      expect(runtime.state.contentGeneration, greaterThan(generation));
      expect(find.byType(LoadingVeil), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);
    });
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
    await _pumpReveal(tester);
  }

  group('a paper whose owner gives up never leaves the reader blank', () {
    ReaderLayoutSpec specWithFont(double fontSize) =>
        ReaderLayoutSpec.fromViewport(
          viewportSize: _viewport,
          style: ReaderLayoutStyle(
            fontSize: fontSize,
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

    LoadingVeilController? veilOf(WidgetTester tester) {
      final veil = find.byType(LoadingVeil);
      return veil.evaluate().isEmpty
          ? null
          : tester.widget<LoadingVeil>(veil).controller;
    }

    /// 推進到沒有操作、紙掀完、正文在畫面上（最多 2000 幀）。
    Future<void> untilSettled(WidgetTester tester) async {
      for (
        var frame = 0;
        frame < 2000 &&
            (runtime.stateMachine.currentOperation != null ||
                find.byType(LoadingVeil).evaluate().isNotEmpty ||
                find.byType(CustomScrollView).evaluate().isEmpty);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    void expectTextBack({required double fontSize, int chapter = 0}) {
      expect(find.byType(CustomScrollView), findsOneWidget, reason: '正文回來');
      expect(find.byType(LoadingVeil), findsNothing, reason: '紙掀掉');
      expect(runtime.stateMachine.currentOperation, isNull);
      expect(runtime.state.visibleLocation.chapterIndex, chapter);
      expect(runtime.state.layoutSpec.style.fontSize, fontSize);
    }

    testWidgets('a jump that fails while a font change fades the paper in', (
      tester,
    ) async {
      final target = Completer<String?>();
      await pumpReaderWaitingForChapter7(tester, target);
      await settle(tester);

      final applied = runtime.applyPresentation(spec: specWithFont(26));
      for (
        var frame = 0;
        frame < 200 && runtime.state.layoutGeneration == 0;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(runtime.state.layoutGeneration, 1, reason: '新版面已經生效');
      await tester.pump(const Duration(milliseconds: 16));
      expect(veilOf(tester)!.isCovered, isFalse, reason: '紙還在淡入');

      final jump = runtime.jumpToChapter(7);
      await tester.pump(const Duration(milliseconds: 16));
      target.completeError(
        const ReaderContentUnavailableException('第 7 章暫時取不到'),
      );
      await untilSettled(tester);
      await jump;
      await applied;

      expect(tester.takeException(), isNull);
      expect(runtime.takeUserNotice()?.message, '第 7 章暫時取不到');
      expectTextBack(fontSize: 26);
    });

    testWidgets('a jump that fails after a font change covered the text', (
      tester,
    ) async {
      final target = Completer<String?>();
      await pumpReaderWaitingForChapter7(tester, target);
      await settle(tester);

      final applied = runtime.applyPresentation(spec: specWithFont(26));
      for (
        var frame = 0;
        frame < 200 && runtime.state.layoutGeneration == 0;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final jump = runtime.jumpToChapter(7);
      for (
        var frame = 0;
        frame < 200 && find.byType(CustomScrollView).evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(CustomScrollView), findsNothing, reason: '舊正文已拆掉');

      target.completeError(
        const ReaderContentUnavailableException('第 7 章暫時取不到'),
      );
      await untilSettled(tester);
      await jump;
      await applied;

      expect(tester.takeException(), isNull);
      expectTextBack(fontSize: 26);
    });

    testWidgets('a second font change during the fade-in wins', (tester) async {
      await pumpReader(tester);
      await settle(tester);

      final first = runtime.applyPresentation(spec: specWithFont(26));
      for (
        var frame = 0;
        frame < 200 && runtime.state.layoutGeneration == 0;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(veilOf(tester)!.isCovered, isFalse);
      final second = runtime.applyPresentation(spec: specWithFont(30));
      await untilSettled(tester);
      await first;
      await second;

      expect(tester.takeException(), isNull);
      expectTextBack(fontSize: 30);
    });

    testWidgets('a finger already down cannot drag the text under a '
        'speech-follow paper', (tester) async {
      await pumpReader(tester, customRuntime: _makeRuntime(chapterCount: 8));
      await settle(tester);
      final position = scrollPosition(tester);
      final start = position.pixels;
      final gesture = await tester.startGesture(const Offset(200, 300));

      final followed = viewport.ensureCharRangeVisible!(
        chapterIndex: 7,
        startCharOffset: 0,
        endCharOffset: 4,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final veil = veilOf(tester);
      expect(veil, isNotNull, reason: '紙淡入時就畫在正文上');
      expect(veil!.isCovered, isFalse);
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      expect(position.pixels, start, reason: '紙下的拖動作廢');
      await gesture.up();
      await untilSettled(tester);

      expect(tester.takeException(), isNull);
      expect(await followed, isTrue, reason: '拖動不取消朗讀跟隨');
      expect(find.byType(LoadingVeil), findsNothing);
      expect(runtime.state.visibleLocation.chapterIndex, 7);
    });

    testWidgets('a speech-follow paper cancelled mid-fade lifts off the old '
        'text', (tester) async {
      await pumpReader(tester, customRuntime: _makeRuntime(chapterCount: 8));
      await settle(tester);
      final position = scrollPosition(tester);
      final start = position.pixels;

      final followed = viewport.ensureCharRangeVisible!(
        chapterIndex: 7,
        startCharOffset: 0,
        endCharOffset: 4,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(veilOf(tester)!.isCovered, isFalse, reason: '紙還在淡入');
      // 停止自動捲動這類「停在原處」的要求讓這次跟隨作廢，沒有別的操作接手。
      unawaited(viewport.settleScroll!());
      await untilSettled(tester);

      expect(tester.takeException(), isNull);
      expect(await followed, isFalse);
      expect(find.byType(LoadingVeil), findsNothing, reason: '紙掀回舊正文');
      expect(identical(scrollPosition(tester), position), isTrue);
      expect(position.pixels, start);
      expect(runtime.state.visibleLocation.chapterIndex, 0);
    });
  });

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

    target.completeError(const ReaderContentUnavailableException('第 7 章暫時取不到'));
    await jump;
    await settle(tester);

    expect(runtime.takeUserNotice()?.message, '第 7 章暫時取不到');
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
    expect(find.byType(LoadingVeil), findsOneWidget, reason: '紙還在正文上');

    // 正文在整張紙底下建好、畫出來，停過預留停頓才開始掀。
    await _pumpUntilRevealing(tester);
    expect(find.byType(LoadingVeil), findsOneWidget, reason: '紙還在正文上淡出');
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, hasLength(1), reason: '淡出中的紙不攔點擊');

    await tester.pump(SkeletonReveal.defaultDuration);
    expect(find.byType(LoadingVeil), findsNothing);
  });

  testWidgets(
    'the pause before the paper lifts starts after the text is drawn',
    (tester) async {
      // 停頓從正文在紙底下建好、畫出之後才算，建正文的時間不吃掉停頓。
      await pumpReader(tester, waitForOpen: false);
      const frame = Duration(milliseconds: 16);
      Duration elapsed = Duration.zero;
      Duration? built;
      for (var i = 0; i < 2000; i++) {
        await tester.pump(frame);
        elapsed += frame;
        built ??= find.byType(CustomScrollView).evaluate().isNotEmpty
            ? elapsed
            : null;
        final veil = find.byType(LoadingVeil);
        if (veil.evaluate().isNotEmpty &&
            tester.widget<LoadingVeil>(veil).controller.isRevealing) {
          break;
        }
      }
      expect(built, isNotNull);
      expect(elapsed - built!, greaterThanOrEqualTo(AppMotion.stillGap));
      await settle(tester);
    },
  );

  testWidgets('auto-scroll waits while the paper rests after a jump', (
    tester,
  ) async {
    await pumpReader(tester);
    await settle(tester);
    ReaderFrameCallback? tick;
    final auto = ReaderAutoPageController(
      runtime: runtime,
      viewportController: viewport,
      viewportExtent: () => _viewport.height,
      frameSource: (callback) {
        tick = callback;
        return () => tick = null;
      },
    );
    addTearDown(auto.dispose);
    auto.start();
    tick!(Duration.zero);

    var jumped = false;
    unawaited(runtime.jumpToChapter(1).then((_) => jumped = true));
    for (var i = 0; i < 2000 && !jumped; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(jumped, isTrue);
    expect(
      tester
          .widget<LoadingVeil>(find.byType(LoadingVeil))
          .controller
          .isRevealing,
      isFalse,
      reason: '跳章排好了，紙還在掀紙前的預留停頓',
    );

    // 紙蓋著正文時這一步跳過，不當成到了書尾而停下。
    tick!(const Duration(milliseconds: 16));
    await tester.pump();
    expect(auto.isRunning, isTrue);
    auto.stop();
    await _pumpReveal(tester);
  });

  // 自動翻頁捲到排好的正文盡頭、下一章還在抓：翻頁在等下一章。這時打開
  // 選單暫停，等的那一下不能在下一章到了之後自己翻過去。
  testWidgets('auto-scroll paused while its page turn waits for the next '
      'chapter does not turn when the chapter arrives', (tester) async {
    final next = Completer<String?>();
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(
        chapterCount: 2,
        contentLoader: (index, chapter) =>
            index == 1 ? next.future : Future.value(chapter.content),
      ),
    );
    await settle(tester);
    final position = scrollPosition(tester);
    // 捲到第一章排好的盡頭：盡頭跟著排版往後長，捲到不再長為止。
    for (var i = 0; i < 20; i++) {
      final end = position.maxScrollExtent;
      position.jumpTo(end);
      await settle(tester);
      if (position.maxScrollExtent == end) break;
    }
    ReaderFrameCallback? tick;
    final auto = ReaderAutoPageController(
      runtime: runtime,
      viewportController: viewport,
      viewportExtent: () => _viewport.height,
      frameSource: (callback) {
        tick = callback;
        return () => tick = null;
      },
    );
    addTearDown(auto.dispose);
    auto.start();
    tick!(Duration.zero);
    tick!(const Duration(milliseconds: 16));
    await tester.pump();
    final paused = position.pixels;

    auto.setPaused(true);
    next.complete(_chapter(1).content);
    await settle(tester);

    expect(auto.isRunning, isTrue, reason: '只是暫停，還在自動翻頁');
    expect(position.pixels, closeTo(paused, 0.5), reason: '暫停中不自己翻');
    auto.stop();
  });

  // 轉螢幕、分割畫面這類改了正文寬度的重排：紙蓋著、正文在排版中，自動
  // 捲動等它排好，不當成到了書尾而停下。
  testWidgets('auto-scroll keeps going through a re-layout', (tester) async {
    await pumpReader(tester);
    await settle(tester);
    ReaderFrameCallback? tick;
    final auto = ReaderAutoPageController(
      runtime: runtime,
      viewportController: viewport,
      viewportExtent: () => _viewport.height,
      frameSource: (callback) {
        tick = callback;
        return () => tick = null;
      },
    );
    addTearDown(auto.dispose);
    auto.start();
    var elapsed = Duration.zero;
    tick!(elapsed);

    // 正文欄變窄（同轉螢幕、分割畫面改了寬度）：排版簽章跟著變。
    final narrower = ReaderLayoutSpec.fromViewport(
      viewportSize: _viewport,
      style: ReaderLayoutStyle(
        fontSize: _style.fontSize,
        lineHeight: _style.lineHeight,
        letterSpacing: _style.letterSpacing,
        paragraphSpacing: _style.paragraphSpacing,
        paddingTop: _style.paddingTop,
        paddingBottom: _style.paddingBottom,
        paddingLeft: _style.paddingLeft + 40,
        paddingRight: _style.paddingRight + 40,
        textIndent: _style.textIndent,
      ),
    );
    final applied = runtime.applyPresentation(spec: narrower);
    for (
      var frame = 0;
      frame < 2000 && runtime.stateMachine.currentOperation != null;
      frame++
    ) {
      elapsed += const Duration(milliseconds: 16);
      tick?.call(elapsed);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await applied;
    expect(auto.isRunning, isTrue);
    auto.stop();
    await settle(tester);
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
        initialLocation: const ReaderLocation(
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
        initialLocation: const ReaderLocation(chapterIndex: 1, charOffset: 0),
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

  testWidgets('with the previous chapter unavailable the forward lead is '
      'counted from where the scroll stops', (tester) async {
    await pumpReader(
      tester,
      waitForOpen: false,
      customRuntime: _makeRuntime(
        initialLocation: const ReaderLocation(chapterIndex: 1, charOffset: 0),
        contentLoader: (index, chapter) => index == 0
            ? Future.error(
                const ReaderContentUnavailableException('第 0 章暫時取不到'),
              )
            : Future.value(chapter.content),
      ),
    );
    // 開書一完成就量：之後捲動位置附近的補排會把差距補上。
    for (
      var frame = 0;
      frame < 2000 && !runtime.state.hasStableWorld;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(runtime.state.hasStableWorld, isTrue);
    final position = scrollPosition(tester);
    expect(
      position.pixels,
      position.minScrollExtent,
      reason: '前面沒有正文，章名頂在最上面。',
    );
    expect(
      position.maxScrollExtent - position.pixels,
      greaterThanOrEqualTo(3000),
      reason: '開書完成時，停住的位置之後已經排好一整段領先量。',
    );
  });

  testWidgets('a resize while the text appears restores for the new size', (
    tester,
  ) async {
    // 一章很短的書，從一章往下 120 的位置打開：矮的正文區還捲得到那裡，
    // 變高之後整章不到一屏、捲動只能停在 0。
    tester.view.physicalSize = const Size(400, 100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    runtime = _makeRuntime(
      chapterCount: 1,
      paragraphs: 5,
      initialLocation: const ReaderLocation(
        chapterIndex: 0,
        charOffset: 0,
        visualOffsetPx: 120,
      ),
    );
    final owned = runtime;
    addTearDown(() => _disposeRuntime(owned));
    final outside = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: _RuntimeOwner(
          runtime: runtime,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.outOfRange) {
                outside.add(notification.metrics.pixels);
              }
              return false;
            },
            child: ReaderTextView(
              runtime: runtime,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              style: _style,
              enableDiskCache: false,
              preprocessor: const TextPreprocessor(useIsolate: false),
            ),
          ),
        ),
      ),
    );
    unawaited(runtime.openBook());
    var resized = false;
    for (
      var frame = 0;
      frame < 2000 && !runtime.state.hasStableWorld;
      frame++
    ) {
      // 正文剛在紙底下建好（紙停過預留停頓才掀）：停住的位置已經算好，正文
      // 的捲動位置還沒套上。
      if (!resized &&
          find.byType(LoadingVeil).evaluate().isNotEmpty &&
          find.byType(CustomScrollView).evaluate().isNotEmpty) {
        tester.view.physicalSize = _viewport;
        resized = true;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(resized, isTrue);
    expect(runtime.state.hasStableWorld, isTrue);
    expect(outside, isEmpty, reason: '還原不會跳到捲不到的位置');
    final position = scrollPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
  });

  testWidgets('opened at a chapter start, an unavailable previous chapter is '
      'reported and retried at the top', (tester) async {
    var requests = 0;
    var available = false;
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(
        chapterCount: 2,
        initialLocation: const ReaderLocation(chapterIndex: 1, charOffset: 0),
        contentLoader: (index, chapter) async {
          if (index != 0) return chapter.content;
          requests += 1;
          if (!available) {
            throw const ReaderContentUnavailableException('第 0 章暫時取不到');
          }
          return chapter.content;
        },
      ),
    );
    final position = scrollPosition(tester);
    final afterOpen = requests;
    expect(position.pixels, closeTo(position.minScrollExtent, 0.5));

    available = true;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
    await settle(tester);
    expect(runtime.takeUserNotice()?.message, '第 0 章暫時取不到');
    expect(requests, afterOpen + 1, reason: '停在上緣時重試一次');
    for (var frame = 0; frame < 200; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.minScrollExtent, lessThan(0), reason: '重試成功後前一章接在上面');
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
            throw const ReaderContentUnavailableException('第 1 章暫時取不到');
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
    // 提示帶著取不到的那一章：登入或前往驗證回來後跳過去。
    expect(runtime.takeUserNotice(), (message: '第 1 章暫時取不到', chapterIndex: 1));
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

  testWidgets('paging past the first or last page says the book ends there', (
    tester,
  ) async {
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(chapterCount: 1, paragraphs: 30),
    );
    final position = scrollPosition(tester);
    expect(await viewport.moveToPrevPage!(), isFalse);
    expect(runtime.takeUserNotice()?.message, '已到書首');

    for (var i = 0; i < 5 && position.pixels < position.maxScrollExtent; i++) {
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);
    }
    final turn = viewport.moveToNextPage!();
    await settle(tester);
    expect(await turn, isFalse);
    expect(runtime.takeUserNotice()?.message, '已到書尾');
  });

  testWidgets('speech follow scrolls to laid-out text below the screen', (
    tester,
  ) async {
    // 第 0 章第 40 段：已經排好、在畫面下方。朗讀高亮標在同一段，看它在
    // 畫面上的位置。
    final offset = _chapter(0).content!.indexOf('第 0 章第 40 段');
    await pumpReader(
      tester,
      ttsHighlight: ReaderTtsHighlight(
        chapterIndex: 0,
        sentenceStart: offset,
        sentenceEnd: offset + 4,
      ),
    );
    await tester.pump(SkeletonReveal.defaultDuration);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(LoadingVeil), findsNothing);
    List<LineBox> boxes() => tester
        .widget<TtsHighlightOverlay>(find.byType(TtsHighlightOverlay))
        .sentence;
    expect(boxes(), isNotEmpty, reason: '跟隨前那一段已經排好');
    expect(boxes().first.top, greaterThan(_viewport.height), reason: '在畫面下方');

    final followed = viewport.ensureCharRangeVisible!(
      chapterIndex: 0,
      startCharOffset: offset,
      endCharOffset: offset + 4,
    );
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byType(LoadingVeil),
        findsNothing,
        reason: '排好的範圍裡不蓋紙（第 $frame 幀）',
      );
    }
    expect(await followed, isTrue);
    final after = boxes();
    expect(after, isNotEmpty);
    expect(after.first.top, greaterThanOrEqualTo(0));
    expect(after.last.bottom, lessThanOrEqualTo(_viewport.height));
  });

  testWidgets('paging into a paid chapter jumps past it', (tester) async {
    await pumpReader(
      tester,
      customRuntime: _makeRuntime(
        paragraphs: 20,
        locked: const {1},
        contentLoader: (index, chapter) async {
          if (index == 1) {
            throw const ReaderContentUnavailableException(lockedChapterNotice);
          }
          return chapter.content;
        },
      ),
    );
    final position = scrollPosition(tester);
    for (var i = 0; i < 5 && position.pixels < position.maxScrollExtent; i++) {
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);
    }
    final turn = viewport.moveToNextPage!();
    await settle(tester);
    await settle(tester);
    expect(await turn, isFalse);
    expect(runtime.state.visibleLocation.chapterIndex, 2, reason: '跳過付費的第 1 章');
  });

  testWidgets('the speech highlight follows the text while scrolling', (
    tester,
  ) async {
    await pumpReader(
      tester,
      ttsHighlight: const ReaderTtsHighlight(
        chapterIndex: 0,
        sentenceStart: 10,
        sentenceEnd: 40,
      ),
    );
    List<LineBox> boxes() => tester
        .widget<TtsHighlightOverlay>(find.byType(TtsHighlightOverlay))
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

  testWidgets('a selection drags into the next paragraphs and scrolls past '
      'the bottom edge', (tester) async {
    // 原生斷詞不在，長按只選一個字。
    const segmenter = MethodChannel('com.inkpage.reader/word_segmenter');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      segmenter,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        segmenter,
        null,
      ),
    );
    // 朗讀高亮只拿來找第一段字在畫面上的位置。
    await pumpReader(
      tester,
      textSelectionEnabled: true,
      ttsHighlight: const ReaderTtsHighlight(
        chapterIndex: 0,
        sentenceStart: 10,
        sentenceEnd: 12,
      ),
    );
    await settle(tester);
    final word = tester
        .widget<TtsHighlightOverlay>(find.byType(TtsHighlightOverlay))
        .sentence
        .first;
    final layer = tester.widget<ReaderTextSelectionLayer>(
      find.byType(ReaderTextSelectionLayer),
    );
    final service = layer.selection;
    final height = tester.getSize(find.byType(ReaderTextSelectionLayer)).height;

    // 放開時事件的時間要過了長按門檻，才不會被當成點正文、收掉選取。
    const held = Duration(milliseconds: 600);
    final press = await tester.startGesture(
      Offset((word.left + word.right) / 2, (word.top + word.bottom) / 2),
    );
    await tester.pump(held);
    await press.up(timeStamp: held);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final selected = service.selection;
    expect(selected, isNotNull);
    expect(selected!.text, isNot(contains('\n')));
    final end = layer.paintFor(selected, height).endBox!;

    final gesture = await tester.startGesture(
      Offset(end.right + 8, end.bottom + 12),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();
    final across = service.selection!;
    expect(across.text, contains('\n\n'), reason: '拉到下面幾段');
    expect(across.inParagraphs.pieces.length, greaterThan(1));
    expect(across.range.start, selected.range.start);

    final position = scrollPosition(tester);
    final before = position.pixels;
    await gesture.moveTo(Offset(end.right + 8, height + 15));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, greaterThan(before), reason: '拖出下緣時正文往下捲');
    final scrolled = service.selection!;
    expect(scrolled.range.end, greaterThan(across.range.end));
    expect(scrolled.range.start, selected.range.start);
    expect(layer.paintFor(scrolled, height).endBox, isNotNull);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    final rested = position.pixels;
    await tester.pump(const Duration(milliseconds: 200));
    expect(position.pixels, rested, reason: '放開就停');
    expect(service.selection?.range, scrolled.range, reason: '選取留著');
  });

  testWidgets('dragging past the bottom edge stops scrolling at the end of '
      'the chapter', (tester) async {
    const segmenter = MethodChannel('com.inkpage.reader/word_segmenter');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      segmenter,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        segmenter,
        null,
      ),
    );
    // 一章 30 段，從倒數幾段開始讀；朗讀高亮只拿來找那裡的字。
    const start = 800;
    await pumpReader(
      tester,
      // 章末是兩個單位的字（表情符號）。
      customRuntime: _makeRuntime(
        paragraphs: 30,
        contentLoader: (_, chapter) =>
            Future<String?>.value('${chapter.content}😀'),
        initialLocation: const ReaderLocation(
          chapterIndex: 0,
          charOffset: start,
        ),
      ),
      textSelectionEnabled: true,
      ttsHighlight: const ReaderTtsHighlight(
        chapterIndex: 0,
        sentenceStart: start + 2,
        sentenceEnd: start + 4,
      ),
    );
    await settle(tester);
    final word = tester
        .widget<TtsHighlightOverlay>(find.byType(TtsHighlightOverlay))
        .sentence
        .first;
    final layer = tester.widget<ReaderTextSelectionLayer>(
      find.byType(ReaderTextSelectionLayer),
    );
    final height = tester.getSize(find.byType(ReaderTextSelectionLayer)).height;
    const held = Duration(milliseconds: 600);
    final press = await tester.startGesture(
      Offset((word.left + word.right) / 2, (word.top + word.bottom) / 2),
    );
    await tester.pump(held);
    await press.up(timeStamp: held);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final selected = layer.selection.selection!;
    final end = layer.paintFor(selected, height).endBox!;
    final gesture = await tester.startGesture(
      Offset(end.right + 8, end.bottom + 12),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(Offset(end.right + 8, height + 20));
    final position = scrollPosition(tester);
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final stopped = position.pixels;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, stopped, reason: '章末已經在畫面上，不再捲');
    expect(
      layer.paintFor(layer.selection.selection!, height).chapterEndBelow,
      lessThanOrEqualTo(0),
      reason: '這一章的最後一行整行在畫面上',
    );
    // 手指往右拖到行尾外，選到這一章最後一個字。
    await gesture.moveTo(Offset(390, height + 20));
    await tester.pump();
    expect(
      layer.selection.selection!.range.end,
      ReaderTextSelection.bodyRangeOf(selected.blocks).end,
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('releasing a handle during a page turn lets the turn finish', (
    tester,
  ) async {
    const segmenter = MethodChannel('com.inkpage.reader/word_segmenter');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      segmenter,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        segmenter,
        null,
      ),
    );
    await pumpReader(
      tester,
      textSelectionEnabled: true,
      ttsHighlight: const ReaderTtsHighlight(
        chapterIndex: 0,
        sentenceStart: 10,
        sentenceEnd: 12,
      ),
    );
    await settle(tester);
    final position = scrollPosition(tester);
    final pageDistance = await plainPageDistance(tester);
    position.jumpTo(0);
    await settle(tester);
    final word = tester
        .widget<TtsHighlightOverlay>(find.byType(TtsHighlightOverlay))
        .sentence
        .first;
    final layer = tester.widget<ReaderTextSelectionLayer>(
      find.byType(ReaderTextSelectionLayer),
    );
    final height = tester.getSize(find.byType(ReaderTextSelectionLayer)).height;
    const held = Duration(milliseconds: 600);
    final press = await tester.startGesture(
      Offset((word.left + word.right) / 2, (word.top + word.bottom) / 2),
    );
    await tester.pump(held);
    await press.up(timeStamp: held);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final end = layer.paintFor(layer.selection.selection!, height).endBox!;
    final gesture = await tester.startGesture(
      Offset(end.right + 8, end.bottom + 12),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    // 拖到下緣自動捲一下，再回到中間。
    await gesture.moveTo(Offset(end.right + 8, height - 5));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.moveTo(Offset(end.right + 8, height / 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, greaterThan(0), reason: '自動捲過');

    // 音量鍵翻頁，翻到一半放開把手。
    final start = position.pixels;
    final turn = viewport.moveToNextPage!();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await settle(tester);
    expect(await turn, isTrue);
    expect(position.pixels, closeTo(start + pageDistance, 1));
  });

  testWidgets('a highlight several screens long is drawn on every screen '
      'while scrolling through it', (tester) async {
    final highlights = ValueNotifier<List<ReaderHighlightMark>>(const [
      (
        id: 1,
        location: ReaderLocation(chapterIndex: 0, charOffset: 10),
        length: 2000,
        unanchoredQuote: null,
        color: HighlightColor.amber,
        style: HighlightStyle.fill,
      ),
    ]);
    addTearDown(highlights.dispose);
    await pumpReader(tester, highlights: highlights);
    await settle(tester);
    final position = scrollPosition(tester);
    for (var screen = 0; screen < 8; screen++) {
      final boxes = tester
          .widget<HighlightMarksOverlay>(find.byType(HighlightMarksOverlay))
          .items
          .single
          .boxes;
      final visible = boxes.where((box) => box.bottom > 0 && box.top < 600);
      expect(
        visible.length,
        greaterThan(10),
        reason: '第 $screen 屏每一行都畫著（捲到 ${position.pixels}）',
      );
      position.jumpTo(position.pixels + 550);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
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

  group('手指捲動', () {
    Future<void> flingUp(WidgetTester tester) async {
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -300),
        3000,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(scrollPosition(tester).isScrollingNotifier.value, isTrue);
    }

    testWidgets('a fling saves where it comes to rest', (tester) async {
      await pumpReader(tester);
      await settle(tester);
      final before = runtime.state.visibleLocation;
      _savedProgress = null;

      await flingUp(tester);
      await settle(tester);

      final rest = runtime.state.visibleLocation;
      expect(scrollPosition(tester).isScrollingNotifier.value, isFalse);
      expect((
        rest.chapterIndex,
        rest.charOffset,
      ), isNot((before.chapterIndex, before.charOffset)));
      expect(_savedProgress, (
        chapter: rest.chapterIndex,
        pos: rest.charOffset,
      ));
    });

    testWidgets('a page turn while the fling runs leaves the text to it', (
      tester,
    ) async {
      await pumpReader(tester);
      await settle(tester);
      await flingUp(tester);

      final turn = viewport.moveToNextPage!();
      await settle(tester);
      expect(await turn, isFalse, reason: '甩動中的捲動歸手指，翻頁不接');

      final rest = scrollPosition(tester).pixels;
      final next = viewport.moveToNextPage!();
      await settle(tester);
      expect(await next, isTrue, reason: '停下之後照常翻頁');
      expect(scrollPosition(tester).pixels, greaterThan(rest));
    });

    testWidgets('pulling at the edge keeps the text to the finger', (
      tester,
    ) async {
      await pumpReader(tester);
      await settle(tester);
      final position = scrollPosition(tester);
      expect(position.pixels, closeTo(position.minScrollExtent, 0.5));

      // 書首往下拉：正文不動，手指還按著時翻頁不接。
      final gesture = await tester.startGesture(const Offset(200, 200));
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(position.pixels, closeTo(position.minScrollExtent, 0.5));
      final turn = viewport.moveToNextPage!();
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await settle(tester);
      expect(await turn, isFalse, reason: '手指按著時捲動歸手指');

      final next = viewport.moveToNextPage!();
      await settle(tester);
      expect(await next, isTrue, reason: '放開之後照常翻頁');
    });
  });

  testWidgets('text laid out while the skeleton breathes waits for the '
      'breath to settle before it is built', (tester) async {
    final previous = Completer<String?>();
    final neverLoaded = Completer<String?>();
    await pumpReader(
      tester,
      waitForOpen: false,
      customRuntime: _makeRuntime(
        paragraphs: 400,
        // 第一頁在這一章裡，往前的領先量跨進前一章。
        initialLocation: const ReaderLocation(chapterIndex: 1, charOffset: 600),
        contentLoader: (index, chapter) => switch (index) {
          0 => previous.future,
          1 => Future.value(chapter.content),
          _ => neverLoaded.future,
        },
      ),
    );
    LoadingVeilController veil() =>
        tester.widget<LoadingVeil>(find.byType(LoadingVeil)).controller;
    // 第一頁排好、骨架長完，前一章還沒到：停過 restBeforeBreath 就開始呼吸。
    for (
      var frame = 0;
      frame < 2000 && !(veil().hasSkeleton && !veil().isSkeletonFading);
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(veil().hasSkeleton, isTrue);
    await tester.pump(
      LoadingVeilController.restBeforeBreath +
          const Duration(milliseconds: 200),
    );

    // 前一章很短、幾幀就排好：之後等的是呼吸。
    previous.complete(_chapter(0, paragraphs: 40).content);
    var waited = Duration.zero;
    while (waited < const Duration(seconds: 10) &&
        find.byType(CustomScrollView).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      waited += const Duration(milliseconds: 16);
    }
    expect(find.byType(CustomScrollView), findsOneWidget);
    // 呼吸剛開始 0.2 秒：等這一口呼完、停回最深才建正文，不在半淺時凍住。
    expect(
      waited,
      greaterThanOrEqualTo(
        Skeleton.breathCycle - const Duration(milliseconds: 300),
      ),
    );
    await settle(tester);
    expect(runtime.state.hasStableWorld, isTrue, reason: '開書做完');
    expect(runtime.pendingLocation, isNull);
    final position = scrollPosition(tester);
    expect(
      position.pixels - position.minScrollExtent,
      greaterThan(0),
      reason: '停在第 1 章裡、前一章接在上面',
    );
    expect(runtime.state.visibleLocation.chapterIndex, 1);
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
      _expectSameLines(await linesOnLeaving(tester), veil.lines!);
    });

    testWidgets('opening without a record waits for the first page too', (
      tester,
    ) async {
      await pumpReader(tester, skeletonPages: store, waitForOpen: false);
      expect(veilLines(tester), isNull);
      final veil = await untilVeilLines(tester);
      await untilVeilGone(tester);
      _expectSameLines(await linesOnLeaving(tester), veil.lines!);
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
      _expectSameLines(await linesOnLeaving(tester), veil.lines!);
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
      _expectSameLines(await linesOnLeaving(tester), veil.lines!);
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
      _expectSameLines(await linesOnLeaving(tester), last);
    });

    testWidgets('a layout change during the fade-in measures the page again', (
      tester,
    ) async {
      await pumpReader(tester, skeletonPages: store, waitForOpen: false);
      final first = (await untilVeilLines(tester)).lines!;
      final larger = ReaderLayoutSpec.fromViewport(
        viewportSize: _viewport,
        style: ReaderLayoutStyle(
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
      _expectSameLines(await linesOnLeaving(tester), last);
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
      await _pumpReveal(tester);
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
          initialLocation: const ReaderLocation(chapterIndex: 2, charOffset: 0),
        ),
        skeletonPages: store,
        waitForOpen: false,
      );
      final last = await lastLinesUntilVeilGone(tester);
      _expectSameLines(await linesOnLeaving(tester), last);
    });

    testWidgets('with the previous chapter unavailable the skeleton sits '
        'where the scroll stops', (tester) async {
      await pumpReader(
        tester,
        customRuntime: _makeRuntime(
          initialLocation: const ReaderLocation(chapterIndex: 1, charOffset: 0),
          contentLoader: (index, chapter) => index == 0
              ? Future.error(
                  const ReaderContentUnavailableException('第 0 章暫時取不到'),
                )
              : Future.value(chapter.content),
        ),
        skeletonPages: store,
        waitForOpen: false,
      );
      final last = await lastLinesUntilVeilGone(tester);
      _expectSameLines(await linesOnLeaving(tester), last);
    });
  });
}

/// 紀錄存到小數一位，兩次記下的同一行最多差 0.1。
void _expectSameLines(List<Rect> actual, List<Rect> expected) {
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
