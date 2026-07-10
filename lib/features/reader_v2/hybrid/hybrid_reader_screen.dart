import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui show FrameTiming, Paragraph;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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

/// 方案 B 混合架構的閱讀主面（W3 整合層）。
///
/// 取代 `EngineReaderV2Screen`：對上維持 D5 的三個契約面——
/// 1. `ReaderV2ViewportController` 七閉包 attach/detach（前六個經 FIFO 佇列，
///    settleScroll 直達）；
/// 2. runtime 的 capture / restore 註冊（owner 語意照舊）；
/// 3. settle 點（拖曳結束、fling 停止、跳章完成、epoch 重建完成）一律
///    capture + saveProgress。
/// 對下組裝 hybrid 各模組：text→measure→paragraph/pump→view，錨點換算
/// 全部經 [HybridAnchor]（I6），epoch 對齊 runtime 的 layoutGeneration（D9）。
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

  /// D6：章序 + 章內百分比的對外通道（頁面組裝層讀取顯示）。
  final ValueNotifier<HybridProgressSnapshot?>? progressListenable;

  /// D10 磁碟 metrics 的檔名 key；null 時停用磁碟快取。
  final String? bookUrl;

  /// 測試可注入 `TextPreprocessor(useIsolate: false)` 避免真 isolate。
  final HybridTextPreprocessor preprocessor;
  final bool enableDiskMetrics;

  @override
  State<HybridReaderScreen> createState() => _HybridReaderScreenState();
}

class _HybridReaderScreenState extends State<HybridReaderScreen>
    with WidgetsBindingObserver {
  /// 動作中 capture 觸發 runtime notify 的最小間隔（沿用舊引擎節流值）。
  static const Duration _motionNotifyInterval = Duration(milliseconds: 200);
  static const Duration _ensureAnimateDuration = Duration(milliseconds: 260);

  final GlobalKey _centerKey = GlobalKey(debugLabel: 'hybrid-center-sliver');
  final MeasurementStore _measurementStore = MeasurementStore();
  final DocumentIndex _documentIndex = DocumentIndex(
    centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
  );
  final AnchorManager _anchorManager = AnchorManager();
  final BudgetGovernor _governor = BudgetGovernor();
  final HybridTelemetry _telemetry = HybridTelemetry();
  final _HybridCommandQueue _commands = _HybridCommandQueue();

  late HybridChapterRepository _chapterRepo;
  late final AdmissionController _admission;
  late ParagraphCache _paragraphCache;
  late LayoutPump _pump;
  late LayoutEpoch _epoch;
  late StyleFingerprint _fingerprint;
  late MeasurementNamespace _namespace;

  final Map<int, ChapterBlocks> _blocks = <int, ChapterBlocks>{};
  final Map<int, Future<ChapterBlocks?>> _blocksInFlight =
      <int, Future<ChapterBlocks?>>{};
  final Set<BlockKey> _enqueued = <BlockKey>{};
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
  ReaderV2Location? _lastSyncedLocation;
  DateTime? _lastMotionNotifyAt;
  bool _initialRestoreCompleted = false;
  bool _capturing = false;
  bool _dragging = false;
  bool _sawUserScroll = false;
  bool _rebuildQueued = false;
  bool _pumpFramePending = false;
  bool _captureFramePending = false;

  @override
  void initState() {
    super.initState();
    _chapterRepo = HybridChapterRepository(
      repository: widget.runtime.repository,
    );
    _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
    _admission = AdmissionController(documentIndex: _documentIndex)
      ..addListener(_scheduleRebuild);
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
      // 冷開機由 runtime.openBook() 經 restore 鏈進來；熱掛載（runtime 已
      // ready）沒有人會再叫 restore，這裡自己補一次同步。
      if (widget.runtime.state.phase == ReaderV2Phase.ready) {
        unawaited(_syncToRuntimeLocation(force: true));
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
      _lastSyncedLocation = null;
      _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
      _restoreTicket += 1;
      _initialRestoreCompleted = false;
      _handleEpochRebuild();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_syncToRuntimeLocation(force: true));
      });
    }
    if (oldWidget.viewportController != widget.viewportController) {
      _detachController(oldWidget.viewportController);
      _attachController();
    }
  }

  @override
  void dispose() {
    widget.runtime.unregisterHybridViewport(this);
    widget.runtime.removeListener(_onRuntimeChanged);
    widget.runtime.unregisterVisibleLocationCapture(this);
    widget.runtime.unregisterViewportRestore(this);
    _detachController(widget.viewportController);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _chapterEventsSub?.cancel();
    unawaited(_writeDiskMetrics(_measurementStore.snapshot(_namespace)));
    unawaited(_chapterRepo.dispose());
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
      unawaited(_writeDiskMetrics(_measurementStore.snapshot(_namespace)));
    }
  }

  void _handleFrameTimings(List<ui.FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    widget.runtime.recordFrameTimings(timings);
    _governor.recordFrameTimings(timings);
    _telemetry.recordFrameTimings(timings);
  }

  // ---- epoch / namespace（D9：epoch 對齊 layoutGeneration） ----

  void _refreshEpochBinding() {
    _epoch = LayoutEpoch(widget.runtime.state.layoutGeneration);
    _fingerprint = StyleFingerprint.fromLayoutSpec(
      widget.runtime.state.layoutSpec,
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
  }

  void _handleEpochRebuild() {
    _enqueued.clear();
    _blocks.clear();
    _blocksInFlight.clear();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _pump.dispose();
    final oldCache = _paragraphCache;
    _paragraphCache = ParagraphCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCache.dispose());
    _refreshEpochBinding();
  }

  // ---- runtime 事件 ----

  void _onRuntimeChanged() {
    if (!mounted) return;
    final state = widget.runtime.state;
    final layoutChanged = _lastLayoutGeneration != state.layoutGeneration;
    if (layoutChanged) {
      _lastLayoutGeneration = state.layoutGeneration;
      _handleEpochRebuild();
    }
    if (_capturing) {
      _scheduleRebuild();
      return;
    }
    final locationChanged = state.visibleLocation != _lastReportedLocation;
    final needsViewportSync =
        locationChanged ||
        (layoutChanged && !widget.runtime.hybridViewportActive);
    if (needsViewportSync) {
      _runtimeLocationRevision += 1;
      final revision = _runtimeLocationRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || revision != _runtimeLocationRevision) return;
        unawaited(_syncToRuntimeLocation(force: true));
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    _scheduleRebuild();
  }

  Future<void> _syncToRuntimeLocation({bool force = false}) async {
    final runtime = widget.runtime;
    if (runtime.chapterCount <= 0) return;
    final location = runtime.state.visibleLocation.normalized(
      chapterCount: runtime.chapterCount,
    );
    if (!force && _initialRestoreCompleted && _lastSyncedLocation == location) {
      return;
    }
    final generation = runtime.state.layoutGeneration;
    bool still() =>
        mounted &&
        runtime.state.layoutGeneration == generation &&
        runtime.state.visibleLocation.normalized(
              chapterCount: runtime.chapterCount,
            ) ==
            location;
    final ok = await _restoreCore(location, isCurrent: still);
    if (!ok || !still()) return;
    _lastSyncedLocation = location;
    _lastReportedLocation = location;
    _scheduleRebuild();
  }

  // ---- capture / restore（D5 條款 2；I6：一切重建以 HybridAnchor 為基準） ----

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
    final hit =
        _documentIndex.hitTest(worldY) ?? _documentIndex.hitTest(offset);
    if (hit == null) return null;
    final blocks = _blocks[hit.key.chapterIndex];
    if (blocks == null || hit.key.blockIndex >= blocks.blocks.length) {
      return null;
    }
    final block = blocks.blocks[hit.key.blockIndex];
    var lineTop = 0.0;
    var charOffset = block.charRange.start;
    final paragraph = _paragraphCache.acquire(hit.key, _epoch);
    if (paragraph != null) {
      final line = _lineAt(paragraph, hit.offsetInBlock);
      if (line != null) {
        lineTop = line.top;
        final indent = _indentCharsFor(block);
        final position = paragraph.getPositionForOffset(
          Offset(0, line.top + 0.1),
        );
        charOffset =
            (block.charRange.start + math.max(0, position.offset - indent))
                .clamp(block.charRange.start, block.charRange.end)
                .toInt();
      }
    }
    final visual =
        (worldY - (hit.blockTop + lineTop))
            .clamp(
              ReaderV2Location.minVisualOffsetPx,
              ReaderV2Location.maxVisualOffsetPx,
            )
            .toDouble();
    return ReaderV2Location(
      chapterIndex: hit.key.chapterIndex,
      charOffset: charOffset,
      visualOffsetPx: visual,
    ).normalized(
      chapterCount: widget.runtime.chapterCount,
      chapterLength: blocks.displayText.length,
    );
  }

  Future<bool> _restoreToLocation(ReaderV2Location location) async {
    if (!mounted || widget.runtime.chapterCount <= 0) return false;
    // 拖曳中拒絕 restore——settle-restore 硬拉回目標會跟手勢打架。
    if (!_anchorManager.beginRestore(isDragging: _dragging)) return false;
    try {
      final ok = await _restoreCore(location);
      if (!ok || !mounted) return false;
      _scheduleRebuild();
      final captured = _captureVisibleLocation();
      if (captured == null) return false;
      _lastSyncedLocation = location;
      _lastReportedLocation = location;
      return true;
    } finally {
      _anchorManager.completeRestore();
    }
  }

  Future<bool> _restoreCore(
    ReaderV2Location location, {
    bool Function()? isCurrent,
  }) async {
    final runtime = widget.runtime;
    if (runtime.chapterCount <= 0) return false;
    final ticket = ++_restoreTicket;
    bool still() =>
        mounted && ticket == _restoreTicket && (isCurrent?.call() ?? true);
    final chapterIndex =
        location.chapterIndex.clamp(0, runtime.chapterCount - 1).toInt();
    _pump.onScrollStateChanged(PumpState.rebuilding);
    try {
      final blocks = await _ensureChapterBlocks(chapterIndex);
      if (blocks == null || !still()) return false;
      final normalized = location.normalized(
        chapterCount: runtime.chapterCount,
        chapterLength: blocks.displayText.length,
      );
      final anchor = _anchorManager.captureFromLocation(normalized, blocks);
      // 重定中心：admitted 度量由 store 回填（經 _ensureWindowTasks 的
      // 連續段 direct-admit），上側走 center 負座標生長（I3）。
      _documentIndex.reset(centerKey: anchor.blockKey);
      _admission.reset(epoch: _epoch, chapterCount: runtime.chapterCount);
      _admission.attach(_pump.completed);
      for (final loadedBlocks in _blocks.values) {
        _admission.registerChapter(loadedBlocks);
      }
      _enqueued.clear();
      _windowCenter = chapterIndex;
      _chapterRepo.setPrefetchCenter(chapterIndex);
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
      _initialRestoreCompleted = true;
      _scheduleRebuild();
      _schedulePump();
      return true;
    } finally {
      if (ticket == _restoreTicket) {
        _pump.onScrollStateChanged(
          _dragging ? PumpState.dragging : PumpState.idle,
        );
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
      final requiredTop = target - _admission.backwardGuaranteedWindow;
      final requiredBottom = target + viewport + _admission.guaranteedWindow;
      final hasTop = -_documentIndex.beforeExtent <= requiredTop;
      final hasBottom = _documentIndex.afterExtent >= requiredBottom;
      return (hasTop || _isBookStartAdmitted()) &&
          (hasBottom || _isBookEndAdmitted());
    }

    var guard = 0;
    while (guard++ < 600) {
      if (!stillCurrent()) return false;
      if (initialWindowReady()) return true;
      final completed = await _pump.pumpPending();
      if (completed != 0) continue;
      final pendingLoads = _blocksInFlight.values.toList(growable: false);
      if (pendingLoads.isEmpty) return anchorReady();
      await Future.wait(pendingLoads);
      if (!stillCurrent()) return false;
      _ensureWindowTasks(anchorKey: anchor.blockKey);
    }
    return anchorReady();
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
    final top = _documentIndex.topOf(anchor.blockKey);
    if (top == null) return null;
    final lineTop =
        _lineTopForChar(blocks, anchor.blockKey, anchor.charOffsetInChapter) ??
        0.0;
    final anchorLine = AnchorManager.anchorOffsetInViewport(
      _viewportSize.height,
    );
    return top + lineTop - anchorLine + anchor.visualOffsetPx;
  }

  double? _lineTopForChar(
    ChapterBlocks blocks,
    BlockKey key,
    int charOffsetInChapter,
  ) {
    if (key.blockIndex >= blocks.blocks.length) return null;
    final block = blocks.blocks[key.blockIndex];
    final paragraph = _paragraphCache.acquire(key, _epoch);
    if (paragraph == null) return 0.0;
    final indent = _indentCharsFor(block);
    final local =
        (charOffsetInChapter - block.charRange.start)
            .clamp(0, block.text.length)
            .toInt() +
        indent;
    final boxes = paragraph.getBoxesForRange(
      local,
      math.min(local + 1, block.text.length + indent),
    );
    if (boxes.isEmpty) return 0.0;
    return boxes.first.top;
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

  // ---- 章節文字 → block 管線 ----

  Future<ChapterBlocks?> _ensureChapterBlocks(int chapterIndex) {
    final cached = _blocks[chapterIndex];
    if (cached != null) return Future<ChapterBlocks?>.value(cached);
    final inFlight = _blocksInFlight[chapterIndex];
    if (inFlight != null) return inFlight;
    final generation = _lastLayoutGeneration;
    late final Future<ChapterBlocks?> task;
    task = () async {
      try {
        final text = await _chapterRepo.load(chapterIndex);
        final blocks = await widget.preprocessor.process(
          text,
          maxBlockChars: _pump.maxCharsForBudget(
            _governor.ballisticSliceBudget,
          ),
        );
        if (!mounted || _lastLayoutGeneration != generation) return null;
        await _warmDiskMetricsForChapter(blocks);
        if (!mounted || _lastLayoutGeneration != generation) return null;
        _blocks[chapterIndex] = blocks;
        _admission.registerChapter(blocks);
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
        if ((event.chapterId - _windowCenter).abs() <=
            _chapterRepo.windowRadius) {
          unawaited(
            _ensureChapterBlocks(event.chapterId).then((blocks) {
              if (blocks == null || !mounted) return;
              _enqueueChapterTasks(blocks);
              _schedulePump();
              _scheduleRebuild();
            }),
          );
        }
      case ChapterEventKind.evicted:
        _blocks.remove(event.chapterId);
      case ChapterEventKind.invalidated:
        _blocks.remove(event.chapterId);
        _measurementStore.invalidateChapter(event.chapterId);
        _paragraphCache.invalidateChapter(event.chapterId);
        _enqueued.removeWhere((key) => key.chapterIndex == event.chapterId);
    }
  }

  void _shiftWindow(int chapterIndex) {
    if (chapterIndex == _windowCenter) return;
    _windowCenter = chapterIndex;
    _chapterRepo.setPrefetchCenter(chapterIndex);
    _ensureWindowTasks();
    _schedulePump();
  }

  // ---- 排版任務投放（admit 保持每側自 center 起連續，I2/I3 前提） ----

  void _ensureWindowTasks({BlockKey? anchorKey}) {
    final admittedBefore = _documentIndex.admittedCount;
    for (final delta in const <int>[0, 1, -1, 2, -2]) {
      final chapter = _windowCenter + delta;
      if (chapter < 0 || chapter >= widget.runtime.chapterCount) continue;
      final blocks = _blocks[chapter];
      if (blocks == null) {
        unawaited(
          _ensureChapterBlocks(chapter).then((loaded) {
            if (loaded == null || !mounted) return;
            if ((loaded.chapterIndex - _windowCenter).abs() > 2) return;
            _enqueueChapterTasks(loaded);
            _schedulePump();
            _scheduleRebuild();
          }),
        );
        continue;
      }
      _enqueueChapterTasks(blocks, anchorKey: delta == 0 ? anchorKey : null);
    }
    if (_documentIndex.admittedCount != admittedBefore) _scheduleRebuild();
  }

  void _enqueueChapterTasks(ChapterBlocks blocks, {BlockKey? anchorKey}) {
    final list = blocks.blocks;
    if (list.isEmpty) return;
    final centerKey = _documentIndex.centerKey;
    List<ChapterBlock> forward;
    List<ChapterBlock> backward;
    if (blocks.chapterIndex == centerKey.chapterIndex) {
      final center = centerKey.blockIndex.clamp(0, list.length - 1).toInt();
      forward = list.sublist(center);
      backward = list.sublist(0, center).reversed.toList(growable: false);
    } else if (blocks.chapterIndex > centerKey.chapterIndex) {
      forward = list;
      backward = const <ChapterBlock>[];
    } else {
      forward = const <ChapterBlock>[];
      backward = list.reversed.toList(growable: false);
    }
    var forwardBlocked = false;
    var backwardBlocked = false;
    final rounds = math.max(forward.length, backward.length);
    for (var i = 0; i < rounds; i += 1) {
      if (i < forward.length) {
        forwardBlocked = _admitOrSubmit(
          blocks,
          forward[i],
          blocked: forwardBlocked,
          anchor: anchorKey != null && forward[i].key == anchorKey,
        );
      }
      if (i < backward.length) {
        backwardBlocked = _admitOrSubmit(
          blocks,
          backward[i],
          blocked: backwardBlocked,
          anchor: anchorKey != null && backward[i].key == anchorKey,
        );
      }
    }
  }

  /// 就緒（有 metrics + paragraph）且同側尚未斷檔 → 直接 admit；
  /// 否則送 pump。回傳「此側是否已斷檔」（斷檔後不得再 direct-admit，
  /// 否則 DocumentIndex 會出現中間洞，補齊時可見內容會位移，違反 I3）。
  bool _admitOrSubmit(
    ChapterBlocks blocks,
    ChapterBlock block, {
    required bool blocked,
    bool anchor = false,
  }) {
    final key = block.key;
    final metrics = _measurementStore.get(_namespace, key);
    final hasParagraph = _paragraphCache.contains(key, _epoch);
    final admitted = _documentIndex.metricsFor(key) != null;
    if (admitted) {
      if (!hasParagraph) _submitTask(blocks, block, anchor: anchor);
      return blocked;
    }
    if (metrics != null && hasParagraph && !blocked) {
      _admission.offer(BlockReady(key: key, epoch: _epoch, metrics: metrics));
      return blocked;
    }
    _submitTask(blocks, block, anchor: anchor);
    return true;
  }

  void _submitTask(
    ChapterBlocks blocks,
    ChapterBlock block, {
    bool anchor = false,
  }) {
    final key = block.key;
    if (!_enqueued.add(key)) return;
    final spec = widget.runtime.state.layoutSpec;
    _pump.submit(
      LayoutTask(
        block: block,
        epoch: _epoch,
        fingerprint: _fingerprint,
        textStyle: HybridBlockTextStyle.fromLayoutStyle(
          spec.style,
          isTitle: block.isTitle,
          justify: !block.isTitle,
        ),
        contentWidth: spec.contentWidth,
        priority: _priorityFor(key, anchor: anchor),
        direction:
            key < _documentIndex.centerKey
                ? HybridScrollDirection.backward
                : HybridScrollDirection.forward,
        indentChars: _indentCharsFor(block),
        trailingSpacing: _trailingSpacingFor(blocks, block),
      ),
    );
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

  /// 沿用舊引擎間距規則：標題後 = paragraphSpacing*8px（硬編碼特例）；
  /// 段落後 = fontSize×行高×paragraphSpacing；超長段切塊之間零間距（D2）。
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

  // ---- pump 驅動 ----

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
    // 已排定的 post-frame pump 可能剛好撞上使用者開始拖曳；
    // I4 在這裡硬停，待 ScrollEnd 再恢復，不能讓 debug assert 擊穿手勢。
    if (_dragging) return;
    final completed = await _pump.pumpPending();
    if (!mounted) return;
    if (_pump.queueDepth > 0) {
      _schedulePump();
    } else {
      // 佇列見底 → 允許之後的視窗掃描重新投放（處理段落被 LRU 逐出的重排）。
      _enqueued.clear();
      _updateLeadTelemetry();
    }
    if (completed > 0) _scheduleRebuild();
  }

  void _updateLeadTelemetry() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    _admission.updateLead(
      viewportTop: offset,
      viewportBottom: offset + _viewportSize.height,
    );
    _governor.updateLeadDeficit(_admission.hasLeadDeficit);
    _telemetry.updateRuntimeStats(
      pumpQueueDepth: _pump.queueDepth,
      forwardLeadPx: _admission.latestForwardLead,
      backwardLeadPx: _admission.latestBackwardLead,
    );
  }

  // ---- 滾動事件 / settle（D5 條款 3） ----

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _dragging = true;
        _sawUserScroll = true;
        _setPumpState(PumpState.dragging);
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_dragging && notification.dragDetails == null) {
        _dragging = false;
        _setPumpState(PumpState.ballistic);
        _schedulePump();
      }
      _scheduleMotionCapture();
    } else if (notification is ScrollEndNotification) {
      final wasUser = _sawUserScroll;
      _dragging = false;
      _sawUserScroll = false;
      _setPumpState(PumpState.idle);
      _schedulePump();
      if (wasUser) unawaited(_handleScrollSettled());
    }
    return false;
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending || !mounted) return;
    _captureFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted) return;
      final location = _captureAndReport(notify: _shouldNotifyForMotion());
      final offset = _effectiveScrollOffset();
      if (offset != null) {
        _admission.updateViewport(
          visibleTop: offset,
          visibleBottom: offset + _viewportSize.height,
          cacheExtent: _viewportSize.height,
        );
      }
      _updateParagraphPins();
      _publishProgress();
      _updateLeadTelemetry();
      if (location != null && location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      }
    });
  }

  bool _shouldNotifyForMotion() {
    final now = DateTime.now();
    final last = _lastMotionNotifyAt;
    if (last == null || now.difference(last) >= _motionNotifyInterval) {
      _lastMotionNotifyAt = now;
      return true;
    }
    return false;
  }

  ReaderV2Location? _captureAndReport({required bool notify}) {
    _capturing = true;
    try {
      final location = widget.runtime.captureVisibleLocation(
        notifyIfChanged: notify,
      );
      if (location != null) _lastReportedLocation = location;
      return location;
    } finally {
      _capturing = false;
    }
  }

  Future<void> _handleScrollSettled() async {
    if (!mounted || _dragging) return;
    final location = _captureAndReport(notify: true);
    if (location != null) {
      // settle 即刻落盤：背景 flush 靠不住（app 可能被系統回收）。
      final saved = await widget.runtime.saveProgress(
        location: location,
        immediate: true,
      );
      if (saved != null) _lastReportedLocation = saved;
      if (mounted && location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      }
    }
    if (!mounted) return;
    _publishProgress();
    _updateLeadTelemetry();
    _ensureWindowTasks();
    _schedulePump();
  }

  void _publishProgress() {
    final notifier = widget.progressListenable;
    if (notifier == null) return;
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    final worldY =
        offset + AnchorManager.anchorOffsetInViewport(_viewportSize.height);
    notifier.value = HybridProgress(
      documentIndex: _documentIndex,
      chapterCount: widget.runtime.chapterCount,
    ).progressForOffset(worldY);
  }

  // ---- D5 條款 1：七閉包 attach/detach（前六個經 FIFO 佇列） ----

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

  Future<bool> _enqueueCommand(Future<bool> Function() command) {
    return _commands.enqueue(isMounted: () => mounted, command: command);
  }

  Future<bool> _scrollBy(double delta) =>
      _enqueueCommand(() => _scrollByNow(delta));

  Future<bool> _continuousScrollBy(double delta) =>
      _enqueueCommand(() => _continuousScrollByNow(delta));

  Future<bool> _animateBy(double delta) =>
      _enqueueCommand(() => _animateByNow(delta));

  Future<bool> _moveToNextPage() =>
      _enqueueCommand(() => _movePageNow(forward: true));

  Future<bool> _moveToPrevPage() =>
      _enqueueCommand(() => _movePageNow(forward: false));

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) {
    return _enqueueCommand(
      () => _ensureCharRangeVisibleNow(
        chapterIndex: chapterIndex,
        startCharOffset: startCharOffset,
        endCharOffset: endCharOffset,
      ),
    );
  }

  /// settleScroll 不經佇列（D5）：先停住殘餘慣性再走 settle。
  Future<void> _settleScroll() async {
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
    final target =
        (before + delta).clamp(position.minScrollExtent, max).toDouble();
    if ((target - before).abs() < 0.01) return false;
    position.jumpTo(target);
    return true;
  }

  Future<bool> _scrollByNow(double delta) async {
    if (!mounted || !_jumpBy(delta)) return false;
    await _handleScrollSettled();
    return mounted;
  }

  Future<bool> _continuousScrollByNow(double delta) async {
    if (!mounted || !_jumpBy(delta)) return false;
    _scheduleMotionCapture();
    _schedulePump();
    return mounted;
  }

  Future<bool> _animateByNow(double delta) async {
    final controller = _scrollController;
    if (!mounted ||
        controller == null ||
        !controller.hasClients ||
        delta == 0) {
      return false;
    }
    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target =
        (before + delta).clamp(position.minScrollExtent, max).toDouble();
    if ((target - before).abs() < 0.01) return false;
    await position.animateTo(
      target,
      duration: _ensureAnimateDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return false;
    await _handleScrollSettled();
    return mounted;
  }

  Future<bool> _movePageNow({required bool forward}) {
    final height = _viewportSize.height;
    if (height <= 0) return Future<bool>.value(false);
    final style = widget.runtime.state.layoutSpec.style;
    final overlap = math.max(24.0, style.fontSize * style.effectiveLineHeight);
    final magnitude = math.max(height * 0.5, height - overlap - 8.0);
    return _animateByNow(forward ? magnitude : -magnitude);
  }

  // ---- D5 條款 6：ensureCharRangeVisible ----

  Future<bool> _ensureCharRangeVisibleNow({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) async {
    final runtime = widget.runtime;
    if (!mounted || runtime.chapterCount <= 0) return false;
    final safeChapter = chapterIndex.clamp(0, runtime.chapterCount - 1).toInt();
    final blocks = await _ensureChapterBlocks(safeChapter);
    if (blocks == null || !mounted) return false;
    final start = math.min(startCharOffset, endCharOffset);
    final end = math.max(startCharOffset, endCharOffset);
    final anchorKey = blocks.blockForCharOffset(start).key;
    if (_documentIndex.topOf(anchorKey) == null) {
      // 目標不在目前 world（跨窗跳讀）：以 restore 流程重定中心過去。
      final ok = await _restoreCore(
        ReaderV2Location(chapterIndex: safeChapter, charOffset: start),
      );
      if (ok && mounted) await _handleScrollSettled();
      return ok && mounted;
    }
    await _ensureRangeLaidOut(blocks, start, end);
    if (!mounted) return false;
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
    final target =
        minTarget <= maxTarget
            ? preferredTarget.clamp(minTarget, maxTarget).toDouble()
            : minTarget;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final position = controller.position;
    final bounded =
        target
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
    if (!mounted) return false;
    await _handleScrollSettled();
    return mounted;
  }

  Future<void> _ensureRangeLaidOut(
    ChapterBlocks blocks,
    int start,
    int end,
  ) async {
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    final targets = blocks.blocks
        .where((block) {
          return block.charRange.intersects(range) ||
              (range.isEmpty && block.charRange.containsOffset(range.start));
        })
        .toList(growable: false);
    for (final block in targets) {
      if (_paragraphCache.contains(block.key, _epoch) &&
          _measurementStore.get(_namespace, block.key) != null) {
        continue;
      }
      _submitTask(blocks, block, anchor: true);
    }
    var guard = 0;
    bool allReady() => targets.every(
      (block) =>
          _paragraphCache.contains(block.key, _epoch) &&
          _measurementStore.get(_namespace, block.key) != null,
    );
    while (guard++ < 100 && !allReady()) {
      final completed = await _pump.pumpPending();
      if (completed == 0) break;
    }
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
      final paragraph = _paragraphCache.acquire(block.key, _epoch);
      double localTop = 0;
      double localBottom =
          _documentIndex.metricsFor(block.key)?.height ??
          paragraph?.height ??
          0;
      if (paragraph != null) {
        final indent = _indentCharsFor(block);
        final localStart =
            math.max(range.start, block.charRange.start) -
            block.charRange.start +
            indent;
        final localEnd =
            math.min(range.end, block.charRange.end) -
            block.charRange.start +
            indent;
        if (localEnd > localStart) {
          final boxes = paragraph.getBoxesForRange(localStart, localEnd);
          if (boxes.isNotEmpty) {
            localTop = boxes.first.top;
            localBottom =
                boxes.map((box) => box.bottom).reduce(math.max).toDouble();
          }
        }
      }
      final rangeTop = blockTop + localTop;
      final rangeBottom = blockTop + localBottom;
      top = top == null ? rangeTop : math.min(top, rangeTop);
      bottom = bottom == null ? rangeBottom : math.max(bottom, rangeBottom);
    }
    if (top == null || bottom == null) return null;
    return Rect.fromLTRB(0, top, 0, bottom);
  }

  // ---- D5 條款 5：TTS 高亮 ----

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
    for (final block in blocks.blocks) {
      if (!block.charRange.intersects(range)) continue;
      final top = _documentIndex.topOf(block.key);
      if (top == null) continue;
      final paragraph = _paragraphCache.acquire(block.key, _epoch);
      if (paragraph == null) continue;
      final indent = _indentCharsFor(block);
      final localStart =
          math.max(range.start, block.charRange.start) -
          block.charRange.start +
          indent;
      final localEnd =
          math.min(range.end, block.charRange.end) -
          block.charRange.start +
          indent;
      if (localEnd <= localStart) continue;
      final clipped = HybridTextRange(
        math.max(range.start, block.charRange.start),
        math.min(range.end, block.charRange.end),
      );
      for (final box in paragraph.getBoxesForRange(localStart, localEnd)) {
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

  // ---- D10：磁碟 metrics ----

  Future<void> _warmDiskMetricsForChapter(ChapterBlocks blocks) async {
    if (!widget.enableDiskMetrics || widget.bookUrl == null) return;
    final warmKey = (
      namespace: _namespace,
      chapter: blocks.chapterIndex,
      contentHash: blocks.contentHash,
    );
    if (!_warmedChapters.add(warmKey)) return;
    try {
      final cache = await _obtainDiskCache();
      final namespace = _namespace;
      final count = await cache.warmIntoStore(
        bookUrl: widget.bookUrl!,
        namespace: namespace,
        chapterContentHashes: <int, String>{
          blocks.chapterIndex: blocks.contentHash,
        },
        put: (key, metrics) {
          if (namespace == _namespace) {
            _measurementStore.put(namespace, key, metrics);
          }
        },
      );
      _telemetry.recordDiskMetricsHit(count > 0);
    } catch (_) {
      // 測試環境無 path_provider、或 IO 失敗：磁碟快取屬最佳努力，靜默略過。
    }
  }

  Future<void> _writeDiskMetrics(Map<BlockKey, BlockMetrics> snapshot) async {
    if (!widget.enableDiskMetrics ||
        widget.bookUrl == null ||
        snapshot.isEmpty) {
      return;
    }
    try {
      final cache = await _obtainDiskCache();
      await cache.write(
        bookUrl: widget.bookUrl!,
        fingerprint: _fingerprint,
        metrics: snapshot,
        chapterContentHashes: <int, String>{
          for (final blocks in _blocks.values)
            blocks.chapterIndex: blocks.contentHash,
        },
      );
    } catch (_) {
      // 同上：最佳努力。
    }
  }

  Future<MetricsDiskCache> _obtainDiskCache() async {
    final existing = _metricsDiskCache;
    if (existing != null) return existing;
    final directory = await getApplicationSupportDirectory();
    return _metricsDiskCache = MetricsDiskCache(baseDirectory: directory);
  }

  // ---- 建構 ----

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
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
      return true; // 動畫中的點擊只用來停住，不觸發分區動作。
    }
    return false;
  }

  ({double top, double bottom})? _lineAt(ui.Paragraph paragraph, double dy) {
    ({double top, double bottom})? last;
    for (final line in paragraph.computeLineMetrics()) {
      final lineTop = line.baseline - line.ascent;
      final lineBottom = lineTop + line.height;
      last = (top: lineTop, bottom: lineBottom);
      if (dy < lineBottom) return last;
    }
    return last;
  }

  ReaderV2Style _overlayStyle() => widget.style.copyWith(paddingTop: 0.0);

  void _updateParagraphPins() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    final top = offset - _admission.backwardGuaranteedWindow;
    final bottom = offset + _viewportSize.height + _admission.guaranteedWindow;
    final keys = <BlockKey>[];
    for (final key in _documentIndex.keys) {
      final blockTop = _documentIndex.topOf(key);
      final blockBottom = _documentIndex.bottomOf(key);
      if (blockTop == null || blockBottom == null) continue;
      if (blockBottom > top && blockTop < bottom) keys.add(key);
    }
    _paragraphCache
      ..unpinAll()
      ..pinKeys(keys, _epoch);
  }

  Widget _buildLoading(ReaderV2State state) {
    final Widget child;
    if (state.phase == ReaderV2Phase.error) {
      child = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          state.errorMessage ?? '章節載入失敗',
          style: TextStyle(color: widget.textColor, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      child = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: widget.textColor.withValues(alpha: 0.6),
        ),
      );
    }
    return ColoredBox(
      color: widget.backgroundColor,
      child: ReaderV2PointerTapLayer(
        onTapUp: widget.onContentTapUp,
        child: Center(child: child),
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
        final controller =
            _scrollController ??= ScrollController(
              initialScrollOffset: _pendingScrollOffset ?? 0.0,
            );
        _updateParagraphPins();
        final highlight = widget.ttsHighlight;
        return ColoredBox(
          color: widget.backgroundColor,
          child: ReaderV2PointerTapLayer(
            onTapUp: widget.onContentTapUp,
            onPointerDownTapPolicy: _holdScrollOnPointerDown,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                NotificationListener<ScrollNotification>(
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
                      left: widget.style.paddingLeft,
                      right: widget.style.paddingRight,
                    ),
                    physics: HybridScrollPhysics(
                      applyForwardFriction: _admission.needsForwardFriction,
                      applyBackwardFriction: _admission.needsBackwardFriction,
                    ),
                  ),
                ),
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
              ],
            ),
          ),
        );
      },
    );
  }
}

/// D5 條款 1 的 FIFO 命令佇列——hybrid 自帶實作，不 import 舊 viewport 內部。
final class _HybridCommandQueue {
  Future<void> _tail = Future<void>.value();

  Future<bool> enqueue({
    required bool Function() isMounted,
    required Future<bool> Function() command,
  }) {
    if (!isMounted()) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _tail = _tail
        .catchError((_) {})
        .then((_) async {
          if (!isMounted()) return false;
          return command();
        })
        .then(
          completer.complete,
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );
    return completer.future;
  }
}
