import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/motion_gate.dart';

import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
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
import 'core/hybrid_types.dart';
import 'geometry/text_geometry.dart';
import 'measure/document_index.dart';
import 'measure/measurement_store.dart';
import 'overlay/loading_veil.dart';
import 'overlay/reader_skeleton_page.dart';
import 'overlay/selection_service.dart';
import 'overlay/text_selection_overlay.dart';
import 'overlay/tts_highlight_overlay.dart';
import 'pipeline/layout_disk_cache.dart';
import 'pipeline/layout_pipeline.dart';
import 'progress/hybrid_progress.dart';
import 'pump/budget_governor.dart';
import 'text/hybrid_chapter_repository.dart';
import 'text/text_preprocessor.dart';
import 'text/word_segmenter.dart';
import 'view/admission_controller.dart';
import 'view/hybrid_scroll_controller.dart';
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
    this.textSelectionEnabled = false,
    this.highlightColor = const Color(0xFFFFC857),
    this.highlightStrength = ReaderV2HighlightStrength.defaultValue,
    this.progressListenable,
    this.bookUrl,
    this.skeletonPages,
    this.preprocessor = const TextPreprocessor(),
    this.enableDiskCache = true,
    this.paragraphCacheCapacity = 512,
  });

  final ReaderV2Runtime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final GestureTapUpCallback? onContentTapUp;
  final ReaderV2ViewportController? viewportController;
  final ReaderV2TtsHighlight? ttsHighlight;

  /// 長按選字。朗讀、自動翻頁與閱讀選單開著時由上層關閉；關閉時清掉
  /// 既有選取。
  final bool textSelectionEnabled;

  /// 朗讀高亮與選字反白的顏色；[highlightStrength] 只套在朗讀高亮，選字
  /// 反白固定深淺以保持可辨識。
  final Color highlightColor;
  final double highlightStrength;
  final ValueNotifier<HybridProgressSnapshot?>? progressListenable;
  final String? bookUrl;

  /// 每本書上一次離開時的那一頁（ADR 0024）：開書時從同一處打開就照它畫
  /// 骨架；離開閱讀器或 App 切到背景時記下目前這一頁。
  final ReaderSkeletonPageStore? skeletonPages;
  final HybridTextPreprocessor preprocessor;
  final bool enableDiskCache;
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
    with TickerProviderStateMixin {
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
  HybridLayoutDiskCache? _diskCache;

  /// 目前排版世代的排版管線；排版或內容換代時整份換新（見
  /// [_handleEpochRebuild]）。
  late HybridLayoutPipeline _pipeline;
  StreamSubscription<ChapterEvent>? _chapterEventsSub;
  HybridScrollController? _scrollController;
  _PageTurn? _pageTurn;
  Size _viewportSize = Size.zero;
  double? _pendingScrollOffset;
  ReaderV2OperationToken? _demandOwner;
  int _windowCenter = 0;
  int _lastLayoutGeneration = 0;
  int _lastContentGeneration = 0;
  int _runtimeLocationRevision = 0;

  /// 視窗還原的世代：只有新的還原與排版世代重建會讓進行中的還原作廢。
  /// 使用者捲動或停止自動捲動不會；跳轉被使用者捲動取代時，由 Runtime
  /// 放棄該操作。
  int _restoreRevision = 0;
  ReaderV2Location? _lastReportedLocation;
  bool _initialRestoreCompleted = false;

  /// 正在等正文的跳章：一開始就蓋紙、攔下觸控，排版開始後交給
  /// [_restoreCore]（見 [_syncJumpVeil]）。
  ReaderV2OperationToken? _jumpVeil;

  /// 蓋上等跳章的紙那一刻的捲動位置；紙下的正文停在這裡，取不到正文時
  /// 掀開紙回到的就是這個位置。
  double? _jumpVeilOffset;
  late final LoadingVeilController _veil = LoadingVeilController(
    vsync: this,
    onHidden: () {
      // 紙掀完了；下一次蓋紙另外決定照什麼畫骨架。
      _openingPage = null;
      _veilPage = null;
      _veilAwaitsPage = false;
      if (mounted) setState(() {});
    },
  );

  /// 開書的位置與版面都和上次記下的那一頁相同時，開書的紙照它畫骨架。
  ReaderSkeletonPage? _openingPage;

  /// 這次排好的第一頁；紙上的骨架照它畫（見 [_coverUntilFirstPage]）。
  _PageLines? _veilPage;

  /// 紙蓋著、中間還空著，等第一頁排好。
  bool _veilAwaitsPage = false;

  /// App 切到背景時記下目前這一頁（之後可能被系統關掉，不會再走到
  /// [dispose]）。
  late final AppLifecycleListener _lifecycle;
  bool _dragging = false;

  /// 正文捲動中（拖動、甩動、翻頁動畫）持有 [MotionGate]（ADR 0018）。
  final MotionHold _scrollHold = MotionHold();
  bool _sawUserScroll = false;
  bool _rebuildQueued = false;
  bool _captureFramePending = false;
  final SelectionService _selection = SelectionService();
  final WordSegmenter _wordSegmenter = const WordSegmenter();

  /// 每次長按或取消都換號；選詞要等原生斷詞回來，期間若已取消或又長按
  /// 別處，舊結果作廢。
  int _selectionRequest = 0;

  @override
  void initState() {
    super.initState();
    _chapterRepo = HybridChapterRepository(
      repository: widget.runtime.repository,
      loadContent: widget.runtime.loadContentAt,
    );
    _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
    _admission = AdmissionController(documentIndex: _documentIndex);
    _diskCache = _diskCacheFor(widget);
    _pipeline = _createPipeline();
    _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
    _lastContentGeneration = widget.runtime.state.contentGeneration;
    _lastReportedLocation = widget.runtime.state.visibleLocation;
    _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
    _registerRuntime();
    _attachController();
    _openingPage = _rememberedPageForOpening();
    if (_openingPage == null) {
      _coverUntilFirstPage();
    } else {
      _veil.cover();
    }
    _lifecycle = AppLifecycleListener(onHide: _rememberPage);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreAttachedRuntime();
    });
  }

  void _registerRuntime() {
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.addViewportGeometryListener(_onViewportGeometryChanged);
    widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
  }

  void _unregisterRuntime(ReaderV2Runtime runtime) {
    runtime.removeListener(_onRuntimeChanged);
    runtime.removeViewportGeometryListener(_onViewportGeometryChanged);
    runtime.unregisterVisibleLocationCapture(this);
    runtime.unregisterViewportRestore(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _veil.reduceMotion = MediaQuery.disableAnimationsOf(context);
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
        loadContent: widget.runtime.loadContentAt,
      );
      _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _lastContentGeneration = widget.runtime.state.contentGeneration;
      _lastReportedLocation = widget.runtime.state.visibleLocation;
      _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
      // 舊世代的段落尺寸由舊管線存回它那本書的快取。
      _diskCache = _diskCacheFor(widget);
      _handleEpochRebuild();
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
    if (oldWidget.runtime != widget.runtime || !widget.textSelectionEnabled) {
      _clearSelection();
    }
  }

  /// 離開閱讀器時記下目前這一頁。在 [dispose] 時正文的捲動位置已經拆掉，
  /// 這裡子樹都還在。
  @override
  void deactivate() {
    _rememberPage();
    super.deactivate();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _scrollHold.release();
    _unregisterRuntime(widget.runtime);
    _detachController(widget.viewportController);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _chapterEventsSub?.cancel();
    _pipeline.dispose();
    unawaited(_chapterRepo.dispose());
    _admission.dispose();
    _scrollController?.dispose();
    _selection.dispose();
    _veil.dispose();
    super.dispose();
  }

  /// 正文是否已排好可以顯示；切換時蓋上或掀開 [_veil]。
  void _setRestoreCompleted(bool completed) {
    // 排版流程接手這張紙，等正文的跳章不再另外管它。
    _jumpVeil = null;
    if (_initialRestoreCompleted == completed) return;
    _initialRestoreCompleted = completed;
    if (completed) {
      _veil.reveal(SkeletonReveal.of(context));
    } else {
      _coverUntilFirstPage();
    }
  }

  static HybridLayoutDiskCache? _diskCacheFor(HybridReaderScreen widget) {
    final bookUrl = widget.bookUrl;
    if (!widget.enableDiskCache || bookUrl == null) return null;
    return HybridLayoutDiskCache(bookUrl: bookUrl);
  }

  HybridLayoutPipeline _createPipeline() {
    final state = widget.runtime.state;
    return HybridLayoutPipeline(
      epoch: LayoutEpoch(
        state.layoutGeneration,
        contentGeneration: state.contentGeneration,
      ),
      layoutSpec: () => widget.runtime.state.layoutSpec,
      measurementStore: _measurementStore,
      documentIndex: _documentIndex,
      admission: _admission,
      governor: _governor,
      chapters: _chapterRepo,
      preprocessor: widget.preprocessor,
      diskCache: _diskCache,
      paragraphCacheCapacity: widget.paragraphCacheCapacity,
      chapterCount: () => widget.runtime.chapterCount,
      textColor: () => widget.textColor,
      onProgress: _reconcileVisibleWindow,
    );
  }

  void _handleEpochRebuild() {
    _runtimeLocationRevision += 1;
    _restoreRevision += 1;
    _setRestoreCompleted(false);
    _pipeline.dispose();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _documentIndex.reset(centerKey: _documentIndex.centerKey);
    _pipeline = _createPipeline();
  }

  Future<bool> _restoreCore(
    ReaderV2Location location, {
    required bool Function() isCurrent,
    ReaderV2OperationKind? operationKind,
  }) async {
    if (!isCurrent() || widget.runtime.chapterCount <= 0) return false;
    // 開書、跳章與重新定位都是使用者的動作：之前取不到的章節都再試一次。
    _chapterRepo.forgetFailures();
    final pipeline = _pipeline;
    final chapter = location.chapterIndex
        .clamp(0, widget.runtime.chapterCount - 1)
        .toInt();
    _windowCenter = chapter;
    pipeline.demandAround(chapter);
    pipeline.clearPendingLayouts();
    pipeline.onScrollStateChanged(
      _initialRestoreCompleted ? PumpState.rebuilding : PumpState.loading,
    );
    try {
      final blocks = await pipeline.ensureChapter(
        chapter,
        priority: LayoutTaskPriority.anchor,
      );
      if (blocks == null || !isCurrent()) return false;

      // Open and jump wait for the steady-state lead in both directions, but
      // only as far as that distance reaches: the window loop below pulls in
      // an adjacent chapter exactly when the lead crosses into it.
      final operationOwnsReadyWorld =
          operationKind == ReaderV2OperationKind.open ||
          operationKind == ReaderV2OperationKind.jump;

      final normalized = location.normalized(
        chapterCount: widget.runtime.chapterCount,
        chapterLength: blocks.displayText.length,
      );
      final anchor = HybridAnchor.fromLocation(normalized, blocks);
      _setRestoreCompleted(false);
      // 開書照上次記下的那一頁畫著骨架，但正文換過了（替換規則、重新取得）
      // 或紙還沒掀開版面就變了（例如轉向）：那些行不是這次的，淡掉改等
      // 第一頁。
      if (_openingPage case final opening?
          when opening.contentHash != blocks.contentHash ||
              opening.layout !=
                  ReaderSkeletonPage.layoutKeyOf(
                    widget.runtime.state.layoutSpec,
                  )) {
        setState(_coverUntilFirstPage);
      }
      pipeline.onScrollStateChanged(PumpState.loading);
      _scheduleRebuild();
      pipeline.resetDocument(anchor.blockKey);
      final pageHeight = math.max(1.0, _viewportSize.height);
      restoreLoop:
      while (isCurrent()) {
        final revision = _documentIndex.revisionNumber;
        if (_veilAwaitsPage) {
          // 先只排第一頁：骨架照它畫，淡入播完才排前後其他頁。
          final pageTop = _clampToBook(_offsetForAnchor(anchor, blocks) ?? 0);
          pipeline.requestWindow(
            pageTop,
            pageTop + pageHeight,
            anchorKey: anchor.blockKey,
          );
          final positioned = _offsetForAnchor(anchor, blocks);
          final page = positioned == null ? null : _clampToBook(positioned);
          if (page != null && pipeline.windowReady(page, page + pageHeight)) {
            if (!await _showFirstPageSkeleton(page, isCurrent)) {
              return false;
            }
            continue;
          }
          if (_documentIndex.revisionNumber != revision) continue;
          final wait = await pipeline.waitForProgress(isCurrent);
          switch (wait) {
            case MaterializationWait.progressed:
              continue;
            case MaterializationWait.frontierUnavailable:
              break restoreLoop;
            case MaterializationWait.cancelled:
              return false;
          }
        }
        final target = _offsetForAnchor(anchor, blocks);
        final readyTop = _readyWorldTop(
          target: target ?? 0,
          operationOwnsReadyWorld: operationOwnsReadyWorld,
        );
        final readyBottom = _readyWorldBottom(
          target: target ?? 0,
          operationOwnsReadyWorld: operationOwnsReadyWorld,
        );
        pipeline.requestWindow(
          readyTop,
          readyBottom,
          anchorKey: anchor.blockKey,
        );
        final positionedTarget = _offsetForAnchor(anchor, blocks);
        if (positionedTarget != null &&
            pipeline.windowReady(
              _readyWorldTop(
                target: positionedTarget,
                operationOwnsReadyWorld: operationOwnsReadyWorld,
              ),
              _readyWorldBottom(
                target: positionedTarget,
                operationOwnsReadyWorld: operationOwnsReadyWorld,
              ),
            )) {
          break;
        }
        // Cached exact metrics may advance admission synchronously, without
        // creating a layout task. Re-evaluate that progress before waiting.
        if (_documentIndex.revisionNumber != revision) continue;
        final wait = await pipeline.waitForProgress(isCurrent);
        switch (wait) {
          case MaterializationWait.progressed:
            continue;
          case MaterializationWait.frontierUnavailable:
            break restoreLoop;
          case MaterializationWait.cancelled:
            return false;
        }
      }
      if (!isCurrent()) return false;
      final target = _offsetForAnchor(anchor, blocks);
      // 排不滿一頁就沒有更多可排了（例如書尾）：骨架照排出來的那些行畫。
      if (target != null &&
          _veilAwaitsPage &&
          !await _showFirstPageSkeleton(_clampToBook(target), isCurrent)) {
        return false;
      }
      if (target == null) {
        throw StateError(
          'Hybrid restore target has no admitted anchor geometry after '
          'materialization completed.',
        );
      }
      _pendingScrollOffset = target;
      _lastReportedLocation = normalized;
      _setRestoreCompleted(true);
      pipeline.onScrollStateChanged(PumpState.rebuilding);
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
      if (mounted && identical(pipeline, _pipeline)) {
        pipeline.onScrollStateChanged(
          _dragging ? PumpState.dragging : PumpState.idle,
        );
      }
    }
  }

  double _readyWorldTop({
    required double target,
    required bool operationOwnsReadyWorld,
  }) {
    if (!operationOwnsReadyWorld) return target;
    // Open and jump commit into the same backward lead invariant used by
    // steady-state scrolling. The first interactive frame therefore starts
    // warm instead of asking the user gesture to build the lead afterward.
    return target - _admission.backwardGuaranteedWindow;
  }

  double _readyWorldBottom({
    required double target,
    required bool operationOwnsReadyWorld,
  }) {
    final viewportBottom = target + math.max(1, _viewportSize.height);
    if (!operationOwnsReadyWorld) return viewportBottom;
    return viewportBottom + _admission.guaranteedWindow;
  }

  Future<void> _nextFrame() {
    WidgetsBinding.instance.ensureVisualUpdate();
    return WidgetsBinding.instance.endOfFrame;
  }

  void _onChapterEvent(ChapterEvent event) {
    if (!mounted) return;
    if (_pipeline.handleChapterEvent(event)) _scheduleRebuild();
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
    _pipeline.reconcile(top: top, bottom: bottom, windowCenter: _windowCenter);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) _scrollHold.moving = true;
    if (notification is ScrollEndNotification) _scrollHold.moving = false;
    if (_jumpVeil != null) {
      // 紙蓋上前就按下的手指，在紙下開始拖動：不算使用者接手、不取消
      // 跳章，拖動作廢並回到蓋紙那一刻的位置。
      if (_isDragNotification(notification)) {
        scheduleMicrotask(_holdScrollUnderJumpVeilAgain);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      // 拖動真的推動正文才算使用者接手捲動。正文上只有捲動手勢時，
      // 原生 Scrollable 連單純的點擊也會發出零位移的拖動開始。
      if (!_dragging && notification.dragDetails != null) {
        _dragging = true;
        _sawUserScroll = true;
        _clearSelection();
        _runtimeLocationRevision += 1;
        widget.runtime.cancelJumpForUserScroll();
        _pipeline.onScrollStateChanged(PumpState.dragging);
      } else if (_dragging && notification.dragDetails == null) {
        _dragging = false;
        _pipeline.onScrollStateChanged(PumpState.ballistic);
      }
      _scheduleMotionCapture();
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      // 停在可捲範圍盡頭再往外拖，正文不動、只有 overscroll；手勢結束時
      // 一樣要檢查那個邊緣是不是取不到的章節。
      _sawUserScroll = true;
    } else if (notification is ScrollEndNotification) {
      final wasUser = _sawUserScroll;
      _dragging = false;
      _sawUserScroll = false;
      _pipeline.onScrollStateChanged(PumpState.idle);
      if (wasUser) {
        _retryUnavailableFrontierAtExtent();
        unawaited(_handleScrollSettled());
      }
    }
    return false;
  }

  /// 使用者把正文捲到可捲範圍的盡頭時，若那裡是取不到的章節，說明原因
  /// 並重試。
  void _retryUnavailableFrontierAtExtent() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    if (position.pixels >=
        position.maxScrollExtent - _minimumViewportMovement) {
      _retryUnavailableFrontier(forward: true);
    }
    if (position.pixels <=
        position.minScrollExtent + _minimumViewportMovement) {
      _retryUnavailableFrontier(forward: false);
    }
  }

  /// 已排好的正文在章節邊緣結束、而相鄰章節取不到時：把取不到的原因
  /// 告訴使用者，並重試一次那一章。只在使用者捲到或翻到這個邊緣時呼叫，
  /// 不會在背景反覆請求。
  void _retryUnavailableFrontier({required bool forward}) {
    final unavailable = _pipeline.unavailableFrontier(forward: forward);
    if (unavailable == null) return;
    widget.runtime.emitUserNotice(unavailable.failure.message);
    _pipeline.retryChapter(unavailable.chapter);
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending || !mounted) return;
    _captureFramePending = true;
    final revision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted ||
          !_initialRestoreCompleted ||
          revision != _runtimeLocationRevision) {
        return;
      }
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
        widget.runtime.pendingLocation != null) {
      return;
    }
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
        !(_scrollController?.hasClients ?? false)) {
      return false;
    }
    final geometryRevision = _documentIndex.revisionNumber;
    final pixels = _scrollController!.position.pixels;
    final target = pixels + (forward ? distance : -distance);
    final top = math.min(pixels, target);
    final bottom = math.max(pixels, target) + _viewportSize.height;
    final pipeline = _pipeline;
    while (isCurrent()) {
      pipeline.requestWindow(top, bottom);
      if (pipeline.windowReady(top, bottom)) {
        if (_documentIndex.revisionNumber != geometryRevision) {
          await _nextFrame();
        }
        return isCurrent();
      }
      final wait = await pipeline.waitForProgress(isCurrent);
      switch (wait) {
        case MaterializationWait.progressed:
          continue;
        case MaterializationWait.frontierUnavailable:
        case MaterializationWait.cancelled:
          return false;
      }
    }
    return false;
  }

  void _handleFrameTimings(List<ui.FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    _governor.recordFrameTimings(timings);
  }

  void _onViewportGeometryChanged() {
    if (!mounted) return;
    _reconcileVisibleWindow();
    _scheduleRebuild();
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    final runtime = widget.runtime;
    final state = runtime.state;
    final operation = runtime.stateMachine.currentOperation;
    _syncJumpVeil(operation);
    final layoutChanged = _lastLayoutGeneration != state.layoutGeneration;
    final contentChanged = _lastContentGeneration != state.contentGeneration;
    if (layoutChanged || contentChanged) {
      _lastLayoutGeneration = state.layoutGeneration;
      _lastContentGeneration = state.contentGeneration;
      _handleEpochRebuild();
      if (contentChanged && operation == null && state.hasStableWorld) {
        _restorePublishedContentGeneration(
          state.visibleLocation,
          state.contentGeneration,
        );
      }
    }
    final requested = runtime.pendingLocation;
    if (requested != null && !identical(operation, _demandOwner)) {
      _demandOwner = operation;
      if (widget.runtime.chapterCount > 0) {
        final chapter = requested.chapterIndex
            .clamp(0, widget.runtime.chapterCount - 1)
            .toInt();
        _windowCenter = chapter;
        _pipeline.clearPendingLayouts();
        _pipeline.demandAround(chapter);
      }
    }
    if (state.hasStableWorld && _initialRestoreCompleted) {
      _demandOwner = null;
      _reconcileVisibleWindow();
      _publishProgress();
    }
    _scheduleRebuild();
  }

  /// 跳章一開始就蓋紙：正文還在取得時，舊正文不留在畫面上，紙也攔下捲動。
  /// 排版開始後由 [_restoreCore] 接手；跳章在那之前就結束（取不到正文、被
  /// 別的操作取代）時掀開紙，舊正文原封不動。
  void _syncJumpVeil(ReaderV2OperationToken? operation) {
    final jump = operation?.kind == ReaderV2OperationKind.jump
        ? operation
        : null;
    if (identical(jump, _jumpVeil)) return;
    final wasVeiled = _jumpVeil != null;
    _jumpVeil = null;
    if (!_initialRestoreCompleted) return;
    if (jump != null) {
      _jumpVeil = jump;
      _clearSelection();
      _holdScrollUnderJumpVeil();
      _coverUntilFirstPage();
    } else if (wasVeiled) {
      _veilAwaitsPage = false;
      _veil.reveal(SkeletonReveal.of(context));
    }
  }

  /// 停住紙下正在跑的捲動（甩動的慣性、已經開始的拖動），固定在蓋紙那一刻
  /// 的位置。`jumpTo` 會結束目前的捲動活動，進行中的拖動也一併作廢。
  void _holdScrollUnderJumpVeil() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    _jumpVeilOffset = position.pixels;
    position.jumpTo(position.pixels);
    _dragging = false;
    _sawUserScroll = false;
    _pipeline.onScrollStateChanged(PumpState.idle);
  }

  void _holdScrollUnderJumpVeilAgain() {
    final offset = _jumpVeilOffset;
    final controller = _scrollController;
    if (!mounted ||
        _jumpVeil == null ||
        offset == null ||
        controller == null ||
        !controller.hasClients) {
      return;
    }
    controller.position.jumpTo(offset);
  }

  static bool _isDragNotification(ScrollNotification notification) =>
      (notification is ScrollStartNotification &&
          notification.dragDetails != null) ||
      (notification is ScrollUpdateNotification &&
          notification.dragDetails != null) ||
      (notification is OverscrollNotification &&
          notification.dragDetails != null);

  void _restorePublishedContentGeneration(
    ReaderV2Location location,
    int contentGeneration,
  ) {
    unawaited(
      Future<void>.microtask(() async {
        if (!mounted) return;
        final runtime = widget.runtime;
        if (runtime.state.contentGeneration != contentGeneration ||
            runtime.stateMachine.currentOperation != null) {
          return;
        }
        await _restoreToLocation(location);
      }),
    );
  }

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
    return _pipeline.geometry.locationAt(
      hit,
      worldY: worldY,
      chapterCount: widget.runtime.chapterCount,
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
    final pipeline = _pipeline;
    _runtimeLocationRevision += 1;
    final revision = ++_restoreRevision;
    bool current() =>
        mounted &&
        identical(widget.runtime, runtime) &&
        identical(_pipeline, pipeline) &&
        revision == _restoreRevision &&
        (operation == null || runtime.isCurrentOperationToken(operation));
    if (!current() || runtime.chapterCount <= 0) return false;
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.position.jumpTo(controller.position.pixels);
    }
    _dragging = false;
    _sawUserScroll = false;
    final ok = await _restoreCore(
      location,
      isCurrent: current,
      operationKind: operation?.kind,
    );
    if (!ok || !current()) return false;
    _lastReportedLocation = location;
    _scheduleRebuild();
    return true;
  }

  double? _offsetForAnchor(HybridAnchor anchor, ChapterBlocks blocks) =>
      _pipeline.geometry.scrollOffsetForAnchor(
        anchor,
        blocks,
        anchorLine: AnchorManager.anchorOffsetInViewport(_viewportSize.height),
      );

  double? _effectiveScrollOffset() {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      return controller.position.pixels;
    }
    return _pendingScrollOffset;
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
        _initialRestoreCompleted && widget.runtime.state.hasStableWorld;
    final location = runtimeLocationIsPublished
        ? widget.runtime.state.visibleLocation
        : _captureVisibleLocation();
    if (location == null) return;
    final blocks = _pipeline.blocksOf(location.chapterIndex);
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
      ..ensureCharRangeVisible = _ensureCharRangeVisible
      ..dismissSelection = _dismissSelection;
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
    if (controller.dismissSelection == _dismissSelection) {
      controller.dismissSelection = null;
    }
    if (controller.ensureCharRangeVisible == _ensureCharRangeVisible) {
      controller.ensureCharRangeVisible = null;
    }
  }

  bool Function() _captureCommandOwner() {
    final runtime = widget.runtime;
    final operation = runtime.stateMachine.currentOperation;
    final pipeline = _pipeline;
    final revision = _runtimeLocationRevision;
    final admitted =
        _initialRestoreCompleted && !_sawUserScroll && _jumpVeil == null;
    return () =>
        admitted &&
        mounted &&
        identical(widget.runtime, runtime) &&
        !runtime.disposed &&
        runtime.state.hasStableWorld &&
        identical(_pipeline, pipeline) &&
        revision == _runtimeLocationRevision &&
        identical(runtime.stateMachine.currentOperation, operation) &&
        !_sawUserScroll &&
        // 等跳章正文時紙下的正文歸那次跳章：翻頁、自動捲動與朗讀跟隨都
        // 不能移動它，跳章結束後再來。
        _jumpVeil == null;
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

  Future<bool> _moveToNextPage() => _movePage(forward: true);

  Future<bool> _moveToPrevPage() => _movePage(forward: false);

  /// 同方向的翻頁動畫還在跑時，這一下直接把目標再往後推一頁、從目前
  /// 位置接著捲，不等前一下停下來；推不了（正文還沒排好）才排隊。
  /// 翻頁後面已經有排隊的命令（例如反方向的一下）時也排隊，照點擊順序
  /// 執行。
  Future<bool> _movePage({required bool forward}) {
    final turn = _pageTurn;
    if (turn != null &&
        turn.forward == forward &&
        _commands.queued <= 1 &&
        turn.isCurrent() &&
        _extendPageTurn(turn)) {
      return turn.finished.future;
    }
    return _enqueueCommand(
      (current) => _movePageNow(forward: forward, isCurrent: current),
    );
  }

  Future<void> _settleScroll() async {
    // 使用者正在拖動或甩動時捲動歸使用者：停在這裡會打斷手勢，
    // 手勢結束時也會自行儲存位置。
    if (_sawUserScroll) return;
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

  /// 一次翻頁的距離：一屏減一行，保留一行重疊（ADR 0006）。
  double? _pageTurnDistance() {
    final height = _viewportSize.height;
    if (height <= 0) return null;
    final style = widget.runtime.state.layoutSpec.style;
    final overlap = math.max(24.0, style.fontSize * style.effectiveLineHeight);
    return math.max(height * 0.5, height - overlap - 8.0);
  }

  /// 把進行中的翻頁再推一頁。只在新目標之前的正文已經排好、而且在目前
  /// 捲動範圍內時才推，否則回傳 false 讓這一下排隊。
  bool _extendPageTurn(_PageTurn turn) {
    final controller = _scrollController;
    final distance = _pageTurnDistance();
    if (controller == null || !controller.hasClients || distance == null) {
      return false;
    }
    final position = controller.position;
    if (!position.isPageTurning) return false;
    final target = turn.target + (turn.forward ? distance : -distance);
    if (target < position.minScrollExtent ||
        target > position.maxScrollExtent) {
      return false;
    }
    final top = math.min(position.pixels, target);
    final bottom = math.max(position.pixels, target) + _viewportSize.height;
    _pipeline.requestWindow(top, bottom);
    if (!_pipeline.windowReady(top, bottom)) return false;
    turn
      ..target = target
      ..requestedDistance += distance
      ..animation = position.animatePageTo(
        target,
        duration: _viewportMotionDuration,
        curve: Curves.easeOutCubic,
      );
    return true;
  }

  Future<bool> _movePageNow({
    required bool forward,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    final distance = _pageTurnDistance();
    if (distance == null) return false;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;

    final reachable = await _ensurePageDistanceAvailable(
      forward: forward,
      distance: distance,
      isCurrent: isCurrent,
    );
    if (!isCurrent() || !controller.hasClients) return false;
    if (!reachable) {
      _retryUnavailableFrontier(forward: forward);
      return false;
    }

    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + (forward ? distance : -distance))
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) {
      _emitBookBoundaryNotice(forward: forward);
      return false;
    }

    final turn = _PageTurn(
      forward: forward,
      target: target,
      requestedDistance: distance,
      isCurrent: isCurrent,
    );
    _pageTurn = turn;
    try {
      turn.animation = position.animatePageTo(
        target,
        duration: _viewportMotionDuration,
        curve: Curves.easeOutCubic,
      );
      // 連點會換掉 turn.animation；等到最後一段動畫結束才算翻完。
      while (true) {
        final animation = turn.animation;
        await animation;
        if (!isCurrent()) return turn.finish(false);
        if (identical(animation, turn.animation)) break;
      }
      _pageTurn = null;
      // 沒停在目標上代表手指拖動接手了；位置歸使用者，由拖動結束時儲存。
      if (!controller.hasClients ||
          (position.pixels - turn.target).abs() >= _minimumViewportMovement) {
        return turn.finish(false);
      }
      await _handleScrollSettled();
      if (!isCurrent() || !controller.hasClients) return turn.finish(false);
      final atBookBoundary = forward
          ? _admission.atForwardBookBoundary
          : _admission.atBackwardBookBoundary;
      return turn.finish(
        isHybridPageMoveComplete(
          requestedDistance: turn.requestedDistance,
          actualDistance: (position.pixels - before).abs(),
          atBookBoundary: atBookBoundary,
        ),
      );
    } catch (_) {
      turn.finish(false);
      rethrow;
    } finally {
      if (identical(_pageTurn, turn)) _pageTurn = null;
    }
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
    final pipeline = _pipeline;
    final blocks = await pipeline.ensureChapter(
      safeChapter,
      priority: LayoutTaskPriority.anchor,
    );
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
    final leases = await pipeline.retainRange(blocks, start, end, isCurrent);
    try {
      if (!isCurrent()) return false;
      final rect = pipeline.geometry.rangeRect(blocks, start, end);
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

  /// 拖把手時 viewport 座標 [point] 在選取段落內最近的游標位置。
  int? _selectionCaretAt(ReaderTextSelection selection, Offset point) {
    final scrollOffset = _effectiveScrollOffset();
    if (scrollOffset == null) return null;
    return _pipeline.geometry.caretAt(
      selection,
      point.translate(0, scrollOffset),
    );
  }

  List<HybridLineBox> _selectionBoxes(ReaderTextSelection selection) {
    if (!_pipeline.geometry.isSelectionCurrent(selection)) {
      // 章節重新切分、換內容或樣式換代後，舊 offset 不再對應畫面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_selection.selection, selection)) {
          _clearSelection();
        }
      });
      return const <HybridLineBox>[];
    }
    return _lineBoxes(
      selection.chapterIndex,
      selection.range.start,
      selection.range.end,
    );
  }

  Future<void> _handleLongPressStart(LongPressStartDetails details) async {
    final request = ++_selectionRequest;
    final scrollOffset = _effectiveScrollOffset();
    final hit = scrollOffset == null
        ? null
        : _pipeline.geometry.glyphAt(
            details.localPosition.translate(0, scrollOffset),
          );
    if (hit == null) {
      _selection.clear();
      return;
    }
    unawaited(Feedback.forLongPress(context));
    final epoch = _pipeline.epoch;
    final paragraphText = hit.blocks.displayText.substring(
      hit.paragraph.start,
      hit.paragraph.end,
    );
    final word = await _wordSegmenter.wordAt(
      paragraphText,
      hit.offset - hit.paragraph.start,
    );
    if (!mounted ||
        request != _selectionRequest ||
        !widget.textSelectionEnabled ||
        epoch != _pipeline.epoch ||
        !identical(_pipeline.blocksOf(hit.blocks.chapterIndex), hit.blocks)) {
      return;
    }
    _selection.select(
      ReaderTextSelection(
        blocks: hit.blocks,
        epoch: epoch,
        paragraph: hit.paragraph,
        range: HybridTextRange(
          hit.paragraph.start + word.start,
          hit.paragraph.start + word.end,
        ),
      ),
    );
  }

  void _clearSelection() {
    _selectionRequest += 1;
    _selection.clear();
  }

  bool _dismissSelection() {
    if (!_selection.active) return false;
    _clearSelection();
    return true;
  }

  void _handleContentTapUp(TapUpDetails details) {
    // 選取中點正文只取消選取，不觸發翻頁或叫出選單。
    if (_selection.active) {
      _clearSelection();
      return;
    }
    widget.onContentTapUp?.call(details);
  }

  /// [start, end) 在 viewport 上的字形範圍，每條視覺行一個框（見
  /// [HybridTextGeometry.lineBoxes]）；每幀只扣掉捲動位置。
  List<HybridLineBox> _lineBoxes(int chapterIndex, int start, int end) {
    final offset = _effectiveScrollOffset();
    if (offset == null) return const <HybridLineBox>[];
    final world = _pipeline.geometry.lineBoxes(chapterIndex, start, end);
    return <HybridLineBox>[
      for (final box in world)
        HybridLineBox(
          left: box.left,
          top: box.top - offset,
          right: box.right,
          bottom: box.bottom - offset,
        ),
    ];
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

  /// 使用者甩出去的慣性還在跑：這時按下只是要停住它，放開不算點擊。
  /// 停住由原生 Scrollable 在同一個按下事件裡處理。翻頁等程式捲動不算，
  /// 連點翻頁時每一下都要生效。
  bool _isUserFlingInProgress() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    return controller.position.isScrollingNotifier.value && _sawUserScroll;
  }

  /// 紙上的骨架照哪些行畫。
  _PageLines? _veilLines() {
    if (_veilPage case final page?) return page;
    final opening = _openingPage;
    // 紙還沒掀開前版面就變了（例如轉向），記下的行對不上，先不畫；重新
    // 排版時改等第一頁。
    if (opening == null ||
        opening.layout !=
            ReaderSkeletonPage.layoutKeyOf(widget.runtime.state.layoutSpec)) {
      return null;
    }
    return (lines: opening.lines, titleLines: opening.titleLines);
  }

  Widget _buildVeil(ReaderV2State state) {
    final page = _veilLines();
    return LoadingVeil(
      controller: _veil,
      spec: state.layoutSpec,
      lines: page?.lines,
      titleLines: page?.titleLines ?? const <int>{},
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
    );
  }

  /// 蓋上紙，中間先空著（頁首頁尾照樣畫成骨架），等第一頁排好才照它淡入
  /// 骨架（ADR 0016）。開書有上次記下的那一頁時不走這裡，直接照紀錄畫。
  void _coverUntilFirstPage() {
    // 畫著的骨架照原樣淡掉，第一頁排好才換。
    _veilPage = _veilLines();
    _openingPage = null;
    _veilAwaitsPage = true;
    _veil.cover(skeleton: false);
  }

  /// 第一頁排好了：紙上照它的每一行淡入骨架，淡入播完才回來排前後其他頁
  /// （ADR 0016、0023）。
  Future<bool> _showFirstPageSkeleton(
    double offset,
    bool Function() isCurrent,
  ) async {
    _veilAwaitsPage = false;
    setState(() => _veilPage = _pageLinesAt(offset));
    _veil.showSkeleton();
    while (_veil.isSkeletonFading) {
      await _nextFrame();
      if (!isCurrent()) return false;
    }
    return isCurrent();
  }

  /// 書頭書尾都排進來時捲動停得住的位置：還原的捲動位置最後也夾在這裡
  /// （例如從書的最開頭開書，章名上方不留空）。
  double _clampToBook(double offset) {
    var result = offset;
    if (_admission.atForwardBookBoundary) {
      result = math.min(
        result,
        _documentIndex.afterExtent - _viewportSize.height,
      );
    }
    if (_admission.atBackwardBookBoundary) {
      result = math.max(result, -_documentIndex.beforeExtent);
    }
    return result;
  }

  /// 捲動位置在 [offset] 時畫面上每一行字的位置（viewport 座標），與其中
  /// 章名那幾行的索引。
  _PageLines _pageLinesAt(double offset) {
    final height = _viewportSize.height;
    final lines = <Rect>[];
    final titleLines = <int>{};
    final ranges = <int, (int, int)>{};
    for (final key in _documentIndex.keysInRange(offset, offset + height)) {
      final blocks = _pipeline.blocksOf(key.chapterIndex);
      if (blocks == null) continue;
      final range = blocks
          .blockForCharOffset(blocks.blockStartOffset(key))
          .charRange;
      final previous = ranges[key.chapterIndex];
      ranges[key.chapterIndex] = previous == null
          ? (range.start, range.end)
          : (
              math.min(previous.$1, range.start),
              math.max(previous.$2, range.end),
            );
    }
    void addLines(int chapter, int start, int end, {required bool title}) {
      if (end <= start) return;
      for (final box in _pipeline.geometry.lineBoxes(chapter, start, end)) {
        final top = box.top - offset;
        final bottom = box.bottom - offset;
        if (bottom <= 0 || top >= height) continue;
        if (title) titleLines.add(lines.length);
        lines.add(Rect.fromLTRB(box.left, top, box.right, bottom));
      }
    }

    for (final MapEntry(key: chapter, value: (start, end)) in ranges.entries) {
      // 章名在一章的最前面，和正文不會在同一行。
      var titleEnd = 0;
      for (final block in _pipeline.blocksOf(chapter)!.blocks) {
        if (!block.isTitle) break;
        titleEnd = block.charRange.end;
      }
      addLines(chapter, start, math.min(end, titleEnd), title: true);
      addLines(chapter, math.max(start, titleEnd), end, title: false);
    }
    return (lines: lines, titleLines: titleLines);
  }

  /// 上次離開這本書時的那一頁，開書的位置與版面都相同時才用。當時的進度
  /// 先放進進度通道，頁尾的進度骨架就照「本章 3/10」這類字樣的寬度畫；
  /// 排好後換成重算的進度（同一個位置，數字相同）。
  ReaderSkeletonPage? _rememberedPageForOpening() {
    final store = widget.skeletonPages;
    final bookUrl = widget.bookUrl;
    if (store == null || bookUrl == null) return null;
    final state = widget.runtime.state;
    final page = store.read(bookUrl);
    if (page == null ||
        !page.matches(state.visibleLocation, state.layoutSpec)) {
      return null;
    }
    final progress = page.progress;
    final notifier = widget.progressListenable;
    if (progress != null && notifier != null) {
      // 建構中不能通知別的元件重建，等這一幀畫完；這時骨架才剛開始淡入，
      // 看不出寬度換了。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && notifier.value == null) notifier.value = progress;
      });
    }
    return page;
  }

  /// 記下畫面上這一頁每一行字的位置與進度，下次從這裡開書時骨架照它畫。
  /// 正文還沒排好、紙還蓋著（跳章中）時不記：畫面上不是要記的那一頁。
  void _rememberPage() {
    final store = widget.skeletonPages;
    final bookUrl = widget.bookUrl;
    if (store == null || bookUrl == null) return;
    if (!_initialRestoreCompleted || _jumpVeil != null) return;
    final location = _captureVisibleLocation();
    final offset = _effectiveScrollOffset();
    if (location == null || offset == null) return;
    final contentHash = _pipeline.blocksOf(location.chapterIndex)?.contentHash;
    final (:lines, :titleLines) = _pageLinesAt(offset);
    if (lines.isEmpty || contentHash == null) return;
    unawaited(
      store.write(
        bookUrl,
        ReaderSkeletonPage(
          chapterIndex: location.chapterIndex,
          charOffset: location.charOffset,
          visualOffsetPx: location.visualOffsetPx,
          layout: ReaderSkeletonPage.layoutKeyOf(
            widget.runtime.state.layoutSpec,
          ),
          contentHash: contentHash,
          lines: lines,
          titleLines: titleLines,
          progress: widget.progressListenable?.value,
        ),
      ),
    );
  }

  Widget _buildLoading(ReaderV2State state) {
    final unavailable = state.lifecycle == ReaderV2Lifecycle.unavailable;
    final message = unavailable ? _friendlyErrorMessage : '正在準備閱讀內容';
    return ColoredBox(
      color: widget.backgroundColor,
      child: ReaderV2PointerTapLayer(
        onTapUp: widget.onContentTapUp,
        child: Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label: message,
          child: unavailable
              ? Center(
                  child: Padding(
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
                          style: AppTextStyles.bodyBase.copyWith(
                            color: widget.textColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              // 載入中不放轉圈與文字：紙上照一頁真正的每一行畫骨架（見
              // [LoadingVeilController] 與 ADR 0016）。
              : _buildVeil(state),
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
        final controller = _scrollController ??= HybridScrollController(
          initialScrollOffset: _pendingScrollOffset ?? 0.0,
          keepScrollOffset: false,
        );
        final highlight = widget.ttsHighlight;
        final visualContent = NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: HybridScrollView(
            centerKey: _centerKey,
            documentIndex: _documentIndex,
            namespace: _pipeline.namespace,
            measurementStore: _measurementStore,
            paragraphCache: _pipeline.paragraphCache,
            epoch: _pipeline.epoch,
            controller: controller,
            cacheExtent: _viewportSize.height,
            textColor: widget.textColor,
            horizontalPadding: EdgeInsets.only(
              left: state.layoutSpec.textPaddingLeft,
              right: state.layoutSpec.textPaddingRight,
            ),
            physics: _physics,
            // 跨在上下緣的段落畫到正文區外，閱讀頁框架只露出正文與頁首頁尾
            // 之間那段空隙，並在那裡漸隱（ReaderV2PageShell）。
            clipBehavior: Clip.none,
          ),
        );
        final readerStack = Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            visualContent,
            if (highlight != null && highlight.isValid)
              Positioned.fill(
                // 朗讀高亮只畫在正文可視區內，捲到邊緣的句子不會在邊距與
                // 頁尾區留下沒有字的色帶。
                child: ClipRect(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => HybridTtsHighlightOverlay(
                      sentence: _lineBoxes(
                        highlight.chapterIndex,
                        highlight.sentenceStart,
                        highlight.sentenceEnd,
                      ),
                      color: widget.highlightColor.withValues(
                        alpha: widget.highlightStrength,
                      ),
                    ),
                  ),
                ),
              ),
            // 正文剛排好時，蓋著的紙在上面淡出；等跳章的正文時紙攔下捲動。
            if (_veil.isVisible)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _jumpVeil == null,
                  child: _buildVeil(state),
                ),
              ),
          ],
        );
        // 長按與捲動在同一個手勢競技場：先拖動就是捲動，按住不動才選字。
        // 選取層在點擊層之外，按把手與選單不會被當成點正文。
        return ColoredBox(
          color: widget.backgroundColor,
          child: ReaderTextSelectionLayer(
            selection: _selection,
            repaint: controller,
            boxesFor: _selectionBoxes,
            caretAt: _selectionCaretAt,
            highlightColor: widget.highlightColor,
            child: ReaderV2PointerTapLayer(
              onTapUp: widget.onContentTapUp == null
                  ? null
                  : _handleContentTapUp,
              suppressTapAtPointerDown: _isUserFlingInProgress,
              child: GestureDetector(
                onLongPressStart:
                    widget.textSelectionEnabled && _jumpVeil == null
                    ? (details) => unawaited(_handleLongPressStart(details))
                    : null,
                child: readerStack,
              ),
            ),
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

/// 進行中的一次翻頁；連點時目標與距離會一路累加。
final class _PageTurn {
  _PageTurn({
    required this.forward,
    required this.target,
    required this.requestedDistance,
    required this.isCurrent,
  });

  final bool forward;
  final bool Function() isCurrent;
  final Completer<bool> finished = Completer<bool>();
  double target;
  double requestedDistance;
  late Future<void> animation;

  bool finish(bool completed) {
    if (!finished.isCompleted) finished.complete(completed);
    return completed;
  }
}

final class _HybridCommandQueue {
  Future<void>? _tail;
  int _queued = 0;
  bool get isBusy => _tail != null;

  /// 還沒完成的命令數，包含正在執行的那一個。
  int get queued => _queued;

  Future<bool> enqueue({
    required bool Function() isCurrent,
    required Future<bool> Function() command,
  }) {
    if (!isCurrent()) return Future<bool>.value(false);
    _queued += 1;
    final result = (_tail ?? Future<void>.value()).then((_) async {
      if (!isCurrent()) return false;
      final completed = await command();
      return isCurrent() && completed;
    });
    final drained = result.then<void>(
      (_) => _queued -= 1,
      onError: (Object _, StackTrace _) => _queued -= 1,
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

/// 一頁上每一行字的位置（viewport 座標，由上而下），與其中章名那幾行的
/// 索引。
typedef _PageLines = ({List<Rect> lines, Set<int> titleLines});
