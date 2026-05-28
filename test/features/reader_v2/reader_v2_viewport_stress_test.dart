import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_layer.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_chapter_view.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_viewport.dart';
import 'package:night_reader/features/reader_v2/viewport/slide_reader_v2_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'slide runtime walks adjacent pages across uneven chapters',
    () async {
      final seed = _stressSeed();
      final fixture = _StressFixture.fromSeed(seed);
      final style = _stressStyle(pageMode: ReaderV2PageMode.slide);
      final viewport = const Size(260, 360);
      final runtime = _runtime(
        initialMode: ReaderV2Mode.slide,
        fixture: fixture,
        viewport: viewport,
        style: style,
      );
      final log = _StressLog(
        seed: seed,
        mode: 'slide-runtime',
        viewport: viewport,
        style: style,
        chapterProfile: fixture.profileSummary,
      );

      await _ensureAllLayouts(runtime);
      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      await _flushMicrotasks();
      await _assertSlideState(runtime, log, step: 0, op: 'initial');

      var step = 1;
      final totalPages = await _totalPageCount(runtime);
      for (; step <= totalPages + 3; step += 1) {
        final moved = await _performRuntimeSlideMove(
          runtime: runtime,
          log: log,
          step: step,
          forward: true,
        );
        if (!moved) break;
      }
      final end = runtime.state.pageWindow?.current;
      if (end == null ||
          end.chapterIndex != runtime.chapterCount - 1 ||
          !end.isChapterEnd) {
        fail(log.failure('slide forward walk did not reach the book end'));
      }

      for (; step <= totalPages * 2 + 6; step += 1) {
        final moved = await _performRuntimeSlideMove(
          runtime: runtime,
          log: log,
          step: step,
          forward: false,
        );
        if (!moved) break;
      }
      final start = runtime.state.pageWindow?.current;
      if (start == null || start.chapterIndex != 0 || start.pageIndex != 0) {
        fail(
          log.failure('slide backward walk did not return to the book start'),
        );
      }

      final random = math.Random(seed);
      final randomSteps = _stressSteps();
      for (var i = 0; i < randomSteps; i += 1) {
        await _performRuntimeSlideMove(
          runtime: runtime,
          log: log,
          step: step + i,
          forward: random.nextBool(),
        );
      }

      runtime.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'slide viewport stress serializes rapid commands without page drift',
    (tester) async {
      final seed = _stressSeed();
      final fixture = _StressFixture.fromSeed(seed + 17);
      final style = _stressStyle(pageMode: ReaderV2PageMode.slide);
      final viewport = const Size(260, 360);
      final runtime = _runtime(
        initialMode: ReaderV2Mode.slide,
        fixture: fixture,
        viewport: viewport,
        style: style,
      );
      var controller = ReaderV2ViewportController();
      final log = _StressLog(
        seed: seed,
        mode: 'slide-widget',
        viewport: viewport,
        style: style,
        chapterProfile: fixture.profileSummary,
      );

      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      await _pumpReaderViewport(
        tester,
        runtime: runtime,
        controller: controller,
        mode: ReaderV2Mode.slide,
        viewport: viewport,
        style: style,
      );
      await runtime.saveProgress(immediate: false);
      await _pumpViewportCommand(tester);
      await _assertSlideState(runtime, log, step: 0, op: 'initial');

      final random = math.Random(seed + 23);
      final steps = math.max(12, _stressSteps() ~/ 2);
      for (var step = 1; step <= steps; step += 1) {
        final op = random.nextInt(6);
        if (op == 0) {
          await _performSlideDrag(
            tester: tester,
            runtime: runtime,
            log: log,
            step: step,
            forward: true,
            viewport: viewport,
          );
        } else if (op == 1) {
          await _performSlideDrag(
            tester: tester,
            runtime: runtime,
            log: log,
            step: step,
            forward: false,
            viewport: viewport,
          );
        } else if (op == 2 || op == 3) {
          await _performSlideViewportMove(
            tester: tester,
            runtime: runtime,
            controller: controller,
            log: log,
            step: step,
            forward: op == 2,
          );
        } else {
          await _performRapidSlideCommands(
            tester: tester,
            runtime: runtime,
            controller: controller,
            log: log,
            step: step,
            forward: op == 4,
          );
        }
        _assertNoFlutterException(tester, log, 'slide step $step');
      }

      runtime.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'scroll viewport stress keeps visible line ranges continuous',
    (tester) async {
      final seed = _stressSeed();
      final fixture = _StressFixture.fromSeed(seed + 41);
      final style = _stressStyle(
        pageMode: ReaderV2PageMode.scroll,
        fontSize: 17,
        lineHeight: 1.62,
        paragraphSpacing: 1.0,
        paddingTop: 14,
        paddingBottom: 18,
      );
      final viewport = const Size(300, 520);
      final runtime = _runtime(
        initialMode: ReaderV2Mode.scroll,
        fixture: fixture,
        viewport: viewport,
        style: style,
      );
      var controller = ReaderV2ViewportController();
      final log = _StressLog(
        seed: seed,
        mode: 'scroll-widget',
        viewport: viewport,
        style: style,
        chapterProfile: fixture.profileSummary,
      );

      await runtime.jumpToLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        immediateSave: false,
      );
      await _pumpReaderViewport(
        tester,
        runtime: runtime,
        controller: controller,
        mode: ReaderV2Mode.scroll,
        viewport: viewport,
        style: style,
      );
      await runtime.saveProgress(immediate: false);
      await _pumpViewportCommand(tester);
      var lineIndex = await _LineOrdinalIndex.build(runtime);
      var range = await _assertScrollState(
        tester,
        runtime,
        lineIndex,
        log,
        step: 0,
        op: 'initial',
        viewport: viewport,
      );

      final steps = _stressSteps();
      for (var step = 1; step <= steps; step += 1) {
        final moved = await _performScrollPageCommand(
          tester: tester,
          runtime: runtime,
          controller: controller,
          lineIndex: lineIndex,
          log: log,
          step: step,
          forward: true,
          before: range,
          viewport: viewport,
        );
        range = await _assertScrollState(
          tester,
          runtime,
          lineIndex,
          log,
          step: step,
          op: 'next-settled',
          viewport: viewport,
        );
        if (!moved) break;
      }

      for (var step = steps + 1; step <= steps * 2; step += 1) {
        final moved = await _performScrollPageCommand(
          tester: tester,
          runtime: runtime,
          controller: controller,
          lineIndex: lineIndex,
          log: log,
          step: step,
          forward: false,
          before: range,
          viewport: viewport,
        );
        range = await _assertScrollState(
          tester,
          runtime,
          lineIndex,
          log,
          step: step,
          op: 'prev-settled',
          viewport: viewport,
        );
        if (!moved) break;
      }

      final random = math.Random(seed + 53);
      for (var i = 0; i < steps; i += 1) {
        final step = steps * 2 + i + 1;
        final op = random.nextInt(7);
        switch (op) {
          case 0:
          case 1:
            await _performScrollPageCommand(
              tester: tester,
              runtime: runtime,
              controller: controller,
              lineIndex: lineIndex,
              log: log,
              step: step,
              forward: op == 0,
              before: range,
              viewport: viewport,
            );
          case 2:
            await _performScrollDeltaCommand(
              tester: tester,
              runtime: runtime,
              controller: controller,
              lineIndex: lineIndex,
              log: log,
              step: step,
              delta: viewport.height * (random.nextBool() ? 1.75 : -1.25),
              animated: false,
              viewport: viewport,
            );
          case 3:
            await _performScrollDeltaCommand(
              tester: tester,
              runtime: runtime,
              controller: controller,
              lineIndex: lineIndex,
              log: log,
              step: step,
              delta: viewport.height * (random.nextInt(5) + 2),
              animated: true,
              viewport: viewport,
            );
          case 4:
            await _performScrollDrag(
              tester: tester,
              runtime: runtime,
              lineIndex: lineIndex,
              log: log,
              step: step,
              fingerDeltaY: -viewport.height * 0.32,
              viewport: viewport,
            );
          case 5:
            await _performScrollDrag(
              tester: tester,
              runtime: runtime,
              lineIndex: lineIndex,
              log: log,
              step: step,
              fingerDeltaY: viewport.height * 0.22,
              viewport: viewport,
            );
          case 6:
            await _performRapidScrollCommands(
              tester: tester,
              runtime: runtime,
              controller: controller,
              lineIndex: lineIndex,
              log: log,
              step: step,
              forward: random.nextBool(),
              viewport: viewport,
            );
        }
        range = await _assertScrollState(
          tester,
          runtime,
          lineIndex,
          log,
          step: step,
          op: 'random-settled',
          viewport: viewport,
        );
        if (runtime.state.layoutGeneration != lineIndex.layoutGeneration) {
          lineIndex = await _LineOrdinalIndex.build(runtime);
        }
        _assertNoFlutterException(tester, log, 'scroll step $step');
      }

      runtime.dispose();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'mode and style switches preserve nearby reader anchors',
    (tester) async {
      final seed = _stressSeed();
      final fixture = _StressFixture.fromSeed(seed + 79);
      final slideStyle = _stressStyle(pageMode: ReaderV2PageMode.slide);
      final scrollStyle = slideStyle.copyWith(
        pageMode: ReaderV2PageMode.scroll,
      );
      var viewport = const Size(260, 360);
      final runtime = _runtime(
        initialMode: ReaderV2Mode.slide,
        fixture: fixture,
        viewport: viewport,
        style: slideStyle,
      );
      var controller = ReaderV2ViewportController();
      final log = _StressLog(
        seed: seed,
        mode: 'mode-style',
        viewport: viewport,
        style: slideStyle,
        chapterProfile: fixture.profileSummary,
      );
      final lineIndex = await _LineOrdinalIndex.build(runtime);

      await _pumpReaderViewport(
        tester,
        runtime: runtime,
        controller: controller,
        mode: ReaderV2Mode.slide,
        viewport: viewport,
        style: slideStyle,
      );

      final middleLayout = await runtime.debugResolver.ensureLayout(3);
      final tailLayout = await runtime.debugResolver.ensureLayout(4);
      final targets = <ReaderV2Location>[
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
        ReaderV2Location(
          chapterIndex: 3,
          charOffset: middleLayout.displayText.length ~/ 2,
        ),
        ReaderV2Location(
          chapterIndex: 4,
          charOffset: tailLayout.pages.last.startCharOffset,
        ),
      ];

      for (var index = 0; index < targets.length; index += 1) {
        await runtime.jumpToLocation(targets[index], immediateSave: false);
        await _pumpViewportCommand(tester);
        final before =
            runtime.captureVisibleLocation() ?? runtime.state.visibleLocation;
        final beforeLine = lineIndex.ordinalForLocation(before);
        if (beforeLine == null) {
          fail(log.failure('missing line ordinal before mode switch $index'));
        }

        controller = ReaderV2ViewportController();
        await _applyPresentationAndPump(
          tester,
          runtime: runtime,
          controller: controller,
          mode: ReaderV2Mode.scroll,
          viewport: viewport,
          style: scrollStyle,
        );
        final afterScroll =
            runtime.captureVisibleLocation() ?? runtime.state.visibleLocation;
        final afterScrollLine = lineIndex.ordinalForLocation(afterScroll);
        if (afterScrollLine == null ||
            (afterScrollLine - beforeLine).abs() > 1) {
          log.record(
            'modeSwitch[$index] before=$before afterScroll=$afterScroll '
            'beforeLine=$beforeLine afterLine=$afterScrollLine',
          );
          fail(log.failure('slide -> scroll anchor drift exceeded one line'));
        }

        controller = ReaderV2ViewportController();
        await _applyPresentationAndPump(
          tester,
          runtime: runtime,
          controller: controller,
          mode: ReaderV2Mode.slide,
          viewport: viewport,
          style: slideStyle,
        );
        final afterSlide =
            runtime.captureVisibleLocation() ?? runtime.state.visibleLocation;
        final afterSlideLine = lineIndex.ordinalForLocation(afterSlide);
        if (afterSlideLine == null || (afterSlideLine - beforeLine).abs() > 1) {
          log.record(
            'modeSwitch[$index] before=$before afterSlide=$afterSlide '
            'beforeLine=$beforeLine afterLine=$afterSlideLine',
          );
          fail(log.failure('scroll -> slide anchor drift exceeded one line'));
        }
        _assertNoFlutterException(tester, log, 'mode switch $index');
      }

      viewport = const Size(220, 300);
      final denseScrollStyle = _stressStyle(
        pageMode: ReaderV2PageMode.scroll,
        fontSize: 20,
        lineHeight: 1.38,
        paragraphSpacing: 0.6,
        paddingTop: 20,
        paddingBottom: 24,
        paddingLeft: 18,
        paddingRight: 18,
      );
      controller = ReaderV2ViewportController();
      await _applyPresentationAndPump(
        tester,
        runtime: runtime,
        controller: controller,
        mode: ReaderV2Mode.scroll,
        viewport: viewport,
        style: denseScrollStyle,
      );
      final denseIndex = await _LineOrdinalIndex.build(runtime);
      var range = await _assertScrollState(
        tester,
        runtime,
        denseIndex,
        log,
        step: 1000,
        op: 'dense-style',
        viewport: viewport,
      );
      for (var step = 1001; step < 1005; step += 1) {
        await _performScrollPageCommand(
          tester: tester,
          runtime: runtime,
          controller: controller,
          lineIndex: denseIndex,
          log: log,
          step: step,
          forward: true,
          before: range,
          viewport: viewport,
        );
        range = await _assertScrollState(
          tester,
          runtime,
          denseIndex,
          log,
          step: step,
          op: 'dense-next',
          viewport: viewport,
        );
      }

      runtime.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<bool> _performRuntimeSlideMove({
  required ReaderV2Runtime runtime,
  required _StressLog log,
  required int step,
  required bool forward,
}) async {
  final before = _currentSlideAddress(runtime);
  final expected = await _neighborPageAddress(runtime, before, forward);
  final op = forward ? 'runtime-next' : 'runtime-prev';
  log.operation(step, op);
  final moved = forward ? runtime.moveToNextPage() : runtime.moveToPrevPage();
  await _flushMicrotasks();
  final after = await _assertSlideState(runtime, log, step: step, op: op);
  if (expected == null) {
    if (moved || after != before) {
      fail(log.failure('$op moved at a book boundary'));
    }
    return false;
  }
  if (!moved || after != expected) {
    fail(
      log.failure(
        '$op expected adjacent page ${expected.label}, '
        'moved=$moved actual=${after.label}',
      ),
    );
  }
  return true;
}

Future<void> _performSlideViewportMove({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required _StressLog log,
  required int step,
  required bool forward,
}) async {
  final before = _currentSlideAddress(runtime);
  final expected = await _neighborPageAddress(runtime, before, forward);
  final op = forward ? 'controller-next' : 'controller-prev';
  log.operation(step, op);
  final command =
      forward ? controller.moveToNextPage : controller.moveToPrevPage;
  if (command == null) fail(log.failure('$op command is not attached'));
  final future = command();
  await _pumpViewportCommand(tester);
  final moved = await future;
  await _pumpViewportCommand(tester);
  final after = await _assertSlideState(runtime, log, step: step, op: op);
  if (expected == null) {
    if (moved || after != before) {
      fail(log.failure('$op moved at a book boundary'));
    }
    return;
  }
  if (!moved || after != expected) {
    fail(
      log.failure(
        '$op expected adjacent page ${expected.label}, '
        'moved=$moved actual=${after.label}',
      ),
    );
  }
}

Future<void> _performRapidSlideCommands({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required _StressLog log,
  required int step,
  required bool forward,
}) async {
  final before = _currentSlideAddress(runtime);
  final firstExpected = await _neighborPageAddress(runtime, before, forward);
  final secondExpected =
      firstExpected == null
          ? null
          : await _neighborPageAddress(runtime, firstExpected, forward);
  final op = forward ? 'rapid-next-next' : 'rapid-prev-prev';
  log.operation(step, op);
  final command =
      forward ? controller.moveToNextPage : controller.moveToPrevPage;
  if (command == null) fail(log.failure('$op command is not attached'));
  final first = command();
  await tester.pump(const Duration(milliseconds: 48));
  final second = command();
  await _pumpViewportLongCommand(tester);
  final firstMoved = await first;
  final secondMoved = await second;
  await _pumpViewportCommand(tester);
  final after = await _assertSlideState(runtime, log, step: step, op: op);
  final expected = secondExpected ?? firstExpected ?? before;
  if (after != expected) {
    fail(
      log.failure(
        '$op expected ${expected.label}, actual=${after.label}, '
        'firstMoved=$firstMoved secondMoved=$secondMoved',
      ),
    );
  }
}

Future<void> _performSlideDrag({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required _StressLog log,
  required int step,
  required bool forward,
  required Size viewport,
}) async {
  final before = _currentSlideAddress(runtime);
  final expected = await _neighborPageAddress(runtime, before, forward);
  final op = forward ? 'drag-next' : 'drag-prev';
  log.operation(step, op);
  await tester.fling(
    find.byType(SlideReaderV2Viewport),
    Offset(viewport.width * (forward ? -0.55 : 0.55), 0),
    1200,
  );
  await _pumpViewportCommand(tester);
  final after = await _assertSlideState(runtime, log, step: step, op: op);
  if (expected == null) {
    if (after != before) fail(log.failure('$op moved at a book boundary'));
    return;
  }
  if (after != expected) {
    fail(
      log.failure(
        '$op expected adjacent page ${expected.label}, actual=${after.label}',
      ),
    );
  }
}

Future<bool> _performScrollPageCommand({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required _LineOrdinalIndex lineIndex,
  required _StressLog log,
  required int step,
  required bool forward,
  required _VisibleLineRange before,
  required Size viewport,
}) async {
  final op = forward ? 'scroll-next-page' : 'scroll-prev-page';
  log.operation(step, op);
  final command =
      forward ? controller.moveToNextPage : controller.moveToPrevPage;
  if (command == null) fail(log.failure('$op command is not attached'));
  final future = command();
  await _pumpViewportCommand(tester);
  final moved = await future;
  await _pumpViewportCommand(tester);
  final after = await _assertScrollState(
    tester,
    runtime,
    lineIndex,
    log,
    step: step,
    op: op,
    viewport: viewport,
  );
  if (moved) {
    if (forward && after.firstOrdinal > before.lastOrdinal + 1) {
      fail(
        log.failure(
          '$op skipped visible lines: before=${before.label}, after=${after.label}',
        ),
      );
    }
    if (!forward && after.lastOrdinal < before.firstOrdinal - 1) {
      fail(
        log.failure(
          '$op skipped visible lines backward: '
          'before=${before.label}, after=${after.label}',
        ),
      );
    }
  } else if (forward && before.lastOrdinal < lineIndex.maxOrdinal) {
    fail(log.failure('$op could not advance before book end'));
  } else if (!forward && before.firstOrdinal > 0) {
    fail(log.failure('$op could not retreat before book start'));
  }
  return moved;
}

Future<void> _performScrollDeltaCommand({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required _LineOrdinalIndex lineIndex,
  required _StressLog log,
  required int step,
  required double delta,
  required bool animated,
  required Size viewport,
}) async {
  final op = animated ? 'animateBy($delta)' : 'scrollBy($delta)';
  log.operation(step, op);
  final command = animated ? controller.animateBy : controller.scrollBy;
  if (command == null) fail(log.failure('$op command is not attached'));
  final future = command(delta);
  if (animated) {
    await _pumpViewportLongCommand(tester);
  } else {
    await _pumpViewportCommand(tester);
  }
  await future;
  await _pumpViewportCommand(tester);
  await _assertScrollState(
    tester,
    runtime,
    lineIndex,
    log,
    step: step,
    op: op,
    viewport: viewport,
  );
}

Future<void> _performScrollDrag({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required _LineOrdinalIndex lineIndex,
  required _StressLog log,
  required int step,
  required double fingerDeltaY,
  required Size viewport,
}) async {
  final op = 'drag($fingerDeltaY)';
  log.operation(step, op);
  final center = tester.getCenter(find.byType(ScrollReaderV2Viewport));
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(Offset(0, fingerDeltaY));
  await tester.pump();
  await gesture.up();
  await _pumpViewportCommand(tester);
  await _assertScrollState(
    tester,
    runtime,
    lineIndex,
    log,
    step: step,
    op: op,
    viewport: viewport,
  );
}

Future<void> _performRapidScrollCommands({
  required WidgetTester tester,
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required _LineOrdinalIndex lineIndex,
  required _StressLog log,
  required int step,
  required bool forward,
  required Size viewport,
}) async {
  final op = forward ? 'rapid-scroll-next' : 'rapid-scroll-prev';
  log.operation(step, op);
  final command =
      forward ? controller.moveToNextPage : controller.moveToPrevPage;
  if (command == null) fail(log.failure('$op command is not attached'));
  final first = command();
  await tester.pump(const Duration(milliseconds: 48));
  final second = command();
  await _pumpViewportLongCommand(tester);
  await first;
  await second;
  await _pumpViewportCommand(tester);
  await _assertScrollState(
    tester,
    runtime,
    lineIndex,
    log,
    step: step,
    op: op,
    viewport: viewport,
  );
}

Future<_PageAddress> _assertSlideState(
  ReaderV2Runtime runtime,
  _StressLog log, {
  required int step,
  required String op,
}) async {
  final state = runtime.state;
  if (state.phase != ReaderV2Phase.ready) {
    fail(log.failure('slide state is not ready after $op: ${state.phase}'));
  }
  final window = state.pageWindow;
  if (window == null) fail(log.failure('slide pageWindow is null after $op'));
  final current = window.current;
  if (current.isPlaceholder) {
    fail(log.failure('slide current page is a placeholder after $op'));
  }
  final address = _PageAddress(current.chapterIndex, current.pageIndex);
  final layout = await runtime.debugResolver.ensureLayout(current.chapterIndex);
  if (current.pageIndex < 0 || current.pageIndex >= layout.pages.length) {
    fail(log.failure('slide current page index is out of layout range'));
  }
  final expected = layout.pages[current.pageIndex];
  if (current.startCharOffset != expected.startCharOffset ||
      current.endCharOffset != expected.endCharOffset) {
    fail(
      log.failure(
        'slide page slice mismatch at ${address.label}: '
        'actual=${current.startCharOffset}-${current.endCharOffset}, '
        'expected=${expected.startCharOffset}-${expected.endCharOffset}',
      ),
    );
  }
  _assertLegalLocation(state.visibleLocation, log, 'visibleLocation');
  _assertLegalLocation(state.committedLocation, log, 'committedLocation');
  if (state.visibleLocation != state.committedLocation) {
    fail(
      log.failure(
        'slide visibleLocation and committedLocation diverged after $op: '
        '${state.visibleLocation} vs ${state.committedLocation}',
      ),
    );
  }
  if (state.visibleLocation.chapterIndex != current.chapterIndex ||
      !current.containsCharOffset(state.visibleLocation.charOffset)) {
    fail(
      log.failure(
        'slide visibleLocation is outside current page after $op: '
        'location=${state.visibleLocation}, current=${address.label}',
      ),
    );
  }
  log.record(_slideRecord(step, op, runtime));
  return address;
}

Future<_VisibleLineRange> _assertScrollState(
  WidgetTester tester,
  ReaderV2Runtime runtime,
  _LineOrdinalIndex lineIndex,
  _StressLog log, {
  required int step,
  required String op,
  required Size viewport,
}) async {
  final state = runtime.state;
  if (state.phase != ReaderV2Phase.ready) {
    fail(log.failure('scroll state is not ready after $op: ${state.phase}'));
  }
  _assertLegalLocation(state.visibleLocation, log, 'visibleLocation');
  _assertLegalLocation(state.committedLocation, log, 'committedLocation');
  final beforeCapture = state.visibleLocation;
  final captured = runtime.captureVisibleLocation();
  if (captured == null) {
    fail(log.failure('scroll captureVisibleLocation returned null after $op'));
  }
  if (captured != beforeCapture) {
    fail(
      log.failure(
        'scroll settled visibleLocation drifted after capture: '
        'before=$beforeCapture captured=$captured',
      ),
    );
  }
  if (runtime.state.visibleLocation != runtime.state.committedLocation) {
    fail(
      log.failure(
        'scroll visibleLocation and committedLocation diverged after $op: '
        '${runtime.state.visibleLocation} vs ${runtime.state.committedLocation}',
      ),
    );
  }
  final range = _visibleLineRange(tester, lineIndex, viewport);
  if (range == null) {
    fail(log.failure('scroll has no visible text line after $op'));
  }
  final capturedOrdinal = lineIndex.ordinalForLocation(captured);
  if (capturedOrdinal == null) {
    fail(
      log.failure('scroll captured location has no line ordinal: $captured'),
    );
  }
  if (capturedOrdinal < range.firstOrdinal - 1 ||
      capturedOrdinal > range.lastOrdinal + 1) {
    fail(
      log.failure(
        'scroll captured location is outside visible range after $op: '
        'captured=$captured ordinal=$capturedOrdinal range=${range.label}',
      ),
    );
  }
  log.record(_scrollRecord(step, op, runtime, range, captured));
  return range;
}

void _assertLegalLocation(
  ReaderV2Location location,
  _StressLog log,
  String label,
) {
  if (location.chapterIndex < 0 ||
      location.visualOffsetPx < ReaderV2Location.minVisualOffsetPx ||
      location.visualOffsetPx > ReaderV2Location.maxVisualOffsetPx ||
      !location.visualOffsetPx.isFinite) {
    fail(log.failure('$label is outside legal range: $location'));
  }
}

_VisibleLineRange? _visibleLineRange(
  WidgetTester tester,
  _LineOrdinalIndex lineIndex,
  Size viewport,
) {
  final visible = <_VisibleLine>[];
  for (final element in find.byType(ReaderV2TileLayer).evaluate()) {
    final widget = element.widget as ReaderV2TileLayer;
    if (widget.tile.source.isPlaceholder) continue;
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) continue;
    final tileTop = renderObject.localToGlobal(Offset.zero).dy;
    final tileBottom = tileTop + renderObject.size.height;
    if (tileBottom <= 0.5 || tileTop >= viewport.height - 0.5) continue;
    for (final line in widget.tile.lines) {
      if (line.text.isEmpty) continue;
      final screenTop = tileTop + line.top;
      final screenBottom = tileTop + line.bottom;
      if (screenBottom <= 0.5 || screenTop >= viewport.height - 0.5) {
        continue;
      }
      final ordinal = lineIndex.ordinalForLine(line);
      if (ordinal == null) continue;
      visible.add(
        _VisibleLine(
          chapterIndex: line.chapterIndex,
          lineIndex: line.lineIndex,
          startCharOffset: line.startCharOffset,
          endCharOffset: line.endCharOffset,
          ordinal: ordinal,
        ),
      );
    }
  }
  if (visible.isEmpty) return null;
  visible.sort((a, b) => a.ordinal.compareTo(b.ordinal));
  return _VisibleLineRange(first: visible.first, last: visible.last);
}

Future<void> _applyPresentationAndPump(
  WidgetTester tester, {
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required ReaderV2Mode mode,
  required Size viewport,
  required ReaderV2Style style,
}) async {
  final presentation = runtime.applyPresentation(
    spec: _spec(viewport: viewport, style: style),
    mode: mode,
  );
  await _pumpReaderViewport(
    tester,
    runtime: runtime,
    controller: controller,
    mode: mode,
    viewport: viewport,
    style: style,
  );
  await _pumpViewportLongCommand(tester);
  await presentation;
  await _pumpViewportCommand(tester);
}

Future<void> _pumpReaderViewport(
  WidgetTester tester, {
  required ReaderV2Runtime runtime,
  required ReaderV2ViewportController controller,
  required ReaderV2Mode mode,
  required Size viewport,
  required ReaderV2Style style,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: viewport.width,
        height: viewport.height,
        child:
            mode == ReaderV2Mode.slide
                ? SlideReaderV2Viewport(
                  runtime: runtime,
                  backgroundColor: Colors.white,
                  textColor: Colors.black,
                  style: style.copyWith(pageMode: ReaderV2PageMode.slide),
                  controller: controller,
                )
                : ScrollReaderV2Viewport(
                  runtime: runtime,
                  backgroundColor: Colors.white,
                  textColor: Colors.black,
                  style: style.copyWith(pageMode: ReaderV2PageMode.scroll),
                  controller: controller,
                ),
      ),
    ),
  );
  await _pumpViewportCommand(tester);
}

Future<void> _pumpViewportCommand(WidgetTester tester) async {
  for (var i = 0; i < 32; i += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpViewportLongCommand(WidgetTester tester) async {
  for (var i = 0; i < 180; i += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _ensureAllLayouts(ReaderV2Runtime runtime) async {
  for (
    var chapterIndex = 0;
    chapterIndex < runtime.chapterCount;
    chapterIndex += 1
  ) {
    await runtime.debugResolver.ensureLayout(chapterIndex);
  }
}

Future<int> _totalPageCount(ReaderV2Runtime runtime) async {
  var total = 0;
  for (
    var chapterIndex = 0;
    chapterIndex < runtime.chapterCount;
    chapterIndex += 1
  ) {
    final layout = await runtime.debugResolver.ensureLayout(chapterIndex);
    total += layout.pages.length;
  }
  return total;
}

_PageAddress _currentSlideAddress(ReaderV2Runtime runtime) {
  final current = runtime.state.pageWindow?.current;
  if (current == null) {
    throw StateError('slide current page is null');
  }
  return _PageAddress(current.chapterIndex, current.pageIndex);
}

Future<_PageAddress?> _neighborPageAddress(
  ReaderV2Runtime runtime,
  _PageAddress address,
  bool forward,
) async {
  final layout = await runtime.debugResolver.ensureLayout(address.chapterIndex);
  if (forward) {
    if (address.pageIndex + 1 < layout.pages.length) {
      return _PageAddress(address.chapterIndex, address.pageIndex + 1);
    }
    final nextChapter = address.chapterIndex + 1;
    if (nextChapter >= runtime.chapterCount) return null;
    final nextLayout = await runtime.debugResolver.ensureLayout(nextChapter);
    return nextLayout.pages.isEmpty ? null : _PageAddress(nextChapter, 0);
  }
  if (address.pageIndex > 0) {
    return _PageAddress(address.chapterIndex, address.pageIndex - 1);
  }
  final previousChapter = address.chapterIndex - 1;
  if (previousChapter < 0) return null;
  final previousLayout = await runtime.debugResolver.ensureLayout(
    previousChapter,
  );
  if (previousLayout.pages.isEmpty) return null;
  return _PageAddress(previousChapter, previousLayout.pages.length - 1);
}

String _slideRecord(int step, String op, ReaderV2Runtime runtime) {
  final state = runtime.state;
  final window = state.pageWindow;
  final current = window?.current;
  return 'step=$step op=$op mode=slide '
      'current=${_pageLabel(current)} prev=${_pageLabel(window?.prev)} '
      'next=${_pageLabel(window?.next)} '
      'visible=${state.visibleLocation} committed=${state.committedLocation}';
}

String _scrollRecord(
  int step,
  String op,
  ReaderV2Runtime runtime,
  _VisibleLineRange range,
  ReaderV2Location captured,
) {
  final state = runtime.state;
  return 'step=$step op=$op mode=scroll range=${range.label} '
      'captured=$captured visible=${state.visibleLocation} '
      'committed=${state.committedLocation}';
}

String _pageLabel(ReaderV2RenderPage? page) {
  if (page == null) return 'null';
  final kind = page.isPlaceholder ? ':placeholder' : '';
  return 'c${page.chapterIndex}/p${page.pageIndex}'
      '(${page.startCharOffset}-${page.endCharOffset}$kind)';
}

void _assertNoFlutterException(
  WidgetTester tester,
  _StressLog log,
  String context,
) {
  final exception = tester.takeException();
  if (exception != null) {
    fail(log.failure('tester.takeException after $context: $exception'));
  }
}

int _stressSeed() => _envInt('READER_V2_STRESS_SEED', 20260502);

int _stressSteps() => math.max(1, _envInt('READER_V2_STRESS_STEPS', 24));

int _envInt(String name, int fallback) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) return fallback;
  return int.tryParse(value) ?? fallback;
}

ReaderV2Runtime _runtime({
  required ReaderV2Mode initialMode,
  required _StressFixture fixture,
  required Size viewport,
  required ReaderV2Style style,
}) {
  final book = Book(
    bookUrl: 'test://reader-v2-stress',
    origin: 'local',
    originName: 'fixture',
    name: '壓測書',
  );
  final bookDao = _FakeBookDao();
  final chapterDao = _FakeChapterDao(fixture.chapters(book.bookUrl));
  final sourceDao = _FakeSourceDao();
  final repository = ReaderV2ChapterRepository(
    book: book,
    initialChapters: chapterDao.storedChapters,
    bookDao: bookDao,
    chapterDao: chapterDao,
    sourceDao: sourceDao,
    contentDao: null,
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
    initialLayoutSpec: _spec(viewport: viewport, style: style),
    initialMode: initialMode,
    initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
  );
}

ReaderV2LayoutSpec _spec({
  required Size viewport,
  required ReaderV2Style style,
}) {
  return ReaderV2LayoutSpec.fromViewport(
    viewportSize: viewport,
    style: ReaderV2LayoutStyle(
      fontSize: style.fontSize,
      lineHeight: style.lineHeight,
      letterSpacing: style.letterSpacing,
      paragraphSpacing: style.paragraphSpacing,
      paddingTop: style.paddingTop,
      paddingBottom: style.paddingBottom,
      paddingLeft: style.paddingLeft,
      paddingRight: style.paddingRight,
      bold: style.bold,
      textIndent: style.textIndent,
    ),
  );
}

ReaderV2Style _stressStyle({
  required ReaderV2PageMode pageMode,
  double fontSize = 18,
  double lineHeight = 1.5,
  double paragraphSpacing = 0.8,
  double paddingTop = 12,
  double paddingBottom = 12,
  double paddingLeft = 12,
  double paddingRight = 12,
}) {
  return ReaderV2Style(
    fontSize: fontSize,
    lineHeight: lineHeight,
    letterSpacing: 0,
    paragraphSpacing: paragraphSpacing,
    paddingTop: paddingTop,
    paddingBottom: paddingBottom,
    paddingLeft: paddingLeft,
    paddingRight: paddingRight,
    textIndent: 2,
    pageMode: pageMode,
  );
}

class _StressFixture {
  _StressFixture(this.paragraphCounts, this._salt);

  factory _StressFixture.fromSeed(int seed) {
    final base = <int>[1, 3, 9, 2, 14, 5, 20, 1, 11];
    final random = math.Random(seed);
    return _StressFixture(<int>[
      for (final count in base) count + random.nextInt(3),
    ], seed % 997);
  }

  final List<int> paragraphCounts;
  final int _salt;

  String get profileSummary => paragraphCounts.join(',');

  List<BookChapter> chapters(String bookUrl) {
    return List<BookChapter>.generate(paragraphCounts.length, (chapterIndex) {
      return BookChapter(
        index: chapterIndex,
        bookUrl: bookUrl,
        title: '第${chapterIndex + 1}章 邊界測試',
        content: _chapterContent(chapterIndex, paragraphCounts[chapterIndex]),
      );
    });
  }

  String _chapterContent(int chapterIndex, int paragraphCount) {
    final paragraphs = <String>[];
    for (var index = 0; index < paragraphCount; index += 1) {
      paragraphs.add(_paragraph(chapterIndex, index));
      if (index % 5 == 2) {
        paragraphs.add('');
      }
    }
    return paragraphs.join('\n\n');
  }

  String _paragraph(int chapterIndex, int paragraphIndex) {
    final serial = '${chapterIndex + 1}-${paragraphIndex + 1}-$_salt';
    switch (paragraphIndex % 5) {
      case 0:
        return '短句 $serial。';
      case 1:
        return '這是第$serial段，用來檢查中文標點、章節邊界與翻頁錨點。'
            '句子刻意拉長，讓排版引擎在不同 viewport 與字級下產生多行內容。';
      case 2:
        return '標題式段落 $serial：風聲、燈影、書頁，連續排列以觸發換行。';
      case 3:
        return '　　縮排段落 $serial，包含全形空白與較長描述。'
            '讀者在此處快速前後翻動時，不能重複行，也不能跳過任何一行。'
            '最後再補上一句，增加 page slice 的邊界壓力。';
      default:
        return '尾段 $serial。\n這一段含有單行換行，會先被內容正規化，再交給 layout。';
    }
  }
}

class _LineOrdinalIndex {
  _LineOrdinalIndex({
    required this.layoutGeneration,
    required this.views,
    required this.ordinals,
    required this.maxOrdinal,
  });

  final int layoutGeneration;
  final Map<int, ReaderV2ChapterView> views;
  final Map<String, int> ordinals;
  final int maxOrdinal;

  static Future<_LineOrdinalIndex> build(ReaderV2Runtime runtime) async {
    final views = <int, ReaderV2ChapterView>{};
    final ordinals = <String, int>{};
    var ordinal = 0;
    for (
      var chapterIndex = 0;
      chapterIndex < runtime.chapterCount;
      chapterIndex += 1
    ) {
      final view = await runtime.debugResolver.ensureLayout(chapterIndex);
      views[chapterIndex] = view;
      for (final line in view.lines) {
        if (line.text.isEmpty) continue;
        ordinals[_lineKey(line.chapterIndex, line.lineIndex)] = ordinal;
        ordinal += 1;
      }
    }
    return _LineOrdinalIndex(
      layoutGeneration: runtime.state.layoutGeneration,
      views: views,
      ordinals: ordinals,
      maxOrdinal: ordinal == 0 ? 0 : ordinal - 1,
    );
  }

  int? ordinalForLine(ReaderV2RenderLine line) {
    return ordinals[_lineKey(line.chapterIndex, line.lineIndex)];
  }

  int? ordinalForLocation(ReaderV2Location location) {
    final view = views[location.chapterIndex];
    final line = view?.lineForCharOffset(location.charOffset);
    if (line == null) return null;
    return ordinalForLine(line);
  }

  static String _lineKey(int chapterIndex, int lineIndex) {
    return '$chapterIndex:$lineIndex';
  }
}

class _VisibleLineRange {
  const _VisibleLineRange({required this.first, required this.last});

  final _VisibleLine first;
  final _VisibleLine last;

  int get firstOrdinal => first.ordinal;
  int get lastOrdinal => last.ordinal;

  String get label => '${first.label}..${last.label}';
}

class _VisibleLine {
  const _VisibleLine({
    required this.chapterIndex,
    required this.lineIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.ordinal,
  });

  final int chapterIndex;
  final int lineIndex;
  final int startCharOffset;
  final int endCharOffset;
  final int ordinal;

  String get label =>
      'c$chapterIndex/l$lineIndex#$ordinal($startCharOffset-$endCharOffset)';
}

class _PageAddress {
  const _PageAddress(this.chapterIndex, this.pageIndex);

  final int chapterIndex;
  final int pageIndex;

  String get label => 'c$chapterIndex/p$pageIndex';

  @override
  bool operator ==(Object other) {
    return other is _PageAddress &&
        other.chapterIndex == chapterIndex &&
        other.pageIndex == pageIndex;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, pageIndex);
}

class _StressLog {
  _StressLog({
    required this.seed,
    required this.mode,
    required this.viewport,
    required this.style,
    required this.chapterProfile,
  });

  final int seed;
  final String mode;
  final Size viewport;
  final ReaderV2Style style;
  final String chapterProfile;
  final List<String> _operations = <String>[];
  final List<String> _records = <String>[];

  void operation(int step, String op) {
    _operations.add('step=$step op=$op');
    if (_operations.length > 80) _operations.removeAt(0);
  }

  void record(String value) {
    _records.add(value);
    if (_records.length > 80) _records.removeAt(0);
  }

  String failure(String message) {
    final operations = _operations.skip(math.max(0, _operations.length - 20));
    final records = _records.skip(math.max(0, _records.length - 10));
    return '$message\n'
        'seed=$seed mode=$mode viewport=${viewport.width}x${viewport.height} '
        'style=${_styleSummary(style)} chapters=$chapterProfile\n'
        'operations(last20)=\n${operations.join('\n')}\n'
        'records(last10)=\n${records.join('\n')}';
  }

  String _styleSummary(ReaderV2Style style) {
    return 'font=${style.fontSize},line=${style.lineHeight},'
        'paragraph=${style.paragraphSpacing},'
        'padding=${style.paddingLeft}/${style.paddingTop}/'
        '${style.paddingRight}/${style.paddingBottom},'
        'mode=${style.pageMode.name}';
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
