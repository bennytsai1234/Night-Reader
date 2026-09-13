import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';

import 'reader_test_support.dart';

const int _seed = int.fromEnvironment(
  'NIGHT_READER_MONKEY_SEED',
  defaultValue: 48291723,
);
const int _iterations = int.fromEnvironment(
  'NIGHT_READER_MONKEY_ITERATIONS',
  defaultValue: 120,
);
const int _durationSeconds = int.fromEnvironment(
  'NIGHT_READER_MONKEY_DURATION_SECONDS',
  defaultValue: 0,
);
const int _lastActionLimit = 20;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('西游记 deterministic seeded Reader monkey', (tester) async {
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    final previousFlutterErrorHandler = FlutterError.onError;
    try {
      final harness = ReaderTestHarness(tester);
      await harness.startAndProvision();
      await harness.openBook();

      final random = math.Random(_seed);
      final lastActions = <String>[];
      final actionCounts = <String, int>{};
      final startedAt = DateTime.now();
      var completed = 0;

      bool shouldContinue() {
        final iterationLimit = _iterations > 0 && completed < _iterations;
        final durationLimit =
            _durationSeconds > 0 &&
            DateTime.now().difference(startedAt).inSeconds < _durationSeconds;
        return _durationSeconds > 0 ? durationLimit : iterationLimit;
      }

      void record(String action) {
        final entry = '#$completed $action';
        lastActions.add(entry);
        if (lastActions.length > _lastActionLimit) lastActions.removeAt(0);
        actionCounts.update(action, (value) => value + 1, ifAbsent: () => 1);
        debugPrint('READER_MONKEY_ACTION seed=$_seed $entry');
      }

      Future<void> runAction(String action) async {
        switch (action) {
          case 'small_scroll_up':
            await _drag(tester, const Offset(0, -180));
          case 'small_scroll_down':
            await _drag(tester, const Offset(0, 180));
          case 'large_scroll_up':
            await _drag(tester, const Offset(0, -900));
          case 'large_scroll_down':
            await _drag(tester, const Offset(0, 900));
          case 'fling_up':
            await _fling(tester, const Offset(0, -1900), 4300);
          case 'fling_down':
            await _fling(tester, const Offset(0, 1900), 4300);
          case 'reverse_direction':
            await _fling(tester, const Offset(0, -1500), 4000);
            await tester.pump(const Duration(milliseconds: 120));
            await _fling(tester, const Offset(0, 1450), 4000);
          case 'next_chapter':
            await harness.moveRelativeChapter(forward: true);
          case 'previous_chapter':
            await harness.moveRelativeChapter(forward: false);
          case 'random_chapter':
            await harness.jumpToChapter(
              random.nextInt(harness.chapters.length),
            );
          case 'far_forward_jump':
            await harness.jumpToChapter(harness.chapters.length - 1);
          case 'far_backward_jump':
            await harness.jumpToChapter(0);
          case 'pause':
            await tester.pump(
              Duration(milliseconds: 150 + random.nextInt(500)),
            );
          case 'background':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            // Pair the lifecycle transition before pumping so the test does
            // not wait on a paused engine while the real app is flushing.
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump(const Duration(milliseconds: 400));
          case 'foreground':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump(const Duration(milliseconds: 400));
          case 'reopen_reader':
            await harness.showControls();
            final backButton = find.byIcon(Icons.arrow_back).hitTestable();
            expect(backButton, findsOneWidget, reason: 'Reader 返回按鈕未顯示');
            await tester.tap(backButton);
            await tester.pump(const Duration(milliseconds: 500));
            await pumpUntil(
              tester,
              () => find.byType(BookshelfPage).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 60),
              reason: 'monkey reopen 沒有回到書架',
            );
            await harness.openBook();
          case 'tts_toggle_while_scrolling':
            await harness.toggleTtsWhileScrolling();
        }
        harness.expectNoFlutterException();
      }

      final actions = <String>[
        'small_scroll_up',
        'small_scroll_down',
        'large_scroll_up',
        'large_scroll_down',
        'fling_up',
        'fling_down',
        'reverse_direction',
        'next_chapter',
        'previous_chapter',
        'random_chapter',
        'far_forward_jump',
        'far_backward_jump',
        'pause',
        'background',
        'foreground',
        'reopen_reader',
        'tts_toggle_while_scrolling',
      ];

      try {
        while (shouldContinue()) {
          final action = actions[random.nextInt(actions.length)];
          record(action);
          await runAction(action);
          completed += 1;
        }
      } catch (error, stackTrace) {
        debugPrint(
          'READER_MONKEY_FAILURE seed=$_seed completed=$completed '
          'lastActions=${lastActions.join(' || ')} error=$error\n$stackTrace',
        );
        rethrow;
      }

      debugPrint(
        'READER_MONKEY_RESULT status=passed seed=$_seed '
        'requestedIterations=$_iterations requestedDurationSeconds=$_durationSeconds '
        'completed=$completed actualDuration=${DateTime.now().difference(startedAt)} '
        'actions=$actionCounts lastActions=${lastActions.join(' || ')}',
      );
    } finally {
      ErrorWidget.builder = previousErrorWidgetBuilder;
      FlutterError.onError = previousFlutterErrorHandler;
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<void> _drag(WidgetTester tester, Offset delta) async {
  await _dismissReaderControls(tester);
  final reader = find.byType(HybridReaderScreen).first;
  await tester.drag(reader, delta);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _fling(WidgetTester tester, Offset velocity, double speed) async {
  await _dismissReaderControls(tester);
  final reader = find.byType(HybridReaderScreen).first;
  await tester.fling(reader, velocity, speed);
  await tester.pump(const Duration(milliseconds: 650));
}

Future<void> _dismissReaderControls(WidgetTester tester) async {
  if (find.text('目錄').hitTestable().evaluate().isEmpty) return;
  final viewport = tester.binding.renderViews.single.size;
  await tester.tapAt(Offset(viewport.width / 2, viewport.height / 2));
  await tester.pump(const Duration(milliseconds: 250));
  await pumpUntil(
    tester,
    () => find.text('目錄').hitTestable().evaluate().isEmpty,
    reason: 'Reader controls 未關閉',
  );
}
