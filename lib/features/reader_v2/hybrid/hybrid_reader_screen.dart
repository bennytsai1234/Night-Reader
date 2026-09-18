import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

import 'anchor/anchor_manager.dart';
import 'core/hybrid_contracts.dart';
import 'core/hybrid_types.dart';
import 'measure/document_index.dart';
import 'measure/measurement_store.dart';
import 'measure/metrics_disk_cache.dart';
import 'overlay/tts_highlight_overlay.dart';
import 'paragraph/paragraph_cache.dart';
import 'progress/hybrid_progress.dart';
import 'pump/budget_governor.dart';
import 'pump/layout_pump.dart';
import 'telemetry/hybrid_telemetry.dart';
import 'text/hybrid_chapter_repository.dart';
import 'text/text_preprocessor.dart';
import 'view/admission_controller.dart';
import 'view/hybrid_scroll_view.dart';

class HybridReaderScreen extends StatefulWidget {
  const HybridReaderScreen({
    super.key,
    required this.runtime,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.onContentTapUp,
    this.viewportController,
    this.ttsHighlight,
    this.progressListenable,
    this.bookUrl,
    this.preprocessor = const TextPreprocessor(),
    this.enableDiskMetrics = true,
  });

  final ReaderV2Runtime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final GestureTapUpCallback? onContentTapUp;
  final ReaderV2ViewportController? viewportController;
  final ReaderV2TtsHighlight? ttsHighlight;
  final ValueNotifier<HybridProgressSnapshot?>? progressListenable;
  final String? bookUrl;
  final HybridTextPreprocessor preprocessor;
  final bool enableDiskMetrics;

  @override
  State<HybridReaderScreen> createState() => _HybridReaderScreenState();
}

bool isHybridPageMoveComplete({
  required double requestedDistance,
  required double actualDistance,
  required bool atBookBoundary,
}) {
  if (!requestedDistance.isFinite || requestedDistance <= 0) return false;
  if (!actualDistance.isFinite || actualDistance <= 0) return false;
  const tolerance = 0.5;
  if (actualDistance + tolerance >= requestedDistance) return true;
  return atBookBoundary;
}

class _HybridReaderScreenState extends State<HybridReaderScreen>
    with WidgetsBindingObserver {
  static const Duration _ensureAnimateDuration = Duration(milliseconds: 260);
  static const double _minimumViewportMovement = 0.01;

  final GlobalKey _centerKey = GlobalKey(debugLabel: 'hybrid-center-sliver');
  final MeasurementStore _measurementStore = MeasurementStore();
  final DocumentIndex _documentIndex = DocumentIndex(
    centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
  );
  final BudgetGovernor _governor = BudgetGovernor();
  final HybridTelemetry _telemetry = HybridTelemetry();
  final _HybridCommandQueue _commands = _HybridCommandQueue();

  late HybridChapterRepository _chapterRepo;
  late final AdmissionController _admission;
  late final HybridScrollPhysics _physics;
  late ParagraphCache _paragraphCache;
  late LayoutPump _pump;
  late LayoutEpoch _epoch;
  late StyleFingerprint _fingerprint;
  late MeasurementNamespace _namespace;

  final Map<int, ChapterBlocks> _blocks = <int, ChapterBlocks>{};
  final Map<int, Future<ChapterBlocks?>> _blocksInFlight =
      <int, Future<ChapterBlocks?>>{};
  final Set<({MeasurementNamespace namespace, int chapter, String contentHash})>
  _warmedChapters =
      <({MeasurementNamespace namespace, int chapter, String contentHash})>{};

  StreamSubscription<ChapterEvent>? _chapterEventsSub;
  ScrollController? _scrollController;
  MetricsDiskCache? _metricsDiskCache;

  Size _viewportSize = Size.zero;
  double? _pendingScrollOffset;
  int _windowCenter = 0;
  int _lastLayoutGeneration = 0;
  int _runtimeLocationRevision = 0;
  int _restoreTicket = 0;
  ReaderV2Location? _lastReportedLocation;
  String? _lastLoggedErrorMessage;
  bool _initialRestoreCompleted = false;
  bool _rebuildQueued = false;
  bool _pumpFramePending = false;
  bool _captureFramePending = false;
  double? _lastDebugSnapshotOffset;
  int _discardedLayoutTaskCount = 0;
  int _fallbackItemExtentCount = 0;

  @override
  void initState() {
    super.initState();
    _chapterRepo = HybridChapterRepository(
      repository: widget.runtime.repository,
    );
    _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
    _admission = AdmissionController(documentIndex: _documentIndex);
    _admission.addListener(_refreshProvisionalGeometry);
    _physics = const HybridScrollPhysics();
    _paragraphCache = ParagraphCache();
    _refreshEpochBinding();

    _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
    _lastReportedLocation = widget.runtime.state.visibleLocation;
    _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;

    widget.runtime.registerHybridViewport(this);
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
    _attachController();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.runtime.state.phase == ReaderV2Phase.ready) {
        _restoreAttachedRuntime();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HybridReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      oldWidget.runtime.unregisterHybridViewport(this);
      oldWidget.runtime.removeListener(_onRuntimeChanged);
      oldWidget.runtime.unregisterVisibleLocationCapture(this);
      oldWidget.runtime.unregisterViewportRestore(this);
      _chapterEventsSub?.cancel();
      unawaited(_chapterRepo.dispose());
      _chapterRepo = HybridChapterRepository(
        repository: widget.runtime.repository,
      );
      _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
      widget.runtime.registerHybridViewport(this);
      widget.runtime.addListener(_onRuntimeChanged);
      widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
      widget.runtime.registerViewportRestore(this, _restoreToLocation);
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _lastReportedLocation = widget.runtime.state.visibleLocation;
      _lastLoggedErrorMessage = null;
      _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
      _restoreTicket += 1;
      _initialRestoreCompleted = false;
      _handleEpochRebuild(oldWidget.bookUrl);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreAttachedRuntime();
      });
    }
    if (oldWidget.viewportController != widget.viewportController) {
      _detachController(oldWidget.viewportController);
      _attachController();
    }
    if (oldWidget.textColor != widget.textColor) {
      _ensureWindowTasks(anchorKey: _documentIndex.centerKey);
      _schedulePump();
    }
  }

  @override
  void dispose() {
    _logTelemetrySessionSummary();
    widget.runtime.unregisterHybridViewport(this);
    widget.runtime.removeListener(_onRuntimeChanged);
    widget.runtime.unregisterVisibleLocationCapture(this);
    widget.runtime.unregisterViewportRestore(this);
    _detachController(widget.viewportController);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _chapterEventsSub?.cancel();
    unawaited(
      _writeDiskMetrics(
        _measurementStore.snapshot(_namespace),
        bookUrl: widget.bookUrl,
      ),
    );
    unawaited(_chapterRepo.dispose());
    _admission.removeListener(_refreshProvisionalGeometry);
    _admission.dispose();
    _pump.dispose();
    _paragraphCache.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      unawaited(widget.runtime.flushProgress());
      unawaited(
        _writeDiskMetrics(
          _measurementStore.snapshot(_namespace),
          bookUrl: widget.bookUrl,
        ),
      );
    }
  }

  void _logTelemetrySessionSummary() {
    final summary = _telemetry.sessionSummary();
    if ((summary['frames'] as int? ?? 0) == 0) return;
    summary['fontSize'] = _fingerprint.fontSize;
    summary['lastLineSpacingCompensation'] =
        _fingerprint.lastLineSpacingCompensation;
    AppLog.i('ReaderV2 telemetry session: ${jsonEncode(summary)}');
  }

  @visibleForTesting
  Map<String, Object?> debugSnapshot() {
    final controller = _scrollController;
    final position = controller != null && controller.hasClients
        ? controller.position
        : null;
    final offset = _effectiveScrollOffset();
    final viewportHeight = _viewportSize.height;
    final hasViewport = offset != null && viewportHeight > 0;
    final visibleKeys = hasViewport
        ? _documentIndex
              .keysInRange(offset, offset + viewportHeight)
              .toList(growable: false)
        : const <BlockKey>[];
    final missingParagraphKeys = <BlockKey>[];
    for (final key in visibleKeys) {
      if (!_paragraphCache.containsFresh(key, _epoch, widget.textColor)) {
        missingParagraphKeys.add(key);
      }
    }

    String scrollDirection = 'idle';
    final previousOffset = _lastDebugSnapshotOffset;
    if (offset != null && previousOffset != null) {
      final delta = offset - previousOffset;
      if (delta > 0.5) {
        scrollDirection = 'forward';
      } else if (delta < -0.5) {
        scrollDirection = 'backward';
      }
    }
    _lastDebugSnapshotOffset = offset;

    final captured = _captureVisibleLocation();
    final runtimeState = widget.runtime.state;
    final telemetry = _telemetry.snapshot;
    _telemetry.recordPumpQueueDepth(_pump.queueDepth);

    Map<String, int> keyJson(BlockKey key) => <String, int>{
      'chapterIndex': key.chapterIndex,
      'blockIndex': key.blockIndex,
    };

    double? finiteOrNull(double value) => value.isFinite ? value : null;

    bool isConsecutive(BlockKey previous, BlockKey next) {
      if (previous.chapterIndex == next.chapterIndex) {
        return next.blockIndex == previous.blockIndex + 1;
      }
      return next.chapterIndex == previous.chapterIndex + 1 &&
          next.blockIndex == 0;
    }

    final visibleKeysContiguous = visibleKeys.length < 2
        ? true
        : Iterable<int>.generate(visibleKeys.length - 1).every(
            (index) =>
                isConsecutive(visibleKeys[index], visibleKeys[index + 1]),
          );
    final visibleChapters = <int>[];
    for (final key in visibleKeys) {
      if (visibleChapters.isEmpty || visibleChapters.last != key.chapterIndex) {
        visibleChapters.add(key.chapterIndex);
      }
    }

    return <String, Object?>{
      'capturedAtMs': DateTime.now().millisecondsSinceEpoch,
      'displayRefreshRate': ui.PlatformDispatcher.instance.views.isEmpty
          ? null
          : finiteOrNull(
              ui.PlatformDispatcher.instance.views.first.display.refreshRate,
            ),
      'phase': runtimeState.phase.name,
      'scrollOffset': finiteOrNull(offset ?? double.nan),
      'viewportHeight': finiteOrNull(viewportHeight),
      'viewportBottom': hasViewport
          ? finiteOrNull(offset + viewportHeight)
          : null,
      'scrollDirection': scrollDirection,
      'isScrolling': position?.isScrollingNotifier.value ?? false,
      'initialRestoreCompleted': _initialRestoreCompleted,
      'runtimeLocationRevision': _runtimeLocationRevision,
      'pendingLocation': widget.runtime.pendingLocation?.toJson(),
      'runtimeVisibleLocation': runtimeState.visibleLocation.toJson(),
      'runtimeCommittedLocation': runtimeState.committedLocation.toJson(),
      'capturedLocation': captured?.toJson(),
      'layoutGeneration': runtimeState.layoutGeneration,
      'epoch': _epoch.value,
      'documentIndexRevision': _documentIndex.revisionNumber,
      'documentIndexResetGeneration': _documentIndex.resetGeneration,
      'documentIndexCenter': keyJson(_documentIndex.centerKey),
      'admittedCount': _documentIndex.admittedCount,
      'beforeCount': _documentIndex.beforeCount,
      'centerAndAfterCount': _documentIndex.centerAndAfterCount,
      'beforeExtent': finiteOrNull(_documentIndex.beforeExtent),
      'afterExtent': finiteOrNull(_documentIndex.afterExtent),
      'provisionalBeforeExtent': finiteOrNull(
        _documentIndex.provisionalBeforeExtent,
      ),
      'provisionalAfterExtent': finiteOrNull(
        _documentIndex.provisionalAfterExtent,
      ),
      'scrollableBeforeExtent': finiteOrNull(
        _documentIndex.scrollableBeforeExtent,
      ),
      'scrollableAfterExtent': finiteOrNull(
        _documentIndex.scrollableAfterExtent,
      ),
      'backwardEdge': _documentIndex.backwardEdgeKey == null
          ? null
          : keyJson(_documentIndex.backwardEdgeKey!),
      'forwardEdge': _documentIndex.forwardEdgeKey == null
          ? null
          : keyJson(_documentIndex.forwardEdgeKey!),
      'visibleKeys': [for (final key in visibleKeys) keyJson(key)],
      'visibleChapters': visibleChapters,
      'visibleKeysContiguous': visibleKeysContiguous,
      'missingParagraphKeys': [
        for (final key in missingParagraphKeys) keyJson(key),
      ],
      'paragraphCacheLength': _paragraphCache.length,
      'loadedChapterCount': _blocks.length,
      'loadedContentHashes': {
        for (final entry in _blocks.entries) entry.key: entry.value.contentHash,
      },
      'chaptersInFlight': _blocksInFlight.keys.toList(growable: false),
      'residentFirstChapter': _chapterRepo.residentFirst,
      'residentLastChapter': _chapterRepo.residentLast,
      'pumpQueueDepth': _pump.queueDepth,
      'discardedLayoutTasks': _discardedLayoutTaskCount,
      'fallbackItemExtentHits': _fallbackItemExtentCount,
      'forwardLeadPx': finiteOrNull(_admission.latestForwardLead),
      'backwardLeadPx': finiteOrNull(_admission.latestBackwardLead),
      'rollingFrameP50Micros': telemetry.frameP50Micros,
      'rollingFrameP95Micros': telemetry.frameP95Micros,
      'rollingFrameP99Micros': telemetry.frameP99Micros,
      'rollingJankOver8ms': telemetry.jankOver8ms,
      'rollingJankOver16ms': telemetry.jankOver16ms,
      'rollingJankOver33ms': telemetry.jankOver33ms,
      'worstFrameMicros': telemetry.worstFrameMicros,
      'consecutiveMissedFrames': telemetry.consecutiveMissedFrames,
      'maxConsecutiveMissedFrames': telemetry.maxConsecutiveMissedFrames,
      'layoutTaskCount': telemetry.layoutTaskCount,
      'layoutTaskP99Micros': telemetry.layoutTaskP99Micros,
      'worstLayoutTaskMicros': telemetry.worstLayoutTaskMicros,
      'worstLayoutTaskPredictedMicros':
          telemetry.worstLayoutTaskPredictedMicros,
      'worstLayoutTaskCharCount': telemetry.worstLayoutTaskCharCount,
      'layoutTasksOver8ms': telemetry.layoutTasksOver8ms,
      'vsyncOverheadP99Micros': telemetry.vsyncOverheadP99Micros,
      'buildP99Micros': telemetry.buildP99Micros,
      'rasterP99Micros': telemetry.rasterP99Micros,
      'worstVsyncOverheadMicros': telemetry.worstVsyncOverheadMicros,
      'worstBuildMicros': telemetry.worstBuildMicros,
      'worstRasterMicros': telemetry.worstRasterMicros,
    };
  }

  void _handleFrameTimings(List<ui.FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    widget.runtime.recordFrameTimings(timings);
    _governor.recordFrameTimings(timings);
    _telemetry.recordFrameTimings(timings);
  }

  void _handleLayoutTaskCompleted(LayoutPumpTaskStats stats) {
    _telemetry.recordLayoutTask(
      elapsedMicros: stats.elapsed.inMicroseconds.toDouble(),
      predictedMicros: stats.predicted.inMicroseconds.toDouble(),
      charCount: stats.charCount,
    );
  }

  void _refreshEpochBinding() {
    _epoch = LayoutEpoch(widget.runtime.state.layoutGeneration);
    _fingerprint = StyleFingerprint.fromLayoutSpec(
      widget.runtime.state.layoutSpec,
      justify: AppConfig.readerV2ContentJustify,
      platformFontSignature:
          '${defaultTargetPlatform.name}:${io.Platform.operatingSystemVersion}',
    );
    _namespace = MeasurementNamespace(epoch: _epoch, fingerprint: _fingerprint);
    _pump = LayoutPump(
      paragraphCache: _paragraphCache,
      measurementStore: _measurementStore,
      namespace: _namespace,
      governor: _governor,
      onTaskCompleted: _handleLayoutTaskCompleted,
      isTaskStillDesired: _isLayoutTaskStillDesired,
      onTaskDiscarded: _handleLayoutTaskDiscarded,
    );
    _admission.reset(epoch: _epoch, chapterCount: widget.runtime.chapterCount);
    _admission.attach(_pump.completed);
  }

  void _handleEpochRebuild(String? previousBookUrl) {
    _runtimeLocationRevision += 1;
    _restoreTicket += 1;
    _initialRestoreCompleted = false;

    final oldNamespace = _namespace;
    unawaited(
      _writeDiskMetrics(
        _measurementStore.snapshot(oldNamespace),
        fingerprint: oldNamespace.fingerprint,
        bookUrl: previousBookUrl,
      ),
    );
    _measurementStore.invalidateNamespace(oldNamespace);
    _blocks.clear();
    _blocksInFlight.clear();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _pump.dispose();
    final oldCache = _paragraphCache;
    _paragraphCache = ParagraphCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCache.dispose());
    _documentIndex.reset(centerKey: _documentIndex.centerKey);

    _refreshEpochBinding();
    _warmedChapters.clear();
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    final state = widget.runtime.state;
    final errorMessage = state.errorMessage;
    if (state.phase != ReaderV2Phase.error) {
      _lastLoggedErrorMessage = null;
    } else if (errorMessage != null &&
        errorMessage.isNotEmpty &&
        errorMessage != _lastLoggedErrorMessage) {
      _lastLoggedErrorMessage = errorMessage;
      debugPrint('ReaderV2 operation failed: $errorMessage');
    }
    final layoutChanged = _lastLayoutGeneration != state.layoutGeneration;
    if (layoutChanged) {
      _lastLayoutGeneration = state.layoutGeneration;
      _handleEpochRebuild(widget.bookUrl);
    }
    if (state.phase == ReaderV2Phase.ready && _initialRestoreCompleted) {
      _publishProgress();
    }
    _scheduleRebuild();
  }

  void _restoreAttachedRuntime() {
    final runtime = widget.runtime;
    if (runtime.state.phase == ReaderV2Phase.ready) {
      unawaited(runtime.restoreFromLocation(runtime.state.visibleLocation));
    }
  }

  ReaderV2Location? _captureForBridge() {
    final location = _captureVisibleLocation();
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  ReaderV2Location? _captureVisibleLocation() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return null;
    final anchorLine = AnchorManager.anchorOffsetInViewport(
      _viewportSize.height,
    );
    final worldY = offset + anchorLine;
    final anchorHit = _documentIndex.hitTest(worldY);
    final scrollTopHit = _documentIndex.hitTest(offset);
    final preserved = _preserveShortChapterAtBoundary(
      anchorHit: anchorHit,
      scrollOffset: offset,
    );
    if (preserved != null) return preserved;
    final hit = anchorHit ?? scrollTopHit;
    if (hit == null) return null;
    final blocks = _blocks[hit.key.chapterIndex];
    if (blocks == null || hit.key.blockIndex >= blocks.blocks.length) {
      return null;
    }
    final block = blocks.blocks[hit.key.blockIndex];
    var lineTop = 0.0;
    var charOffset = block.charRange.start;
    final entry = _paragraphCache.acquireEntry(hit.key, _epoch);
    if (entry != null) {
      final paragraph = entry.paragraph;
      final line = _lineAt(paragraph, hit.offsetInBlock + entry.localTop);
      if (line != null) {
        final group = blocks.groupContaining(hit.key);
        final indent = _indentCharsFor(group.first);
        final groupTextLength = indent + _groupTextLength(group);
        final position = paragraph.getPositionForOffset(
          Offset(0, line.top + 0.1),
        );
        final boxTop = _textBoxTopForOffset(
          paragraph,
          position.offset,
          groupTextLength,
        );
        lineTop = (boxTop ?? line.top) - entry.localTop;
        final groupStart = group.first.charRange.start;
        final groupEnd = group.last.charRange.end;
        charOffset = (groupStart + math.max(0, position.offset - indent))
            .clamp(groupStart, groupEnd)
            .toInt();
      }
    }
    final visual = (worldY - (hit.blockTop + lineTop))
        .clamp(
          ReaderV2Location.minVisualOffsetPx,
          ReaderV2Location.maxVisualOffsetPx,
        )
        .toDouble();
    return ReaderV2Location(
          chapterIndex: hit.key.chapterIndex,
          charOffset: charOffset,
          visualOffsetPx: visual,
        )
        .normalized(
          chapterCount: widget.runtime.chapterCount,
          chapterLength: blocks.displayText.length,
        )
        .withContentIdentity(
          contentHash: blocks.contentHash,
          displayText: blocks.displayText,
        );
  }

  ReaderV2Location? _preserveShortChapterAtBoundary({
    required DocumentOffsetHit? anchorHit,
    required double scrollOffset,
  }) {
    final previous = _lastReportedLocation;
    if (previous == null ||
        anchorHit == null ||
        anchorHit.key.chapterIndex != previous.chapterIndex + 1) {
      return null;
    }
    final range = _documentIndex.chapterRange(previous.chapterIndex);
    if (range == null || scrollOffset > range.bottom + 0.5) return null;
    return previous;
  }

  Future<bool> _restoreToLocation(ReaderV2Location location) async {
    final runtime = widget.runtime;
    final operation = runtime.stateMachine.currentOperation;
    final binding = _pump;
    final revision = ++_runtimeLocationRevision;
    bool current() =>
        mounted &&
        identical(widget.runtime, runtime) &&
        identical(_pump, binding) &&
        revision == _runtimeLocationRevision &&
        (operation == null || runtime.isCurrentOperationToken(operation));
    if (!current() || runtime.chapterCount <= 0) return false;
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.position.jumpTo(controller.position.pixels);
    }
    final ok = await _restoreCore(location, isCurrent: current);
    if (!ok || !current()) return false;
    _lastReportedLocation = location;
    _scheduleRebuild();
    return true;
  }

  Future<bool> _restoreCore(
    ReaderV2Location location, {
    bool Function()? isCurrent,
  }) async {
    final runtime = widget.runtime;
    if (runtime.chapterCount <= 0) return false;
    final ticket = ++_restoreTicket;
    final binding = _pump;
    bool still() =>
        mounted &&
        identical(_pump, binding) &&
        ticket == _restoreTicket &&
        (isCurrent?.call() ?? true);
    final chapterIndex = location.chapterIndex
        .clamp(0, runtime.chapterCount - 1)
        .toInt();
    _pump.onScrollStateChanged(PumpState.rebuilding);
    try {
      final blocks = await _ensureChapterBlocks(chapterIndex);
      if (blocks == null || !still()) return false;
      final normalized = location.normalized(
        chapterCount: runtime.chapterCount,
        chapterLength: blocks.displayText.length,
      );
      final anchor = HybridAnchor.fromLocation(normalized, blocks);
      // reset() invalidates the mounted sliver's old index synchronously.
      // Hide that sliver on the next frame while the anchor window is rebuilt.
      // _scheduleRebuild defers setState to a post-frame callback, so the
      // loading build only arrives later; the current frame is covered by
      // HybridScrollView's total itemExtentBuilder, not by a separate
      // total-extent callback (no such callback exists).
      _initialRestoreCompleted = false;
      _scheduleRebuild();
      _documentIndex.reset(centerKey: anchor.blockKey);

      _admission.reset(epoch: _epoch, chapterCount: runtime.chapterCount);
      _admission.attach(_pump.completed);
      for (final loadedBlocks in _blocks.values) {
        _admission.registerChapter(loadedBlocks);
      }
      _windowCenter = chapterIndex;
      final initialRadius = _chapterRepo.windowRadius;
      _chapterRepo.setResidentRange(
        math.max(0, chapterIndex - initialRadius),
        math.min(runtime.chapterCount - 1, chapterIndex + initialRadius),
      );
      _refreshProvisionalGeometry();
      _ensureWindowTasks(anchorKey: anchor.blockKey);
      final ready = await _pumpUntilAnchorReady(anchor, stillCurrent: still);
      if (!ready || !still()) return false;
      final target = _offsetForAnchor(anchor, blocks);
      if (target == null) return false;
      _applyScrollOffset(target);
      _admission.activateViewport(
        visibleTop: target,
        visibleBottom: target + _viewportSize.height,
        cacheExtent: _viewportSize.height,
      );
      _syncResidentRangeToViewport(
        fallbackCenter: chapterIndex,
        includeLead: false,
      );
      _initialRestoreCompleted = true;
      _publishProgress();
      _scheduleRebuild();
      _schedulePump();
      return true;
    } finally {
      if (mounted && identical(_pump, binding) && ticket == _restoreTicket) {
        _pump.onScrollStateChanged(PumpState.idle);
      }
    }
  }

  Future<bool> _pumpUntilAnchorReady(
    HybridAnchor anchor, {
    required bool Function() stillCurrent,
  }) async {
    bool anchorReady() =>
        _measurementStore.get(_namespace, anchor.blockKey) != null &&
        _paragraphCache.contains(anchor.blockKey, _epoch);
    bool initialWindowReady() {
      if (!anchorReady()) return false;
      final blocks = _blocks[anchor.chapterIndex];
      final target = blocks == null ? null : _offsetForAnchor(anchor, blocks);
      if (target == null) return false;
      final viewport = math.max(1.0, _viewportSize.height);
      final requiredTop = target;
      final requiredBottom = target + viewport;
      final hasTop = -_documentIndex.beforeExtent <= requiredTop;
      final hasBottom = _documentIndex.afterExtent >= requiredBottom;
      return (hasTop || _isBookStartAdmitted()) &&
          (hasBottom || _isBookEndAdmitted());
    }

    while (stillCurrent()) {
      _pump.onScrollStateChanged(PumpState.rebuilding);
      if (initialWindowReady()) return true;

      final completed = await _pump.pumpPending();
      if (!stillCurrent()) return false;
      if (completed != 0) continue;
      if (_pump.queueDepth > 0) continue;

      final pendingLoads = _blocksInFlight.values.toList(growable: false);
      if (pendingLoads.isNotEmpty) {
        await Future.wait(pendingLoads);
        if (!stillCurrent()) return false;
        _ensureWindowTasks(anchorKey: anchor.blockKey);
        continue;
      }

      final admittedBefore = _documentIndex.admittedCount;
      _ensureWindowTasks(anchorKey: anchor.blockKey);
      if (_pump.queueDepth > 0 ||
          _documentIndex.admittedCount != admittedBefore) {
        continue;
      }
      if (initialWindowReady()) return true;

      if (_expandRestoreResidency(anchor)) {
        _ensureWindowTasks(anchorKey: anchor.blockKey);
        continue;
      }
      return false;
    }
    return false;
  }

  bool _expandRestoreResidency(HybridAnchor anchor) {
    final blocks = _blocks[anchor.chapterIndex];
    final target = blocks == null ? null : _offsetForAnchor(anchor, blocks);
    if (target == null) return false;
    final viewport = math.max(1.0, _viewportSize.height);
    final needsBackward =
        -_documentIndex.beforeExtent > target && !_isBookStartAdmitted();
    final needsForward =
        _documentIndex.afterExtent < target + viewport && !_isBookEndAdmitted();
    return _expandResidentRange(backward: needsBackward, forward: needsForward);
  }

  bool _isBookStartAdmitted() {
    const first = BlockKey(chapterIndex: 0, blockIndex: 0);
    return _documentIndex.metricsFor(first) != null;
  }

  bool _isBookEndAdmitted() {
    final lastChapter = widget.runtime.chapterCount - 1;
    if (lastChapter < 0) return true;
    final blocks = _blocks[lastChapter];
    if (blocks == null || blocks.blocks.isEmpty) return false;
    return _documentIndex.metricsFor(blocks.blocks.last.key) != null;
  }

  double? _offsetForAnchor(HybridAnchor anchor, ChapterBlocks blocks) {
    final resolved = _visualPositionForChar(blocks, anchor.charOffsetInChapter);
    final key = resolved?.key ?? anchor.blockKey;
    final top = _documentIndex.topOf(key);
    if (top == null) return null;
    final lineTop = resolved?.localTop ?? 0.0;
    final anchorLine = AnchorManager.anchorOffsetInViewport(
      _viewportSize.height,
    );
    return top + lineTop - anchorLine + anchor.visualOffsetPx;
  }

  ({BlockKey key, double localTop})? _visualPositionForChar(
    ChapterBlocks blocks,
    int charOffsetInChapter,
  ) {
    final rawBlock = blocks.blockForCharOffset(charOffsetInChapter);
    final group = blocks.groupContaining(rawBlock.key);
    if (group.isEmpty) return null;
    final head = group.first;
    final rawEntry = _paragraphCache.acquireEntry(rawBlock.key, _epoch);
    if (rawEntry == null) return null;
    final indent = _indentCharsFor(head);
    final groupTextLength = indent + _groupTextLength(group);
    final groupLocalOffset =
        indent +
        (charOffsetInChapter - head.charRange.start)
            .clamp(0, groupTextLength - indent)
            .toInt();
    final paragraphY =
        _textBoxTopForOffset(
          rawEntry.paragraph,
          groupLocalOffset,
          groupTextLength,
        ) ??
        0.0;
    var owningKey = rawBlock.key;
    var owningLocalTop = rawEntry.localTop;
    for (final member in group) {
      final memberEntry = _paragraphCache.acquireEntry(member.key, _epoch);
      if (memberEntry == null) continue;
      if (memberEntry.localTop <= paragraphY + 0.001) {
        owningKey = member.key;
        owningLocalTop = memberEntry.localTop;
      } else {
        break;
      }
    }
    return (key: owningKey, localTop: paragraphY - owningLocalTop);
  }

  int _groupTextLength(List<ChapterBlock> group) {
    var total = 0;
    for (final block in group) {
      total += block.text.length;
    }
    return total;
  }

  void _applyScrollOffset(double target) {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.position.jumpTo(target);
    } else {
      _pendingScrollOffset = target;
    }
  }

  double? _effectiveScrollOffset() {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      return controller.position.pixels;
    }
    return _pendingScrollOffset;
  }

  Future<ChapterBlocks?> _ensureChapterBlocks(int chapterIndex) {
    final cached = _blocks[chapterIndex];
    if (cached != null) return Future<ChapterBlocks?>.value(cached);
    final inFlight = _blocksInFlight[chapterIndex];
    if (inFlight != null) return inFlight;
    final binding = _pump;
    final repository = _chapterRepo;
    final preprocessor = widget.preprocessor;
    final maxBlockChars = binding.maxCharsForBudget(
      _governor.ballisticSliceBudget,
    );
    late final Future<ChapterBlocks?> task;
    bool current() =>
        mounted &&
        identical(binding, _pump) &&
        identical(_blocksInFlight[chapterIndex], task);
    task = () async {
      try {
        final text = await repository.load(chapterIndex);
        if (!current()) return null;
        final preprocessed = await preprocessor.process(
          text,
          maxBlockChars: maxBlockChars,
        );
        if (!current()) return null;
        final spec = widget.runtime.state.layoutSpec;
        final blocks = await binding.alignChapterBlocksToVisualLines(
          preprocessed,
          maxBlockChars: maxBlockChars,
          bodyStyle: HybridBlockTextStyle.fromLayoutStyle(
            spec.style,
            justify: AppConfig.readerV2ContentJustify,
          ),
          contentWidth: spec.contentWidth,
          cellWidth: spec.cellWidth,
          textIndent: spec.style.textIndent.clamp(0, 8).toInt(),
        );
        if (!current()) return null;
        await _warmDiskMetricsForChapter(blocks);
        if (!current()) return null;
        _blocks[chapterIndex] = blocks;
        _admission.registerChapter(blocks);
        _refreshProvisionalGeometry();
        return blocks;
      } catch (_) {
        return null;
      }
    }();
    _blocksInFlight[chapterIndex] = task;
    task.whenComplete(() {
      if (identical(_blocksInFlight[chapterIndex], task)) {
        _blocksInFlight.remove(chapterIndex);
      }
    });
    return task;
  }

  void _onChapterEvent(ChapterEvent event) {
    if (!mounted) return;
    switch (event.kind) {
      case ChapterEventKind.loaded:
        if (_chapterRepo.isResident(event.chapterId)) {
          unawaited(
            _ensureChapterBlocks(event.chapterId).then((blocks) {
              if (blocks == null ||
                  !mounted ||
                  !_chapterRepo.isResident(event.chapterId)) {
                return;
              }
              _enqueueChapterTasks(blocks);
              _schedulePump();
            }),
          );
        }
        return;
      case ChapterEventKind.evicted:
        // Raw chapter residency is only a memory-cache policy. Existing block
        // geometry/Paragraphs remain valid for this epoch and must not vanish
        // from the scroll world merely because raw text was evicted.
        return;
      case ChapterEventKind.invalidated:
        _blocks.remove(event.chapterId);
        _blocksInFlight.remove(event.chapterId);
        _warmedChapters.removeWhere(
          (entry) => entry.chapter == event.chapterId,
        );
        _pump.invalidateChapter(event.chapterId);
        _measurementStore.invalidateChapter(event.chapterId);
        _paragraphCache.invalidateChapter(event.chapterId);
        _admission.invalidateChapter(event.chapterId);
        if (_documentIndex.invalidateChapter(event.chapterId)) {
          _scheduleRebuild();
        }
        _refreshProvisionalGeometry();
        return;
    }
  }

  void _shiftWindow(int chapterIndex) {
    if (chapterIndex == _windowCenter) return;
    _windowCenter = chapterIndex;
    _syncResidentRangeToViewport(fallbackCenter: chapterIndex);
    _ensureWindowTasks();
    _schedulePump();
  }

  void _syncResidentRangeToViewport({
    int? fallbackCenter,
    bool includeLead = true,
  }) {
    final chapterCount = widget.runtime.chapterCount;
    if (chapterCount <= 0) return;
    final center = (fallbackCenter ?? _windowCenter)
        .clamp(0, chapterCount - 1)
        .toInt();
    final radius = _chapterRepo.windowRadius;
    var first = math.max(0, center - radius);
    var last = math.min(chapterCount - 1, center + radius);

    final offset = _effectiveScrollOffset();
    if (offset != null &&
        _viewportSize.height > 0 &&
        _documentIndex.admittedCount > 0) {
      final top = includeLead
          ? offset - _admission.backwardGuaranteedWindow
          : offset;
      final bottom = includeLead
          ? offset + _viewportSize.height + _admission.guaranteedWindow
          : offset + _viewportSize.height;
      for (final key in _documentIndex.keysInRange(top, bottom)) {
        first = math.min(first, key.chapterIndex);
        last = math.max(last, key.chapterIndex);
      }
      if (top < -_documentIndex.beforeExtent &&
          !_admission.atBackwardBookBoundary) {
        final edge = _documentIndex.backwardEdgeKey;
        if (edge != null && edge.chapterIndex > 0) {
          first = math.min(first, edge.chapterIndex - 1);
        }
      }
      if (bottom > _documentIndex.afterExtent &&
          !_admission.atForwardBookBoundary) {
        final edge = _documentIndex.forwardEdgeKey;
        if (edge != null && edge.chapterIndex + 1 < chapterCount) {
          last = math.max(last, edge.chapterIndex + 1);
        }
      }
    }
    _chapterRepo.setResidentRange(first, last);
  }

  bool _expandResidentRange({required bool backward, required bool forward}) {
    if (!backward && !forward) return false;
    final chapterCount = widget.runtime.chapterCount;
    if (chapterCount <= 0) return false;
    final currentFirst = (_chapterRepo.residentFirst ?? _windowCenter)
        .clamp(0, chapterCount - 1)
        .toInt();
    final currentLast = (_chapterRepo.residentLast ?? _windowCenter)
        .clamp(currentFirst, chapterCount - 1)
        .toInt();
    final nextFirst = backward && currentFirst > 0
        ? currentFirst - 1
        : currentFirst;
    final nextLast = forward && currentLast + 1 < chapterCount
        ? currentLast + 1
        : currentLast;
    if (nextFirst == currentFirst && nextLast == currentLast) return false;
    _chapterRepo.setResidentRange(nextFirst, nextLast);
    return true;
  }

  List<int> _residentChaptersNearestCenter() {
    final chapterCount = widget.runtime.chapterCount;
    if (chapterCount <= 0) return const <int>[];
    final first = (_chapterRepo.residentFirst ?? _windowCenter)
        .clamp(0, chapterCount - 1)
        .toInt();
    final last = (_chapterRepo.residentLast ?? _windowCenter)
        .clamp(first, chapterCount - 1)
        .toInt();
    final chapters = <int>[
      for (var index = first; index <= last; index++) index,
    ];
    chapters.sort((a, b) {
      final da = (a - _windowCenter).abs();
      final db = (b - _windowCenter).abs();
      final distance = da.compareTo(db);
      if (distance != 0) return distance;
      return b.compareTo(a);
    });
    return chapters;
  }

  void _refreshProvisionalGeometry() {
    final center = _documentIndex.centerKey;
    final first = _chapterRepo.residentFirst;
    final last = _chapterRepo.residentLast;
    if (first == null || last == null || _blocks.isEmpty) {
      _documentIndex.setProvisionalExtents(before: 0, after: 0);
      return;
    }

    var before = 0.0;
    var after = 0.0;

    for (var chapter = center.chapterIndex; chapter >= first; chapter -= 1) {
      final blocks = _blocks[chapter];
      if (blocks == null) break;
      for (final block in blocks.blocks) {
        if (block.key >= center) continue;
        if (_documentIndex.metricsFor(block.key) != null) continue;
        before += _provisionalHeightFor(blocks, block);
      }
    }

    for (var chapter = center.chapterIndex; chapter <= last; chapter += 1) {
      final blocks = _blocks[chapter];
      if (blocks == null) break;
      for (final block in blocks.blocks) {
        if (block.key < center) continue;
        if (_documentIndex.metricsFor(block.key) != null) continue;
        after += _provisionalHeightFor(blocks, block);
      }
    }

    _documentIndex.setProvisionalExtents(before: before, after: after);
  }

  double _provisionalHeightFor(ChapterBlocks blocks, ChapterBlock block) {
    final exact = _measurementStore.get(_namespace, block.key);
    if (exact != null) return exact.height;

    final spec = widget.runtime.state.layoutSpec;
    final style = spec.style;
    final cell = spec.cellWidth;
    final fallbackCell = style.fontSize > 0 ? style.fontSize : 1.0;
    final advance = cell != null && cell.isFinite && cell > 0
        ? cell
        : fallbackCell;
    final columns = math.max(1, (spec.contentWidth / advance).floor());
    final textUnits = math.max(1, block.text.length + _indentCharsFor(block));
    final lines = math.max(1, (textUnits / columns).ceil());
    final lineHeight = math.max(
      1.0,
      style.fontSize * style.effectiveLineHeight,
    );
    return lines * lineHeight + _trailingSpacingFor(blocks, block);
  }

  void _ensureWindowTasks({BlockKey? anchorKey}) {
    if (!mounted) return;
    for (final chapter in _residentChaptersNearestCenter()) {
      final blocks = _blocks[chapter];
      if (blocks == null) {
        unawaited(
          _ensureChapterBlocks(chapter).then((loaded) {
            if (loaded == null ||
                !mounted ||
                !_chapterRepo.isResident(loaded.chapterIndex)) {
              return;
            }
            _enqueueChapterTasks(
              loaded,
              anchorKey: loaded.chapterIndex == _windowCenter
                  ? anchorKey
                  : null,
            );
            _schedulePump();
          }),
        );
        continue;
      }
      _enqueueChapterTasks(
        blocks,
        anchorKey: chapter == _windowCenter ? anchorKey : null,
      );
    }
  }

  void _enqueueChapterTasks(ChapterBlocks blocks, {BlockKey? anchorKey}) {
    final groups = blocks.paragraphGroups();
    if (groups.isEmpty) return;
    final centerKey = _documentIndex.centerKey;
    List<List<ChapterBlock>> forward;
    List<List<ChapterBlock>> backward;
    if (blocks.chapterIndex == centerKey.chapterIndex) {
      var centerGroupIndex = groups.indexWhere(
        (group) => group.first.key <= centerKey && centerKey <= group.last.key,
      );
      if (centerGroupIndex < 0) centerGroupIndex = 0;
      forward = groups.sublist(centerGroupIndex);
      backward = groups
          .sublist(0, centerGroupIndex)
          .reversed
          .toList(growable: false);
    } else if (blocks.chapterIndex > centerKey.chapterIndex) {
      forward = groups;
      backward = const <List<ChapterBlock>>[];
    } else {
      forward = const <List<ChapterBlock>>[];
      backward = groups.reversed.toList(growable: false);
    }
    final rounds = math.max(forward.length, backward.length);
    for (var i = 0; i < rounds; i += 1) {
      if (i < forward.length) {
        _admitOrSubmitGroup(
          blocks,
          forward[i],
          anchorKey: anchorKey,
        );
      }
      if (i < backward.length) {
        _admitOrSubmitGroup(
          blocks,
          backward[i],
          anchorKey: anchorKey,
        );
      }
    }
  }

  void _admitOrSubmitGroup(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    BlockKey? anchorKey,
  }) {
    final anchor = anchorKey != null && group.any((b) => b.key == anchorKey);
    final notYetAdmitted = group
        .where((b) => _documentIndex.metricsFor(b.key) == null)
        .toList(growable: false);
    if (notYetAdmitted.isEmpty) {
      final missingParagraph = group.any(
        (b) => !_paragraphCache.containsFresh(b.key, _epoch, widget.textColor),
      );
      if (missingParagraph) _submitGroupTask(blocks, group, anchor: anchor);
      return;
    }
    final allReady = notYetAdmitted.every(
      (b) =>
          _measurementStore.get(_namespace, b.key) != null &&
          _paragraphCache.containsFresh(b.key, _epoch, widget.textColor),
    );
    if (allReady) {
      for (final b in notYetAdmitted) {
        final metrics = _measurementStore.get(_namespace, b.key)!;
        _admission.offer(
          BlockReady(key: b.key, epoch: _epoch, metrics: metrics),
        );
      }
      return;
    }
    _submitGroupTask(blocks, group, anchor: anchor);
  }

  /// 排版需求的唯一判準：`(epoch, fingerprint, residentRange)`。
  ///
  /// 投放端（[_ensureWindowTasks]／[_onChapterEvent]）與 drain 端都查同一個
  /// geometry-owned resident range，避免 viewport 擴張後投放、卻被固定半徑
  /// 立即丟棄的震盪。
  ///
  /// epoch／fingerprint 改變時 [_handleEpochRebuild] 會整個換掉 pump，理論上
  /// 走不到這裡；仍然檢查，讓失效鍵在單一處完整表達。
  bool _isLayoutTaskStillDesired(LayoutTask task) {
    return task.epoch == _epoch && task.fingerprint == _fingerprint;
  }

  /// layout 熱路徑：只遞增，不配置、不組字串、不 log。
  void _handleFallbackItemExtent() {
    _fallbackItemExtentCount += 1;
  }

  void _handleLayoutTaskDiscarded(LayoutTask _) {
    _discardedLayoutTaskCount += 1;
  }

  void _submitGroupTask(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    bool anchor = false,
  }) {
    final head = group.first;
    final headKey = head.key;
    final last = group.last;
    final spec = widget.runtime.state.layoutSpec;
    _pump.submit(
      LayoutTask(
        block: head,
        continuationBlocks: group.length > 1
            ? group.sublist(1)
            : const <ChapterBlock>[],
        epoch: _epoch,
        fingerprint: _fingerprint,
        textStyle: HybridBlockTextStyle.fromLayoutStyle(
          spec.style,
          isTitle: head.isTitle,
          justify: AppConfig.readerV2ContentJustify && !head.isTitle,
        ),
        contentWidth: spec.contentWidth,
        cellWidth: spec.cellWidth,
        textColor: widget.textColor,
        priority: _priorityFor(headKey, anchor: anchor),
        direction: headKey < _documentIndex.centerKey
            ? HybridScrollDirection.backward
            : HybridScrollDirection.forward,
        indentChars: _indentCharsFor(head),
        trailingSpacing: _trailingSpacingFor(blocks, last),
        trailingLayoutLookahead: _layoutLookaheadAfter(blocks, last),
      ),
    );
  }

  String _layoutLookaheadAfter(ChapterBlocks blocks, ChapterBlock block) {
    final nextIndex = block.blockIndex + 1;
    if (nextIndex >= blocks.blocks.length) return '';
    final next = blocks.blocks[nextIndex];
    if (!next.isContinuation ||
        !next.layoutBreakBefore ||
        next.sourceParagraphIndex != block.sourceParagraphIndex ||
        next.text.isEmpty) {
      return '';
    }
    return String.fromCharCode(next.text.runes.first);
  }

  LayoutTaskPriority _priorityFor(BlockKey key, {required bool anchor}) {
    if (anchor) return LayoutTaskPriority.anchor;
    final center = _documentIndex.centerKey;
    if (key.chapterIndex == center.chapterIndex &&
        (key.blockIndex - center.blockIndex).abs() <= 40) {
      return LayoutTaskPriority.visible;
    }
    return LayoutTaskPriority.prefetch;
  }

  int _indentCharsFor(ChapterBlock block) {
    if (block.isTitle || block.isContinuation) return 0;
    return widget.runtime.state.layoutSpec.style.textIndent.clamp(0, 8).toInt();
  }

  double _trailingSpacingFor(ChapterBlocks blocks, ChapterBlock block) {
    final style = widget.runtime.state.layoutSpec.style;
    if (block.isTitle) return style.paragraphSpacing * 8;
    final nextIndex = block.blockIndex + 1;
    if (nextIndex < blocks.blocks.length) {
      final next = blocks.blocks[nextIndex];
      if (next.isContinuation &&
          next.sourceParagraphIndex == block.sourceParagraphIndex) {
        return 0.0;
      }
    }
    return style.fontSize * style.effectiveLineHeight * style.paragraphSpacing;
  }

  void _setPumpState(PumpState state) {
    _pump.onScrollStateChanged(state);
  }

  void _schedulePump() {
    if (_pumpFramePending || !mounted) return;
    _pumpFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pumpFramePending = false;
      if (!mounted) return;
      unawaited(_pumpOnce());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _pumpOnce() async {
    await _pump.pumpPending();
    if (!mounted) return;
    if (_pump.queueDepth > 0) {
      _schedulePump();
    } else {
      _updateLeadTelemetry();
    }
  }

  void _updateLeadTelemetry() {
    if (!_initialRestoreCompleted) return;
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    _admission.updateLead(
      viewportTop: offset,
      viewportBottom: offset + _viewportSize.height,
    );
    _telemetry.updateRuntimeStats(
      pumpQueueDepth: _pump.queueDepth,
      forwardLeadPx: _admission.latestForwardLead,
      backwardLeadPx: _admission.latestBackwardLead,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _runtimeLocationRevision += 1;
      _setPumpState(PumpState.dragging);
      _schedulePump();
    } else if (notification is ScrollUpdateNotification) {
      _setPumpState(
        notification.dragDetails == null
            ? PumpState.ballistic
            : PumpState.dragging,
      );
      _schedulePump();
      _scheduleMotionCapture();
    } else if (notification is ScrollEndNotification) {
      _setPumpState(PumpState.idle);
      _schedulePump();
      unawaited(_handleScrollSettled());
    }
    return false;
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending ||
        !mounted ||
        widget.runtime.pendingLocation != null) {
      return;
    }
    _captureFramePending = true;
    final scheduledRevision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted) return;
      if (!_initialRestoreCompleted) return;
      if (scheduledRevision != _runtimeLocationRevision) return;
      if (widget.runtime.pendingLocation != null) return;
      final location = _captureAndReport(notify: false);
      final offset = _effectiveScrollOffset();
      if (offset != null) {
        _admission.updateViewport(
          visibleTop: offset,
          visibleBottom: offset + _viewportSize.height,
          cacheExtent: _viewportSize.height,
        );
      }
      _publishProgress();
      _updateLeadTelemetry();
      if (location != null && location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      } else {
        _syncResidentRangeToViewport();
        _ensureWindowTasks();
        _schedulePump();
      }
    });
  }

  ReaderV2Location? _captureAndReport({required bool notify}) {
    final location = widget.runtime.captureVisibleLocation(
      notifyIfChanged: notify,
    );
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  Future<void> _handleScrollSettled() async {
    if (!mounted || !_initialRestoreCompleted) return;
    final settleRestoreTicket = _restoreTicket;
    final location = _captureAndReport(notify: true);
    if (location != null) {
      final saved = await widget.runtime.saveProgress(
        location: location,
        immediate: true,
      );
      if (saved != null) _lastReportedLocation = saved;
      if (!mounted || settleRestoreTicket != _restoreTicket) return;
      if (location.chapterIndex != _windowCenter) {
        _windowCenter = location.chapterIndex;
      }
    }
    _publishProgress();
    _updateLeadTelemetry();
    _syncResidentRangeToViewport();
    _ensureWindowTasks();
    _schedulePump();
  }

  void _publishProgress() {
    final notifier = widget.progressListenable;
    if (notifier == null) return;

    // Chapter progress is semantic content progress, not materialized layout
    // progress. DocumentIndex intentionally contains only the admitted window.
    final runtimeLocationIsPublished =
        _initialRestoreCompleted &&
        widget.runtime.state.phase == ReaderV2Phase.ready;
    final location = runtimeLocationIsPublished
        ? widget.runtime.state.visibleLocation
        : _captureVisibleLocation();
    if (location == null) return;
    final blocks = _blocks[location.chapterIndex];
    if (blocks == null) return;

    notifier.value = HybridProgress(
      chapterCount: widget.runtime.chapterCount,
    ).progressForLocation(location, chapterLength: blocks.displayText.length);
  }

  void _attachController() {
    widget.viewportController
      ?..scrollBy = _scrollBy
      ..continuousScrollBy = _continuousScrollBy
      ..animateBy = _animateBy
      ..moveToNextPage = _moveToNextPage
      ..moveToPrevPage = _moveToPrevPage
      ..settleScroll = _settleScroll
      ..ensureCharRangeVisible = _ensureCharRangeVisible;
  }

  void _detachController(ReaderV2ViewportController? controller) {
    if (controller == null) return;
    if (controller.scrollBy == _scrollBy) controller.scrollBy = null;
    if (controller.continuousScrollBy == _continuousScrollBy) {
      controller.continuousScrollBy = null;
    }
    if (controller.animateBy == _animateBy) controller.animateBy = null;
    if (controller.moveToNextPage == _moveToNextPage) {
      controller.moveToNextPage = null;
    }
    if (controller.moveToPrevPage == _moveToPrevPage) {
      controller.moveToPrevPage = null;
    }
    if (controller.settleScroll == _settleScroll) {
      controller.settleScroll = null;
    }
    if (controller.ensureCharRangeVisible == _ensureCharRangeVisible) {
      controller.ensureCharRangeVisible = null;
    }
  }

  bool Function() _captureCommandOwner() {
    final runtime = widget.runtime;
    final operation = runtime.stateMachine.currentOperation;
    final binding = _pump;
    final revision = _runtimeLocationRevision;
    return () =>
        _initialRestoreCompleted &&
        mounted &&
        identical(widget.runtime, runtime) &&
        !runtime.disposed &&
        runtime.state.phase == ReaderV2Phase.ready &&
        identical(_pump, binding) &&
        revision == _runtimeLocationRevision &&
        identical(runtime.stateMachine.currentOperation, operation);
  }

  Future<bool> _enqueueCommand(Future<bool> Function(bool Function()) command) {
    final current = _captureCommandOwner();
    return _commands.enqueue(
      isCurrent: current,
      command: () => command(current),
    );
  }

  Future<bool> _scrollBy(double delta) =>
      _enqueueCommand((current) => _scrollByNow(delta, current));
  Future<bool> _continuousScrollBy(double delta) =>
      _enqueueCommand((current) => _continuousScrollByNow(delta, current));
  Future<bool> _animateBy(double delta) =>
      _enqueueCommand((current) => _animateByNow(delta, current));
  Future<bool> _moveToNextPage() => _enqueueCommand(
    (current) => _movePageNow(forward: true, isCurrent: current),
  );
  Future<bool> _moveToPrevPage() => _enqueueCommand(
    (current) => _movePageNow(forward: false, isCurrent: current),
  );

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) {
    final owner = _captureCommandOwner();
    bool current() => owner() && !_commands.isBusy;
    if (!current()) return Future<bool>.value(false);
    return _ensureCharRangeVisibleNow(
      chapterIndex: chapterIndex,
      startCharOffset: startCharOffset,
      endCharOffset: endCharOffset,
      isCurrent: current,
    );
  }

  Future<void> _settleScroll() async {
    _runtimeLocationRevision += 1;
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
    }
    await _handleScrollSettled();
  }

  bool _jumpBy(double delta) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients || delta == 0) {
      return false;
    }
    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) return false;
    position.jumpTo(target);
    return true;
  }

  Future<bool> _scrollByNow(double delta, bool Function() isCurrent) async {
    if (!isCurrent() || !_jumpBy(delta)) return false;
    await _handleScrollSettled();
    return isCurrent();
  }

  Future<bool> _continuousScrollByNow(
    double delta,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent() || !_jumpBy(delta)) return false;
    _scheduleMotionCapture();
    _schedulePump();
    return isCurrent();
  }

  Future<bool> _animateByNow(double delta, bool Function() isCurrent) async {
    final controller = _scrollController;
    if (!isCurrent() ||
        controller == null ||
        !controller.hasClients ||
        delta == 0) {
      return false;
    }
    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) return false;
    await position.animateTo(
      target,
      duration: _ensureAnimateDuration,
      curve: Curves.easeOutCubic,
    );
    if (!isCurrent()) return false;
    await _handleScrollSettled();
    return isCurrent();
  }

  Future<bool> _ensurePageDistanceAvailable({
    required bool forward,
    required double distance,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() || distance <= 0) return false;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;

    while (isCurrent()) {
      _refreshProvisionalGeometry();
      final pixels = controller.position.pixels;
      final available = forward
          ? _documentIndex.scrollableAfterExtent - pixels
          : pixels + _documentIndex.scrollableBeforeExtent;
      final atBookBoundary = forward
          ? _admission.atForwardBookBoundary
          : _admission.atBackwardBookBoundary;
      if (available + 0.5 >= distance || atBookBoundary) return true;

      if (!_expandResidentRange(backward: !forward, forward: forward)) {
        return false;
      }

      // Loading semantic blocks may extend the scroll world immediately via
      // provisional geometry. Exact Paragraph layout stays on the normal pump
      // and is never a precondition for page movement.
      _ensureWindowTasks(anchorKey: _documentIndex.centerKey);
      final pendingLoads = _blocksInFlight.values.toList(growable: false);
      if (pendingLoads.isNotEmpty) {
        await Future.wait(pendingLoads);
        if (!isCurrent()) return false;
      }
      _refreshProvisionalGeometry();
      _ensureWindowTasks(anchorKey: _documentIndex.centerKey);
      _schedulePump();

      WidgetsBinding.instance.ensureVisualUpdate();
      await WidgetsBinding.instance.endOfFrame;
      if (!isCurrent()) return false;
    }
    return false;
  }

  Future<bool> _movePageNow({
    required bool forward,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    final height = _viewportSize.height;
    if (height <= 0) return false;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final style = widget.runtime.state.layoutSpec.style;
    final overlap = math.max(24.0, style.fontSize * style.effectiveLineHeight);
    final magnitude = math.max(height * 0.5, height - overlap - 8.0);

    final reachable = await _ensurePageDistanceAvailable(
      forward: forward,
      distance: magnitude,
      isCurrent: isCurrent,
    );
    if (!reachable || !isCurrent() || !controller.hasClients) return false;

    final before = controller.position.pixels;
    final moved = await _animateByNow(
      forward ? magnitude : -magnitude,
      isCurrent,
    );
    if (!isCurrent()) return false;
    if (!moved) _emitBookBoundaryNotice(forward: forward);
    if (!moved || !controller.hasClients) return false;

    final after = controller.position.pixels;
    final atBookBoundary = forward
        ? _admission.atForwardBookBoundary
        : _admission.atBackwardBookBoundary;
    return isHybridPageMoveComplete(
      requestedDistance: magnitude,
      actualDistance: (after - before).abs(),
      atBookBoundary: atBookBoundary,
    );
  }

  void _emitBookBoundaryNotice({required bool forward}) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final atExtent = forward
        ? position.pixels >= position.maxScrollExtent - _minimumViewportMovement
        : position.pixels <=
              position.minScrollExtent + _minimumViewportMovement;
    final atBookBoundary = forward
        ? _admission.atForwardBookBoundary
        : _admission.atBackwardBookBoundary;
    if (!atExtent || !atBookBoundary) return;
    widget.runtime.emitUserNotice(forward ? '已到書尾' : '已到書首');
  }

  Future<bool> _ensureCharRangeVisibleNow({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
    required bool Function() isCurrent,
  }) async {
    final runtime = widget.runtime;
    if (!isCurrent() || runtime.chapterCount <= 0) return false;
    final safeChapter = chapterIndex.clamp(0, runtime.chapterCount - 1).toInt();
    final blocks = await _ensureChapterBlocks(safeChapter);
    if (blocks == null || !isCurrent()) return false;
    final start = math.min(startCharOffset, endCharOffset);
    final end = math.max(startCharOffset, endCharOffset);
    final anchorKey = blocks.blockForCharOffset(start).key;
    if (_documentIndex.topOf(anchorKey) == null) {
      final ok = await _restoreCore(
        ReaderV2Location(chapterIndex: safeChapter, charOffset: start),
        isCurrent: isCurrent,
      );
      if (ok && isCurrent()) await _handleScrollSettled();
      return ok && isCurrent();
    }
    await _ensureRangeLaidOut(blocks, start, end, isCurrent);
    if (!isCurrent()) return false;
    final rect = _worldRectForRange(blocks, start, end);
    final offset = _effectiveScrollOffset();
    if (rect == null || offset == null) return false;
    final height = _viewportSize.height;
    final topPadding = math.min(80.0, height * 0.14);
    final bottomPadding = math.min(120.0, height * 0.20);
    final preferredTopInset = math.min(180.0, height * 0.32);
    final comfortBottom = offset + math.min(220.0, height * 0.46);
    final visibleTop = offset + topPadding;
    final visibleBottom = offset + height - bottomPadding;
    final safelyVisible =
        rect.top >= visibleTop && rect.bottom <= visibleBottom;
    if (safelyVisible && rect.top <= comfortBottom) return true;
    final preferredTarget = rect.top - preferredTopInset;
    final minTarget = rect.bottom - height + bottomPadding;
    final maxTarget = rect.top - topPadding;
    final target = minTarget <= maxTarget
        ? preferredTarget.clamp(minTarget, maxTarget).toDouble()
        : minTarget;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final position = controller.position;
    final bounded = target
        .clamp(
          math.min(position.minScrollExtent, position.pixels),
          math.max(position.maxScrollExtent, position.pixels),
        )
        .toDouble();
    await position.animateTo(
      bounded,
      duration: _ensureAnimateDuration,
      curve: Curves.easeOutCubic,
    );
    if (!isCurrent()) return false;
    await _handleScrollSettled();
    return isCurrent();
  }

  Future<void> _ensureRangeLaidOut(
    ChapterBlocks blocks,
    int start,
    int end,
    bool Function() isCurrent,
  ) async {
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    final targets = blocks.blocks
        .where((block) {
          return block.charRange.intersects(range) ||
              (range.isEmpty && block.charRange.containsOffset(range.start));
        })
        .toList(growable: false);
    final seenGroupHeads = <BlockKey>{};
    for (final block in targets) {
      if (_paragraphCache.contains(block.key, _epoch) &&
          _measurementStore.get(_namespace, block.key) != null) {
        continue;
      }
      final group = blocks.groupContaining(block.key);
      if (group.isEmpty || !seenGroupHeads.add(group.first.key)) continue;
      _submitGroupTask(blocks, group, anchor: true);
    }
    bool allReady() => targets.every(
      (block) =>
          _paragraphCache.contains(block.key, _epoch) &&
          _measurementStore.get(_namespace, block.key) != null,
    );
    while (isCurrent() && !allReady()) {
      final completed = await _pump.pumpPending();
      if (completed == 0) break;
    }
  }

  List<ui.TextBox>? _blockLocalBoxesForRange(
    ChapterBlocks blocks,
    ChapterBlock block,
    HybridTextRange range,
  ) {
    final entry = _paragraphCache.acquireEntry(block.key, _epoch);
    if (entry == null) return null;
    final group = blocks.groupContaining(block.key);
    if (group.isEmpty) return null;
    final indent = _indentCharsFor(group.first);
    final groupStart = group.first.charRange.start;
    final localStart =
        math.max(range.start, block.charRange.start) - groupStart + indent;
    final localEnd =
        math.min(range.end, block.charRange.end) - groupStart + indent;
    if (localEnd <= localStart) return const <ui.TextBox>[];
    final boxes = entry.paragraph.getBoxesForRange(localStart, localEnd);
    if (boxes.isEmpty) return boxes;
    return <ui.TextBox>[
      for (final box in boxes)
        ui.TextBox.fromLTRBD(
          box.left,
          box.top - entry.localTop,
          box.right,
          box.bottom - entry.localTop,
          box.direction,
        ),
    ];
  }

  Rect? _worldRectForRange(ChapterBlocks blocks, int start, int end) {
    double? top;
    double? bottom;
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    for (final block in blocks.blocks) {
      if (!block.charRange.intersects(range) &&
          !(range.isEmpty && block.charRange.containsOffset(range.start))) {
        continue;
      }
      final blockTop = _documentIndex.topOf(block.key);
      if (blockTop == null) continue;
      double localTop = 0;
      double localBottom = _documentIndex.metricsFor(block.key)?.height ?? 0;
      final boxes = _blockLocalBoxesForRange(blocks, block, range);
      if (boxes != null && boxes.isNotEmpty) {
        localTop = boxes.first.top;
        localBottom = boxes
            .map((box) => box.bottom)
            .reduce(math.max)
            .toDouble();
      }
      final rangeTop = blockTop + localTop;
      final rangeBottom = blockTop + localBottom;
      top = top == null ? rangeTop : math.min(top, rangeTop);
      bottom = bottom == null ? rangeBottom : math.max(bottom, rangeBottom);
    }
    if (top == null || bottom == null) return null;
    return Rect.fromLTRB(0, top, 0, bottom);
  }

  List<HybridLineBox> _ttsLineBoxes(ReaderV2TtsHighlight highlight) {
    final offset = _effectiveScrollOffset();
    final blocks = _blocks[highlight.chapterIndex];
    if (offset == null || blocks == null) return const <HybridLineBox>[];
    final range = HybridTextRange(
      math.max(0, highlight.highlightStart),
      math.max(0, highlight.highlightEnd),
    );
    if (range.isEmpty) return const <HybridLineBox>[];
    final result = <HybridLineBox>[];
    final seenLines = <({BlockKey key, double top, double bottom})>{};
    final blockList = blocks.blocks;
    var low = 0;
    var high = blockList.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (blockList[middle].charRange.end <= range.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < blockList.length; index += 1) {
      final block = blockList[index];
      if (block.charRange.start >= range.end) break;
      if (!block.charRange.intersects(range)) continue;
      final top = _documentIndex.topOf(block.key);
      if (top == null) continue;
      final boxes = _blockLocalBoxesForRange(blocks, block, range);
      if (boxes == null || boxes.isEmpty) continue;
      final clipped = HybridTextRange(
        math.max(range.start, block.charRange.start),
        math.min(range.end, block.charRange.end),
      );
      for (final box in boxes) {
        final screenTop = top + box.top - offset;
        final screenBottom = top + box.bottom - offset;
        if (!seenLines.add((
          key: block.key,
          top: screenTop,
          bottom: screenBottom,
        ))) {
          continue;
        }
        result.add(
          HybridLineBox(
            key: block.key,
            top: screenTop,
            bottom: screenBottom,
            charRange: clipped,
          ),
        );
      }
    }
    return result;
  }

  Future<void> _warmDiskMetricsForChapter(ChapterBlocks blocks) async {
    final bookUrl = widget.bookUrl;
    if (!widget.enableDiskMetrics || bookUrl == null) return;
    final namespace = _namespace;
    final binding = _pump;
    final warmKey = (
      namespace: namespace,
      chapter: blocks.chapterIndex,
      contentHash: blocks.layoutIdentity,
    );
    if (!_warmedChapters.add(warmKey)) return;
    try {
      final cache = await _obtainDiskCache();
      final count = await cache.warmIntoStore(
        bookUrl: bookUrl,
        namespace: namespace,
        chapterLayoutIdentities: {blocks.chapterIndex: blocks.layoutIdentity},
        put: (key, metrics) {
          if (mounted &&
              identical(binding, _pump) &&
              _warmedChapters.contains(warmKey)) {
            _measurementStore.put(namespace, key, metrics);
          }
        },
      );
      if (mounted && identical(binding, _pump)) {
        _telemetry.recordDiskMetricsHit(count > 0);
      }
    } catch (_) {}
  }

  Future<void> _writeDiskMetrics(
    Map<BlockKey, BlockMetrics> snapshot, {
    required String? bookUrl,
    StyleFingerprint? fingerprint,
  }) async {
    if (!widget.enableDiskMetrics || bookUrl == null || snapshot.isEmpty) {
      return;
    }
    final targetFingerprint = fingerprint ?? _fingerprint;
    final chapterLayoutIdentities = <int, String>{
      for (final blocks in _blocks.values)
        blocks.chapterIndex: blocks.layoutIdentity,
    };
    try {
      final cache = await _obtainDiskCache();
      await cache.write(
        bookUrl: bookUrl,
        fingerprint: targetFingerprint,
        metrics: snapshot,
        chapterLayoutIdentities: chapterLayoutIdentities,
      );
    } catch (_) {}
  }

  Future<MetricsDiskCache> _obtainDiskCache() async {
    final existing = _metricsDiskCache;
    if (existing != null) return existing;
    final directory = await getApplicationSupportDirectory();
    return _metricsDiskCache = MetricsDiskCache(baseDirectory: directory);
  }

  void _scheduleRebuild() {
    if (!mounted || _rebuildQueued) return;
    _rebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _holdScrollOnPointerDown(PointerDownEvent event) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final scrolling = controller.position.isScrollingNotifier.value;
    if (scrolling) {
      _runtimeLocationRevision += 1;
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
      return true;
    }
    return false;
  }

  ({double top, double bottom})? _lineAt(ui.Paragraph paragraph, double dy) {
    final lineCount = paragraph.numberOfLines;
    if (lineCount <= 0) return null;
    final position = paragraph.getPositionForOffset(Offset(0, dy));
    final lineNumber =
        (paragraph.getLineNumberAt(math.max(0, position.offset)) ??
                lineCount - 1)
            .clamp(0, lineCount - 1)
            .toInt();
    final line = paragraph.getLineMetricsAt(lineNumber);
    if (line == null) return null;
    final lineTop = line.baseline - line.ascent;
    return (top: lineTop, bottom: lineTop + line.height);
  }

  double? _textBoxTopForOffset(
    ui.Paragraph paragraph,
    int textOffset,
    int textLength,
  ) {
    if (textLength <= 0) return 0.0;
    final safeOffset = textOffset.clamp(0, textLength).toInt();
    final start = safeOffset >= textLength ? textLength - 1 : safeOffset;
    final boxes = paragraph.getBoxesForRange(start, start + 1);
    if (boxes.isEmpty) return null;
    return boxes.first.top;
  }

  ReaderV2Style _overlayStyle() {
    final specStyle = widget.runtime.state.layoutSpec.style;
    return widget.style.copyWith(
      paddingTop: 0.0,
      paddingLeft: specStyle.paddingLeft,
      paddingRight: specStyle.paddingRight,
    );
  }

  Widget _buildLoading(ReaderV2State state) {
    final Widget child;
    if (state.phase == ReaderV2Phase.error) {
      child = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: widget.textColor.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 10),
            Text(
              _friendlyErrorMessage,
              style: TextStyle(color: widget.textColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: widget.textColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _phaseMessage(state.phase),
            style: TextStyle(
              color: widget.textColor.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    return ColoredBox(
      color: widget.backgroundColor,
      child: ReaderV2PointerTapLayer(
        onTapUp: widget.onContentTapUp,
        child: Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label: state.phase == ReaderV2Phase.error
              ? _friendlyErrorMessage
              : _phaseMessage(state.phase),
          child: Center(child: child),
        ),
      ),
    );
  }

  static const String _friendlyErrorMessage = '閱讀內容暫時無法顯示，請稍後再試';

  String _phaseMessage(ReaderV2Phase phase) {
    return switch (phase) {
      ReaderV2Phase.cold => '正在準備閱讀內容',
      ReaderV2Phase.loading => '正在載入章節',
      ReaderV2Phase.layingOut => '正在整理版面',
      ReaderV2Phase.restoring => '正在恢復閱讀位置',
      ReaderV2Phase.switchingMode => '正在套用閱讀設定',
      ReaderV2Phase.ready => '',
      ReaderV2Phase.error => _friendlyErrorMessage,
    };
  }

  Widget _buildOperationOverlay(ReaderV2State state) {
    if (state.phase == ReaderV2Phase.ready) return const SizedBox.shrink();
    final isError = state.phase == ReaderV2Phase.error;
    final message = isError
        ? _friendlyErrorMessage
        : _phaseMessage(state.phase);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        excludeSemantics: true,
        label: message,
        child: Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            minimum: const EdgeInsets.only(top: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.backgroundColor.withValues(alpha: 0.92),
                border: Border.all(
                  color: widget.textColor.withValues(alpha: 0.16),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isError)
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: widget.textColor.withValues(alpha: 0.72),
                      )
                    else
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final state = widget.runtime.state;
        if (!_initialRestoreCompleted) return _buildLoading(state);
        final controller = _scrollController ??= ScrollController(
          initialScrollOffset: _pendingScrollOffset ?? 0.0,
        );
        final highlight = widget.ttsHighlight;
        final visualContent = NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: HybridScrollView(
            centerKey: _centerKey,
            documentIndex: _documentIndex,
            namespace: _namespace,
            measurementStore: _measurementStore,
            paragraphCache: _paragraphCache,
            epoch: _epoch,
            controller: controller,
            cacheExtent: _viewportSize.height,
            textColor: widget.textColor,
            horizontalPadding: EdgeInsets.only(
              left: state.layoutSpec.style.paddingLeft,
              right: state.layoutSpec.style.paddingRight,
            ),
            physics: _physics,
            onFallbackItemExtent: _handleFallbackItemExtent,
          ),
        );
        final readerStack = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            visualContent,
            if (highlight != null && highlight.isValid)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    return HybridTtsHighlightOverlay(
                      lines: _ttsLineBoxes(highlight),
                      style: _overlayStyle(),
                      textColor: widget.textColor,
                      highlight: highlight,
                    );
                  },
                ),
              ),
            if (state.phase != ReaderV2Phase.ready)
              Positioned.fill(child: _buildOperationOverlay(state)),
          ],
        );
        return ColoredBox(
          color: widget.backgroundColor,
          child: ReaderV2PointerTapLayer(
            onTapUp: widget.onContentTapUp,
            onPointerDownTapPolicy: _holdScrollOnPointerDown,
            child: readerStack,
          ),
        );
      },
    );
  }
}

final class _HybridCommandQueue {
  Future<void>? _tail;
  bool get isBusy => _tail != null;

  Future<bool> enqueue({
    required bool Function() isCurrent,
    required Future<bool> Function() command,
  }) {
    if (!isCurrent()) return Future<bool>.value(false);
    final result = (_tail ?? Future<void>.value()).then((_) async {
      if (!isCurrent()) return false;
      final completed = await command();
      return isCurrent() && completed;
    });
    final drained = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _tail = drained;
    unawaited(
      drained.then((_) {
        if (identical(_tail, drained)) _tail = null;
      }),
    );
    return result;
  }
}
