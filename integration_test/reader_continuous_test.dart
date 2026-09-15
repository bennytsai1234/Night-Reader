import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/telemetry/hybrid_telemetry.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import 'reader_test_support.dart';

const int _seed = int.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_SEED',
  defaultValue: 9132026,
);
const int _iterations = int.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_ITERATIONS',
  defaultValue: 18,
);
const int _durationSeconds = int.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_DURATION_SECONDS',
  defaultValue: 0,
);
const int _maxContinuousIterations = 60;
const int _maxContinuousDurationSeconds = 300;
const Duration _continuousNoProgressLimit = Duration(seconds: 15);
const int _lastActionLimit = 24;
const bool _enforceFrameP99 = bool.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_ENFORCE_FRAME_P99',
  defaultValue: true,
);
const bool _enableInvariantHook = bool.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_ENABLE_INVARIANTS',
  defaultValue: false,
);
const Timeout _continuousTestTimeout = _durationSeconds > 0
    ? Timeout(Duration(seconds: _durationSeconds + 120))
    : Timeout(Duration(minutes: 6));
const String _forcedAction = String.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_ACTION',
  defaultValue: '',
);
const bool _simpleScrollControl = bool.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_SIMPLE_CONTROL',
  defaultValue: false,
);
const bool _captureSettledScreenshots = bool.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_CAPTURE_SETTLED_SCREENSHOTS',
  defaultValue: false,
);

const Set<String> _operationAttributionActions = <String>{
  'scroll_slow',
  'scroll_fast',
  'scroll_long_distance',
  'scroll_variable_speed',
  'scroll_brake',
  'scroll_cross_chapter_ballistic',
  'scroll_reverse',
  'scroll_short_chapter_chain',
  'scroll_book_start_boundary',
  'scroll_book_end_boundary',
  'interaction_control',
  'interaction_page',
  'interaction_menu_open_close',
  'interaction_tts_toggle',
  'style_typography',
  'style_theme_text_color',
  'style_chinese_conversion',
  'style_padding',
  'source_reload',
  'visual_checkpoint_matrix',
  'navigation_next_chapter',
  'navigation_previous_chapter',
  'navigation_directory_jump',
  'navigation_directory_jump_then_immediate_read',
  'navigation_bookmark_jump',
  'entry_hot_open_book',
  'entry_cold_open_book',
};

String _operationCategory(String action) {
  if (action.startsWith('scroll_')) return 'scroll';
  if (action.startsWith('interaction_')) return 'interaction';
  if (action.startsWith('navigation_')) return 'navigation';
  if (action.startsWith('entry_')) return 'entry';
  if (action == 'chapter_switch_while_ballistic') {
    return 'scroll';
  }
  if (action == 'slow_read_forward' ||
      action == 'small_correction' ||
      action == 'fling_forward_then_reverse' ||
      action == 'fling_reverse_then_continue') {
    return 'scroll';
  }
  if (action == 'next_or_previous_chapter' ||
      action == 'directory_jump_then_immediate_read') {
    return 'navigation';
  }
  return 'unknown';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('西游記 Reader continuous layout and scroll race validation', (
    tester,
  ) async {
    HybridReaderScreen.debugFrameInvariantsEnabled = _enableInvariantHook;
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    final previousFlutterErrorHandler = FlutterError.onError;
    try {
      if (_iterations > _maxContinuousIterations) {
        fail(
          'continuous batch 超過硬上限：iterations=$_iterations，'
          '上限=$_maxContinuousIterations；請拆成有限短批次。',
        );
      }
      if (_durationSeconds > _maxContinuousDurationSeconds) {
        fail(
          'continuous batch 超過硬上限：duration=$_durationSeconds 秒，'
          '上限=$_maxContinuousDurationSeconds 秒；禁止兩小時級單次長跑。',
        );
      }
      if (_simpleScrollControl) {
        await _runSimpleScrollControl(tester, binding);
        return;
      }
      final harness = ReaderTestHarness(tester);
      await harness.startAndProvision();
      await harness.openBook();

      final probe = _ContinuousReaderProbe(
        tester: tester,
        harness: harness,
        binding: binding,
      );
      final invariantViolations = <Map<String, Object?>>[];
      void collectInvariantViolations(String boundary) {
        final captured = harness.debugFrameInvariantViolations(clear: true);
        for (final violation in captured) {
          final enriched = <String, Object?>{
            'boundary': boundary,
            ...violation,
          };
          invariantViolations.add(enriched);
          debugPrint(
            'READER_CONTINUOUS_INVARIANT_VIOLATION '
            '${jsonEncode(enriched)}',
          );
        }
      }

      probe.sample('open');
      await _settle(probe, 'initial');
      collectInvariantViolations('initial');
      // Do not let cold-open/restore work dominate the strict scroll/layout
      // acceptance window. The reader is already settled and warmed here.
      harness.resetPerformanceWindow();

      final random = math.Random(_seed);
      final actions = <String>[
        'slow_read_forward',
        'small_correction',
        'fling_forward_then_reverse',
        'fling_reverse_then_continue',
        'next_or_previous_chapter',
        'chapter_switch_while_ballistic',
        'directory_jump_then_immediate_read',
      ];
      final lastActions = <String>[];
      final startedAt = DateTime.now();
      var completed = 0;

      bool shouldContinue() {
        if (_durationSeconds > 0) {
          return DateTime.now().difference(startedAt).inSeconds <
              _durationSeconds;
        }
        return _iterations > 0 && completed < _iterations;
      }

      void record(String action) {
        final entry = '#$completed $action';
        lastActions.add(entry);
        if (lastActions.length > _lastActionLimit) lastActions.removeAt(0);
        debugPrint('READER_CONTINUOUS_ACTION seed=$_seed $entry');
      }

      try {
        await binding.watchPerformance(() async {
          while (shouldContinue()) {
            final action = _forcedAction.isEmpty
                ? actions[random.nextInt(actions.length)]
                : _forcedAction;
            if (!actions.contains(action) &&
                !_operationAttributionActions.contains(action)) {
              fail('未支援的 continuous action：$action');
            }
            record(action);
            probe.beginAction('$completed-$action', actionIdentity: action);
            try {
              await _runAction(action, iteration: completed, probe: probe);
            } finally {
              probe.endAction();
            }
            collectInvariantViolations('action-$completed-$action');
            harness.expectNoFlutterException();
            completed += 1;
          }
        }, reportKey: 'timeline');

        probe.throwIfSuspectedAnomalies();
        collectInvariantViolations('final');
        final finalSnapshot = harness.debugSnapshot();
        final performance = harness.debugPerformanceSummary();
        final frameCount = (performance['frames'] as num?)?.toInt() ?? 0;
        final frameP99Micros =
            (performance['frameP99Micros'] as num?)?.toDouble() ?? 0;
        final performanceGateEvaluated =
            !_enableInvariantHook && frameCount >= 300;
        final performancePassed =
            performanceGateEvaluated &&
            frameP99Micros < HybridTelemetry.strict120HzFrameP99TargetMicros;
        final performanceStatus = !performanceGateEvaluated
            ? 'insufficient'
            : performancePassed
            ? 'passed'
            : 'failed';
        final continuousResult = <String, Object?>{
          'semanticStatus': 'passed',
          'completedActions': completed,
          'actionMarkers': List<String>.from(lastActions),
          'samples': probe.sampleCount,
          'suspectedAnomalies': probe.suspectedAnomalyCount,
          'finalPhase': finalSnapshot['phase'],
          'finalQueueDepth': finalSnapshot['pumpQueueDepth'],
          'finalSnapshot': finalSnapshot,
          'performanceStatus': performanceStatus,
          'performanceGateEvaluated': performanceGateEvaluated,
          'invariantHookEnabled': _enableInvariantHook,
          'operationAttribution': probe.attributionSummary(
            performance: performance,
            exclusiveAction:
                _forcedAction.isNotEmpty &&
                _operationAttributionActions.contains(_forcedAction),
          ),
          'invariantViolationCount': invariantViolations.length,
          'invariantViolations': invariantViolations,
        };
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['appTelemetry'] = performance;
        binding.reportData!['continuousResult'] = continuousResult;
        debugPrint(
          'READER_CONTINUOUS_PERFORMANCE '
          'status=$performanceStatus '
          'targetP99Micros=${HybridTelemetry.strict120HzFrameP99TargetMicros} '
          'actualP99Micros=$frameP99Micros frames=$frameCount '
          'taskP99Micros=${performance['layoutTaskP99Micros']} '
          'worstTaskMicros=${performance['worstLayoutTaskMicros']} '
          'worstTaskChars=${performance['worstLayoutTaskCharCount']} '
          'tasksOver8ms=${performance['layoutTasksOver8ms']} '
          'vsyncP99=${performance['vsyncOverheadP99Micros']} '
          'buildP99=${performance['buildP99Micros']} '
          'rasterP99=${performance['rasterP99Micros']}',
        );
        if (!_enableInvariantHook &&
            _enforceFrameP99 &&
            performanceGateEvaluated &&
            !performancePassed) {
          fail(
            '120Hz frame P99 未達標：actual=${frameP99Micros}µs '
            'target=<${HybridTelemetry.strict120HzFrameP99TargetMicros}µs '
            'frames=$frameCount taskP99=${performance['layoutTaskP99Micros']}µs '
            'worstTask=${performance['worstLayoutTaskMicros']}µs '
            'worstTaskChars=${performance['worstLayoutTaskCharCount']} '
            'vsyncP99=${performance['vsyncOverheadP99Micros']}µs '
            'buildP99=${performance['buildP99Micros']}µs '
            'rasterP99=${performance['rasterP99Micros']}µs',
          );
        }
        debugPrint(
          'READER_CONTINUOUS_RESULT status=passed seed=$_seed '
          'requestedIterations=$_iterations '
          'requestedDurationSeconds=$_durationSeconds completed=$completed '
          'samples=${probe.sampleCount} '
          'suspectedAnomalies=${probe.suspectedAnomalyCount} '
          'finalPhase=${finalSnapshot['phase']} '
          'finalQueueDepth=${finalSnapshot['pumpQueueDepth']} '
          'finalLayoutGeneration=${finalSnapshot['layoutGeneration']} '
          'finalEpoch=${finalSnapshot['epoch']} '
          'invariantHookEnabled=$_enableInvariantHook '
          'invariantViolations=${invariantViolations.length} '
          'lastActions=${lastActions.join(' || ')}',
        );
      } catch (error, stackTrace) {
        debugPrint(
          'READER_CONTINUOUS_FAILURE seed=$_seed completed=$completed '
          'samples=${probe.sampleCount} '
          'suspectedAnomalies=${probe.suspectedAnomalyCount} '
          'lastActions=${lastActions.join(' || ')} error=$error\n$stackTrace',
        );
        rethrow;
      }
    } finally {
      HybridReaderScreen.debugFrameInvariantsEnabled = false;
      ErrorWidget.builder = previousErrorWidgetBuilder;
      FlutterError.onError = previousFlutterErrorHandler;
    }
  }, timeout: _continuousTestTimeout);
}

/// Equal-area control for P4 ceiling attribution.
///
/// This is intentionally a harness-only route. It uses the same device
/// viewport and the same pushed fixture text, but replaces the Reader's
/// chapter/layout/pump machinery with one ordinary Flutter scroll surface.
/// The control retains the same app FrameTiming telemetry and driver timeline
/// validation path as the Reader workload.
Future<void> _runSimpleScrollControl(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final previousErrorWidgetBuilder = ErrorWidget.builder;
  final previousFlutterErrorHandler = FlutterError.onError;
  final telemetry = HybridTelemetry();
  final controlKey = GlobalKey<_SimpleScrollControlState>();
  try {
    // Reuse the existing bounded fixture provision path so the control has
    // the same 53MB text source and app-owned external-files visibility as
    // the Reader workload. This warm-up is outside the performance window.
    await ReaderTestHarness(tester).startAndProvision();
    final fixture = File(readerFixturePath);
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'control fixture 不存在：$readerFixturePath',
    );
    final text = await fixture.readAsString();
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: _SimpleScrollControl(
            key: controlKey,
            chunks: _chunkFixtureText(text),
            telemetry: telemetry,
          ),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(_SimpleScrollControl).evaluate().isNotEmpty,
      reason: 'simple scroll control 未建立',
    );
    await pumpVsyncPaced(tester, const Duration(milliseconds: 750));
    telemetry.resetPerformanceWindow();

    final startedAt = DateTime.now();
    var completed = 0;
    final actionMarkers = <String>[];
    void recordAction() {
      final entry = '#$completed simple_scroll_forward';
      actionMarkers.add(entry);
      debugPrint('READER_CONTINUOUS_ACTION seed=$_seed $entry');
    }

    await binding.watchPerformance(() async {
      while ((_durationSeconds > 0 &&
              DateTime.now().difference(startedAt).inSeconds <
                  _durationSeconds) ||
          (_durationSeconds == 0 && completed < _iterations)) {
        recordAction();
        final controller = controlKey.currentState?.controller;
        expect(controller, isNotNull, reason: 'control ScrollController 未建立');
        final maxExtent = controller!.position.maxScrollExtent;
        expect(maxExtent, greaterThan(0), reason: 'control scroll extent 為 0');
        final startOffset = controller.offset;
        for (var step = 0; step < 65; step += 1) {
          controller.jumpTo(
            math.min(maxExtent, startOffset + (step + 1) * 8.0),
          );
          await tester.pump(readerVsyncStep);
        }
        if ((controller.offset - startOffset).abs() < 2) {
          fail('simple control scroll 在 action 內沒有進展');
        }
        if (controller.offset >= maxExtent - 2) {
          controller.jumpTo(0);
          await pumpVsyncPaced(tester, const Duration(milliseconds: 80));
        }
        completed += 1;
      }
    }, reportKey: 'timeline');

    final performance = telemetry.sessionSummary();
    final frameCount = (performance['frames'] as num?)?.toInt() ?? 0;
    final frameP99Micros =
        (performance['frameP99Micros'] as num?)?.toDouble() ?? 0;
    final gateEvaluated = !_enableInvariantHook && frameCount >= 300;
    final passed =
        gateEvaluated &&
        frameP99Micros < HybridTelemetry.strict120HzFrameP99TargetMicros;
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['appTelemetry'] = <String, Object?>{
      ...performance,
      'invariantHookEnabled': false,
      'control': 'simple_lazy_list_view',
    };
    binding.reportData!['continuousResult'] = <String, Object?>{
      'semanticStatus': 'passed',
      'completedActions': completed,
      'actionMarkers': actionMarkers,
      'samples': frameCount,
      'suspectedAnomalies': 0,
      'finalPhase': 'ready',
      'finalQueueDepth': 0,
      'performanceStatus': !gateEvaluated
          ? 'insufficient'
          : passed
          ? 'passed'
          : 'failed',
      'performanceGateEvaluated': gateEvaluated,
      'invariantHookEnabled': false,
      'invariantViolationCount': 0,
      'control': 'simple_lazy_list_view',
    };
    debugPrint(
      'READER_CONTINUOUS_PERFORMANCE '
      'status=${passed ? 'passed' : 'failed'} '
      'targetP99Micros=${HybridTelemetry.strict120HzFrameP99TargetMicros} '
      'actualP99Micros=$frameP99Micros frames=$frameCount '
      'taskP99Micros=0 worstTaskMicros=0 worstTaskChars=0 tasksOver8ms=0 '
      'vsyncP99=${performance['vsyncOverheadP99Micros']} '
      'buildP99=${performance['buildP99Micros']} '
      'rasterP99=${performance['rasterP99Micros']}',
    );
    debugPrint(
      'READER_CONTINUOUS_RESULT status=passed seed=$_seed '
      'requestedIterations=$_iterations requestedDurationSeconds=$_durationSeconds '
      'completed=$completed samples=$frameCount suspectedAnomalies=0 '
      'finalPhase=ready finalQueueDepth=0 finalLayoutGeneration=0 finalEpoch=0 '
      'invariantHookEnabled=false invariantViolations=0 '
      'lastActions=${actionMarkers.join(' || ')}',
    );
    if (_enforceFrameP99 && gateEvaluated && !passed) {
      fail(
        'simple control 120Hz frame P99 未達標：actual=${frameP99Micros}µs '
        'target=<${HybridTelemetry.strict120HzFrameP99TargetMicros}µs '
        'frames=$frameCount',
      );
    }
  } finally {
    // Detach the callback even if the strict control gate fails. The state is
    // owned by the temporary runApp tree and will be disposed by Flutter.
    controlKey.currentState?.detachTimingCallback();
    ErrorWidget.builder = previousErrorWidgetBuilder;
    FlutterError.onError = previousFlutterErrorHandler;
  }
}

class _SimpleScrollControl extends StatefulWidget {
  const _SimpleScrollControl({
    super.key,
    required this.chunks,
    required this.telemetry,
  });

  final List<String> chunks;
  final HybridTelemetry telemetry;

  @override
  State<_SimpleScrollControl> createState() => _SimpleScrollControlState();
}

class _SimpleScrollControlState extends State<_SimpleScrollControl> {
  final ScrollController controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_recordFrameTimings);
  }

  void _recordFrameTimings(List<ui.FrameTiming> timings) {
    widget.telemetry.recordFrameTimings(timings);
  }

  void detachTimingCallback() {
    WidgetsBinding.instance.removeTimingsCallback(_recordFrameTimings);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_recordFrameTimings);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
      itemCount: widget.chunks.length,
      itemBuilder: (context, index) => Text(
        widget.chunks[index],
        textDirection: TextDirection.ltr,
        style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.6),
      ),
    );
  }
}

List<String> _chunkFixtureText(String text) {
  const chunkCharLimit = 2000;
  final chunks = <String>[];
  final current = StringBuffer();
  for (final line in text.split('\n')) {
    final nextLength = current.length + line.length + 1;
    if (current.isNotEmpty && nextLength > chunkCharLimit) {
      chunks.add(current.toString());
      current.clear();
    }
    current.writeln(line);
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}

Future<void> _runAction(
  String action, {
  required int iteration,
  required _ContinuousReaderProbe probe,
}) async {
  switch (action) {
    case 'scroll_slow':
      await _slowDrag(
        probe,
        label: 'scroll-slow',
        moves: const <double>[-70, -70, -55, -55, -40, -40],
      );
      await _settle(probe, 'scroll-slow');
    case 'scroll_fast':
      await _fling(
        probe,
        label: 'scroll-fast',
        velocity: const Offset(0, -2200),
        speed: 4500,
        samples: const <int>[55, 110, 230],
      );
      await _settle(probe, 'scroll-fast');
    case 'scroll_long_distance':
      await _fling(
        probe,
        label: 'scroll-long-distance',
        velocity: const Offset(0, -3200),
        speed: 6000,
        samples: const <int>[55, 120, 260, 520],
      );
      await _settle(probe, 'scroll-long-distance');
    case 'scroll_variable_speed':
      await _slowDrag(
        probe,
        label: 'scroll-variable-speed',
        moves: const <double>[-35, -125, -20, -190, 75, -55, 25],
      );
      await _settle(probe, 'scroll-variable-speed');
    case 'scroll_brake':
      await _fling(
        probe,
        label: 'scroll-brake-forward',
        velocity: const Offset(0, -2600),
        speed: 5200,
        samples: const <int>[55, 120],
      );
      await _fling(
        probe,
        label: 'scroll-brake-reverse',
        velocity: const Offset(0, 1900),
        speed: 4300,
        samples: const <int>[55, 120, 260],
      );
      await _settle(probe, 'scroll-brake');
    case 'scroll_cross_chapter_ballistic':
      await _runBallisticChapterRace(probe, iteration);
    case 'scroll_reverse':
      await _fling(
        probe,
        label: 'scroll-reverse-backward',
        velocity: const Offset(0, 1900),
        speed: 4300,
        samples: const <int>[55, 120, 260],
      );
      await _fling(
        probe,
        label: 'scroll-reverse-forward',
        velocity: const Offset(0, -1500),
        speed: 3900,
        samples: const <int>[55, 120, 260],
      );
      await _settle(probe, 'scroll-reverse');
    case 'scroll_short_chapter_chain':
      await _fling(
        probe,
        label: 'scroll-short-chapter-chain',
        velocity: const Offset(0, -3600),
        speed: 6500,
        samples: const <int>[55, 120, 260, 520, 900],
      );
      await _settle(probe, 'scroll-short-chapter-chain');
    case 'scroll_book_start_boundary':
      final startRuntime = probe.harness.runtimeForTesting;
      await startRuntime.jumpToChapter(0);
      await _settle(probe, 'scroll-book-start-setup');
      await _fling(
        probe,
        label: 'scroll-book-start-boundary',
        velocity: const Offset(0, 2200),
        speed: 4500,
        samples: const <int>[55, 120, 260],
      );
      await _settle(probe, 'scroll-book-start-boundary');
    case 'scroll_book_end_boundary':
      final endRuntime = probe.harness.runtimeForTesting;
      await endRuntime.jumpToChapter(probe.harness.chapters.length - 1);
      await _settle(probe, 'scroll-book-end-setup');
      await _fling(
        probe,
        label: 'scroll-book-end-boundary',
        velocity: const Offset(0, -2600),
        speed: 5200,
        samples: const <int>[55, 120, 260],
      );
      await _settle(probe, 'scroll-book-end-boundary');
    case 'interaction_control':
      await probe.harness.showControls();
      probe.sample('interaction-control-open');
      final floatingButtons = find.byType(FloatingActionButton);
      if (floatingButtons.evaluate().isNotEmpty) {
        await probe.tester.tap(floatingButtons.last);
        await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 260));
        probe.sample('interaction-control-toggle');
      }
      await probe.harness.dismissControls();
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 260));
      probe.sample('interaction-control-settled');
      await probe.captureSettledScreenshot('interaction-control');
    case 'interaction_page':
      probe.harness.setTapAction(4, 1);
      await probe.harness.dismissControls();
      final pageReader = find.byType(HybridReaderScreen).last;
      await probe.tester.tapAt(probe.tester.getCenter(pageReader));
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 800));
      probe.sample('interaction-page-end');
      await _settle(probe, 'interaction-page');
    case 'interaction_menu_open_close':
      await probe.harness.showControls();
      probe.sample('interaction-menu-open');
      await probe.harness.dismissControls();
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 260));
      probe.sample('interaction-menu-close');
      await probe.captureSettledScreenshot('interaction-menu-close');
    case 'interaction_tts_toggle':
      await probe.harness.toggleTts();
      await probe.harness.dismissTransientSheetsForTesting();
      await _settle(probe, 'interaction-tts');
    case 'style_typography':
      probe.harness.setTypographyForTesting();
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
      await _settle(probe, 'style-typography');
    case 'style_theme_text_color':
      probe.harness.setThemeForTesting();
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
      await _settle(probe, 'style-theme-text-color');
    case 'style_chinese_conversion':
      probe.harness.setChineseConversionForTesting();
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
      await _settle(probe, 'style-chinese-conversion');
    case 'style_padding':
      probe.harness.setPaddingForTesting();
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
      await _settle(probe, 'style-padding');
    case 'source_reload':
      await probe.harness.reloadContentForTesting();
      await _settle(probe, 'source-reload');
    case 'visual_checkpoint_matrix':
      await _runVisualCheckpointMatrix(probe);
    case 'navigation_next_chapter':
      final nextRuntime = probe.harness.runtimeForTesting;
      final nextTarget = math.min(
        nextRuntime.state.visibleLocation.chapterIndex + 1,
        probe.harness.chapters.length - 1,
      );
      await _jumpAndSample(probe, target: nextTarget, label: 'navigation-next');
      await _settle(probe, 'navigation-next');
    case 'navigation_previous_chapter':
      final previousRuntime = probe.harness.runtimeForTesting;
      final previousTarget = math.max(
        previousRuntime.state.visibleLocation.chapterIndex - 1,
        0,
      );
      await _jumpAndSample(
        probe,
        target: previousTarget,
        label: 'navigation-previous',
      );
      await _settle(probe, 'navigation-previous');
    case 'navigation_directory_jump':
      final directoryTarget =
          (probe.harness.runtimeForTesting.state.visibleLocation.chapterIndex +
                  13)
              .clamp(0, probe.harness.chapters.length - 1)
              .toInt();
      await probe.harness.jumpToChapterFromDirectory(directoryTarget);
      probe.sample('navigation-directory-first-readable');
      await _settle(probe, 'navigation-directory');
    case 'navigation_directory_jump_then_immediate_read':
      final harness = probe.harness;
      final runtime = harness.runtimeForTesting;
      final current = runtime.state.visibleLocation.chapterIndex;
      final target = (current + 13)
          .clamp(0, harness.chapters.length - 1)
          .toInt();
      await harness.jumpToChapterFromDirectory(target);
      probe.sample('directory-jump-complete-target-$target');
      await _slowDrag(
        probe,
        label: 'directory-immediate-read',
        moves: const <double>[-70, -60, -45, 35],
      );
      await _settle(probe, 'directory-jump-then-immediate-read');
    case 'navigation_bookmark_jump':
      final bookmarkRuntime = probe.harness.runtimeForTesting;
      final bookmarkTarget = math.min(
        bookmarkRuntime.state.visibleLocation.chapterIndex + 3,
        probe.harness.chapters.length - 1,
      );
      final bookmarkLocation = ReaderV2Location(
        chapterIndex: bookmarkTarget,
        charOffset: 0,
      );
      final bookmarkJump = bookmarkRuntime.jumpToLocation(bookmarkLocation);
      await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 55));
      probe.sample('navigation-bookmark-first-readable');
      await bookmarkJump.timeout(_continuousNoProgressLimit);
      await _settle(probe, 'navigation-bookmark');
    case 'entry_cold_open_book':
      await probe.harness.closeReaderToBookshelf();
      await probe.harness.openBook();
      probe.sample('entry-cold-first-readable');
      await _settle(probe, 'entry-cold');
    case 'entry_hot_open_book':
      await probe.harness.hotReopenCurrentBook();
      probe.sample('entry-hot-first-readable');
      await _settle(probe, 'entry-hot');
      await probe.harness.closeHotReentry();
    case 'slow_read_forward':
      await _slowDrag(
        probe,
        label: 'slow-forward',
        moves: const <double>[-70, -70, -55, -55, -40, -40],
      );
      await _settle(probe, 'slow-forward');
    case 'small_correction':
      await _slowDrag(
        probe,
        label: 'correction',
        moves: const <double>[-100, -70, 45, 35, -45],
      );
      await _settle(probe, 'correction');
    case 'fling_forward_then_reverse':
      await _fling(
        probe,
        label: 'fling-forward',
        velocity: const Offset(0, -1750),
        speed: 4000,
        samples: const <int>[55, 105, 220],
      );
      await _fling(
        probe,
        label: 'fling-reverse',
        velocity: const Offset(0, 1450),
        speed: 3800,
        samples: const <int>[55, 120, 260],
      );
      await _settle(probe, 'fling-forward-then-reverse');
    case 'fling_reverse_then_continue':
      await _fling(
        probe,
        label: 'fling-backward',
        velocity: const Offset(0, 1650),
        speed: 3900,
        samples: const <int>[55, 110, 230],
      );
      await _slowDrag(
        probe,
        label: 'backward-then-continue',
        moves: const <double>[-60, -60, -45, -45],
      );
      await _settle(probe, 'fling-reverse-then-continue');
    case 'next_or_previous_chapter':
      final harness = probe.harness;
      final runtime = harness.runtimeForTesting;
      final current = runtime.state.visibleLocation.chapterIndex;
      final forward = iteration.isEven;
      final target = forward
          ? math.min(current + 1, harness.chapters.length - 1)
          : math.max(current - 1, 0);
      await _jumpAndSample(
        probe,
        target: target,
        label: forward ? 'next-chapter' : 'previous-chapter',
      );
      await _slowDrag(
        probe,
        label: 'after-${forward ? 'next' : 'previous'}',
        moves: const <double>[-65, -55, -45],
      );
      await _settle(probe, 'next-or-previous');
    case 'chapter_switch_while_ballistic':
      await _runBallisticChapterRace(probe, iteration);
    case 'directory_jump_then_immediate_read':
      final harness = probe.harness;
      final runtime = harness.runtimeForTesting;
      final current = runtime.state.visibleLocation.chapterIndex;
      final target = (current + 13)
          .clamp(0, harness.chapters.length - 1)
          .toInt();
      await harness.jumpToChapterFromDirectory(target);
      probe.sample('directory-jump-complete-target-$target');
      await _slowDrag(
        probe,
        label: 'directory-immediate-read',
        moves: const <double>[-70, -60, -45, 35],
      );
      await _settle(probe, 'directory-jump-then-immediate-read');
    default:
      fail('未處理的 continuous action：$action');
  }
}

Future<void> _runBallisticChapterRace(
  _ContinuousReaderProbe probe,
  int iteration,
) async {
  final harness = probe.harness;
  final runtime = harness.runtimeForTesting;
  final current = runtime.state.visibleLocation.chapterIndex;
  final direction = iteration.isEven ? 1 : -1;
  final target = (current + direction * 7)
      .clamp(0, harness.chapters.length - 1)
      .toInt();
  await harness.dismissControls();
  final reader = find.byType(HybridReaderScreen).last;
  await probe.tester.fling(reader, const Offset(0, -1600), 3800);
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 90));
  probe.sample('race-fling-before-jump');
  final jump = runtime.jumpToChapter(target);
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 55));
  probe.sample('race-jump-start-target-$target');
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 125));
  probe.sample('race-jump-mid-target-$target');
  await jump.timeout(_continuousNoProgressLimit);
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 70));
  probe.sample('race-jump-complete-target-$target');
  await _slowDrag(
    probe,
    label: 'race-immediate-read',
    moves: const <double>[-55, -55, -40],
  );
  await _settle(probe, 'chapter-switch-while-ballistic');
}

/// Bounded visual-only matrix. Every screenshot is requested from inside the
/// integration test immediately after the same semantic settled predicate;
/// the host driver only persists the returned PNG bytes.
Future<void> _runVisualCheckpointMatrix(_ContinuousReaderProbe probe) async {
  await _slowDrag(
    probe,
    label: 'visual-ordinary-reading',
    moves: const <double>[-70, -70, -55, -55, -40, -40],
  );
  await _settle(probe, 'visual-ordinary-reading-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-ordinary-reading');

  await _fling(
    probe,
    label: 'visual-long-scroll',
    velocity: const Offset(0, -3200),
    speed: 6000,
    samples: const <int>[55, 120, 260, 520],
  );
  await _settle(probe, 'visual-long-scroll-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-long-scroll');

  final runtime = probe.harness.runtimeForTesting;
  final target = (runtime.state.visibleLocation.chapterIndex + 3)
      .clamp(0, probe.harness.chapters.length - 1)
      .toInt();
  await _jumpAndSample(probe, target: target, label: 'visual-chapter-jump');
  await _settle(probe, 'visual-chapter-jump-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-chapter-jump');

  probe.harness.setTypographyForTesting();
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
  await _settle(probe, 'visual-style-typography-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-style-typography');

  probe.harness.setThemeForTesting();
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
  await _settle(probe, 'visual-theme-text-color-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-theme-text-color');

  probe.harness.setPaddingForTesting();
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
  await _settle(probe, 'visual-padding-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-padding');

  probe.harness.setChineseConversionForTesting();
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 180));
  await _settle(probe, 'visual-chinese-conversion-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-chinese-conversion');

  await probe.harness.reloadContentForTesting();
  await _settle(probe, 'visual-source-reload-route-end', capture: false);
  await _settleAtFixedCheckpoint(probe, 'visual-source-reload');

  await probe.harness.toggleTts();
  await probe.harness.dismissTransientSheetsForTesting();
  await _settle(probe, 'visual-tts');
}

Future<void> _slowDrag(
  _ContinuousReaderProbe probe, {
  required String label,
  required List<double> moves,
}) async {
  await probe.harness.dismissControls();
  final reader = find.byType(HybridReaderScreen).last;
  final gesture = await probe.tester.startGesture(
    probe.tester.getCenter(reader),
  );
  for (var index = 0; index < moves.length; index += 1) {
    await moveVsyncPaced(probe.tester, gesture, Offset(0, moves[index]));
    probe.sample('$label-move-$index');
  }
  await gesture.up();
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 80));
  probe.sample('$label-up');
}

Future<void> _fling(
  _ContinuousReaderProbe probe, {
  required String label,
  required Offset velocity,
  required double speed,
  required List<int> samples,
}) async {
  await probe.harness.dismissControls();
  final reader = find.byType(HybridReaderScreen).last;
  await probe.tester.fling(reader, velocity, speed);
  var elapsed = 0;
  const ballisticDuration = 2500;
  var nextSampleIndex = 0;
  while (elapsed < ballisticDuration) {
    final nextElapsed = math.min(
      elapsed + readerVsyncStep.inMilliseconds,
      ballisticDuration,
    );
    await pumpVsyncPaced(
      probe.tester,
      Duration(milliseconds: nextElapsed - elapsed),
    );
    elapsed = nextElapsed;
    while (nextSampleIndex < samples.length &&
        elapsed >= samples[nextSampleIndex]) {
      probe.sample('$label-${samples[nextSampleIndex]}ms');
      nextSampleIndex += 1;
    }
  }
}

Future<void> _jumpAndSample(
  _ContinuousReaderProbe probe, {
  required int target,
  required String label,
}) async {
  final runtime = probe.harness.runtimeForTesting;
  final jump = runtime.jumpToChapter(target);
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 55));
  probe.sample('$label-start-target-$target');
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 120));
  probe.sample('$label-mid-target-$target');
  await jump.timeout(_continuousNoProgressLimit);
  await pumpVsyncPaced(probe.tester, const Duration(milliseconds: 70));
  probe.sample('$label-complete-target-$target');
}

Future<void> _settle(
  _ContinuousReaderProbe probe,
  String label, {
  bool capture = true,
}) async {
  Map<String, Object?>? latest;
  await pumpUntil(
    probe.tester,
    () {
      latest = probe.harness.debugSnapshot();
      probe.checkNoProgressWatchdog('settle-$label', snapshot: latest);
      final snapshot = latest!;
      final missing = snapshot['missingParagraphKeys'] as List<dynamic>;
      return snapshot['phase'] == 'ready' &&
          snapshot['initialRestoreCompleted'] == true &&
          snapshot['isScrolling'] == false &&
          snapshot['pumpQueueDepth'] == 0 &&
          snapshot['visibleKeysContiguous'] == true &&
          missing.isEmpty &&
          snapshot['pendingChapterJumpTarget'] == null;
    },
    timeout: const Duration(seconds: 20),
    step: readerVsyncStep,
    reason: 'Reader 在 $label 後沒有進入可驗證的 settled 狀態：$latest',
  );
  probe.markFullyStable();
  probe.sample('$label-settled');
  final snapshot = probe.harness.debugSnapshot();
  expect(snapshot['phase'], 'ready');
  expect(snapshot['initialRestoreCompleted'], isTrue);
  expect(snapshot['layoutGeneration'], snapshot['epoch']);
  expect(snapshot['pumpQueueDepth'], 0);
  expect(snapshot['visibleKeysContiguous'], isTrue);
  expect((snapshot['visibleKeys'] as List<dynamic>), isNotEmpty);
  expect((snapshot['missingParagraphKeys'] as List<dynamic>), isEmpty);
  expect(snapshot['pendingChapterJumpTarget'], isNull);
  expect(snapshot['capturedLocation'], isNotNull);
  if (capture) {
    // Semantic settling can complete on the frame that schedules the final
    // layout update. Give the actual Flutter surface two vsync-paced frames
    // before capture so the checkpoint observes painted output, not merely a
    // ready/empty queue state.
    await pumpVsyncPaced(probe.tester, readerVsyncStep * 2);
    await probe.captureSettledScreenshot(label);
  }
}

Future<void> _settleAtFixedCheckpoint(
  _ContinuousReaderProbe probe,
  String label,
) async {
  final jump = probe.harness.runtimeForTesting.jumpToLocation(
    const ReaderV2Location(chapterIndex: 4, charOffset: 40),
  );
  await jump.timeout(_continuousNoProgressLimit);
  await _settle(probe, label);
}

final class _OperationTiming {
  const _OperationTiming({
    required this.duration,
    required this.firstReadable,
    required this.fullyStable,
  });

  final Duration duration;
  final Duration firstReadable;
  final Duration fullyStable;
}

final class _ContinuousReaderProbe {
  _ContinuousReaderProbe({
    required this.tester,
    required this.harness,
    required this.binding,
  });

  final WidgetTester tester;
  final ReaderTestHarness harness;
  final IntegrationTestWidgetsFlutterBinding binding;
  bool _surfaceConvertedForScreenshot = false;
  int _screenshotIndex = 0;
  Map<String, Object?>? _previousSnapshot;
  final List<String> _suspectedAnomalies = <String>[];
  final Map<String, List<_OperationTiming>> _operationTimings =
      <String, List<_OperationTiming>>{};
  DateTime? _lastProgressAt;
  String? _lastProgressSignature;
  String? _activeAction;
  String? _activeOperation;
  Stopwatch? _operationStopwatch;
  Duration? _firstReadable;
  Duration? _fullyStable;
  int sampleCount = 0;

  int get suspectedAnomalyCount => _suspectedAnomalies.length;

  /// Capture the actual Flutter surface while the Reader's semantic oracle is
  /// settled. This is enabled only by a compile-time integration-test define;
  /// production app code has no screenshot path or runtime switch.
  Future<void> captureSettledScreenshot(String label) async {
    if (!_captureSettledScreenshots) return;
    if (!_surfaceConvertedForScreenshot) {
      await binding.convertFlutterSurfaceToImage();
      _surfaceConvertedForScreenshot = true;
    }
    final normalized = label.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    final name = 'p4v-settled-seed-$_seed-$normalized-${_screenshotIndex++}';
    final snapshot = harness.debugSnapshot();
    await binding.takeScreenshot(name);
    debugPrint(
      'READER_CONTINUOUS_SCREENSHOT name=$name '
      'phase=${snapshot['phase']} '
      'location=${jsonEncode(snapshot['capturedLocation'])} '
      'visible=${jsonEncode(snapshot['visibleKeys'])}',
    );
  }

  void beginAction(String action, {required String actionIdentity}) {
    _activeAction = action;
    _activeOperation = actionIdentity;
    // Motion attribution is scoped to one action. Carrying the previous
    // action's settled chapter location into a deliberate chapter jump makes
    // the reverse-jump heuristic compare two different coordinate worlds.
    _previousSnapshot = null;
    _operationStopwatch = Stopwatch()..start();
    _firstReadable = null;
    _fullyStable = null;
    _lastProgressAt = DateTime.now();
    _lastProgressSignature = null;
  }

  void endAction() {
    final operation = _activeOperation;
    final stopwatch = _operationStopwatch;
    if (operation != null && stopwatch != null) {
      stopwatch.stop();
      final readable = _firstReadable ?? stopwatch.elapsed;
      final stable = _fullyStable ?? stopwatch.elapsed;
      _operationTimings
          .putIfAbsent(operation, () => <_OperationTiming>[])
          .add(
            _OperationTiming(
              duration: stopwatch.elapsed,
              firstReadable: readable,
              fullyStable: stable,
            ),
          );
    }
    _activeAction = null;
    _activeOperation = null;
    _operationStopwatch = null;
    _firstReadable = null;
    _fullyStable = null;
    _lastProgressAt = DateTime.now();
    _lastProgressSignature = null;
  }

  void markFullyStable() {
    if (_operationStopwatch == null || _fullyStable != null) return;
    _fullyStable = _operationStopwatch!.elapsed;
  }

  Map<String, Object?> attributionSummary({
    required Map<String, Object?> performance,
    required bool exclusiveAction,
  }) {
    double percentile(List<Duration> values, double p) {
      if (values.isEmpty) return 0;
      final micros = values.map((value) => value.inMicroseconds).toList()
        ..sort();
      final index = ((micros.length - 1) * p).round();
      return micros[index].toDouble();
    }

    final actions = <Map<String, Object?>>[];
    for (final entry in _operationTimings.entries) {
      final durations = entry.value.map((item) => item.duration).toList();
      final readable = entry.value.map((item) => item.firstReadable).toList();
      final stable = entry.value.map((item) => item.fullyStable).toList();
      actions.add(<String, Object?>{
        'action': entry.key,
        'category': _operationCategory(entry.key),
        'samples': entry.value.length,
        'durationP50Micros': percentile(durations, 0.50),
        'durationP95Micros': percentile(durations, 0.95),
        'durationP99Micros': percentile(durations, 0.99),
        'durationWorstMicros': percentile(durations, 1.0),
        'firstReadableP50Micros': percentile(readable, 0.50),
        'firstReadableP95Micros': percentile(readable, 0.95),
        'fullyStableP50Micros': percentile(stable, 0.50),
        'fullyStableP95Micros': percentile(stable, 0.95),
        'fullyStableP99Micros': percentile(stable, 0.99),
        'fullyStableWorstMicros': percentile(stable, 1.0),
      });
    }
    return <String, Object?>{
      'exclusiveAction': exclusiveAction,
      'frameScope': exclusiveAction
          ? 'performance window contains only this forced action'
          : 'mixed action session; not a category conclusion',
      'frameMetrics': <String, Object?>{
        'frames': performance['frames'],
        'p50': performance['frameP50Micros'],
        'p95': performance['frameP95Micros'],
        'p99': performance['frameP99Micros'],
        'worst': performance['worstFrameMicros'],
        'j8': performance['jankOver8ms'],
        'j16': performance['jankOver16ms'],
        'j33': performance['jankOver33ms'],
        'maxStreak': performance['maxConsecutiveMissedFrames'],
        'taskP99': performance['layoutTaskP99Micros'],
        'taskOver8': performance['layoutTasksOver8ms'],
        'vsyncP99': performance['vsyncOverheadP99Micros'],
        'buildP99': performance['buildP99Micros'],
        'rasterP99': performance['rasterP99Micros'],
      },
      'actions': actions,
    };
  }

  void sample(String label) {
    final snapshot = harness.debugSnapshot();
    _markReadableIfReady(snapshot);
    sampleCount += 1;
    checkNoProgressWatchdog(label, snapshot: snapshot);
    _checkMotion(label, snapshot);
    final payload = _compactSnapshot(label, snapshot);
    debugPrint('READER_CONTINUOUS_SAMPLE ${jsonEncode(payload)}');
    _previousSnapshot = snapshot;
    harness.expectNoFlutterException();
  }

  void _markReadableIfReady(Map<String, Object?> snapshot) {
    if (_operationStopwatch == null || _firstReadable != null) return;
    final visible =
        (snapshot['visibleKeys'] as List<dynamic>?) ?? const <dynamic>[];
    final missing =
        (snapshot['missingParagraphKeys'] as List<dynamic>?) ??
        const <dynamic>[];
    if (snapshot['phase'] == 'ready' &&
        visible.isNotEmpty &&
        missing.isEmpty &&
        snapshot['initialRestoreCompleted'] == true) {
      _firstReadable = _operationStopwatch!.elapsed;
    }
  }

  void checkNoProgressWatchdog(String label, {Map<String, Object?>? snapshot}) {
    final current = snapshot ?? harness.debugSnapshot();
    final active =
        _activeAction != null ||
        current['phase'] != 'ready' ||
        current['dragging'] == true ||
        current['isScrolling'] == true ||
        current['restoreLocked'] == true ||
        current['initialRestoreCompleted'] != true ||
        current['pendingChapterJumpTarget'] != null ||
        (current['pumpQueueDepth'] as num? ?? 0) > 0 ||
        ((current['missingParagraphKeys'] as List<dynamic>?)?.isNotEmpty ??
            false) ||
        ((current['visibleKeys'] as List<dynamic>?)?.isEmpty ?? true);
    if (!active) {
      _lastProgressAt = DateTime.now();
      _lastProgressSignature = null;
      return;
    }

    final signature = jsonEncode(<String, Object?>{
      'phase': current['phase'],
      'offset': current['scrollOffset'],
      'location': current['capturedLocation'],
      'locationRevision': current['runtimeLocationRevision'],
      'layout': current['layoutGeneration'],
      'epoch': current['epoch'],
      'reset': current['documentIndexResetGeneration'],
      'pending': current['pendingChapterJumpTarget'],
      'queue': current['pumpQueueDepth'],
      'visible': current['visibleKeys'],
      'missing': current['missingParagraphKeys'],
    });
    final now = DateTime.now();
    if (_lastProgressSignature != signature || _lastProgressAt == null) {
      _lastProgressSignature = signature;
      _lastProgressAt = now;
      return;
    }
    final stagnantFor = now.difference(_lastProgressAt!);
    if (stagnantFor < _continuousNoProgressLimit) return;

    final evidence = <String, Object?>{
      'label': label,
      'action': _activeAction,
      'stagnantSeconds': stagnantFor.inMilliseconds / 1000.0,
      'signature': signature,
      'snapshot': _compactSnapshot(label, current),
    };
    debugPrint('READER_CONTINUOUS_WATCHDOG_ABORT ${jsonEncode(evidence)}');
    throw StateError(
      'continuous watchdog 在 $label 發現 ${stagnantFor.inSeconds} 秒無進展；'
      '已中止並交由 runner 收集 failure artifacts。',
    );
  }

  void throwIfSuspectedAnomalies() {
    if (_suspectedAnomalies.isEmpty) return;
    fail(
      'Reader continuous workload 發現疑似 semantic reverse jump：'
      '${_suspectedAnomalies.join(' || ')}',
    );
  }

  Map<String, Object?> _compactSnapshot(
    String label,
    Map<String, Object?> snapshot,
  ) {
    final visibleKeys =
        snapshot['visibleKeys'] as List<dynamic>? ?? const <dynamic>[];
    final missingKeys =
        snapshot['missingParagraphKeys'] as List<dynamic>? ?? const <dynamic>[];
    return <String, Object?>{
      'label': label,
      // Keep one logcat record below Android's per-line limit. The full
      // debugSnapshot remains available to the in-process assertions; this
      // compact record carries the cross-sample race/performance evidence.
      't': snapshot['capturedAtMs'],
      'rate': snapshot['displayRefreshRate'],
      'phase': snapshot['phase'],
      'o': snapshot['scrollOffset'],
      'vh': snapshot['viewportHeight'],
      'dir': snapshot['scrollDirection'],
      'scrolling': snapshot['isScrolling'],
      'dragging': snapshot['dragging'],
      'locked': snapshot['restoreLocked'],
      'locRev': snapshot['runtimeLocationRevision'],
      'location': snapshot['capturedLocation'],
      'pending': snapshot['pendingChapterJumpTarget'],
      'layout': snapshot['layoutGeneration'],
      'epoch': snapshot['epoch'],
      'idxRev': snapshot['documentIndexRevision'],
      'reset': snapshot['documentIndexResetGeneration'],
      'admitted': snapshot['admittedCount'],
      'before': snapshot['beforeCount'],
      'after': snapshot['centerAndAfterCount'],
      'visible': visibleKeys.length,
      'chapters': snapshot['visibleChapters'],
      'contiguous': snapshot['visibleKeysContiguous'],
      'missing': missingKeys.length,
      'loaded': snapshot['loadedChapterCount'],
      'enqueued': snapshot['enqueuedCount'],
      'queue': snapshot['pumpQueueDepth'],
      'leadF': snapshot['forwardLeadPx'],
      'leadB': snapshot['backwardLeadPx'],
      'frames': <String, Object?>{
        'p50': snapshot['rollingFrameP50Micros'],
        'p95': snapshot['rollingFrameP95Micros'],
        'p99': snapshot['rollingFrameP99Micros'],
        'j8': snapshot['rollingJankOver8ms'],
        'j16': snapshot['rollingJankOver16ms'],
        'j33': snapshot['rollingJankOver33ms'],
        'worst': snapshot['worstFrameMicros'],
        'streak': snapshot['consecutiveMissedFrames'],
        'maxStreak': snapshot['maxConsecutiveMissedFrames'],
        'taskP99': snapshot['layoutTaskP99Micros'],
        'taskWorst': snapshot['worstLayoutTaskMicros'],
        'taskChars': snapshot['worstLayoutTaskCharCount'],
        'taskOver8': snapshot['layoutTasksOver8ms'],
        'vsyncP99': snapshot['vsyncOverheadP99Micros'],
        'buildP99': snapshot['buildP99Micros'],
        'rasterP99': snapshot['rasterP99Micros'],
      },
    };
  }

  void _checkMotion(String label, Map<String, Object?> snapshot) {
    final previous = _previousSnapshot;
    if (previous == null) return;
    if (previous['phase'] != 'ready' || snapshot['phase'] != 'ready') return;
    if (previous['dragging'] == true || snapshot['dragging'] == true) return;
    if (previous['pendingChapterJumpTarget'] != null ||
        snapshot['pendingChapterJumpTarget'] != null) {
      return;
    }
    final previousOffset = _asDouble(previous['scrollOffset']);
    final currentOffset = _asDouble(snapshot['scrollOffset']);
    final previousLocation = _asLocation(previous['capturedLocation']);
    final currentLocation = _asLocation(snapshot['capturedLocation']);
    final viewportHeight = _asDouble(snapshot['viewportHeight']);
    if (previousOffset == null ||
        currentOffset == null ||
        previousLocation == null ||
        currentLocation == null ||
        viewportHeight == null) {
      return;
    }
    final physicalDelta = currentOffset - previousOffset;
    final logicalDelta =
        _logicalOrder(currentLocation) - _logicalOrder(previousLocation);
    // A small correction or a chapter transition is expected to change the
    // semantic anchor. Only flag a large forward physical move that reports a
    // substantial backward logical move while both samples are otherwise
    // stable; the final settled checks then decide whether it is actionable.
    if (physicalDelta > math.max(300.0, viewportHeight * 0.75) &&
        logicalDelta < -2000) {
      final evidence =
          'label=$label physicalDelta=${physicalDelta.toStringAsFixed(1)} '
          'logicalDelta=${logicalDelta.toStringAsFixed(1)} '
          'previous=$previousLocation current=$currentLocation';
      _suspectedAnomalies.add(evidence);
      debugPrint('READER_CONTINUOUS_ANOMALY $evidence');
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  static Map<String, Object?>? _asLocation(Object? value) {
    if (value is! Map) return null;
    final chapter = value['chapterIndex'];
    final offset = value['charOffset'];
    if (chapter is! num || offset is! num) return null;
    return <String, Object?>{
      'chapterIndex': chapter.toInt(),
      'charOffset': offset.toInt(),
    };
  }

  static double _logicalOrder(Map<String, Object?> location) {
    return (location['chapterIndex'] as int) * 1000000000.0 +
        (location['charOffset'] as int).toDouble();
  }
}
