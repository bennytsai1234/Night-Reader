import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui show FrameTiming, Paragraph, TextBox;

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
import 'view/hybrid_ensure_gate.dart';

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
    this.paragraphCacheCapacity = 512,
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

  /// 測試 seam：縮小 ParagraphCache 容量以重現 LRU 逐出；正式路徑用預設。
  final int paragraphCacheCapacity;

  @override
  State<HybridReaderScreen> createState() => _HybridReaderScreenState();
}

/// 判斷一次「完整翻頁」是否真的完成。
///
/// Hybrid 的目前 scroll extent 只包含已 admission 的 block。若排版供給
/// 落後，`ScrollPosition.animateTo` 會把目標夾到暫時的 extent；這種情況
/// 畫面雖然有移動，卻不代表完成了呼叫端要求的整頁距離。只有真正到達
/// 已確認的書首／書尾時，最後不足整頁的移動才是合法成功。
@visibleForTesting
bool isHybridPageMoveComplete({
  required double requestedDistance,
  required double actualDistance,
  required bool atBookBoundary,
}) {
  if (!requestedDistance.isFinite || requestedDistance <= 0) return false;
  if (!actualDistance.isFinite || actualDistance <= 0) return false;
  // animateTo／DocumentIndex 的浮點誤差不應讓完整頁面被誤判為失敗；
  // 0.5 logical px 遠小於閱讀器一行，且不會掩蓋明顯的 lazy-edge 短移動。
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
  final AnchorManager _anchorManager = AnchorManager();
  final BudgetGovernor _governor = BudgetGovernor();
  final HybridTelemetry _telemetry = HybridTelemetry();
  final _HybridCommandQueue _commands = _HybridCommandQueue();
  final HybridEnsureGate _ensureGate = HybridEnsureGate();

  late HybridChapterRepository _chapterRepo;
  late final AdmissionController _admission;

  /// 單一穩定實例：`Scrollable` 只認 physics 的 runtimeType 鏈，position
  /// 抱的是第一顆——動態摩擦由 physics 透過 [_admission] 即時查詢。
  late final HybridScrollPhysics _physics;
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
  String? _lastLoggedErrorMessage;
  bool _initialRestoreCompleted = false;
  bool _capturing = false;

  /// restore 進行中旗標：此期間投放的 block 於建置「之前」即 pin 進
  /// ParagraphCache（見 [_admitOrSubmitGroup]），防止初始視窗建置量超過
  /// 快取容量時 LRU 把首屏段落逐出。
  bool _restorePinning = false;
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
    // 放行不再驅動 widget 層 setState：新 block 的材料化由
    // DocumentIndex.revision → RenderHybridBlockSliver.markNeedsLayout
    // 直驅（fling 幀 build 成本歸零的關鍵）。
    _admission = AdmissionController(documentIndex: _documentIndex);
    _physics = HybridScrollPhysics(admission: _admission);
    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);
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
      _lastLoggedErrorMessage = null;
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
    if (oldWidget.textColor != widget.textColor) {
      // 換色不 bump epoch（幾何不變）：清投放記錄讓視窗掃描以新色
      // 重投 LayoutTask，重建期間 paint 以 tint 過渡、逐塊收斂到直繪。
      _enqueued.clear();
      _ensureWindowTasks();
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
    unawaited(_writeDiskMetrics(_measurementStore.snapshot(_namespace)));
    unawaited(_chapterRepo.dispose());
    _admission.dispose();
    _ensureGate.dispose();
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

  /// session 結束時把 telemetry 累計摘要寫入 AppLog（設定頁日誌可回收），
  /// 附帶影響幀成本的關鍵樣式脈絡，供真機驗收劇本對比（如 B2 開/關）。
  void _logTelemetrySessionSummary() {
    final summary = _telemetry.sessionSummary();
    if ((summary['frames'] as int? ?? 0) == 0) return;
    summary['fontSize'] = _fingerprint.fontSize;
    summary['lastLineSpacingCompensation'] =
        _fingerprint.lastLineSpacingCompensation;
    AppLog.i('ReaderV2 telemetry session: ${jsonEncode(summary)}');
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
  }

  void _handleEpochRebuild() {
    // Do not leave a mounted sliver reading the old render tree while the
    // index and metrics namespace are being replaced. The extent callback has
    // a defensive fallback as a same-frame guard, but the normal transition
    // must render the loading state until restore has rebuilt the window.
    _initialRestoreCompleted = false;
    _lastSyncedLocation = null;
    // 舊 namespace 的量測 best-effort 落盤後自 store 回收——同款樣式改回
    // 來可直接 warm；不回收的話每次樣式變更都漏一整組 metrics 在記憶體。
    final oldNamespace = _namespace;
    unawaited(
      _writeDiskMetrics(
        _measurementStore.snapshot(oldNamespace),
        fingerprint: oldNamespace.fingerprint,
      ),
    );
    _measurementStore.invalidateNamespace(oldNamespace);
    _enqueued.clear();
    _blocks.clear();
    _blocksInFlight.clear();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _pump.dispose();
    final oldCache = _paragraphCache;
    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCache.dispose());
    // 舊索引的 extent 屬於已回收的舊 namespace；不清空的話重建到 restore
    // 完成之間的幀會拿舊座標配空 metrics 觸發 I1。restore 會重定中心。
    _documentIndex.reset(centerKey: _documentIndex.centerKey);
    _refreshEpochBinding();
    _warmedChapters.removeWhere((entry) => entry.namespace != _namespace);
  }

  // ---- runtime 事件 ----

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
    // hit.key 的 Paragraph 可能與同一連續排版 group 內的其他 block 共用；
    // hit.offsetInBlock 是「這個 block 自己 Y 窗」內的座標，要先平移回
    // 共用 Paragraph 的座標系（+entry.localTop）才能查行／查字元。
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
        // 換算回這個 block 自己的 Y 窗座標，才能跟 hit.blockTop 相加。
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
    ).normalized(
      chapterCount: widget.runtime.chapterCount,
      chapterLength: blocks.displayText.length,
    );
  }

  /// A short chapter can end before the visual anchor line while the viewport
  /// is still at that chapter's physical start.  In that transition the
  /// anchor hit points at the next chapter, but the reader has not scrolled
  /// past the current chapter yet.  Keep the last reported chapter until the
  /// scroll offset leaves its admitted range; otherwise opening a book at a
  /// one-line preface is immediately persisted as chapter 1.
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
    if (!mounted || widget.runtime.chapterCount <= 0) return false;
    // 拖曳中拒絕 restore——settle-restore 硬拉回目標會跟手勢打架。
    if (!_anchorManager.beginRestore(isDragging: _dragging)) return false;
    try {
      final ok = await _restoreCore(location);
      if (!ok || !mounted) return false;
      _scheduleRebuild();
      final captured = _captureVisibleLocation();
      if (captured == null) return false;
      // _lastReportedLocation is intentionally set to the requested anchor
      // below, before runtime.completeReady() publishes the new state.  Bump
      // the revision here as well so a scroll callback queued by the old
      // viewport cannot run after that publication and overwrite the target.
      _runtimeLocationRevision += 1;
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
      final anchor = _anchorManager.captureFromLocation(normalized, blocks);
      // reset() invalidates the mounted sliver's old index synchronously.
      // Hide that sliver on the next frame while the anchor window is rebuilt;
      // the total extent callback above also protects the current frame.
      _initialRestoreCompleted = false;
      _lastSyncedLocation = null;
      _scheduleRebuild();
      // 重定中心：admitted 度量由 store 回填（經 _ensureWindowTasks 的
      // 連續段 direct-admit），上側走 center 負座標生長（I3）。
      _documentIndex.reset(centerKey: anchor.blockKey);
      _admission.reset(epoch: _epoch, chapterCount: runtime.chapterCount);
      _admission.attach(_pump.completed);
      for (final loadedBlocks in _blocks.values) {
        _admission.registerChapter(loadedBlocks);
      }
      // restore 期間畫面停在 loading，_updateParagraphPins 不會執行；先清
      // 舊 pin、預 pin 錨點，並開啟 submit-time pinning——不 pin 的話初始
      // 視窗建置量超過快取容量時，LRU 會把首屏段落逐出（開書只剩錨點
      // 一行、其餘佔位空白）。正式 build 的 _updateParagraphPins 會接手
      // 重整 pin 集合。
      _paragraphCache
        ..unpinAll()
        ..pinKeys(<BlockKey>[anchor.blockKey], _epoch);
      _restorePinning = true;
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
        _restorePinning = false;
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

  /// 把「章節絕對 charOffset」換算成視覺上真正落點的
  /// `(BlockKey, 這個 block 自己 Y 窗內的 local top)`。
  ///
  /// 純文字模型的 `blockForCharOffset` 只看 charRange；當人工效能切點落
  /// 在一行中間時，那一整行仍完整畫在前一個切塊的 Y 窗裡（見
  /// [LayoutPump._groupSplitYs]），此時字元的視覺歸屬與 charRange 歸屬
  /// 不同。DocumentIndex 的座標以視覺歸屬為準，兩者不一致時必須以此為準
  /// 才能讓 restore／TTS／ensureCharRangeVisible 卷到正確的世界座標。
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
            }),
          );
        }
      case ChapterEventKind.evicted:
      case ChapterEventKind.invalidated:
        // maxBlockChars 由 LayoutCostModel 即時校準推導，同一章重新載入時
        // 可能切出不同的 block 邊界；evicted 與 invalidated 因此都必須清掉
        // 舊 metrics／Paragraph，否則同一個 BlockKey 換到新切法後可能重用
        // 舊切法量到的高度／文字（見任務規劃文件 Background）。DocumentIndex
        // 與 AdmissionController 也要同步清該章已放行的座標與記住的舊章節
        // 形狀，否則新 segmentation 缺席的舊高 blockIndex 會永遠殘留，錯誤
        // 貢獻文檔幾何。
        _blocks.remove(event.chapterId);
        _measurementStore.invalidateChapter(event.chapterId);
        _paragraphCache.invalidateChapter(event.chapterId);
        _admission.invalidateChapter(event.chapterId);
        if (_documentIndex.invalidateChapter(event.chapterId)) {
          _scheduleRebuild();
        }
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
          }),
        );
        continue;
      }
      _enqueueChapterTasks(blocks, anchorKey: delta == 0 ? anchorKey : null);
    }
  }

  void _enqueueChapterTasks(ChapterBlocks blocks, {BlockKey? anchorKey}) {
    final groups = blocks.paragraphGroups();
    if (groups.isEmpty) return;
    final centerKey = _documentIndex.centerKey;
    List<List<ChapterBlock>> forward;
    List<List<ChapterBlock>> backward;
    if (blocks.chapterIndex == centerKey.chapterIndex) {
      // center 可能落在某個 group 中間；該 group 不可切半送 forward/
      // backward 兩側（會破壞「group 只用一個 ui.Paragraph 連續排版」的
      // 前提），因此整個含 center 的 group 一律算進 forward。
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
    var forwardBlocked = false;
    var backwardBlocked = false;
    final rounds = math.max(forward.length, backward.length);
    for (var i = 0; i < rounds; i += 1) {
      if (i < forward.length) {
        forwardBlocked = _admitOrSubmitGroup(
          blocks,
          forward[i],
          blocked: forwardBlocked,
          anchorKey: anchorKey,
        );
      }
      if (i < backward.length) {
        backwardBlocked = _admitOrSubmitGroup(
          blocks,
          backward[i],
          blocked: backwardBlocked,
          anchorKey: anchorKey,
        );
      }
    }
  }

  /// group 內每個 block 就緒（有 metrics + paragraph）且同側尚未斷檔 →
  /// 整組直接 admit；否則整組送 pump（連續排版必須整組一起重建，不能
  /// 只補其中一塊，否則會在切點退回獨立 Paragraph 的硬換行）。回傳
  /// 「此側是否已斷檔」（斷檔後不得再 direct-admit，否則 DocumentIndex
  /// 會出現中間洞，補齊時可見內容會位移，違反 I3）。
  bool _admitOrSubmitGroup(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    required bool blocked,
    BlockKey? anchorKey,
  }) {
    // pin 必須發生在建置之前：pumpPending 單一批次就可能建掉整個初始
    // 視窗，put 之後才 pin 救不回批次途中已被 LRU 逐出的條目。
    if (_restorePinning) {
      _paragraphCache.pinKeys(<BlockKey>[for (final b in group) b.key], _epoch);
    }
    final anchor = anchorKey != null && group.any((b) => b.key == anchorKey);
    final notYetAdmitted = group
        .where((b) => _documentIndex.metricsFor(b.key) == null)
        .toList(growable: false);
    if (notYetAdmitted.isEmpty) {
      // 整組已 admit，只可能缺 paragraph（被 LRU 逐出）；缺就整組重建，
      // 不影響既有座標與斷檔狀態。
      final missingParagraph = group.any(
        (b) => !_paragraphCache.containsFresh(b.key, _epoch, widget.textColor),
      );
      if (missingParagraph) _submitGroupTask(blocks, group, anchor: anchor);
      return blocked;
    }
    final allReady = notYetAdmitted.every(
      (b) =>
          _measurementStore.get(_namespace, b.key) != null &&
          _paragraphCache.containsFresh(b.key, _epoch, widget.textColor),
    );
    if (allReady && !blocked) {
      for (final b in notYetAdmitted) {
        final metrics = _measurementStore.get(_namespace, b.key)!;
        _admission.offer(
          BlockReady(key: b.key, epoch: _epoch, metrics: metrics),
        );
      }
      return blocked;
    }
    _submitGroupTask(blocks, group, anchor: anchor);
    return true;
  }

  void _submitGroupTask(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    bool anchor = false,
  }) {
    final head = group.first;
    final headKey = head.key;
    if (!_enqueued.add(headKey)) return;
    for (final b in group.skip(1)) {
      _enqueued.add(b.key);
    }
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
          // em-grid 鎖寬後滿列天生切齊右緣，justify 只剩把避頭尾列殘差
          // 攤進字距、破壞直行格線的副作用，內文預設 start 對齊；
          // AppConfig 開關僅供真機對照。
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
        // 只有 group 真正的最後一塊（邏輯段落真正結尾）計入間距；
        // group 內部的效能切點恆為 0（見 _trailingSpacingFor）。
        trailingSpacing: _trailingSpacingFor(blocks, last),
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
    await _pump.pumpPending();
    if (!mounted) return;
    if (_pump.queueDepth > 0) {
      _schedulePump();
    } else {
      // 佇列見底 → 允許之後的視窗掃描重新投放（處理段落被 LRU 逐出的重排）。
      _enqueued.clear();
      _updateLeadTelemetry();
    }
    // 完成的排版經 admission 放行時由 DocumentIndex.revision 直驅 sliver
    // relayout，這裡不再 setState 世界重建。
  }

  void _updateLeadTelemetry() {
    // A pump that started before a chapter restore may resume after
    // DocumentIndex.reset() but before the new viewport offset is installed.
    // Its old scroll position is not meaningful in the new centered world;
    // reading it here can trip AdmissionController I5 during a large jump.
    if (!_initialRestoreCompleted || _anchorManager.restoreLocked) return;
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
        _ensureGate.beginUserScroll();
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
      if (wasUser) {
        unawaited(_settleUserScrollAndFlushEnsures());
      } else {
        unawaited(_ensureGate.releaseAndFlush());
      }
    }
    return false;
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending || !mounted) return;
    _captureFramePending = true;
    final scheduledRevision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted) return;
      if (!_initialRestoreCompleted || _anchorManager.restoreLocked) return;
      // Programmatic restore/jump can emit a scroll notification before the
      // runtime publishes its target location.  That callback belongs to the
      // old viewport address; letting it capture after completeReady would
      // replace a short target chapter with the next chapter at the anchor
      // line (for example the 34-byte preface followed by chapter 1).
      if (scheduledRevision != _runtimeLocationRevision) return;
      if (widget.runtime.pendingChapterJumpTarget != null) return;
      // 動作中一律靜默 capture：runtime notify 會連鎖 ReaderV2Page 與本
      // screen 的整面 setState（fling 中的節奏性重活）。頁面層滾動中需要
      // 跟動的顯示走 progressListenable 窄通道；完整 notify 留給 settle。
      final location = _captureAndReport(notify: false);
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
    if (!mounted ||
        _dragging ||
        !_initialRestoreCompleted ||
        _anchorManager.restoreLocked) {
      return;
    }
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

  Future<void> _settleUserScrollAndFlushEnsures() async {
    try {
      await _handleScrollSettled();
    } finally {
      if (mounted) await _ensureGate.releaseAndFlush();
    }
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
      () => _ensureGate.submit(
        () => _ensureCharRangeVisibleNow(
          chapterIndex: chapterIndex,
          startCharOffset: startCharOffset,
          endCharOffset: endCharOffset,
        ),
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
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) return false;
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
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) return false;
    await position.animateTo(
      target,
      duration: _ensureAnimateDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return false;
    await _handleScrollSettled();
    return mounted;
  }

  Future<bool> _movePageNow({required bool forward}) async {
    final height = _viewportSize.height;
    if (height <= 0) return false;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final before = controller.position.pixels;
    final style = widget.runtime.state.layoutSpec.style;
    final overlap = math.max(24.0, style.fontSize * style.effectiveLineHeight);
    final magnitude = math.max(height * 0.5, height - overlap - 8.0);
    final moved = await _animateByNow(forward ? magnitude : -magnitude);
    if (!moved) _emitBookBoundaryNotice(forward: forward);
    if (!moved || !mounted || !controller.hasClients) return false;

    final after = controller.position.pixels;
    final atBookBoundary = forward
        ? _admission.atForwardBookBoundary
        : _admission.atBackwardBookBoundary;
    final complete = isHybridPageMoveComplete(
      requestedDistance: magnitude,
      actualDistance: (after - before).abs(),
      atBookBoundary: atBookBoundary,
    );
    if (!complete) {
      // 目前只到 lazy edge：不要讓 page coordinator／auto page 把短移動
      // 當成完整一頁。settle 已安排下一輪 window/pump，這裡再確保尚有
      // pending task 時會繼續供給；下一次翻頁命令即可重新嘗試。
      _schedulePump();
    }
    return complete;
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
    // 逐 block 讀 ready 狀態，但缺件時整個 group 一起送 pump——只補其中
    // 一塊會退回獨立 Paragraph，重新產生已修正的硬換行問題。
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

  /// [block] 內、與 [range] 相交的字元對應的 boxes；y 座標已從共用
  /// Paragraph 的座標系換算回「這個 block 自己 Y 窗」座標（減去
  /// entry.localTop），呼叫端不需要知道 block 是否與同 group 其他 block
  /// 共用 ui.Paragraph。回傳 null 表示 Paragraph 尚未就緒。
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
    // ChapterBlocks preserves display-text order. Find the first possible
    // overlap with binary search so a short TTS range does not rescan an
    // entire long chapter on every scroll frame.
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

  Future<void> _writeDiskMetrics(
    Map<BlockKey, BlockMetrics> snapshot, {
    StyleFingerprint? fingerprint,
  }) async {
    if (!widget.enableDiskMetrics ||
        widget.bookUrl == null ||
        snapshot.isEmpty) {
      return;
    }
    // await 前同步快照：epoch 重建 / dispose 之後 _blocks 與 _fingerprint
    // 都可能已被換掉。
    final targetFingerprint = fingerprint ?? _fingerprint;
    final chapterContentHashes = <int, String>{
      for (final blocks in _blocks.values)
        blocks.chapterIndex: blocks.contentHash,
    };
    try {
      final cache = await _obtainDiskCache();
      await cache.write(
        bookUrl: widget.bookUrl!,
        fingerprint: targetFingerprint,
        metrics: snapshot,
        chapterContentHashes: chapterContentHashes,
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

  /// 找 dy 所在行（超出末行時回末行）。每個滾動幀都會進來——用單行查詢
  /// API，不可用 computeLineMetrics（整串 LineMetrics 配置進熱路徑）。
  ({double top, double bottom})? _lineAt(ui.Paragraph paragraph, double dy) {
    final lineCount = paragraph.numberOfLines;
    if (lineCount <= 0) return null;
    // x=0 取該行行首字元；y 由引擎 clamp 到首/末行。
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

  /// capture 與 restore 必須共用同一種文字 box 幾何；混用 LineMetrics.top
  /// 與 TextBox.top 會把字型 leading 的差值寫進 visualOffsetPx。
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

  /// 高亮 overlay 的水平 padding 必須用 spec 調整後的值：em-grid 鎖寬把
  /// 殘差平分回左右 padding，widget.style 仍是使用者原始設定。
  ReaderV2Style _overlayStyle() {
    final specStyle = widget.runtime.state.layoutSpec.style;
    return widget.style.copyWith(
      paddingTop: 0.0,
      paddingLeft: specStyle.paddingLeft,
      paddingRight: specStyle.paddingRight,
    );
  }

  void _updateParagraphPins() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    final top = offset - _admission.backwardGuaranteedWindow;
    final bottom = offset + _viewportSize.height + _admission.guaranteedWindow;
    _paragraphCache
      ..unpinAll()
      ..pinKeys(_documentIndex.keysInRange(top, bottom), _epoch);
    _paragraphCache.trimToCapacity();
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
                    // 鎖寬後的置中殘差在 spec.style 的 padding 裡，
                    // 不可用 widget.style（使用者原始 padding）。
                    horizontalPadding: EdgeInsets.only(
                      left: state.layoutSpec.style.paddingLeft,
                      right: state.layoutSpec.style.paddingRight,
                    ),
                    physics: _physics,
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
                if (state.phase != ReaderV2Phase.ready)
                  Positioned.fill(child: _buildOperationOverlay(state)),
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
