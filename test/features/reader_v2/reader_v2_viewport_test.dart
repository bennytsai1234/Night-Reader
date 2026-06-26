import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_controller.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_layer.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_viewport.dart';
import 'package:night_reader/features/reader_v2/viewport/slide_reader_v2_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scroll viewport syncs to runtime location changes', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 3,
      paragraphsPerChapter: 18,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    expect(runtime.captureVisibleLocation()?.chapterIndex, 0);

    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 1, charOffset: 24),
      immediateSave: false,
    );
    await _pumpViewport(tester);

    expect(runtime.captureVisibleLocation()?.chapterIndex, 1);

    runtime.dispose();
  });

  testWidgets('scroll viewport top-aligns chapter jumps', (tester) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 3,
      paragraphsPerChapter: 1,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    await runtime.jumpToChapter(1);
    await _pumpViewportCommand(tester);

    final targetTile = find.byWidgetPredicate(
      (widget) =>
          widget is ReaderV2TileLayer &&
          widget.tile.chapterIndex == 1 &&
          widget.tile.pageIndex == 0,
    );
    expect(targetTile, findsOneWidget);
    expect(tester.getTopLeft(targetTile).dy, closeTo(0, 0.001));
    expect(runtime.state.visibleLocation.chapterIndex, 1);
    expect(runtime.state.visibleLocation.charOffset, 0);

    runtime.dispose();
  });

  testWidgets(
    'scroll viewport keeps a far chapter jump ahead of pending old captures',
    (tester) async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 12,
        paragraphsPerChapter: 80,
      );
      final controller = ReaderV2ViewportController();
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 260,
            height: 360,
            child: ScrollReaderV2Viewport(
              runtime: runtime,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              style: _style(),
              controller: controller,
            ),
          ),
        ),
      );
      await _pumpViewport(tester);

      await controller.continuousScrollBy!(220);
      await runtime.jumpToChapter(8);
      await _pumpViewportCommand(tester);

      final targetTile = find.byWidgetPredicate(
        (widget) =>
            widget is ReaderV2TileLayer &&
            widget.tile.chapterIndex == 8 &&
            widget.tile.pageIndex == 0,
      );
      final visibleTileLabels =
          find.byType(ReaderV2TileLayer).evaluate().map((element) {
            final tile = (element.widget as ReaderV2TileLayer).tile;
            return '${tile.chapterIndex}:${tile.pageIndex}';
          }).toList();
      expect(
        targetTile,
        findsOneWidget,
        reason:
            'state=${runtime.state.visibleLocation}; '
            'visibleTiles=$visibleTileLabels',
      );
      expect(
        tester.getTopLeft(targetTile).dy,
        closeTo(0, 0.001),
        reason:
            'state=${runtime.state.visibleLocation}; '
            'visibleTiles=$visibleTileLabels',
      );
      expect(runtime.state.visibleLocation.chapterIndex, 8);
      expect(runtime.state.visibleLocation.charOffset, 0);
      expect(runtime.captureVisibleLocation()?.chapterIndex, 8);

      runtime.dispose();
    },
  );

  testWidgets(
    'scroll viewport ensureCharRangeVisible accepts visible TTS range',
    (tester) async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 2,
        paragraphsPerChapter: 12,
      );
      final controller = ReaderV2ViewportController();
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 260,
            height: 360,
            child: ScrollReaderV2Viewport(
              runtime: runtime,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              style: _style(),
              controller: controller,
            ),
          ),
        ),
      );
      await _pumpViewport(tester);

      final ensureVisible = controller.ensureCharRangeVisible;
      expect(ensureVisible, isNotNull);
      final captured = runtime.captureVisibleLocation();
      expect(captured, isNotNull);
      final visible = await ensureVisible!(
        chapterIndex: captured!.chapterIndex,
        startCharOffset: captured.charOffset,
        endCharOffset: captured.charOffset + 6,
      );

      expect(visible, isTrue);

      runtime.dispose();
    },
  );

  testWidgets('scroll viewport keeps TTS range in the upper safe area', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 1,
      paragraphsPerChapter: 24,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final content = await runtime.loadContentAt(0);
    final targetOffset = (content.displayText.length * 0.55).round();
    final movedFuture = controller.ensureCharRangeVisible!(
      chapterIndex: 0,
      startCharOffset: targetOffset,
      endCharOffset: targetOffset + 4,
    );
    await _pumpViewportLongCommand(tester);
    final moved = await movedFuture;
    final targetRect = _lineRectForCharOffset(tester, 0, targetOffset);

    expect(moved, isTrue);
    expect(targetRect, isNotNull);
    expect(targetRect!.top, greaterThanOrEqualTo(48));
    expect(targetRect.top, lessThanOrEqualTo(166));
    expect(targetRect.bottom, lessThanOrEqualTo(288));

    runtime.dispose();
  });

  test(
    'scroll cache window covers adjacent extent beyond center chapter',
    () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 8,
        paragraphsPerChapter: 2,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 2, charOffset: 0),
        immediateSave: false,
      );
      final manager = ReaderV2ChapterPageCacheManager(
        runtime: runtime,
        pageExtent: (page) => page.height,
      );
      final center = await manager.ensureChapter(2);
      expect(center, isNotNull);

      final window = await manager.ensureWindowAround(
        centerChapterIndex: 2,
        backwardExtent: center!.extent * 1.5,
        forwardExtent: center.extent * 2.5,
      );

      expect(window, isNotNull);
      expect(window!.previous.length, greaterThanOrEqualTo(2));
      expect(window.next.length, greaterThanOrEqualTo(3));

      runtime.dispose();
    },
  );

  test('scroll cache keeps page boundaries continuous', () async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(1));

    final manager = ReaderV2ChapterPageCacheManager(
      runtime: runtime,
      pageExtent: _visiblePageContentExtent,
    );
    final chapter = await manager.ensureChapter(0);
    expect(chapter, isNotNull);

    final pages = chapter!.pages;
    for (var index = 0; index < pages.length - 1; index++) {
      final current = pages[index];
      final next = pages[index + 1];
      final expectedGap = next.localStartY - current.localStartY;

      expect(chapter.pageOffsetTop(index), closeTo(current.localStartY, 0.001));
      expect(chapter.pageExtentAt(index), closeTo(expectedGap, 0.001));
      expect(
        chapter.pageOffsetTop(index + 1),
        closeTo(next.localStartY, 0.001),
      );
    }

    runtime.dispose();
  });

  testWidgets('scroll viewport exposes line-aware page commands', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    expect(controller.moveToNextPage, isNotNull);
    expect(controller.moveToPrevPage, isNotNull);
    final start = runtime.captureVisibleLocation();
    expect(start, isNotNull);

    final next = controller.moveToNextPage!();
    await _pumpViewportCommand(tester);
    expect(await next, isTrue);
    final afterNext = runtime.captureVisibleLocation();
    expect(afterNext, isNotNull);
    expect(afterNext!.charOffset, greaterThan(start!.charOffset));

    final prev = controller.moveToPrevPage!();
    await _pumpViewportCommand(tester);
    expect(await prev, isTrue);
    final afterPrev = runtime.captureVisibleLocation();
    expect(afterPrev, isNotNull);
    expect(afterPrev!.charOffset, lessThan(afterNext.charOffset));

    runtime.dispose();
  });

  testWidgets('scroll viewport handles tap and vertical drag in one layer', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 2,
      paragraphsPerChapter: 80,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    var tapCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            onTapUp: (_) => tapCalls += 1,
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final center = tester.getCenter(find.byType(ScrollReaderV2Viewport));
    await tester.tapAt(center);
    await tester.pump();

    expect(tapCalls, 1);

    final tapGesture = await tester.startGesture(center);
    await tapGesture.moveBy(const Offset(4, 3));
    await tapGesture.up();
    await tester.pump();

    expect(tapCalls, 1);

    final firstTile = find.byType(ReaderV2TileLayer).first;
    final startTop = tester.getTopLeft(firstTile).dy;
    final dragGesture = await tester.startGesture(center);
    await dragGesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await dragGesture.moveBy(const Offset(0, -96));
    await tester.pump();

    expect(tester.getTopLeft(firstTile).dy, lessThan(startTop));

    await dragGesture.up();
    await _pumpViewportCommand(tester);

    expect(tapCalls, 1);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets(
    'scroll viewport tap holds animated position without tap action',
    (tester) async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 1,
        paragraphsPerChapter: 80,
      );
      final controller = ReaderV2ViewportController();
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      var tapCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 260,
            height: 360,
            child: ScrollReaderV2Viewport(
              runtime: runtime,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              style: _style(),
              onTapUp: (_) => tapCalls += 1,
              controller: controller,
            ),
          ),
        ),
      );
      await _pumpViewport(tester);

      final firstTile = find.byType(ReaderV2TileLayer).first;
      final startTop = tester.getTopLeft(firstTile).dy;
      await tester.fling(
        find.byType(ScrollReaderV2Viewport),
        const Offset(0, -260),
        3000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));

      final movingTop = tester.getTopLeft(firstTile).dy;
      expect(movingTop, lessThan(startTop));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ScrollReaderV2Viewport)),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final heldTop = tester.getTopLeft(firstTile).dy;
      expect(heldTop, closeTo(movingTop, 0.001));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(tapCalls, 0);
      expect(tester.getTopLeft(firstTile).dy, closeTo(heldTop, 0.001));
      expect(tester.takeException(), isNull);

      runtime.dispose();
    },
  );

  testWidgets('scroll viewport rubber-bands when dragged beyond book start', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 2,
      paragraphsPerChapter: 80,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final firstTile = find.byType(ReaderV2TileLayer).first;
    expect(tester.getTopLeft(firstTile).dy, closeTo(0, 0.001));
    final locationBeforeDrag = runtime.state.visibleLocation;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollReaderV2Viewport)),
    );
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();

    expect(tester.getTopLeft(firstTile).dy, greaterThan(0));

    await gesture.up();
    await _pumpViewportCommand(tester);

    expect(tester.getTopLeft(firstTile).dy, closeTo(0, 0.001));
    expect(runtime.state.visibleLocation, locationBeforeDrag);
    expect(runtime.captureVisibleLocation()?.chapterIndex, 0);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('scroll viewport rubber-bands when dragged beyond book end', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    expect(await controller.scrollBy!(100000), isTrue);
    await _pumpViewport(tester);

    final firstVisibleTile = find.byType(ReaderV2TileLayer).first;
    final bottomTileTop = tester.getTopLeft(firstVisibleTile).dy;
    final locationBeforeDrag = runtime.state.visibleLocation;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollReaderV2Viewport)),
    );
    await gesture.moveBy(const Offset(0, -160));
    await tester.pump();

    expect(tester.getTopLeft(firstVisibleTile).dy, lessThan(bottomTileTop));

    await gesture.up();
    await _pumpViewportCommand(tester);

    expect(
      tester.getTopLeft(firstVisibleTile).dy,
      closeTo(bottomTileTop, 0.001),
    );
    expect(runtime.state.visibleLocation, locationBeforeDrag);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('scroll viewport moves continuously from book start', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 2,
      paragraphsPerChapter: 80,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final firstTile = find.byType(ReaderV2TileLayer).first;
    expect(tester.getTopLeft(firstTile).dy, closeTo(0, 0.001));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollReaderV2Viewport)),
    );
    await gesture.moveBy(const Offset(0, -160));
    await tester.pump();

    expect(tester.getTopLeft(firstTile).dy, closeTo(-160, 0.001));

    await gesture.up();
    await _pumpViewportCommand(tester);

    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets(
    'scroll viewport reports small drags through the same live path',
    (tester) async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 2,
        paragraphsPerChapter: 80,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 260,
            height: 360,
            child: ScrollReaderV2Viewport(
              runtime: runtime,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              style: _style(),
              controller: ReaderV2ViewportController(),
            ),
          ),
        ),
      );
      await _pumpViewport(tester);

      var notifyCount = 0;
      void listener() {
        notifyCount += 1;
      }

      runtime.addListener(listener);
      final firstTile = find.byType(ReaderV2TileLayer).first;
      final startTop = tester.getTopLeft(firstTile).dy;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ScrollReaderV2Viewport)),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 700));
        await gesture.moveBy(const Offset(0, -24));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.getTopLeft(firstTile).dy, closeTo(startTop - 72, 0.001));
      expect(notifyCount, greaterThan(0));

      await gesture.up();
      await _pumpViewportCommand(tester);

      expect(tester.getTopLeft(firstTile).dy, closeTo(startTop - 72, 0.001));
      expect(tester.takeException(), isNull);

      runtime.removeListener(listener);
      runtime.dispose();
    },
  );

  testWidgets('scroll viewport keeps short drags pixel-continuous', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 2,
      paragraphsPerChapter: 80,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final firstTile = find.byType(ReaderV2TileLayer).first;
    final startTop = tester.getTopLeft(firstTile).dy;
    final startLocation = runtime.captureVisibleLocation();
    expect(startLocation, isNotNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollReaderV2Viewport)),
    );
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump();
      expect(
        tester.getTopLeft(firstTile).dy,
        closeTo(startTop - (12.0 * (i + 1)), 0.001),
      );
    }

    await gesture.up();
    await _pumpViewportCommand(tester);

    expect(tester.getTopLeft(firstTile).dy, closeTo(startTop - 48, 0.001));
    expect(runtime.captureVisibleLocation(), isNotNull);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('scroll viewport reports visible page before drag settles', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(1));
    final startPageIndex =
        layout
            .pageForCharOffset(runtime.state.visibleLocation.charOffset)
            .pageIndex;

    var notifyCount = 0;
    ReaderV2Location? notifiedLocation;
    void listener() {
      notifyCount += 1;
      notifiedLocation = runtime.state.visibleLocation;
    }

    runtime.addListener(listener);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollReaderV2Viewport)),
    );
    await gesture.moveBy(const Offset(0, -420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(notifyCount, greaterThan(0));
    expect(notifiedLocation, isNotNull);
    final notifiedPageIndex =
        layout.pageForCharOffset(notifiedLocation!.charOffset).pageIndex;
    expect(notifiedPageIndex, greaterThan(startPageIndex));

    await gesture.up();
    await _pumpViewportCommand(tester);
    runtime.removeListener(listener);
    runtime.dispose();
  });

  testWidgets('scroll viewport survives a fast multi-page jump', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 12,
      paragraphsPerChapter: 3,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final moved = await controller.scrollBy!(360 * 8);
    await _pumpViewport(tester);

    expect(moved, isTrue);
    expect(tester.takeException(), isNull);
    expect(runtime.captureVisibleLocation(), isNotNull);

    runtime.dispose();
  });

  testWidgets('scroll viewport expands window during large continuous scroll', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 24,
      paragraphsPerChapter: 4,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final moved = await controller.scrollBy!(360 * 18);
    await _pumpViewportCommand(tester);
    final location = runtime.captureVisibleLocation();

    expect(moved, isTrue);
    expect(location, isNotNull);
    expect(location!.chapterIndex, greaterThan(8));
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('scroll viewport expands window during smooth animation', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 24,
      paragraphsPerChapter: 4,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: ScrollReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final movedFuture = controller.animateBy!(360 * 18);
    await _pumpViewportLongCommand(tester);
    final moved = await movedFuture;
    final location = runtime.captureVisibleLocation();

    expect(moved, isTrue);
    expect(location, isNotNull);
    expect(location!.chapterIndex, greaterThan(8));
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('slide viewport ensureCharRangeVisible animates to TTS page', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 3,
      paragraphsPerChapter: 10,
    );
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final ensureVisible = controller.ensureCharRangeVisible;
    expect(ensureVisible, isNotNull);
    final targetPage = runtime.state.pageWindow?.next;
    expect(targetPage, isNotNull);
    expect(targetPage!.isPlaceholder, isFalse);
    final initialPageStart = runtime.state.pageWindow?.current.startCharOffset;
    final movedFuture = ensureVisible!(
      chapterIndex: targetPage.chapterIndex,
      startCharOffset: targetPage.startCharOffset,
      endCharOffset: targetPage.startCharOffset + 8,
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(runtime.state.pageWindow?.current.startCharOffset, initialPageStart);

    await _pumpViewportLongCommand(tester);
    final moved = await movedFuture;

    expect(moved, isTrue);
    expect(
      runtime.state.pageWindow?.current.chapterIndex,
      targetPage.chapterIndex,
    );
    expect(
      runtime.state.pageWindow?.current.startCharOffset,
      targetPage.startCharOffset,
    );

    runtime.dispose();
  });

  testWidgets('slide viewport syncs to runtime location changes', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 3,
      paragraphsPerChapter: 10,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 2, charOffset: 12),
      immediateSave: false,
    );
    await _pumpViewport(tester);

    expect(runtime.captureVisibleLocation()?.chapterIndex, 2);

    runtime.dispose();
  });

  testWidgets('slide viewport handles tap and horizontal drag in one layer', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(1));
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    var tapCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            onTapUp: (_) => tapCalls += 1,
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final center = tester.getCenter(find.byType(SlideReaderV2Viewport));
    await tester.tapAt(center);
    await tester.pump();

    expect(tapCalls, 1);

    final tapGesture = await tester.startGesture(center);
    await tapGesture.moveBy(const Offset(4, 3));
    await tapGesture.up();
    await tester.pump();

    expect(tapCalls, 1);

    final currentTile = find.byType(ReaderV2TileLayer).first;
    expect(tester.getTopLeft(currentTile).dx, closeTo(0, 0.001));

    final dragGesture = await tester.startGesture(center);
    await dragGesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await dragGesture.moveBy(const Offset(-96, 0));
    await tester.pump();

    expect(tester.getTopLeft(currentTile).dx, lessThan(0));

    await dragGesture.up();
    await _pumpViewportCommand(tester);

    expect(tapCalls, 1);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('slide viewport accepts page commands after manual drag settles', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(2));
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final center = tester.getCenter(find.byType(SlideReaderV2Viewport));
    final dragGesture = await tester.startGesture(center);
    await dragGesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await dragGesture.moveBy(const Offset(-96, 0));
    await tester.pump();
    await dragGesture.up();
    await _pumpViewportCommand(tester);

    final pageAfterDrag = runtime.state.pageWindow?.current.pageIndex;
    expect(pageAfterDrag, isNotNull);

    var commandCompleted = false;
    bool? commandResult;
    unawaited(
      controller.moveToNextPage!().then((result) {
        commandCompleted = true;
        commandResult = result;
      }),
    );
    await _pumpViewportCommand(tester);
    await _flushMicrotasks();

    expect(commandCompleted, isTrue);
    expect(commandResult, isTrue);
    expect(runtime.state.pageWindow?.current.pageIndex, pageAfterDrag! + 1);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('slide viewport suppresses tap while page animation is active', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(1));
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    var tapCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            onTapUp: (_) => tapCalls += 1,
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final animation = controller.moveToNextPage!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SlideReaderV2Viewport)),
    );
    await gesture.up();
    await tester.pump();

    expect(tapCalls, 0);

    await _pumpViewportCommand(tester);
    expect(await animation, isTrue);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('slide viewport ignores mostly vertical swipes at book start', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(1));
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final currentTile = find.byType(ReaderV2TileLayer).first;
    expect(tester.getTopLeft(currentTile).dx, closeTo(0, 0.001));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SlideReaderV2Viewport)),
    );
    await gesture.moveBy(const Offset(-28, -180));
    await tester.pump();

    expect(tester.getTopLeft(currentTile).dx, closeTo(0, 0.001));

    await gesture.up();
    await _pumpViewportCommand(tester);

    expect(runtime.state.pageWindow?.current.pageIndex, 0);
    expect(tester.takeException(), isNull);

    runtime.dispose();
  });

  testWidgets('slide viewport records full-screen loading samples', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 2,
      paragraphsPerChapter: 6,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final snapshot = runtime.performanceSnapshot;
    expect(snapshot.fullScreenLoadingSampleCount, greaterThan(0));

    runtime.dispose();
  });

  testWidgets('slide viewport records placeholder exposure samples', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 2,
      paragraphsPerChapter: 1,
      failingChapters: <int>{1},
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    runtime.clearPerformanceMetrics();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    expect(runtime.state.pageWindow?.next?.isPlaceholder, isTrue);
    final snapshot = runtime.performanceSnapshot;
    expect(snapshot.slidePlaceholderSampleCount, greaterThan(0));
    expect(snapshot.slidePlaceholderExposureCount, greaterThan(0));

    runtime.dispose();
  });

  testWidgets('slide viewport shows placeholders at book edges', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 1,
      paragraphsPerChapter: 1,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: ReaderV2ViewportController(),
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    expect(find.text('已經是第一頁'), findsOneWidget);
    expect(find.text('已經是最後一頁'), findsOneWidget);

    runtime.dispose();
  });

  testWidgets('slide jump keeps current page when neighbor chapter fails', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 2,
      paragraphsPerChapter: 1,
      failingChapters: <int>{1},
    );

    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    expect(runtime.state.phase, ReaderV2Phase.ready);
    expect(runtime.state.pageWindow?.current.chapterIndex, 0);
    expect(runtime.state.pageWindow?.next?.chapterIndex, 1);
    expect(runtime.state.pageWindow?.next?.isPlaceholder, isTrue);

    runtime.dispose();
  });

  testWidgets('slide neighbor warmup refreshes chapter boundary placeholder', (
    tester,
  ) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 2,
      paragraphsPerChapter: 20,
    );
    final firstLayout = await runtime.debugResolver.ensureLayout(0);
    final lastPage = firstLayout.pages.last;

    await runtime.jumpToLocation(
      ReaderV2Location(chapterIndex: 0, charOffset: lastPage.startCharOffset),
      immediateSave: false,
    );

    expect(runtime.state.pageWindow?.current.isChapterEnd, isTrue);
    expect(runtime.state.pageWindow?.next?.isPlaceholder, isTrue);

    runtime.preloadSlideNeighbor(forward: true);
    for (var i = 0; i < 10; i++) {
      if (runtime.state.pageWindow?.next?.isPlaceholder == false) break;
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(runtime.state.pageWindow?.next?.chapterIndex, 1);
    expect(runtime.state.pageWindow?.next?.isPlaceholder, isFalse);

    runtime.dispose();
  });

  testWidgets('slide viewport serializes rapid page commands', (tester) async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 1,
      paragraphsPerChapter: 80,
    );
    final layout = await runtime.debugResolver.ensureLayout(0);
    expect(layout.pages.length, greaterThan(2));
    final controller = ReaderV2ViewportController();
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 360,
          child: SlideReaderV2Viewport(
            runtime: runtime,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            style: _style(),
            controller: controller,
          ),
        ),
      ),
    );
    await _pumpViewport(tester);

    final first = controller.moveToNextPage!();
    final second = controller.moveToNextPage!();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(runtime.state.pageWindow?.current.pageIndex, 2);

    runtime.dispose();
  });

  test(
    'auto page uses continuous scroll steps and ignores overlapping ticks',
    () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 2,
        paragraphsPerChapter: 20,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      final gate = Completer<bool>();
      var animateCalls = 0;
      var scrollCalls = 0;
      final viewportController =
          ReaderV2ViewportController()
            ..continuousScrollBy = (delta) {
              scrollCalls += 1;
              expect(delta, closeTo(1.024, 0.01));
              return gate.future;
            }
            ..animateBy = (delta) async {
              animateCalls += 1;
              return true;
            };
      final autoPage = ReaderV2AutoPageController(
        runtime: runtime,
        viewportController: viewportController,
        viewportExtent: () => 400,
        autoPageSpeed: () => 0.16,
      );

      final first = autoPage.stepAsync();
      final second = await autoPage.stepAsync();
      expect(second, isFalse);
      expect(scrollCalls, 1);
      expect(animateCalls, 0);

      gate.complete(true);
      expect(await first, isTrue);

      autoPage.dispose();
      runtime.dispose();
    },
  );

  test('auto page starts timer and waits for the scheduled tick', () async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 2,
      paragraphsPerChapter: 20,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    late _FakeTimer fakeTimer;
    var pageCommands = 0;
    final viewportController =
        ReaderV2ViewportController()
          ..moveToNextPage = () async {
            pageCommands += 1;
            return true;
          };
    final autoPage = ReaderV2AutoPageController(
      runtime: runtime,
      viewportController: viewportController,
      timerFactory: (_, onTick) => fakeTimer = _FakeTimer(onTick),
    );

    autoPage.start();
    await Future<void>.delayed(Duration.zero);

    expect(autoPage.isRunning, isTrue);
    expect(fakeTimer.isActive, isTrue);
    expect(pageCommands, 0);

    fakeTimer.tickNow();
    await Future<void>.delayed(Duration.zero);

    expect(pageCommands, 1);

    autoPage.dispose();
    runtime.dispose();
  });

  test(
    'auto page rebuilds timer when runtime mode changes while running',
    () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.slide,
        chapterCount: 2,
        paragraphsPerChapter: 20,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      final intervals = <Duration>[];
      final timers = <_FakeTimer>[];
      final autoPage = ReaderV2AutoPageController(
        runtime: runtime,
        scrollInterval: const Duration(milliseconds: 16),
        pageInterval: const Duration(seconds: 8),
        timerFactory: (interval, onTick) {
          intervals.add(interval);
          final timer = _FakeTimer(onTick);
          timers.add(timer);
          return timer;
        },
      );

      autoPage.start();

      expect(intervals, const <Duration>[Duration(seconds: 8)]);
      expect(timers.single.isActive, isTrue);

      await runtime.applyPresentation(
        spec: runtime.state.layoutSpec,
        mode: ReaderV2Mode.scroll,
      );

      expect(intervals, const <Duration>[
        Duration(seconds: 8),
        Duration(milliseconds: 16),
      ]);
      expect(timers[0].isActive, isFalse);
      expect(timers[1].isActive, isTrue);
      expect(autoPage.isRunning, isTrue);

      await runtime.applyPresentation(
        spec: runtime.state.layoutSpec,
        mode: ReaderV2Mode.slide,
      );

      expect(intervals, const <Duration>[
        Duration(seconds: 8),
        Duration(milliseconds: 16),
        Duration(seconds: 8),
      ]);
      expect(timers[1].isActive, isFalse);
      expect(timers[2].isActive, isTrue);

      autoPage.dispose();
      runtime.dispose();
    },
  );

  test('auto page falls back when continuous scroll cannot advance', () async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 2,
      paragraphsPerChapter: 20,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    var animateCalls = 0;
    var scrollCalls = 0;
    final viewportController =
        ReaderV2ViewportController()
          ..scrollBy = (delta) async {
            scrollCalls += 1;
            return false;
          }
          ..animateBy = (delta) async {
            animateCalls += 1;
            return true;
          };
    final autoPage = ReaderV2AutoPageController(
      runtime: runtime,
      viewportController: viewportController,
      viewportExtent: () => 400,
    );

    expect(await autoPage.stepAsync(), isTrue);
    expect(scrollCalls, 1);
    expect(animateCalls, 1);

    autoPage.dispose();
    runtime.dispose();
  });

  test('auto page uses slide moveToNextPage command', () async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.slide,
      chapterCount: 2,
      paragraphsPerChapter: 20,
    );
    await runtime.jumpToLocation(
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      immediateSave: false,
    );
    var pageCommands = 0;
    final viewportController =
        ReaderV2ViewportController()
          ..moveToNextPage = () async {
            pageCommands += 1;
            return true;
          };
    final autoPage = ReaderV2AutoPageController(
      runtime: runtime,
      viewportController: viewportController,
    );

    expect(await autoPage.stepAsync(), isTrue);
    expect(pageCommands, 1);

    autoPage.dispose();
    runtime.dispose();
  });

  test(
    'tts starts from visible location and supports pause resume stop',
    () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 1,
        paragraphsPerChapter: 4,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      final engine = _FakeTtsEngine();
      final tts = ReaderV2TtsController(runtime: runtime, tts: engine);

      await tts.startFromVisibleLocation();
      expect(engine.speakCount, 1);
      expect(engine.currentSpokenText, isNotEmpty);
      expect(tts.isPlaying, isTrue);
      expect(tts.speechStartLocation?.chapterIndex, 0);
      expect(tts.currentHighlight?.chapterIndex, 0);
      expect(tts.currentHighlight?.highlightStart, 0);
      expect(tts.currentHighlight?.highlightEnd, greaterThan(0));

      engine.emitProgress(2, 5);
      expect(tts.currentHighlight?.highlightStart, 2);
      expect(tts.currentHighlight?.highlightEnd, 5);

      await tts.toggle();
      expect(engine.pauseCount, 1);
      expect(tts.isPlaying, isFalse);

      await tts.toggle();
      expect(engine.resumeCount, 1);
      expect(tts.isPlaying, isTrue);

      await tts.stop();
      expect(tts.speechStartLocation, isNull);
      expect(tts.currentHighlight, isNull);

      tts.dispose();
      runtime.dispose();
    },
  );

  test('tts trims start offset so highlight matches spoken text', () async {
    final runtime = _runtime(
      initialMode: ReaderV2Mode.scroll,
      chapterCount: 1,
      paragraphsPerChapter: 4,
    );
    final content = await runtime.loadContentAt(0);
    final bodyStart = content.displayText.indexOf('這是');
    await runtime.jumpToLocation(
      ReaderV2Location(chapterIndex: 0, charOffset: content.title.length),
      immediateSave: false,
    );
    final engine = _FakeTtsEngine();
    final tts = ReaderV2TtsController(runtime: runtime, tts: engine);

    await tts.startFromVisibleLocation();
    expect(engine.currentSpokenText.startsWith('這是'), isTrue);
    expect(tts.speechStartLocation?.charOffset, bodyStart);

    engine.emitProgress(0, 2);
    expect(tts.currentHighlight?.highlightStart, bodyStart);
    expect(tts.currentHighlight?.highlightEnd, bodyStart + 2);

    tts.dispose();
    runtime.dispose();
  });

  test(
    'tts highlights current segment when engine emits no progress',
    () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 1,
        paragraphsPerChapter: 4,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      final engine = _FakeTtsEngine();
      final tts = ReaderV2TtsController(runtime: runtime, tts: engine);

      await tts.startFromVisibleLocation();

      final highlight = tts.currentHighlight;
      expect(engine.currentWordStart, -1);
      expect(highlight, isNotNull);
      expect(highlight!.chapterIndex, 0);
      expect(highlight.highlightStart, tts.speechStartLocation?.charOffset);
      expect(
        highlight.highlightEnd,
        tts.speechStartLocation!.charOffset + engine.currentSpokenText.length,
      );

      tts.dispose();
      runtime.dispose();
    },
  );

  test(
    'tts completion continues with next chapter and clears at book end',
    () async {
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        chapterCount: 2,
        paragraphsPerChapter: 4,
      );
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      final engine = _FakeTtsEngine();
      final tts = ReaderV2TtsController(runtime: runtime, tts: engine);

      await tts.startFromVisibleLocation();
      expect(engine.speakCount, 1);
      expect(tts.speechStartLocation?.chapterIndex, 0);
      final firstOffset = tts.speechStartLocation?.charOffset ?? 0;

      engine.emitComplete();
      await _flushMicrotasks();

      expect(engine.speakCount, 2);
      expect(tts.speechStartLocation?.chapterIndex, 0);
      expect(tts.speechStartLocation?.charOffset, greaterThan(firstOffset));

      for (var i = 0; i < 20; i += 1) {
        if (tts.speechStartLocation?.chapterIndex == 1) break;
        engine.emitComplete();
        await _flushMicrotasks();
      }
      expect(tts.speechStartLocation?.chapterIndex, 1);

      engine.emitProgress(0, 2);
      expect(tts.currentHighlight?.chapterIndex, 1);

      for (var i = 0; i < 40; i += 1) {
        if (tts.speechStartLocation == null) break;
        engine.emitComplete();
        await _flushMicrotasks();
      }

      expect(tts.speechStartLocation, isNull);
      expect(tts.currentHighlight, isNull);

      tts.dispose();
      runtime.dispose();
    },
  );

  test('tts highlight overlay repaints only affected tiles', () {
    final tile = ReaderV2PageCacheFactory.fromRenderPage(
      ReaderV2RenderPage(
        pageIndex: 0,
        chapterIndex: 0,
        chapterSize: 1,
        pageSize: 1,
        contentHeight: 80,
        viewportHeight: 100,
        localStartY: 0,
        localEndY: 80,
        lines: <ReaderV2RenderLine>[
          ReaderV2RenderLine(
            text: '0123456789',
            width: 120,
            lineTop: 0,
            lineBottom: 20,
            startCharOffset: 0,
            endCharOffset: 10,
          ),
        ],
      ),
    );
    ReaderV2TtsHighlightOverlayPainter painter(ReaderV2TtsHighlight highlight) {
      return ReaderV2TtsHighlightOverlayPainter(
        tile: tile,
        style: _style(),
        textColor: Colors.black,
        highlight: highlight,
      );
    }

    final oldUnrelated = painter(
      const ReaderV2TtsHighlight(
        chapterIndex: 1,
        highlightStart: 0,
        highlightEnd: 1,
      ),
    );
    final newUnrelated = painter(
      const ReaderV2TtsHighlight(
        chapterIndex: 0,
        highlightStart: 20,
        highlightEnd: 22,
      ),
    );
    final newAffected = painter(
      const ReaderV2TtsHighlight(
        chapterIndex: 0,
        highlightStart: 2,
        highlightEnd: 5,
      ),
    );

    expect(newUnrelated.shouldRepaint(oldUnrelated), isFalse);
    expect(newAffected.shouldRepaint(oldUnrelated), isTrue);
  });
}

Future<void> _pumpViewport(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _pumpViewportCommand(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpViewportLongCommand(WidgetTester tester) async {
  for (var i = 0; i < 220; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

double _visiblePageContentExtent(ReaderV2PageCache page) {
  if (page.lines.isEmpty) return page.height;
  return page.lines.fold<double>(
    0.0,
    (bottom, line) => line.bottom > bottom ? line.bottom : bottom,
  );
}

Rect? _lineRectForCharOffset(
  WidgetTester tester,
  int chapterIndex,
  int charOffset,
) {
  for (final element in find.byType(ReaderV2TileLayer).evaluate()) {
    final widget = element.widget as ReaderV2TileLayer;
    final tile = widget.tile;
    if (tile.chapterIndex != chapterIndex ||
        !tile.containsCharOffset(charOffset)) {
      continue;
    }
    final line = tile.lineForCharOffset(charOffset);
    if (line == null) continue;
    final renderBox = element.renderObject as RenderBox;
    final tileTopLeft = renderBox.localToGlobal(Offset.zero);
    return Rect.fromLTRB(
      tileTopLeft.dx + widget.style.paddingLeft,
      tileTopLeft.dy + widget.style.paddingTop + line.top,
      tileTopLeft.dx + widget.style.paddingLeft + line.width,
      tileTopLeft.dy + widget.style.paddingTop + line.bottom,
    );
  }
  return null;
}

ReaderV2Runtime _runtime({
  required ReaderV2Mode initialMode,
  required int chapterCount,
  required int paragraphsPerChapter,
  Set<int> failingChapters = const <int>{},
}) {
  final book = Book(
    bookUrl: 'test://viewport',
    origin: 'local',
    originName: 'fixture',
    name: '測試書',
  );
  final chapters = _chapters(
    bookUrl: book.bookUrl,
    count: chapterCount,
    paragraphsPerChapter: paragraphsPerChapter,
  );
  final bookDao = _FakeBookDao();
  final chapterDao = _FakeChapterDao(chapters);
  final sourceDao = _FakeSourceDao();
  final repository =
      failingChapters.isEmpty
          ? ReaderV2ChapterRepository(
            book: book,
            initialChapters: chapters,
            bookDao: bookDao,
            chapterDao: chapterDao,
            sourceDao: sourceDao,
            contentDao: null,
          )
          : _FailingChapterRepository(
            book: book,
            initialChapters: chapters,
            bookDao: bookDao,
            chapterDao: chapterDao,
            sourceDao: sourceDao,
            failingChapters: failingChapters,
          );
  return ReaderV2Runtime(
    book: book,
    repository: repository,
    layoutEngine: ReaderV2LayoutEngine(),
    progressController: ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    ),
    initialLayoutSpec: _spec(),
    initialMode: initialMode,
    initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
  );
}

List<BookChapter> _chapters({
  required String bookUrl,
  required int count,
  required int paragraphsPerChapter,
}) {
  return List<BookChapter>.generate(count, (index) {
    return BookChapter(
      index: index,
      bookUrl: bookUrl,
      title: '第${index + 1}章',
      content: List<String>.filled(
        paragraphsPerChapter,
        '這是第${index + 1}章的測試內容，用於建立 viewport 測試所需的文字。',
      ).join('\n\n'),
    );
  });
}

ReaderV2LayoutSpec _spec() {
  return ReaderV2LayoutSpec.fromViewport(
    viewportSize: const Size(260, 360),
    style: ReaderV2LayoutStyle(
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
  );
}

ReaderV2Style _style() {
  return const ReaderV2Style(
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 0.8,
    paddingTop: 12,
    paddingBottom: 12,
    paddingLeft: 12,
    paddingRight: 12,
    textIndent: 2,
    pageMode: ReaderV2PageMode.slide,
  );
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

class _FakeTtsEngine extends ReaderV2TtsEngine {
  final StreamController<String> _events = StreamController<String>.broadcast();
  bool _isPlaying = false;
  double _rate = 1.0;
  double _pitch = 1.0;
  String? _language = 'zh-TW';
  String _currentSpokenText = '';
  int _currentWordStart = -1;
  int _currentWordEnd = -1;
  int speakCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get rate => _rate;

  @override
  double get pitch => _pitch;

  @override
  String? get language => _language;

  @override
  String get currentSpokenText => _currentSpokenText;

  @override
  int get currentWordStart => _currentWordStart;

  @override
  int get currentWordEnd => _currentWordEnd;

  @override
  Stream<String> get events => _events.stream;

  @override
  Future<void> speak(String text) async {
    speakCount += 1;
    _currentSpokenText = text;
    _currentWordStart = -1;
    _currentWordEnd = -1;
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    resumeCount += 1;
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _currentSpokenText = '';
    _currentWordStart = -1;
    _currentWordEnd = -1;
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> setRate(double value) async {
    _rate = value;
    notifyListeners();
  }

  @override
  Future<void> setPitch(double value) async {
    _pitch = value;
    notifyListeners();
  }

  @override
  Future<void> setLanguage(String value) async {
    _language = value;
    notifyListeners();
  }

  void emitProgress(int start, int end) {
    _currentWordStart = start;
    _currentWordEnd = end;
    notifyListeners();
  }

  void emitComplete() {
    _isPlaying = false;
    _currentSpokenText = '';
    _currentWordStart = -1;
    _currentWordEnd = -1;
    notifyListeners();
    _events.add('onComplete');
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._onTick);

  final void Function(Timer timer) _onTick;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }

  void tickNow() {
    if (!_active) return;
    _tick += 1;
    _onTick(this);
  }
}

class _FailingChapterRepository extends ReaderV2ChapterRepository {
  _FailingChapterRepository({
    required Book book,
    required List<BookChapter> initialChapters,
    required BookDao bookDao,
    required ChapterDao chapterDao,
    required BookSourceDao sourceDao,
    required this.failingChapters,
  }) : super(
         book: book,
         initialChapters: initialChapters,
         bookDao: bookDao,
         chapterDao: chapterDao,
         sourceDao: sourceDao,
         contentDao: null,
       );

  final Set<int> failingChapters;

  @override
  Future<ReaderV2Content> loadContent(int chapterIndex) {
    if (failingChapters.contains(chapterIndex)) {
      throw const ReaderV2ChapterRepositoryException('fixture load failed');
    }
    return super.loadContent(chapterIndex);
  }
}
