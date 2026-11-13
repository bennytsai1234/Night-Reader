import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/features/comic_reader/comic_strip_model.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';
import 'package:night_reader/features/source_login/source_failure_remedy.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'comic_test_pages.dart';

const _screen = Size(400, 800);

class _Harness {
  _Harness(this.source, {int chapter = 0, int page = 0, int chapters = 5})
    : model = ComicStripModel(
        source: source,
        chapterCount: chapters,
        chapterIndex: chapter,
        pageIndex: page,
      );

  final FakeComicSource source;
  final ComicStripModel model;
  final List<ComicLocation> locations = [];
  final List<ComicTapRegion> taps = [];

  ComicLocation get last => locations.last;

  Future<void> pump(
    WidgetTester tester, {
    SourceFailureRemedy? Function(Object error)? remedyFor,
  }) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicStripView(
            model: model,
            foreground: Colors.black,
            accent: Colors.orange,
            onLocation: locations.add,
            onTap: taps.add,
            titleOf: (i) => '第${i + 1}話',
            gapBetween: (a, b) => 0,
            remedyFor: remedyFor,
          ),
        ),
      ),
    );
    model.start();
    await settle(tester);
  }

  /// 等假來源的非同步工作（讀圖、解碼）與畫面。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
}

double _scrollPixels(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

/// 沒登入時每一話都要登入才讀得到；登入後（[locked] 改成 false）照常給圖。
class _LockedSource extends FakeComicSource {
  bool locked = true;

  @override
  Future<List<ComicPage>> pagesOf(int chapterIndex) async {
    if (locked) {
      requestedChapters.add(chapterIndex);
      throw LoginCheckException('第 $chapterIndex 話需要登入才看得到');
    }
    return super.pagesOf(chapterIndex);
  }
}

void main() {
  test('點擊區域照 Mihon 的 L 形', () {
    const size = Size(300, 900);
    expect(
      comicTapRegionOf(const Offset(250, 100), size),
      ComicTapRegion.previous,
    );
    expect(
      comicTapRegionOf(const Offset(50, 450), size),
      ComicTapRegion.previous,
    );
    expect(comicTapRegionOf(const Offset(150, 450), size), ComicTapRegion.menu);
    expect(comicTapRegionOf(const Offset(250, 450), size), ComicTapRegion.next);
    expect(comicTapRegionOf(const Offset(50, 800), size), ComicTapRegion.next);
  });

  testWidgets('開在錨點那一張，往下捲接上下一話，換章分隔寫兩話章名', (tester) async {
    final harness = _Harness(
      FakeComicSource(pagesPerChapter: 3),
      chapter: 1,
      page: 2,
    );
    await harness.pump(tester);

    expect(harness.last, const ComicLocation(1, 2));
    // 圖都到了、淡入播完：骨架拿掉，不再呼吸重畫。
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('已閱畢：'), findsOneWidget);
    expect(find.text('第2話'), findsOneWidget);
    expect(find.text('第3話'), findsOneWidget);
    // 錨點那一話放上去後，先拿前後各兩話（下一話先、上一話後）。
    expect(harness.source.requestedChapters, [1, 2, 0, 3]);

    await tester.drag(find.byType(ComicStripView), const Offset(0, -1200));
    await harness.settle(tester);
    expect(harness.last.chapterIndex, 2);
  });

  testWidgets('第一話上面寫已達盡頭，往上捲到也不會再要上一話', (tester) async {
    final harness = _Harness(FakeComicSource(pagesPerChapter: 2));
    await harness.pump(tester);
    await tester.drag(find.byType(ComicStripView), const Offset(0, 700));
    await harness.settle(tester);
    expect(find.text('已達盡頭'), findsOneWidget);
    expect(find.text('這一章：'), findsOneWidget);
    expect(harness.source.requestedChapters, isNot(contains(-1)));
  });

  testWidgets('這一話抓不到時寫原因，重試後照常顯示', (tester) async {
    final source = FakeComicSource()..failingChapters.add(0);
    final harness = _Harness(source);
    await harness.pump(tester);
    expect(find.textContaining('第 0 話抓不到'), findsOneWidget);

    source.failingChapters.clear();
    await tester.tap(find.text('重試'));
    await harness.settle(tester);
    expect(find.textContaining('抓不到'), findsNothing);
    expect(harness.last, const ComicLocation(0, 0));
  });

  testWidgets('要登入才讀得到的一話：給「登入」排在「重試」前面，登入後重抓', (tester) async {
    final source = _LockedSource();
    var runs = 0;
    final harness = _Harness(source);
    await harness.pump(
      tester,
      remedyFor: (error) => SourceFailureRemedy(
        label: '登入',
        icon: Icons.login_rounded,
        run: (context) async {
          runs += 1;
          source.locked = false;
          return true;
        },
      ),
    );
    expect(find.text('登入'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
    expect(
      tester.getCenter(find.text('登入')).dx,
      lessThan(tester.getCenter(find.text('重試')).dx),
    );

    await tester.tap(find.text('登入'));
    await harness.settle(tester);
    expect(runs, 1);
    // 重抓錨點那一話，放上去後先拿後面兩話。
    expect(source.requestedChapters, [0, 0, 1, 2]);
    expect(harness.last, const ComicLocation(0, 0));
  });

  testWidgets('點一下回報點擊區域；慣性滑動中按下去只停下來', (tester) async {
    final harness = _Harness(FakeComicSource());
    await harness.pump(tester);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(200, 750));
    await tester.pump(const Duration(milliseconds: 400));
    expect(harness.taps, [ComicTapRegion.menu, ComicTapRegion.next]);

    await tester.fling(
      find.byType(ComicStripView),
      const Offset(0, -300),
      3000,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(harness.taps, hasLength(2));
  });

  testWidgets('上面那張圖晚到、高度變了，畫面頂端看到的內容不動', (tester) async {
    final source = FakeComicSource(knownSizes: false, height: 120)
      ..pageGates[(0, 0)] = Completer<void>();
    final harness = _Harness(source);
    await harness.pump(tester);

    await tester.drag(find.byType(ComicStripView), const Offset(0, -300));
    await harness.settle(tester);
    final before = _scrollPixels(tester);
    final location = harness.last;

    // 第一張的圖到了：比例 2.0，比骨架的 1.42 高。
    source.pageGates[(0, 0)]!.complete();
    await harness.settle(tester);
    final grew = 400 * (2.0 - ComicStripModel.defaultAspectRatio);
    expect(_scrollPixels(tester), closeTo(before + grew, 0.5));
    expect(harness.last.pageIndex, location.pageIndex);
  });

  testWidgets('點兩下放大到兩倍、再點兩下回到原本大小', (tester) async {
    final harness = _Harness(FakeComicSource());
    await harness.pump(tester);
    Matrix4 transform() => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(ComicStripView),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform;
    // 縮放動畫 200ms，一幀一幀推完。
    Future<void> zoomFrames() async {
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.tapAt(const Offset(100, 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(100, 400));
    await zoomFrames();
    expect(transform().getMaxScaleOnAxis(), closeTo(2, 0.001));
    // 點的位置留在原處：x = 100 的內容放大後還在 100。
    expect(transform().getTranslation().x, closeTo(-100, 0.5));

    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 400));
    await zoomFrames();
    expect(transform().getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(harness.taps, isEmpty);
  });
}
