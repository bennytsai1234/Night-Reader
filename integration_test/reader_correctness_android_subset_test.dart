import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crypto/crypto.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';

import '../test/reader_correctness/reader_correctness_case_generation.dart';
import 'reader_test_support.dart';

const String _caseId = String.fromEnvironment(
  'NIGHT_READER_C6_CASE_ID',
  defaultValue: '',
);
const String _caseListPath = String.fromEnvironment(
  'NIGHT_READER_C6_CASE_LIST_PATH',
  defaultValue: '',
);
const String _deviceId = String.fromEnvironment(
  'NIGHT_READER_C6_DEVICE_ID',
  defaultValue: 'unknown-device',
);
const bool _captureGolden = bool.fromEnvironment(
  'NIGHT_READER_C6_CAPTURE_GOLDEN',
  defaultValue: false,
);
const bool _captureFailureScreenshots = bool.fromEnvironment(
  'NIGHT_READER_C6_CAPTURE_FAILURE_SCREENSHOTS',
  defaultValue: true,
);
const bool _c6InvariantHookEnabled = bool.fromEnvironment(
  'NIGHT_READER_C6_INVARIANT_HOOK',
  defaultValue: false,
);
const bool _c6VisualOracleEnabled = bool.fromEnvironment(
  'NIGHT_READER_C6_VISUAL_ORACLE',
  defaultValue: false,
);
const String _c6HookProvenance = 'c6-correctness-integration-hook-on';
const String _c6HookMode = 'correctness-hook-on';
const String _c6HookSource =
    'integration_test/reader_correctness_android_subset_test.dart';
const String _c6OperationTraceSource =
    'C6-ReaderTestHarness.operation-trace.v2';
const String _c6RuntimeTraceSource =
    'C6-HybridFrameInvariantRecord.runtime-frame.v2';
const Duration _testTimeout = Duration(minutes: 5);
const Duration _settleTimeout = Duration(seconds: 20);

const Map<String, Object?> _c6HookProvenanceFields = <String, Object?>{
  'invariantHookEnabled': true,
  'visualOracleEnabled': true,
  'hookProvenance': _c6HookProvenance,
  'hookMode': _c6HookMode,
  'hookSource': _c6HookSource,
};

final class _C6SemanticSettleTimeout extends StateError {
  _C6SemanticSettleTimeout({required this.operationState, required this.cause})
    : super(
        'C6_SEMANTIC_SETTLE_TIMEOUT operationState=$operationState: $cause',
      );

  final String operationState;
  final Object cause;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('C6 Android case-id subset replay', (tester) async {
    if (!_c6InvariantHookEnabled || !_c6VisualOracleEnabled) {
      fail(
        'C6 correctness route requires NIGHT_READER_C6_INVARIANT_HOOK=true '
        'and NIGHT_READER_C6_VISUAL_ORACLE=true; refusing hook-off evidence',
      );
    }
    HybridReaderScreen.debugFrameInvariantsEnabled = _c6InvariantHookEnabled;
    HybridReaderScreen.debugVisualOracleEnabled = _c6VisualOracleEnabled;
    debugPrint(
      'READER_C6_HOOK_PROVENANCE ${jsonEncode(_c6HookProvenanceFields)}',
    );
    final harness = ReaderTestHarness(tester);
    final watchdog = ReaderSixDimensionWatchdog();
    final evidenceWriter = _C6EvidenceWriter();
    final summaries = <Map<String, Object?>>[];
    var screenshotSurfaceReady = false;
    try {
      final cases = await _loadCases();
      if (cases.isEmpty) {
        fail('C6 case list is empty; refusing to treat an invalid run as pass');
      }
      if (_caseId.isNotEmpty && cases.length != 1) {
        fail('C6 CaseId mode must resolve exactly one case');
      }
      await harness.startAndProvision();
      await harness.openBook();
      await _settleWithWatchdog(
        tester,
        harness,
        watchdog,
        operationState: 'initial-settle',
      );

      for (final item in cases) {
        final caseStartedAt = DateTime.now();
        final operationTrace = <Map<String, Object?>>[];
        final runtimeFrames = <Map<String, Object?>>[];
        final invariantViolations = <Map<String, Object?>>[];
        final invariantActionObservations = <Map<String, Object?>>[];
        final visualViolations = <Map<String, Object?>>[];
        final visualActionObservations = <Map<String, Object?>>[];
        final goldenNames = <String>[];
        Map<String, Object?>? before;
        Map<String, Object?>? after;
        Map<String, Object?>? failureEvidence;
        // Keep the first-bad retained window outside the try body so the
        // catch branch can reuse the exact frames captured at detection time.
        // A later failure-handling screenshot must never replace this window
        // with a post-detection surface capture.
        var retainedFailureRawFrames = const <ReaderVisualRawFrame>[];
        final requestedState = item.state.wireName;
        debugPrint(
          'READER_C6_CASE_START seed=${item.seed} caseId=${item.id} '
          'ordinal=${item.ordinal} layer=${item.layer.wireName} '
          'position=${item.positionLabel} state=$requestedState '
          'operations=${item.operationIds.join(',')}',
        );
        try {
          // A rerun can reuse the same app-owned case directory. Remove only
          // the three standard retained-frame names before this case starts so
          // a prior visual failure can never masquerade as the current
          // semantic timeout's first-bad frame. A directory collision is not
          // removed; the host validator will report it as incomplete.
          await evidenceWriter.clearStandardFirstBadScreenshots(item);
          await harness.positionAtTopologyAnchor(item.positionAnchor);
          // Positioning is test setup, not the case's operation sequence.
          // A same-chapter jump can legitimately produce a short loading
          // transition while the anchor is being established.  Start every
          // case with fresh C2/C3/C4 history so that setup frames cannot be
          // attributed to the first operation or make a later case fail.
          harness.resetFrameInvariantHistory();
          harness.resetVisualOracle();
          await pumpVsyncPaced(tester, readerVsyncStep * 2);
          before = harness.debugSnapshot();
          runtimeFrames.addAll(harness.debugFrameInvariantRecords());

          if (_captureGolden && _shouldCaptureGolden(item)) {
            if (!screenshotSurfaceReady) {
              await binding.convertFlutterSurfaceToImage();
              screenshotSurfaceReady = true;
            }
            final name =
                'c6-golden-seed-${item.seed}-${item.positionAnchor.name}';
            await tester.pump();
            final screenshotBytes = await binding.takeScreenshot(name);
            await evidenceWriter.writeGoldenPng(item, name, screenshotBytes);
            goldenNames.add(name);
            debugPrint(
              'READER_C6_GOLDEN name=$name caseId=${item.id} '
              'checkpoint=settled-ready bytes=${screenshotBytes.length}',
            );
            // Golden capture is a separate checkpoint observation.  Do not
            // let its stable/async frames become the predecessor window for
            // the first operation (which would turn a small real drag into a
            // false post-settle creep sequence).
            harness.resetFrameInvariantHistory();
            harness.resetVisualOracle();
            await pumpVsyncPaced(tester, readerVsyncStep * 2);
          }

          for (var index = 0; index < item.operations.length; index += 1) {
            // The prior operation's settled visual window is retained for
            // evidence/coverage until its summary is written.  Clear it only
            // when the next operation is about to begin.
            harness.resetFrameInvariantHistory();
            harness.resetVisualOracle();
            final operation = item.operations[index];
            watchdog.reset();
            final operationStartedAt = DateTime.now();
            final operationBefore = harness.debugSnapshot();
            final operationState = 'operation-${index + 1}-${operation.id}';
            operationTrace.add(<String, Object?>{
              'index': index,
              'operation': operation.id,
              'startedAt': operationStartedAt.toIso8601String(),
              'before': operationBefore,
              'expectedTransition': operation.transition,
            });
            await harness.applyReaderOperation(operation);
            final settled = await _settleWithWatchdog(
              tester,
              harness,
              watchdog,
              caseId: item.id,
              operationState: '$operationState-settling',
            );
            final actionInvariant = harness.debugFrameInvariantViolations();
            invariantActionObservations.addAll(
              actionInvariant.map(
                (violation) => <String, Object?>{
                  ...violation,
                  'phase': 'action',
                  'operation': operation.id,
                },
              ),
            );
            runtimeFrames.addAll(harness.debugFrameInvariantRecords());
            // C2/C3 keep their original single-frame and temporal semantics.
            // An operation can legitimately cross a chapter boundary while
            // its final drag/ballistic frame is still being committed.  Keep
            // those observations as first-class evidence, then open a fresh
            // invariant history for the bounded settled gate below.
            harness.resetFrameInvariantHistory();
            operationTrace.last['endedAt'] = DateTime.now().toIso8601String();
            operationTrace.last['after'] = settled;
            operationTrace.last['durationMillis'] = DateTime.now()
                .difference(operationStartedAt)
                .inMilliseconds;
            // C4 deliberately reports action-window observations separately:
            // a real drag is expected to move pixels, so V11/V1 observed while
            // the gesture is settling is evidence, not a settled-window gate.
            // Preserve those observations instead of changing the oracle's
            // semantics, then start a fresh idle window for the C6 gate.
            final actionVisual = harness.debugVisualOracleViolations();
            visualActionObservations.addAll(
              actionVisual.map(
                (violation) => <String, Object?>{
                  ...violation,
                  'phase': 'action',
                  'operation': operation.id,
                },
              ),
            );
            final actionRawFrames = harness
                .debugVisualOracleRetainedRawFrames();
            harness.resetVisualOracle();
            harness.stopVisualMotionForTesting();
            // Semantic _settle() can complete one frame before an in-flight
            // raster from the restore/gesture boundary has finished.  Keep a
            // small, fixed pre-gate window to classify that boundary evidence
            // instead of allowing it to become the predecessor of the actual
            // settled gate.  This is deliberately bounded and is not a soak.
            await _pumpVisualStabilizationWindow(tester);
            final preGateInvariant = harness.debugFrameInvariantViolations();
            invariantActionObservations.addAll(
              preGateInvariant.map(
                (violation) => <String, Object?>{
                  ...violation,
                  'phase': 'pre-gate',
                  'operation': operation.id,
                },
              ),
            );
            runtimeFrames.addAll(harness.debugFrameInvariantRecords());
            final preGateVisual = harness.debugVisualOracleViolations();
            visualActionObservations.addAll(
              preGateVisual.map(
                (violation) => <String, Object?>{
                  ...violation,
                  'phase': 'pre-gate',
                  'operation': operation.id,
                },
              ),
            );
            harness.resetFrameInvariantHistory();
            harness.resetVisualOracle();
            await _pumpSettledVisualWindow(tester);
            final invariant = harness.debugFrameInvariantViolations();
            invariantViolations.addAll(invariant);
            runtimeFrames.addAll(harness.debugFrameInvariantRecords());
            final visual = harness.debugVisualOracleViolations();
            visualViolations.addAll(visual);
            final settledRawFrames = harness
                .debugVisualOracleRetainedRawFrames();
            if (invariant.isNotEmpty || visual.isNotEmpty) {
              retainedFailureRawFrames = settledRawFrames.isNotEmpty
                  ? settledRawFrames
                  : actionRawFrames;
              await evidenceWriter.writeRawFramePngs(
                item,
                retainedFailureRawFrames,
              );
              if (_captureFailureScreenshots) {
                if (!screenshotSurfaceReady) {
                  await binding.convertFlutterSurfaceToImage();
                  screenshotSurfaceReady = true;
                }
                final name = 'c6-failure-violation-${item.id}';
                await binding.takeScreenshot(name);
                debugPrint(
                  'READER_C6_FAILURE_SCREENSHOT name=$name caseId=${item.id} '
                  'firstBadFrame=${_firstBadFrame(invariant, visual)}',
                );
              }
              fail(
                'C6 oracle violation in ${item.id}: '
                'runtime=${invariant.length} visual=${visual.length}',
              );
            }
            harness.resetFrameInvariantHistory();
          }
          after = harness.debugSnapshot();
          runtimeFrames.addAll(harness.debugFrameInvariantRecords());
          final visualEvidence = _visualEvidenceFields(harness);
          final entryStateStatus = requestedState == 'ready'
              ? 'observed'
              : 'not_verified';
          final summary = <String, Object?>{
            'schemaVersion': 2,
            'bundleType': 'c6-case',
            'caseId': item.id,
            'status': 'passed',
            'failureKind': 'passed',
            'failureMarker': _failureMarkerForKind('passed'),
            ..._c6HookProvenanceFields,
            'seed': item.seed,
            'layer': item.layer.wireName,
            'scenario': item.layer.wireName,
            'position': item.positionAnchor.name,
            'positionLabel': item.positionLabel,
            'documentPosition': item.positionLabel,
            'target': item.positionAnchor.name,
            'requestedState': requestedState,
            'runtimeState': _entryState(after),
            'observedEntryState': _entryState(before),
            'entryStateStatus': entryStateStatus,
            'operationIds': item.operationIds,
            'operationCount': item.operations.length,
            'runtimeFrameCount': runtimeFrames.length,
            'runtimeViolations': _countRuntime(invariantViolations),
            'temporalViolations': _countTemporal(invariantViolations),
            'visualViolations': 0,
            'crossOracleViolations': 0,
            'invariantActionObservations': invariantActionObservations.length,
            'runtimeActionObservations': _countRuntime(
              invariantActionObservations,
            ),
            'temporalActionObservations': _countTemporal(
              invariantActionObservations,
            ),
            'visualActionObservations': visualActionObservations.length,
            ...visualEvidence,
            'visualObservation': _visualObservationSummary(visualEvidence),
            'goldenNames': goldenNames,
            'elapsedMillis': DateTime.now()
                .difference(caseStartedAt)
                .inMilliseconds,
          };
          summaries.add(summary);
          await evidenceWriter.writeCase(
            item: item,
            metadata: <String, Object?>{
              ...summary,
              ..._c6HookProvenanceFields,
              'deviceId': _deviceId,
              'displayRefreshRate': before['displayRefreshRate'],
              'viewportSize': <String, Object?>{
                'logicalWidth': tester.binding.renderViews.single.size.width,
                'logicalHeight': tester.binding.renderViews.single.size.height,
                'devicePixelRatio': tester.view.devicePixelRatio,
              },
              'fixtureHostPath': readerFixtureHostPath,
              'fixtureDevicePath': readerFixturePath,
            },
            operationTrace: operationTrace,
            runtimeFrames: runtimeFrames,
            invariantViolations: invariantViolations,
            invariantActionObservations: invariantActionObservations,
            visualViolations: visualViolations,
            visualActionObservations: visualActionObservations,
            summary: summary,
          );
          debugPrint('READER_C6_CASE_RESULT ${jsonEncode(summary)}');
        } catch (error, stackTrace) {
          List<Map<String, Object?>> currentInvariant;
          try {
            currentInvariant = harness.debugFrameInvariantViolations();
          } catch (_) {
            currentInvariant = <Map<String, Object?>>[];
          }
          List<Map<String, Object?>> currentVisual;
          try {
            currentVisual = harness.debugVisualOracleViolations();
          } catch (_) {
            currentVisual = <Map<String, Object?>>[];
          }
          // A settle/queue timeout can throw before the normal operation
          // epilogue copies the current bounded ring.  Capture that ring and
          // the last semantic snapshot here as evidence only; this does not
          // change the timeout, invariant, or visual verdict.
          try {
            runtimeFrames.addAll(harness.debugFrameInvariantRecords());
          } catch (_) {
            // Keep the failure bundle honest if the harness is already torn
            // down: the host validator will report an empty required trace.
          }
          if (operationTrace.isNotEmpty) {
            final failedOperation = operationTrace.last;
            failedOperation['endedAt'] ??= DateTime.now().toIso8601String();
            failedOperation['failure'] ??= error.toString();
            if (!failedOperation.containsKey('after')) {
              try {
                failedOperation['after'] = harness.debugSnapshot();
              } catch (_) {
                failedOperation['after'] = null;
              }
            }
            if (!failedOperation.containsKey('durationMillis')) {
              final startedAt = DateTime.tryParse(
                failedOperation['startedAt']?.toString() ?? '',
              );
              failedOperation['durationMillis'] = startedAt == null
                  ? null
                  : DateTime.now().difference(startedAt).inMilliseconds;
            }
          }
          // The operation branch records the violation before calling
          // fail().  Only add the current hook history when the exception was
          // raised before that branch could copy it; otherwise the same
          // retained window would be counted twice in the bundle.
          if (invariantViolations.isEmpty) {
            invariantViolations.addAll(currentInvariant);
          }
          if (visualViolations.isEmpty) {
            visualViolations.addAll(currentVisual);
          }
          if (retainedFailureRawFrames.isEmpty) {
            try {
              retainedFailureRawFrames = harness
                  .debugVisualOracleRetainedRawFrames();
            } catch (_) {
              retainedFailureRawFrames = const <ReaderVisualRawFrame>[];
            }
          }
          final failureKind = _classifyFailureKind(
            error,
            invariantViolations,
            visualViolations,
          );
          // A semantic settle/queue timeout has no visual first-bad frame.
          // Do not feed its action/retained frames through the visual exporter:
          // a post-detection surface is not evidence of a transient visual
          // violation.  Invariant/visual failures still require the exact C4
          // retained window and remain invalid when it is unavailable.
          Map<String, Object?> screenshotEvidence;
          if (_requiresFirstBadScreenshots(failureKind)) {
            try {
              screenshotEvidence = await evidenceWriter.writeRawFramePngs(
                item,
                retainedFailureRawFrames,
              );
            } catch (screenshotError, screenshotStackTrace) {
              // A missing/uncapturable retained window is an incomplete
              // visual/invariant bundle.  Record the encoding failure, but
              // never replace it with a post-detection image.
              debugPrint(
                'READER_C6_EVIDENCE_SCREENSHOT_FAILURE '
                'caseId=${item.id} error=$screenshotError\n'
                '$screenshotStackTrace',
              );
              screenshotEvidence = <String, Object?>{
                'source': 'not-available',
                'frameCount': retainedFailureRawFrames.length,
                'firstBadFrameSource': 'not-available',
                'firstBadFrameArtifact': null,
                'windowCompleteness': 'not-available',
                'missingSlots': const <String>['before', 'violation', 'after'],
                'frames': const <String, Object?>{},
                'error': screenshotError.toString(),
              };
            }
          } else {
            screenshotEvidence = <String, Object?>{
              'source': 'not-applicable',
              'frameCount': 0,
              'firstBadFrameSource': 'not-applicable',
              'firstBadFrameArtifact': null,
              'windowCompleteness': 'not-applicable',
              'missingSlots': const <String>[],
              'notApplicableSlots': const <String>[
                'before',
                'violation',
                'after',
              ],
              'frames': const <String, Object?>{},
            };
          }
          if (_captureFailureScreenshots) {
            try {
              if (!screenshotSurfaceReady) {
                await binding.convertFlutterSurfaceToImage();
                screenshotSurfaceReady = true;
              }
              // These are supplemental captures made at failure handling
              // time.  They are deliberately named outside the S4 contract:
              // the standard before/violation/after files can only come from
              // the retained C4 raw window above.
              await binding.takeScreenshot(
                'c6-post-detection-before-${item.id}',
              );
              await binding.takeScreenshot(
                'c6-post-detection-violation-${item.id}',
              );
              await binding.takeScreenshot(
                'c6-post-detection-after-${item.id}',
              );
            } catch (screenshotError) {
              debugPrint(
                'READER_C6_SCREENSHOT_FAILURE caseId=${item.id} '
                'error=$screenshotError',
              );
            }
          }
          final visualEvidence = _visualEvidenceFields(harness);
          Map<String, Object?>? failureSnapshot;
          try {
            failureSnapshot = harness.debugSnapshot();
          } catch (_) {
            failureSnapshot = null;
          }
          failureEvidence = <String, Object?>{
            'schemaVersion': 2,
            'bundleType': 'c6-case',
            'caseId': item.id,
            'status': 'failed',
            'failureKind': failureKind,
            'failureMarker': _failureMarkerForKind(failureKind),
            ..._c6HookProvenanceFields,
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
            'firstBadFrame': _firstBadFrame(
              invariantViolations,
              visualViolations,
            ),
            'firstBadFrameArtifact':
                screenshotEvidence['firstBadFrameArtifact'],
            'firstBadFrameSource': screenshotEvidence['firstBadFrameSource'],
            'screenshotEvidence': screenshotEvidence,
          };
          final summary = <String, Object?>{
            ...failureEvidence,
            'seed': item.seed,
            'layer': item.layer.wireName,
            'scenario': item.layer.wireName,
            'position': item.positionAnchor.name,
            'positionLabel': item.positionLabel,
            'documentPosition': item.positionLabel,
            'target': item.positionAnchor.name,
            'requestedState': requestedState,
            'runtimeState': _entryState(failureSnapshot ?? before),
            'observedEntryState': _entryState(before),
            'operationIds': item.operationIds,
            'runtimeFrameCount': runtimeFrames.length,
            'runtimeViolations': _countRuntime(invariantViolations),
            'temporalViolations': _countTemporal(invariantViolations),
            'visualViolations': _countVisual(visualViolations),
            'crossOracleViolations': _countCross(visualViolations),
            'invariantActionObservations': invariantActionObservations.length,
            'runtimeActionObservations': _countRuntime(
              invariantActionObservations,
            ),
            'temporalActionObservations': _countTemporal(
              invariantActionObservations,
            ),
            'visualActionObservations': visualActionObservations.length,
            ...visualEvidence,
            'visualObservation': _visualObservationSummary(visualEvidence),
            'elapsedMillis': DateTime.now()
                .difference(caseStartedAt)
                .inMilliseconds,
          };
          summaries.add(summary);
          try {
            after = harness.debugSnapshot();
          } catch (_) {
            after = null;
          }
          try {
            await evidenceWriter.writeCase(
              item: item,
              metadata: <String, Object?>{
                ...summary,
                ..._c6HookProvenanceFields,
                'deviceId': _deviceId,
                'displayRefreshRate': before?['displayRefreshRate'],
                'fixtureHostPath': readerFixtureHostPath,
                'fixtureDevicePath': readerFixturePath,
              },
              operationTrace: operationTrace,
              runtimeFrames: runtimeFrames,
              invariantViolations: invariantViolations,
              invariantActionObservations: invariantActionObservations,
              visualViolations: visualViolations,
              visualActionObservations: visualActionObservations,
              summary: <String, Object?>{
                ...summary,
                'before': before,
                'after': after,
                'failureEvidence': failureEvidence,
              },
            );
          } catch (writeError, writeStackTrace) {
            // Preserve the original case failure. A writer/teardown failure
            // must leave an incomplete bundle for the host validator rather
            // than replacing the real error with a second exception or fake
            // evidence.
            debugPrint(
              'READER_C6_EVIDENCE_WRITE_FAILURE caseId=${item.id} '
              'error=$writeError\n$writeStackTrace',
            );
          }
          debugPrint('READER_C6_CASE_FAILURE ${jsonEncode(summary)}');
          rethrow;
        } finally {
          try {
            watchdog.reset();
          } catch (teardownError, teardownStackTrace) {
            // Teardown is best-effort and must never replace a case failure or
            // prevent the already-built evidence from being reported.
            debugPrint(
              'READER_C6_TEARDOWN_FAILURE caseId=${item.id} '
              'error=$teardownError\n$teardownStackTrace',
            );
          }
        }
      }

      final result = <String, Object?>{
        'schemaVersion': 1,
        'status': 'passed',
        ..._c6HookProvenanceFields,
        'seed': cases.first.seed,
        'deviceId': _deviceId,
        'caseCount': cases.length,
        'cases': summaries,
        'runtimeViolations': _sum(summaries, 'runtimeViolations'),
        'temporalViolations': _sum(summaries, 'temporalViolations'),
        'visualViolations': _sum(summaries, 'visualViolations'),
        'crossOracleViolations': _sum(summaries, 'crossOracleViolations'),
        'invariantActionObservations': _sum(
          summaries,
          'invariantActionObservations',
        ),
        'runtimeActionObservations': _sum(
          summaries,
          'runtimeActionObservations',
        ),
        'temporalActionObservations': _sum(
          summaries,
          'temporalActionObservations',
        ),
        'visualActionObservations': _sum(summaries, 'visualActionObservations'),
        'goldenCheckpoints': [
          for (final summary in summaries)
            ...((summary['goldenNames'] as List<dynamic>?) ?? const []),
        ],
      };
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['c6Result'] = result;
      binding.reportData!['c6Cases'] = summaries;
      debugPrint('READER_C6_RESULT ${jsonEncode(result)}');
    } finally {
      HybridReaderScreen.debugVisualOracleEnabled = false;
      HybridReaderScreen.debugFrameInvariantsEnabled = false;
    }
  }, timeout: const Timeout(_testTimeout));
}

Future<List<ReaderCorrectnessCase>> _loadCases() async {
  if (_caseId.isEmpty && _caseListPath.isEmpty) {
    throw const FormatException(
      'C6 requires NIGHT_READER_C6_CASE_ID or NIGHT_READER_C6_CASE_LIST_PATH',
    );
  }
  final path = _caseListPath.isNotEmpty
      ? _caseListPath
      : '$readerFixturePath.c6-manifest.json';
  final manifest = ReaderCorrectnessManifest.fromJsonString(
    await File(path).readAsString(),
  );
  if (_caseId.isEmpty) return manifest.cases;
  final matches = manifest.cases.where((item) => item.id == _caseId).toList();
  if (matches.length != 1) {
    throw StateError('C6 case id not found exactly once: $_caseId');
  }
  return matches;
}

Future<Map<String, Object?>> _settleWithWatchdog(
  WidgetTester tester,
  ReaderTestHarness harness,
  ReaderSixDimensionWatchdog watchdog, {
  String? caseId,
  required String operationState,
}) async {
  Map<String, Object?>? latest;
  DateTime? lastProgressMarkerAt;
  var progressSequence = 0;
  var settledFrameStreak = 0;
  final timeoutMarker = 'C6_SEMANTIC_SETTLE_TIMEOUT';
  try {
    await pumpUntil(
      tester,
      () {
        latest = harness.debugSnapshot();
        final frames = harness.debugVisualOracleFrames();
        final lastFrame = frames.isEmpty ? null : frames.last;
        final visualDy = (lastFrame?['visualDy'] as num?)?.toDouble();
        final invariantCount = harness.debugFrameInvariantViolations().length;
        final settled = _isSettled(latest!);
        if (settled) {
          settledFrameStreak += 1;
        } else {
          settledFrameStreak = 0;
          final progressed = watchdog.observe(
            snapshot: latest!,
            operationActive: true,
            operationState: operationState,
            visualDy: visualDy,
            invariantEvaluationCount: invariantCount,
            waitingForLoad: latest!['phase'] == 'loading',
          );
          if (progressed) {
            final now = DateTime.now();
            if (lastProgressMarkerAt == null ||
                now.difference(lastProgressMarkerAt!) >=
                    const Duration(seconds: 1)) {
              progressSequence += 1;
              lastProgressMarkerAt = now;
              // This marker is a progress observation, never a completion
              // signal.  It gives the external runner an independent view of
              // the six-dimensional watchdog while the case itself is still
              // settling, so marker-only no-progress cannot hide a live case.
              debugPrint(
                'READER_C6_PROGRESS ${jsonEncode(<String, Object?>{'caseId': caseId, 'sequence': progressSequence, 'operationState': operationState, 'phase': latest!['phase'], 'runtimeLocationRevision': latest!['runtimeLocationRevision'], 'layoutGeneration': latest!['layoutGeneration'], 'epoch': latest!['epoch'], 'invariantEvaluationCount': invariantCount, 'scrollPixels': latest!['scrollPixels'] ?? latest!['scrollOffset'], 'scrollOffset': latest!['scrollOffset'], 'visualDy': visualDy, 'pumpQueueDepth': latest!['pumpQueueDepth'], 'enqueuedCount': latest!['enqueuedCount'], 'dominantVisibleChapter': latest!['dominantVisibleChapter'], 'displayedProgressChapter': latest!['displayedProgressChapter'], 'capturedChapter': (latest!['capturedLocation'] as Map?)?['chapterIndex']})}',
              );
            }
          }
        }
        // Keep the C6 _settle assertions intact while avoiding a first-ready
        // sample racing with cache work scheduled on the next real vsync.
        return settledFrameStreak >= 4;
      },
      timeout: _settleTimeout,
      step: readerVsyncStep,
      reasonBuilder: () =>
          '$timeoutMarker operationState=$operationState latest=$latest',
    );
  } catch (error) {
    // Only the explicit timeout reason or the structured six-dimension
    // watchdog abort is a semantic settle failure. Generic queue/settling
    // text is deliberately left to the unclassified fail-closed path.
    if (error is ReaderSixDimensionWatchdogAbort ||
        error.toString().contains(timeoutMarker)) {
      throw _C6SemanticSettleTimeout(
        operationState: operationState,
        cause: error,
      );
    }
    rethrow;
  }
  final settled = latest ?? harness.debugSnapshot();
  expect(settled['phase'], 'ready');
  expect(settled['initialRestoreCompleted'], isTrue);
  expect(settled['pumpQueueDepth'], 0);
  expect(settled['visibleKeysContiguous'], isTrue);
  expect((settled['visibleKeys'] as List<dynamic>), isNotEmpty);
  expect((settled['missingParagraphKeys'] as List<dynamic>), isEmpty);
  expect(settled['pendingChapterJumpTarget'], isNull);
  watchdog.reset();
  return settled;
}

Future<void> _pumpSettledVisualWindow(WidgetTester tester) async {
  // Match the bounded C4 settled observation: enough real vsyncs for the
  // asynchronous RepaintBoundary capture queue to drain, but never a soak.
  const frameCount = 24;
  for (var index = 0; index < frameCount; index += 1) {
    await tester.pump(readerVsyncStep);
    if (index % 8 == 0) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
}

Future<void> _pumpVisualStabilizationWindow(WidgetTester tester) async {
  const frameCount = 6;
  for (var index = 0; index < frameCount; index += 1) {
    await tester.pump(readerVsyncStep);
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
}

bool _isSettled(Map<String, Object?> snapshot) {
  return snapshot['phase'] == 'ready' &&
      snapshot['initialRestoreCompleted'] == true &&
      snapshot['isScrolling'] == false &&
      snapshot['pumpQueueDepth'] == 0 &&
      snapshot['visibleKeysContiguous'] == true &&
      ((snapshot['missingParagraphKeys'] as List<dynamic>?)?.isEmpty ??
          false) &&
      snapshot['pendingChapterJumpTarget'] == null;
}

String _entryState(Map<String, Object?>? snapshot) {
  if (snapshot == null) return 'unavailable';
  return _isSettled(snapshot)
      ? 'ready'
      : snapshot['phase']?.toString() ?? 'unknown';
}

bool _shouldCaptureGolden(ReaderCorrectnessCase item) {
  return item.state == ReaderCaseState.ready &&
      item.layer == ReaderCaseLayer.singleOperation;
}

Map<String, Object?> _visualEvidenceFields(ReaderTestHarness harness) {
  try {
    final summary = harness.debugVisualOracleSummary();
    return <String, Object?>{
      'visualTotalFrames': summary['totalFrames'],
      'visualCapturedFrames': summary['capturedFrames'],
      'visualDroppedFrames': summary['droppedFrames'],
      'visualCoverage': summary['coverage'],
      'visualCaptureErrorCount': summary['captureErrorCount'],
    };
  } catch (_) {
    return <String, Object?>{
      'visualTotalFrames': null,
      'visualCapturedFrames': null,
      'visualDroppedFrames': null,
      'visualCoverage': null,
      'visualCaptureErrorCount': null,
    };
  }
}

String _visualObservationSummary(Map<String, Object?> evidence) {
  return 'total=${evidence['visualTotalFrames'] ?? 'unknown'} '
      'captured=${evidence['visualCapturedFrames'] ?? 'unknown'} '
      'dropped=${evidence['visualDroppedFrames'] ?? 'unknown'} '
      'coverage=${evidence['visualCoverage'] ?? 'unknown'} '
      'captureErrors=${evidence['visualCaptureErrorCount'] ?? 'unknown'}';
}

String _classifyFailureKind(
  Object error,
  List<Map<String, Object?>> invariant,
  List<Map<String, Object?>> visual,
) {
  if (visual.isNotEmpty) return 'visual-violation';
  if (invariant.isNotEmpty) return 'invariant-violation';
  if (error is _C6SemanticSettleTimeout ||
      error is ReaderSixDimensionWatchdogAbort) {
    return 'semantic-settle-timeout';
  }
  return 'unclassified-failure';
}

String _failureMarkerForKind(String failureKind) {
  switch (failureKind) {
    case 'passed':
      return 'C6_CASE_PASSED';
    case 'semantic-settle-timeout':
      return 'C6_SEMANTIC_SETTLE_TIMEOUT';
    case 'invariant-violation':
      return 'C6_INVARIANT_VIOLATION';
    case 'visual-violation':
      return 'C6_VISUAL_VIOLATION';
    default:
      return 'C6_UNCLASSIFIED_FAILURE';
  }
}

bool _requiresFirstBadScreenshots(String failureKind) {
  return failureKind == 'visual-violation' ||
      failureKind == 'invariant-violation';
}

String? _firstBadFrame(
  List<Map<String, Object?>> invariant,
  List<Map<String, Object?>> visual,
) {
  final candidates = <int>[];
  for (final item in invariant) {
    final current = item['current'];
    if (current is Map && current['timestampMicros'] is num) {
      candidates.add((current['timestampMicros'] as num).toInt());
    }
  }
  for (final item in visual) {
    if (item['sequence'] is num)
      candidates.add((item['sequence'] as num).toInt());
  }
  if (candidates.isEmpty) return null;
  candidates.sort();
  return candidates.first.toString();
}

int _countRuntime(List<Map<String, Object?>> values) =>
    values.where((item) => item['oracle'] != 'temporal').length;

int _countTemporal(List<Map<String, Object?>> values) =>
    values.where((item) => item['oracle'] == 'temporal').length;

int _countVisual(List<Map<String, Object?>> values) =>
    values.where((item) => item['invariant'] != 'CROSS_ORACLE_MISMATCH').length;

int _countCross(List<Map<String, Object?>> values) =>
    values.where((item) => item['invariant'] == 'CROSS_ORACLE_MISMATCH').length;

int _sum(List<Map<String, Object?>> values, String key) => values.fold<int>(
  0,
  (total, item) => total + ((item[key] as num?)?.toInt() ?? 0),
);

final class _C6EvidenceWriter {
  _C6EvidenceWriter()
    : _root = Directory('${File(readerFixturePath).parent.path}/c6-evidence');

  final Directory _root;

  Future<void> clearStandardFirstBadScreenshots(
    ReaderCorrectnessCase item,
  ) async {
    final directory = Directory('${_root.path}/${_safe(item.id)}');
    if (!await directory.exists()) return;
    for (final name in const <String>[
      'screenshot-before.png',
      'screenshot-violation.png',
      'screenshot-after.png',
    ]) {
      final file = File('${directory.path}/$name');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> writeCase({
    required ReaderCorrectnessCase item,
    required Map<String, Object?> metadata,
    required List<Map<String, Object?>> operationTrace,
    required List<Map<String, Object?>> runtimeFrames,
    required List<Map<String, Object?>> invariantViolations,
    required List<Map<String, Object?>> invariantActionObservations,
    required List<Map<String, Object?>> visualViolations,
    required List<Map<String, Object?>> visualActionObservations,
    required Map<String, Object?> summary,
  }) async {
    final directory = Directory('${_root.path}/${_safe(item.id)}');
    await directory.create(recursive: true);
    await _writeJson(directory, 'metadata.json', metadata);
    await _writeJsonl(
      directory,
      'operation-trace.jsonl',
      operationTrace,
      source: _c6OperationTraceSource,
    );
    // Keep Android evidence bounded. The production debug hooks already have
    // bounded rings; this second cap prevents a future test adapter from
    // accidentally turning one failure into a multi-megabyte bundle.
    await _writeJsonl(
      directory,
      'runtime-frame-trace.jsonl',
      runtimeFrames,
      source: _c6RuntimeTraceSource,
      max: 256,
    );
    await _writeJsonl(
      directory,
      'invariant-violations.jsonl',
      invariantViolations,
      max: 256,
    );
    await _writeJsonl(
      directory,
      'invariant-action-observations.jsonl',
      invariantActionObservations,
      max: 256,
    );
    await _writeJsonl(
      directory,
      'visual-violations.jsonl',
      visualViolations,
      max: 256,
    );
    await _writeJsonl(
      directory,
      'visual-action-observations.jsonl',
      visualActionObservations,
      max: 256,
    );
    await _writeJson(directory, 'summary.json', summary);
    await File('${directory.path}/summary.md')
        .writeAsString(_summaryMarkdown(summary), flush: true);
    await _writeJson(directory, 'bundle-manifest.json', <String, Object?>{
      'schemaVersion': 2,
      'bundleType': 'c6-case',
      'caseId': item.id,
      'safeCaseDirectory': _safe(item.id),
      'status': summary['status'],
      'failureKind': summary['failureKind'] ?? 'unclassified-failure',
      'failureMarker':
          summary['failureMarker'] ??
          _failureMarkerForKind(
            (summary['failureKind'] ?? 'unclassified-failure').toString(),
          ),
      ..._c6HookProvenanceFields,
      'firstBadFrameSource':
          summary['firstBadFrameSource'] ??
          (summary['failureEvidence'] is Map
              ? (summary['failureEvidence'] as Map)['firstBadFrameSource']
              : null),
      'transportStatus': 'app-owned-written',
      'appOwnedFiles': const <String>[
        'metadata.json',
        'operation-trace.jsonl',
        'runtime-frame-trace.jsonl',
        'invariant-violations.jsonl',
        'invariant-action-observations.jsonl',
        'visual-violations.jsonl',
        'visual-action-observations.jsonl',
        'summary.json',
        'summary.md',
      ],
    });
  }

  /// Export the bounded C4 retained window using the C6 S4 artifact names.
  ///
  /// C4 retains the candidate window as [before, middle, after], where the
  /// middle raw frame is the first bad frame that caused the visual oracle
  /// violation.  The old exporter wrote that frame as `middle.png`, which
  /// made the required `screenshot-violation.png` either absent or dependent
  /// on a later failure-handling screenshot.  Return the exact artifact and
  /// frame metadata so the failure summary can point at the same frame.
  Future<Map<String, Object?>> writeRawFramePngs(
    ReaderCorrectnessCase item,
    List<ReaderVisualRawFrame> frames,
  ) async {
    final evidence = <String, Object?>{
      'source': frames.isEmpty
          ? 'not-available'
          : 'C4-retained-raw-frame-window',
      'frameCount': frames.length,
      'firstBadFrameSource': frames.isEmpty
          ? 'not-available'
          : 'C4-retained-raw-frame-window-middle',
      'firstBadFrameArtifact': null,
      'frames': <String, Object?>{},
      'windowCompleteness': frames.length == 3 ? 'complete' : 'incomplete',
      'missingSlots': const <String>[],
    };
    if (frames.isEmpty) {
      evidence['windowCompleteness'] = 'not-available';
      evidence['missingSlots'] = const <String>['before', 'violation', 'after'];
      return evidence;
    }

    final directory = Directory('${_root.path}/${_safe(item.id)}');
    await directory.create(recursive: true);

    // The oracle must provide all three slots for an accepted visual/invariant
    // failure.  A partial retained window is recorded as unavailable; never
    // promote one or two frames into a fabricated before/violation/after
    // contract, and never use a post-detection screenshot for these files.
    if (frames.length < 3) {
      evidence['firstBadFrameSource'] = 'retained-frame-window-incomplete';
      evidence['missingSlots'] = <String>[
        if (frames.isEmpty || frames.length < 1) 'before',
        if (frames.length < 2) 'violation',
        if (frames.length < 3) 'after',
      ];
      return evidence;
    }

    final before = frames[0];
    final violation = frames[1];
    final after = frames[2];

    final selected = <String, ReaderVisualRawFrame>{
      'before': before,
      'violation': violation,
      'after': after,
    };
    final frameMetadata = <String, Object?>{};
    final encoded = <String, Uint8List?>{};
    for (final entry in selected.entries) {
      encoded[entry.key] = await _encodeRawRgbaPng(entry.value);
    }
    if (encoded.values.any((bytes) => bytes == null)) {
      evidence['firstBadFrameSource'] = 'retained-frame-not-encodable';
      evidence['windowCompleteness'] = 'incomplete';
      evidence['missingSlots'] = <String>[
        for (final entry in encoded.entries)
          if (entry.value == null) entry.key,
      ];
      return evidence;
    }
    for (final entry in selected.entries) {
      final label = entry.key;
      final frame = entry.value;
      final png = encoded[label]!;
      final artifactName = 'screenshot-$label.png';
      await File('${directory.path}/$artifactName')
          .writeAsBytes(png, flush: true);
      frameMetadata[label] = <String, Object?>{
        'artifact': artifactName,
        'frame': frame.toJson(label: label),
      };
    }
    evidence['frames'] = frameMetadata;
    if ((frameMetadata['violation'] as Map?)?['artifact'] != null) {
      evidence['firstBadFrameArtifact'] = 'screenshot-violation.png';
      evidence['firstBadFrameSequence'] = violation.sequence;
      evidence['firstBadFrameTimestampMicros'] = violation.timestampMicros;
    } else {
      evidence['firstBadFrameSource'] = 'retained-frame-not-encodable';
    }
    evidence['windowCompleteness'] = 'complete';
    evidence['missingSlots'] = const <String>[];
    return evidence;
  }

  Future<void> writeGoldenPng(
    ReaderCorrectnessCase item,
    String name,
    List<int> bytes,
  ) async {
    if (bytes.isEmpty) {
      throw StateError('C6 golden screenshot returned zero bytes: $name');
    }
    final directory = Directory('${_root.path}/${_safe(item.id)}/golden');
    await directory.create(recursive: true);
    await File('${directory.path}/${_safe(name)}.png')
        .writeAsBytes(bytes, flush: true);
  }

  Future<void> _writeJson(
    Directory directory,
    String name,
    Map<String, Object?> value,
  ) async {
    await File('${directory.path}/$name')
        .writeAsString(jsonEncode(value), flush: true);
  }

  Future<void> _writeJsonl(
    Directory directory,
    String name,
    List<Map<String, Object?>> values, {
    String? source,
    int max = 256,
  }) async {
    final selected = values.length <= max
        ? values
        : values.sublist(values.length - max);
    final content = selected
        .map(
          (record) => jsonEncode(
            source == null
                ? record
                : <String, Object?>{
                    'schemaVersion': 2,
                    'source': source,
                    'record': record,
                  },
          ),
        )
        .join('\n');
    await File('${directory.path}/$name')
        .writeAsString(content.isEmpty ? '' : '$content\n', flush: true);
  }

  String _safe(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
    final source = normalized.isEmpty ? 'case' : normalized;
    final prefixLength = source.length < 48 ? source.length : 48;
    final prefix = source.substring(0, prefixLength);
    final digest = sha1.convert(utf8.encode(value)).toString().substring(0, 12);
    return '$prefix-$digest';
  }

  String _summaryMarkdown(Map<String, Object?> summary) {
    final failureEvidence = summary['failureEvidence'];
    final evidence = failureEvidence is Map
        ? Map<String, Object?>.from(failureEvidence)
        : const <String, Object?>{};
    final failureKind = summary['failureKind'] ?? 'unclassified-failure';
    final firstBadFrameSource =
        summary['firstBadFrameSource'] ??
        evidence['firstBadFrameSource'] ??
        (failureKind == 'semantic-settle-timeout'
            ? 'not-applicable'
            : 'not-available');
    final lines = <String>[
      '# C6 case summary',
      '',
      '- caseId: ${summary['caseId'] ?? 'unknown'}',
      '- status: ${summary['status'] ?? 'unknown'}',
      '- failureKind: $failureKind',
      '- scenario: ${summary['scenario'] ?? summary['layer'] ?? 'unknown'}',
      '- documentPosition: ${summary['documentPosition'] ?? summary['positionLabel'] ?? summary['position'] ?? 'unknown'}',
      '- target: ${summary['target'] ?? summary['requestedState'] ?? 'unknown'}',
      '- seed: ${summary['seed'] ?? 'unknown'}',
      '- layer: ${summary['layer'] ?? 'unknown'}',
      '- position: ${summary['positionLabel'] ?? summary['position'] ?? 'unknown'}',
      '- requestedState: ${summary['requestedState'] ?? 'unknown'}',
      '- runtimeState: ${summary['runtimeState'] ?? summary['observedEntryState'] ?? 'unknown'}',
      '- operationCount: ${summary['operationCount'] ?? (summary['operationIds'] as List<dynamic>?)?.length ?? 'unknown'}',
      '- runtimeFrameCount: ${summary['runtimeFrameCount'] ?? 'unknown'}',
      '- runtimeViolations: ${summary['runtimeViolations'] ?? 'unknown'}',
      '- temporalViolations: ${summary['temporalViolations'] ?? 'unknown'}',
      '- visualViolations: ${summary['visualViolations'] ?? 'unknown'}',
      '- crossOracleViolations: ${summary['crossOracleViolations'] ?? 'unknown'}',
      '- visualObservation: ${summary['visualObservation'] ?? 'not-available'}',
      '- firstBadFrame: ${summary['firstBadFrame'] ?? evidence['firstBadFrame'] ?? 'not-applicable'}',
      '- firstBadFrameSource: $firstBadFrameSource',
      '',
      '## Evidence boundary',
      '',
      if (failureKind == 'semantic-settle-timeout')
        '- This is a semantic settle/queue timeout. No visual first-bad frame is applicable; post-detection screenshots are not an S4 substitute.'
      else
        '- Visual/invariant screenshot files are accepted only when they come from the retained C4 frame window.',
    ];
    if (summary['error'] != null) {
      lines
        ..add('')
        ..add('## Failure')
        ..add('')
        ..add('- error: ${summary['error']}');
    }
    return '${lines.join('\n')}\n';
  }
}

Future<Uint8List?> _encodeRawRgbaPng(ReaderVisualRawFrame frame) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    frame.rgba,
    frame.width,
    frame.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
    rowBytes: frame.width * 4,
  );
  final image = await completer.future;
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  } finally {
    image.dispose();
  }
}
