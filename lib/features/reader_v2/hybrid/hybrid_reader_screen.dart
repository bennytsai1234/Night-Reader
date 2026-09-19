import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_operation_token.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

import 'anchor/anchor_manager.dart';
import 'core/hybrid_contracts.dart';
import 'core/chapter_layout_plan.dart';
import 'core/hybrid_types.dart';
import 'measure/document_index.dart';
import 'measure/measurement_store.dart';
import 'measure/metrics_disk_cache.dart';
import 'overlay/tts_highlight_overlay.dart';
import 'paragraph/paragraph_cache.dart';
import 'progress/hybrid_progress.dart';
import 'pump/budget_governor.dart';
import 'pump/layout_pump.dart';
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
    this.paragraphCacheCapacity = 512,
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
  final int paragraphCacheCapacity;

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
  static const Duration _viewportMotionDuration = Duration(milliseconds: 260);
  static const double _minimumViewportMovement = 0.01;
  static const String _friendlyErrorMessage = '閱讀內容暫時無法顯示，請稍後再試';
  final GlobalKey _centerKey = GlobalKey(debugLabel: 'hybrid-center-sliver');
  final MeasurementStore _measurementStore = MeasurementStore();
  final DocumentIndex _documentIndex = DocumentIndex(
    centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
  );
  final BudgetGovernor _governor = BudgetGovernor();
  final _HybridCommandQueue _commands = _HybridCommandQueue();
  final HybridScrollPhysics _physics = const HybridScrollPhysics();
  late HybridChapterRepository _chapterRepo;
  late final AdmissionController _admission;
  late ParagraphCache _paragraphCache;
  late LayoutPump _pump;
  late LayoutEpoch _epoch;
  late StyleFingerprint _fingerprint;
  late MeasurementNamespace _namespace;
  final Map<int, ChapterLayoutPlan> _layoutPlans = <int, ChapterLayoutPlan>{};
  final Map<int, ChapterBlocks> _blocks = {};
  final Map<int, Future<ChapterBlocks?>> _blocksInFlight = {};
  final Map<BlockKey, ParagraphLease> _viewportLeases = {};
  final Set<({MeasurementNamespace namespace, int chapter, String contentHash})>
  _warmedChapters = {};
  StreamSubscription<ChapterEvent>? _chapterEventsSub;
  StreamSubscription<BlockReady>? _pumpEventsSub;
  ScrollController? _scrollController;
  MetricsDiskCache? _metricsDiskCache;
  Size _viewportSize = Size.zero;
  double? _pendingScrollOffset;
  ReaderV2OperationToken? _demandOwner;
  int _windowCenter = 0;
  int _lastLayoutGeneration = 0;
  int _runtimeLocationRevision = 0;
  ReaderV2Location? _lastReportedLocation;
  bool _initialRestoreCompleted = false;
  bool _dragging = false;
  bool _sawUserScroll = false;
  bool _rebuildQueued = false;
  bool _captureFramePending = false;

  @override
  void initState() {
    super.initState();
    _chapterRepo = HybridChapterRepository(
      repository: widget.runtime.repository,
    );
    _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
    _admission = AdmissionController(documentIndex: _documentIndex);
    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);
    _refreshEpochBinding();
    _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
    _lastReportedLocation = widget.runtime.state.visibleLocation;
    _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
    _registerRuntime();
    _attachController();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreAttachedRuntime();
    });
  }

  void _registerRuntime() {
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
  }

  void _unregisterRuntime(ReaderV2Runtime runtime) {
    runtime.removeListener(_onRuntimeChanged);
    runtime.unregisterVisibleLocationCapture(this);
    runtime.unregisterViewportRestore(this);
  }

  @override
  void didUpdateWidget(covariant HybridReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _unregisterRuntime(oldWidget.runtime);
      _chapterEventsSub?.cancel();
      unawaited(_chapterRepo.dispose());
      _chapterRepo = HybridChapterRepository(
        repository: widget.runtime.repository,
      );
      _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _lastReportedLocation = widget.runtime.state.visibleLocation;
      _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
      _handleEpochRebuild(oldWidget.bookUrl);
      _registerRuntime();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreAttachedRuntime();
      });
    }
    if (oldWidget.viewportController != widget.viewportController) {
      _detachController(oldWidget.viewportController);
      _attachController();
    }
    if (oldWidget.textColor != widget.textColor) _reconcileVisibleWindow();
  }

  @override
  void dispose() {
    _unregisterRuntime(widget.runtime);
    _detachController(widget.viewportController);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _chapterEventsSub?.cancel();
    _pumpEventsSub?.cancel();
    unawaited(
      _writeDiskMetrics(
        _measurementStore.snapshot(_namespace),
        bookUrl: widget.bookUrl,
      ),
    );
    unawaited(_chapterRepo.dispose());
    _releaseViewportLeases();
    _admission.dispose();
    _pump.dispose();
    _paragraphCache.dispose();
    _scrollController?.dispose();
    super.dispose();
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
    );
    _admission.reset(epoch: _epoch, chapterCount: widget.runtime.chapterCount);
    _admission.attach(_pump.completed);
    _pumpEventsSub = _pump.completed.listen((_) {
      // Admission has consumed this result before demand is advanced. Newly
      // measured frontier blocks can therefore supply the same native frame.
      _reconcileVisibleWindow();
    });
  }

  void _handleEpochRebuild(String? previousBookUrl) {
    _runtimeLocationRevision += 1;
    _initialRestoreCompleted = false;
    final oldNamespace = _namespace;
    unawaited(
      _writeDiskMetrics(
        _measurementStore.snapshot(oldNamespace),
        fingerprint: oldNamespace.fingerprint,
        bookUrl: previousBookUrl,
      ),
    );
    _releaseViewportLeases();
    _pumpEventsSub?.cancel();
    _pump.dispose();
    _paragraphCache.dispose();
    _measurementStore.invalidateNamespace(oldNamespace);
    _blocks.clear();
    _layoutPlans.clear();
    _blocksInFlight.clear();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _warmedChapters.clear();
    _documentIndex.reset(centerKey: _documentIndex.centerKey);
    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);
    _refreshEpochBinding();
  }

  Future<bool> _restoreCore(
    ReaderV2Location location, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() || widget.runtime.chapterCount <= 0) return false;
    final binding = _pump;
    final chapter = location.chapterIndex
        .clamp(0, widget.runtime.chapterCount - 1)
        .toInt();
    _windowCenter = chapter;
    _setDemandRange(
      math.max(0, chapter - _chapterRepo.windowRadius),
      math.min(
        widget.runtime.chapterCount - 1,
        chapter + _chapterRepo.windowRadius,
      ),
    );
    binding.clearPendingLayouts();
    binding.onScrollStateChanged(PumpState.rebuilding);
    try {
      final blocks = await _ensureChapterBlocks(chapter, anchor: true);
      if (blocks == null || !isCurrent()) return false;
      final normalized = location.normalized(
        chapterCount: widget.runtime.chapterCount,
        chapterLength: blocks.displayText.length,
      );
      final anchor = HybridAnchor.fromLocation(normalized, blocks);
      _initialRestoreCompleted = false;
      _scheduleRebuild();
      _releaseViewportLeases();
      _documentIndex.reset(centerKey: anchor.blockKey);
      _admission.reset(
        epoch: _epoch,
        chapterCount: widget.runtime.chapterCount,
      );
      // Only a document reset relinquishes the old world. Raw-cache eviction
      // never removes coordinates underneath a mounted viewport.
      for (final oldChapter in _layoutPlans.keys.toList(growable: false)) {
        if (!_chapterRepo.isResident(oldChapter)) _releaseChapter(oldChapter);
      }
      for (final shape in _blocks.values) {
        _admission.registerChapter(shape);
      }
      while (isCurrent()) {
        final revision = _documentIndex.revisionNumber;
        final target = _offsetForAnchor(anchor, blocks);
        _requestWindow(
          target ?? 0,
          (target ?? 0) + math.max(1, _viewportSize.height),
          anchorKey: anchor.blockKey,
        );
        final positionedTarget = _offsetForAnchor(anchor, blocks);
        if (positionedTarget != null &&
            _windowReady(
              positionedTarget,
              positionedTarget + _viewportSize.height,
            ))
          break;
        // Cached exact metrics may advance admission synchronously, without
        // creating a layout task. Re-evaluate that progress before waiting.
        if (_documentIndex.revisionNumber != revision) continue;
        if (!await _waitForMaterialization(isCurrent)) return false;
      }
      if (!isCurrent()) return false;
      final target = _offsetForAnchor(anchor, blocks);
      if (target == null) return false;
      _pendingScrollOffset = target;
      _lastReportedLocation = normalized;
      _initialRestoreCompleted = true;
      _scheduleRebuild();
      // Return only after the native viewport exists and has applied the
      // position. This is a Flutter frame transaction, not a prefetch barrier.
      do {
        await _nextFrame();
        if (!isCurrent()) return false;
      } while (_rebuildQueued || !(_scrollController?.hasClients ?? false));
      final position = _scrollController!.position;
      position.jumpTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
      _pendingScrollOffset = null;
      await _nextFrame();
      if (!isCurrent()) return false;
      _reconcileVisibleWindow();
      _publishProgress();
      return true;
    } finally {
      if (mounted && identical(binding, _pump)) {
        binding.onScrollStateChanged(
          _dragging ? PumpState.dragging : PumpState.idle,
        );
      }
    }
  }

  Future<void> _nextFrame() {
    WidgetsBinding.instance.ensureVisualUpdate();
    return WidgetsBinding.instance.endOfFrame;
  }

  Future<bool> _waitForMaterialization(bool Function() isCurrent) async {
    if (!isCurrent()) return false;
    if (_pump.queueDepth > 0) {
      await _nextFrame();
    } else {
      final loads = _blocksInFlight.values.toList(growable: false);
      if (loads.isEmpty) return false;
      await Future.any(loads);
    }
    return isCurrent();
  }

  bool _windowReady(double top, double bottom) {
    if (_documentIndex.admittedCount == 0) return false;
    if (-_documentIndex.beforeExtent > top + 0.001 && !_isBookStartAdmitted())
      return false;
    if (_documentIndex.afterExtent < bottom - 0.001 && !_isBookEndAdmitted())
      return false;
    return _documentIndex
        .keysInRange(top, bottom)
        .every((key) => _paragraphCache.contains(key, _epoch));
  }

  Future<ChapterBlocks?> _ensureChapterBlocks(
    int chapter, {
    bool anchor = false,
  }) {
    final cached = _blocks[chapter];
    if (cached != null) return Future.value(cached);
    final pending = _blocksInFlight[chapter];
    if (pending != null) return pending;
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
        identical(_blocksInFlight[chapter], task);
    task = () async {
      try {
        final text = await repository.load(chapter);
        if (!current()) return null;
        final plan = _layoutPlans[chapter];
        if (plan != null) {
          final restored = plan.materialize(text);
          if (restored == null) {
            // An actual source edit ends the old document identity. Let the
            // runtime capture/remap/restore it; never overwrite admitted keys.
            await widget.runtime.reloadContentPreservingLocation();
            return null;
          }
          _blocks[chapter] = restored;
          _admission.registerChapter(restored);
          return restored;
        }
        final rough = await preprocessor.process(
          text,
          maxBlockChars: maxBlockChars,
        );
        if (!current()) return null;
        final spec = widget.runtime.state.layoutSpec;
        final blocks = await binding.alignChapterBlocksToVisualLines(
          rough,
          maxBlockChars: maxBlockChars,
          bodyStyle: HybridBlockTextStyle.fromLayoutStyle(
            spec.style,
            justify: AppConfig.readerV2ContentJustify,
          ),
          contentWidth: spec.contentWidth,
          cellWidth: spec.cellWidth,
          textIndent: spec.style.textIndent.clamp(0, 8).toInt(),
          priority: anchor
              ? LayoutTaskPriority.anchor
              : LayoutTaskPriority.prefetch,
        );
        if (blocks == null || !current()) return null;
        _layoutPlans[chapter] = ChapterLayoutPlan(blocks);
        _blocks[chapter] = blocks;
        _admission.registerChapter(blocks);
        // Disk reads may improve later reuse; neither first paint nor command
        // completion waits for this optional cache.
        unawaited(_warmDiskMetricsForChapter(blocks));
        return blocks;
      } on ReaderV2ChapterRepositoryException {
        if (anchor) rethrow;
        return null;
      }
    }();
    _blocksInFlight[chapter] = task;
    unawaited(
      task.then((_) {
        if (identical(_blocksInFlight[chapter], task))
          _blocksInFlight.remove(chapter);
      }),
    );
    return task;
  }

  void _setDemandRange(int first, int last) {
    _pump.setDemandRange(first, last);
    if (_chapterRepo.residentFirst == first &&
        _chapterRepo.residentLast == last)
      return;
    _chapterRepo.setResidentRange(first, last);
  }

  void _requestChapter(int chapter) {
    if (chapter < 0 || chapter >= widget.runtime.chapterCount) return;
    final first = math.min(_chapterRepo.residentFirst ?? chapter, chapter);
    final last = math.max(_chapterRepo.residentLast ?? chapter, chapter);
    _setDemandRange(first, last);
    final binding = _pump;
    unawaited(
      _ensureChapterBlocks(chapter).then((blocks) {
        if (blocks != null && mounted && identical(binding, _pump))
          _reconcileVisibleWindow();
      }),
    );
  }

  void _onChapterEvent(ChapterEvent event) {
    if (!mounted) return;
    switch (event.kind) {
      case ChapterEventKind.loaded:
        if (_chapterRepo.isResident(event.chapterId))
          _requestChapter(event.chapterId);
      case ChapterEventKind.evicted:
        // The active document keeps only text-free boundaries and metrics.
        // Raw text can be released without reinterpreting its geometry.
        if (!_chapterRepo.isResident(event.chapterId)) {
          _blocks.remove(event.chapterId);
          _blocksInFlight.remove(event.chapterId);
        }
        break;
      case ChapterEventKind.invalidated:
        _releaseChapter(event.chapterId);
        _documentIndex.invalidateChapter(event.chapterId);
        _scheduleRebuild();
    }
  }

  void _releaseChapter(int chapter) {
    _blocks.remove(chapter);
    _layoutPlans.remove(chapter);
    _blocksInFlight.remove(chapter);
    _warmedChapters.removeWhere((entry) => entry.chapter == chapter);
    _pump.invalidateChapter(chapter);
    _measurementStore.invalidateChapter(chapter);
    _paragraphCache.invalidateChapter(chapter);
    _admission.invalidateChapter(chapter);
  }

  void _releaseViewportLeases() {
    for (final lease in _viewportLeases.values) {
      lease.release();
    }
    _viewportLeases.clear();
  }

  void _requestWindow(double top, double bottom, {BlockKey? anchorKey}) {
    final needed = <BlockKey>{};
    final groups = <BlockKey>{};
    void request(BlockKey key, {bool anchor = false}) {
      final blocks = _blocks[key.chapterIndex];
      if (blocks == null) {
        _requestChapter(key.chapterIndex);
        return;
      }
      final group = blocks.groupContaining(key);
      if (group.isEmpty || !groups.add(group.first.key)) return;
      for (final block in group) {
        needed.add(block.key);
        _viewportLeases.putIfAbsent(
          block.key,
          () => _paragraphCache.retain(block.key, _epoch),
        );
      }
      final ready = group.every(
        (block) =>
            _measurementStore.get(_namespace, block.key) != null &&
            _paragraphCache.containsFresh(block.key, _epoch, widget.textColor),
      );
      if (!ready) {
        _submitGroupTask(blocks, group, anchor: anchor);
      } else {
        for (final block in group) {
          if (_documentIndex.metricsFor(block.key) == null) {
            _admission.offer(
              BlockReady(
                key: block.key,
                epoch: _epoch,
                metrics: _measurementStore.get(_namespace, block.key)!,
              ),
            );
          }
        }
      }
    }

    if (anchorKey != null) request(anchorKey, anchor: true);
    for (final key
        in _documentIndex.keysInRange(top, bottom).toList(growable: false)) {
      request(key);
    }
    if (_documentIndex.metricsFor(_documentIndex.centerKey) != null) {
      if (_documentIndex.afterExtent < bottom && !_isBookEndAdmitted()) {
        final key = _frontierKey(forward: true);
        if (key != null) request(key);
      }
      if (-_documentIndex.beforeExtent > top && !_isBookStartAdmitted()) {
        final key = _frontierKey(forward: false);
        if (key != null) request(key);
      }
    }
    // New consumers are acquired before old ones release their ownership.
    for (final key in _viewportLeases.keys.toList(growable: false)) {
      if (!needed.contains(key)) _viewportLeases.remove(key)!.release();
    }
  }

  BlockKey? _frontierKey({required bool forward}) {
    final edge =
        (forward
            ? _documentIndex.forwardEdgeKey
            : _documentIndex.backwardEdgeKey) ??
        _documentIndex.centerKey;
    final blocks = _blocks[edge.chapterIndex];
    if (blocks == null) {
      _requestChapter(edge.chapterIndex);
      return null;
    }
    final index = edge.blockIndex + (forward ? 1 : -1);
    if (index >= 0 && index < blocks.blocks.length)
      return blocks.blocks[index].key;
    final chapter = edge.chapterIndex + (forward ? 1 : -1);
    if (chapter < 0 || chapter >= widget.runtime.chapterCount) return null;
    final neighbor = _blocks[chapter];
    if (neighbor == null) {
      _requestChapter(chapter);
      return null;
    }
    return (forward ? neighbor.blocks.first : neighbor.blocks.last).key;
  }

  void _reconcileVisibleWindow() {
    if (!mounted || !_initialRestoreCompleted) return;
    // A runtime operation owns demand until positioning commits. Observations
    // of the previously displayed world cannot overwrite its requested target.
    if (widget.runtime.pendingLocation != null) return;
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    final top = offset - _admission.backwardGuaranteedWindow;
    final bottom = offset + _viewportSize.height + _admission.guaranteedWindow;
    final keys = _documentIndex
        .keysInRange(top, bottom)
        .toList(growable: false);
    var first = math.max(0, _windowCenter - _chapterRepo.windowRadius);
    var last = math.min(
      widget.runtime.chapterCount - 1,
      _windowCenter + _chapterRepo.windowRadius,
    );
    if (keys.isNotEmpty) {
      first = math.min(first, keys.first.chapterIndex);
      last = math.max(last, keys.last.chapterIndex);
    }
    // Keep an in-progress frontier load until it supplies this demand. The
    // outermost chapter may not yet have any admitted geometry.
    if (_documentIndex.afterExtent < bottom && !_isBookEndAdmitted()) {
      last = math.max(
        last,
        math.min(
          widget.runtime.chapterCount - 1,
          (_documentIndex.forwardEdgeKey?.chapterIndex ?? _windowCenter) + 1,
        ),
      );
    }
    if (-_documentIndex.beforeExtent > top && !_isBookStartAdmitted()) {
      first = math.min(
        first,
        math.max(
          0,
          (_documentIndex.backwardEdgeKey?.chapterIndex ?? _windowCenter) - 1,
        ),
      );
    }
    _setDemandRange(first, last);
    _requestWindow(top, bottom);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      _sawUserScroll = true;
      _runtimeLocationRevision += 1;
      _pump.onScrollStateChanged(PumpState.dragging);
    } else if (notification is ScrollUpdateNotification) {
      if (_dragging && notification.dragDetails == null) {
        _dragging = false;
        _pump.onScrollStateChanged(PumpState.ballistic);
      }
      _scheduleMotionCapture();
    } else if (notification is ScrollEndNotification) {
      final wasUser = _sawUserScroll;
      _dragging = false;
      _sawUserScroll = false;
      _pump.onScrollStateChanged(PumpState.idle);
      if (wasUser) unawaited(_handleScrollSettled());
    }
    return false;
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending || !mounted) return;
    _captureFramePending = true;
    final revision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted ||
          !_initialRestoreCompleted ||
          revision != _runtimeLocationRevision)
        return;
      if (widget.runtime.pendingLocation != null) return;
      final location = _captureAndReport(notify: false);
      if (location != null) _windowCenter = location.chapterIndex;
      _reconcileVisibleWindow();
      _publishProgress();
    });
  }

  Future<void> _handleScrollSettled() async {
    if (!mounted ||
        !_initialRestoreCompleted ||
        widget.runtime.pendingLocation != null)
      return;
    final location = _captureAndReport(notify: true);
    if (location != null) _windowCenter = location.chapterIndex;
    _reconcileVisibleWindow();
    _publishProgress();
    await widget.runtime.saveProgress(immediate: true);
  }

  Future<bool> _ensurePageDistanceAvailable({
    required bool forward,
    required double distance,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() ||
        distance <= 0 ||
        !(_scrollController?.hasClients ?? false))
      return false;
    final geometryRevision = _documentIndex.revisionNumber;
    final pixels = _scrollController!.position.pixels;
    final target = pixels + (forward ? distance : -distance);
    final top = math.min(pixels, target);
    final bottom = math.max(pixels, target) + _viewportSize.height;
    while (isCurrent()) {
      _requestWindow(top, bottom);
      if (_windowReady(top, bottom)) {
        if (_documentIndex.revisionNumber != geometryRevision)
          await _nextFrame();
        return isCurrent();
      }
      if (!await _waitForMaterialization(isCurrent)) return false;
    }
    return false;
  }

  Future<List<ParagraphLease>> _ensureRangeLaidOut(
    ChapterBlocks blocks,
    int start,
    int end,
    bool Function() isCurrent,
  ) async {
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    final targets = blocks.blocks
        .where(
          (block) =>
              block.charRange.intersects(range) ||
              (range.isEmpty && block.charRange.containsOffset(range.start)),
        )
        .toList(growable: false);
    // This command owns these drawables until its geometry query and native
    // movement finish. Viewport prefetch may independently release its leases.
    final leases = <ParagraphLease>[];
    final groups = <BlockKey>{};
    try {
      for (final block in targets) {
        leases.add(_paragraphCache.retain(block.key, _epoch));
        if (!_paragraphCache.containsFresh(
          block.key,
          _epoch,
          widget.textColor,
        )) {
          final group = blocks.groupContaining(block.key);
          if (groups.add(group.first.key)) {
            _submitGroupTask(blocks, group, anchor: true);
          }
        }
      }
      while (isCurrent() &&
          !targets.every(
            (block) => _paragraphCache.containsFresh(
              block.key,
              _epoch,
              widget.textColor,
            ),
          )) {
        if (!await _waitForMaterialization(isCurrent)) break;
      }
      return leases;
    } catch (_) {
      for (final lease in leases) {
        lease.release();
      }
      rethrow;
    }
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

    final captured = _captureVisibleLocation();
    final runtimeState = widget.runtime.state;
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
      'lifecycle': runtimeState.lifecycle.name,
      'scrollOffset': finiteOrNull(offset ?? double.nan),
      'viewportHeight': finiteOrNull(viewportHeight),
      'viewportBottom': hasViewport
          ? finiteOrNull(offset + viewportHeight)
          : null,
      'isScrolling': position?.isScrollingNotifier.value ?? false,
      'dragging': _dragging,
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
      'discardedLayoutTasks': _pump.discardedWorkCount,
    };
  }

  void _handleFrameTimings(List<ui.FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    _governor.recordFrameTimings(timings);
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    final state = widget.runtime.state;
    final layoutChanged = _lastLayoutGeneration != state.layoutGeneration;
    if (layoutChanged) {
      _lastLayoutGeneration = state.layoutGeneration;
      _handleEpochRebuild(widget.bookUrl);
    }
    final requested = widget.runtime.pendingLocation;
    final operation = widget.runtime.stateMachine.currentOperation;
    if (requested != null && !identical(operation, _demandOwner)) {
      _demandOwner = operation;
      if (widget.runtime.chapterCount > 0) {
        final chapter = requested.chapterIndex
            .clamp(0, widget.runtime.chapterCount - 1)
            .toInt();
        _windowCenter = chapter;
        _pump.clearPendingLayouts();
        _setDemandRange(
          math.max(0, chapter - _chapterRepo.windowRadius),
          math.min(
            widget.runtime.chapterCount - 1,
            chapter + _chapterRepo.windowRadius,
          ),
        );
      }
    }
    if (state.hasStableWorld && _initialRestoreCompleted) {
      _demandOwner = null;
      _reconcileVisibleWindow();
      _publishProgress();
    }
    _scheduleRebuild();
  }

  void _restoreAttachedRuntime() {
  void _restoreAttachedRuntime() {
    final runtime = widget.runtime;
    if (runtime.state.hasStableWorld) {
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
    _dragging = false;
    _sawUserScroll = false;
    final ok = await _restoreCore(location, isCurrent: current);
    if (!ok || !current()) return false;
    _lastReportedLocation = location;
    _scheduleRebuild();
    return true;
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

  double? _effectiveScrollOffset() {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      return controller.position.pixels;
    }
    return _pendingScrollOffset;
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

  ReaderV2Location? _captureAndReport({required bool notify}) {
    final location = widget.runtime.captureVisibleLocation(
      notifyIfChanged: notify,
    );
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  void _publishProgress() {
    final notifier = widget.progressListenable;
    if (notifier == null) return;

    // Chapter progress is semantic content progress, not materialized layout
    // progress. DocumentIndex intentionally contains only the admitted window.
    final runtimeLocationIsPublished =
        _initialRestoreCompleted &&
        widget.runtime.state.hasStableWorld;
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
    final admitted = _initialRestoreCompleted && !_sawUserScroll;
    return () =>
        admitted &&
        mounted &&
        identical(widget.runtime, runtime) &&
        !runtime.disposed &&
        runtime.state.hasStableWorld &&
        identical(_pump, binding) &&
        revision == _runtimeLocationRevision &&
        identical(runtime.stateMachine.currentOperation, operation) &&
        !_sawUserScroll;
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

  Future<bool> _moveToNextPage() => _enqueueCommand(
    (current) => _movePageNow(forward: true, isCurrent: current),
  );

  Future<bool> _moveToPrevPage() => _enqueueCommand(
    (current) => _movePageNow(forward: false, isCurrent: current),
  );

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
    _reconcileVisibleWindow();
    return isCurrent();
  }

  Future<bool> _animatePageByNow(double delta, bool Function() isCurrent) async {
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
      duration: _viewportMotionDuration,
      curve: Curves.easeOutCubic,
    );
    if (!isCurrent()) return false;
    await _handleScrollSettled();
    return isCurrent();
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
    final moved = await _animatePageByNow(
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
    if (!_chapterRepo.isResident(safeChapter)) {
      final ok = await _restoreCore(
        ReaderV2Location(
          chapterIndex: safeChapter,
          charOffset: math.min(startCharOffset, endCharOffset),
        ),
        isCurrent: isCurrent,
      );
      if (ok && isCurrent()) await _handleScrollSettled();
      return ok && isCurrent();
    }
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
    final leases = await _ensureRangeLaidOut(blocks, start, end, isCurrent);
    try {
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
        duration: _viewportMotionDuration,
        curve: Curves.easeOutCubic,
      );
      if (!isCurrent()) return false;
      await _handleScrollSettled();
      return isCurrent();
    } finally {
      for (final lease in leases) {
        lease.release();
      }
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
      await cache.warmIntoStore(
        bookUrl: bookUrl,
        namespace: namespace,
        chapterLayoutIdentities: {blocks.chapterIndex: blocks.layoutIdentity},
        put: (key, metrics) {
          if (mounted &&
              identical(binding, _pump) &&
              _warmedChapters.contains(warmKey) &&
              _measurementStore.get(namespace, key) == null) {
            _measurementStore.put(namespace, key, metrics);
          }
        },
      );
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
      for (final plan in _layoutPlans.values)
        plan.chapterIndex: plan.layoutIdentity,
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
    if (scrolling && !_dragging) {
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
    final unavailable = state.lifecycle == ReaderV2Lifecycle.unavailable;
    final message = unavailable
        ? _friendlyErrorMessage
        : '正在準備閱讀內容';
    final Widget child;
    if (unavailable) {
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
              message,
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
            message,
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
          label: message,
          child: Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final state = widget.runtime.state;
        if (!_initialRestoreCompleted) return _buildLoading(state);
        final controller = _scrollController ??= ScrollController(
          initialScrollOffset: _pendingScrollOffset ?? 0.0,
          keepScrollOffset: false,
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
          ),
        );
        final readerStack = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            visualContent,
            if (highlight != null && highlight.isValid)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: controller,
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

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) => _enqueueCommand(
    (current) => _ensureCharRangeVisibleNow(
      chapterIndex: chapterIndex,
      startCharOffset: startCharOffset,
      endCharOffset: endCharOffset,
      isCurrent: current,
    ),
  );
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
