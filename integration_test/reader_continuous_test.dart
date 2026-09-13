import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/telemetry/hybrid_telemetry.dart';

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
const int _lastActionLimit = 24;
const bool _enforceFrameP99 = bool.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_ENFORCE_FRAME_P99',
  defaultValue: true,
);
const String _forcedAction = String.fromEnvironment(
  'NIGHT_READER_CONTINUOUS_ACTION',
  defaultValue: '',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('西游記 Reader continuous layout and scroll race validation', (
    tester,
  ) async {
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    final previousFlutterErrorHandler = FlutterError.onError;
    try {
      final harness = ReaderTestHarness(tester);
      await harness.startAndProvision();
      await harness.openBook();

      final probe = _ContinuousReaderProbe(tester: tester, harness: harness);
      probe.sample('open');
      await _settle(probe, 'initial');
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
        while (shouldContinue()) {
          final action = _forcedAction.isEmpty
              ? actions[random.nextInt(actions.length)]
              : _forcedAction;
          if (!actions.contains(action)) {
            fail('未支援的 continuous action：$action');
          }
          record(action);
          await _runAction(action, iteration: completed, probe: probe);
          harness.expectNoFlutterException();
          completed += 1;
        }

        probe.throwIfSuspectedAnomalies();
        final finalSnapshot = harness.debugSnapshot();
        final performance = harness.debugPerformanceSummary();
        final frameCount = (performance['frames'] as num?)?.toInt() ?? 0;
        final frameP99Micros =
            (performance['frameP99Micros'] as num?)?.toDouble() ?? 0;
        final performancePassed =
            frameCount > 0 &&
            frameP99Micros < HybridTelemetry.strict120HzFrameP99TargetMicros;
        debugPrint(
          'READER_CONTINUOUS_PERFORMANCE '
          'status=${performancePassed ? 'passed' : 'failed'} '
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
        if (_enforceFrameP99 && !performancePassed) {
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
      ErrorWidget.builder = previousErrorWidgetBuilder;
      FlutterError.onError = previousFlutterErrorHandler;
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<void> _runAction(
  String action, {
  required int iteration,
  required _ContinuousReaderProbe probe,
}) async {
  switch (action) {
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
      final harness = probe.harness;
      final runtime = harness.runtimeForTesting;
      final current = runtime.state.visibleLocation.chapterIndex;
      final direction = iteration.isEven ? 1 : -1;
      final target = (current + direction * 7)
          .clamp(0, harness.chapters.length - 1)
          .toInt();
      await harness.dismissControls();
      final reader = find.byType(HybridReaderScreen).first;
      await probe.tester.fling(reader, const Offset(0, -1600), 3800);
      await probe.tester.pump(const Duration(milliseconds: 90));
      probe.sample('race-fling-before-jump');
      final jump = runtime.jumpToChapter(target);
      await probe.tester.pump(const Duration(milliseconds: 55));
      probe.sample('race-jump-start-target-$target');
      await probe.tester.pump(const Duration(milliseconds: 125));
      probe.sample('race-jump-mid-target-$target');
      await jump;
      await probe.tester.pump(const Duration(milliseconds: 70));
      probe.sample('race-jump-complete-target-$target');
      await _slowDrag(
        probe,
        label: 'race-immediate-read',
        moves: const <double>[-55, -55, -40],
      );
      await _settle(probe, 'chapter-switch-while-ballistic');
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

Future<void> _slowDrag(
  _ContinuousReaderProbe probe, {
  required String label,
  required List<double> moves,
}) async {
  await probe.harness.dismissControls();
  final reader = find.byType(HybridReaderScreen).first;
  final gesture = await probe.tester.startGesture(
    probe.tester.getCenter(reader),
  );
  for (var index = 0; index < moves.length; index += 1) {
    await gesture.moveBy(Offset(0, moves[index]));
    await probe.tester.pump(const Duration(milliseconds: 65));
    probe.sample('$label-move-$index');
  }
  await gesture.up();
  await probe.tester.pump(const Duration(milliseconds: 80));
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
  final reader = find.byType(HybridReaderScreen).first;
  await probe.tester.fling(reader, velocity, speed);
  var elapsed = 0;
  for (final delay in samples) {
    final delta = delay - elapsed;
    if (delta > 0) {
      await probe.tester.pump(Duration(milliseconds: delta));
      elapsed = delay;
    }
    probe.sample('$label-${delay}ms');
  }
}

Future<void> _jumpAndSample(
  _ContinuousReaderProbe probe, {
  required int target,
  required String label,
}) async {
  final runtime = probe.harness.runtimeForTesting;
  final jump = runtime.jumpToChapter(target);
  await probe.tester.pump(const Duration(milliseconds: 55));
  probe.sample('$label-start-target-$target');
  await probe.tester.pump(const Duration(milliseconds: 120));
  probe.sample('$label-mid-target-$target');
  await jump;
  await probe.tester.pump(const Duration(milliseconds: 70));
  probe.sample('$label-complete-target-$target');
}

Future<void> _settle(_ContinuousReaderProbe probe, String label) async {
  Map<String, Object?>? latest;
  await pumpUntil(
    probe.tester,
    () {
      latest = probe.harness.debugSnapshot();
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
    step: const Duration(milliseconds: 100),
    reason: 'Reader 在 $label 後沒有進入可驗證的 settled 狀態：$latest',
  );
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
}

final class _ContinuousReaderProbe {
  _ContinuousReaderProbe({required this.tester, required this.harness});

  final WidgetTester tester;
  final ReaderTestHarness harness;
  Map<String, Object?>? _previousSnapshot;
  final List<String> _suspectedAnomalies = <String>[];
  int sampleCount = 0;

  int get suspectedAnomalyCount => _suspectedAnomalies.length;

  void sample(String label) {
    final snapshot = harness.debugSnapshot();
    sampleCount += 1;
    _checkMotion(label, snapshot);
    final payload = _compactSnapshot(label, snapshot);
    debugPrint('READER_CONTINUOUS_SAMPLE ${jsonEncode(payload)}');
    _previousSnapshot = snapshot;
    harness.expectNoFlutterException();
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
