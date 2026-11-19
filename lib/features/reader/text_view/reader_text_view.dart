import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton_reveal.dart';
import 'package:night_reader/features/reader/features/settings/reader_highlight_style.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_highlight.dart';
import 'package:night_reader/features/reader/layout/reader_style_preferences.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_operation_token.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/session/reader_state.dart';
import 'package:night_reader/features/reader/viewport/reader_pointer_tap_layer.dart';
import 'package:night_reader/features/reader/viewport/reader_viewport_controller.dart';

import 'anchor/anchor_manager.dart';
import 'core/progress_snapshot.dart';
import 'core/text_view_types.dart';
import 'measure/document_index.dart';
import 'measure/measurement_store.dart';
import 'overlay/bookmark_marks.dart';
import 'overlay/highlight_marks.dart';
import 'overlay/loading_veil.dart';
import 'overlay/paper_owners.dart';
import 'overlay/page_lines.dart';
import 'overlay/reader_mark_layers.dart';
import 'overlay/reader_skeleton_page.dart';
import 'overlay/reader_unavailable_message.dart';
import 'overlay/selection_service.dart';
import 'overlay/reader_text_selection_layer.dart';
import 'overlay/reader_text_touch.dart';
import 'pipeline/layout_disk_cache.dart';
import 'pipeline/layout_pipeline.dart';
import 'progress/progress_calculator.dart';
import 'pump/budget_governor.dart';
import '../use_cases/coordinators/reader_chapter_navigation_resolver.dart';
import 'text/chapter_text_window.dart';
import 'text/text_preprocessor.dart';
import 'view/admission_controller.dart';
import 'view/reader_scroll_controller.dart';
import 'view/reader_scroll_view.dart';
import 'view/viewport_commands.dart';

import 'package:night_reader/core/chinese/ui_language.dart';

class ReaderTextView extends StatefulWidget {
  const ReaderTextView({
    super.key,
    required this.runtime,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.onContentTapUp,
    this.viewportController,
    this.ttsHighlight,
    this.controlsVisible,
    this.textSelectionEnabled = false,
    this.onHideText,
    this.onReplaceText,
    this.onBookmarkText,
    this.marks,
    this.onHighlightText,
    this.highlights,
    this.onHighlightTap,
    this.highlightColor = const Color(0xFFFFC857),
    this.highlightStrength = ReaderHighlightStrength.defaultValue,
    this.progressListenable,
    this.bookUrl,
    this.skeletonPages,
    this.preprocessor = const TextPreprocessor(),
    this.enableDiskCache = true,
    this.paragraphCacheCapacity = 512,
    this.pageTurnOverlap = 1,
    this.pageTurnDuration = const Duration(milliseconds: 260),
    this.skeletonBreath,
  });

  /// 紙上骨架的呼吸，和呼叫端頁首頁尾的骨架共用（[SharedSkeletonBreathScope]）；
  /// null 時紙自己一口。建好後不換。
  final SharedSkeletonBreath? skeletonBreath;

  final ReaderRuntime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderStylePreferences style;
  final GestureTapUpCallback? onContentTapUp;
  final ReaderViewportController? viewportController;
  final ReaderTtsHighlight? ttsHighlight;

  /// 閱讀選單開著：點正文由選單的收起層處理（這裡不翻頁、不叫選單），
  /// 也不能選字，打開時清掉既有選取。只有點擊與長按那一層聽它，選單開關
  /// 時正文不重建。
  final ValueListenable<bool>? controlsVisible;

  /// 長按選字。朗讀與自動翻頁時由上層關閉；關閉時清掉既有選取。閱讀選單
  /// 開著時也不能選字（[controlsVisible]）。
  final bool textSelectionEnabled;

  /// 選字選單的「隱藏」：把選到的字（連同所在段落與段內位置）交給上層
  /// 新增替換規則；沒給就不顯示這個按鈕。
  final ValueChanged<ParagraphSelection>? onHideText;

  /// 選字選單的「替換」：把選到的字（連同所在段落與段內位置）交給上層，
  /// 打開替換規則的編輯畫面；沒給就不顯示這個按鈕。
  final ValueChanged<ParagraphSelection>? onReplaceText;

  /// 選字選單的「書籤」：在選到的字那一句的開頭留一個書籤
  /// （[ReaderTextSelection.asBookmark]）。沒給就不顯示這個按鈕。
  final ValueChanged<SelectionBookmark>? onBookmarkText;

  /// 這本書的書籤，在那一行旁畫記號（[BookmarkMarksOverlay]）。
  final ValueListenable<List<ReaderMark>>? marks;

  /// 選字選單「⋮」裡的「標註」：把選到的字畫上標註
  /// （[ReaderTextSelection.asHighlight]）。沒給就不顯示這個按鈕。
  final ValueChanged<SelectionHighlight>? onHighlightText;

  /// 這本書的標註，在字上畫底色或底線（[HighlightMarksOverlay]）。
  final ValueListenable<List<ReaderHighlightMark>>? highlights;

  /// 點到已畫的標註（給標註的編號）；沒給時點標註和點別處一樣。
  final ValueChanged<int>? onHighlightTap;

  /// 朗讀高亮與選字反白的顏色；[highlightStrength] 只套在朗讀高亮，選字
  /// 反白固定深淺以保持可辨識。
  final Color highlightColor;
  final double highlightStrength;
  final ValueNotifier<ProgressSnapshot?>? progressListenable;
  final String? bookUrl;

  /// 每本書上一次離開時的那一頁（ADR 0024）：開書時從同一處打開就照它畫
  /// 骨架；離開閱讀器或 App 切到背景時記下目前這一頁。
  final ReaderSkeletonPageStore? skeletonPages;
  final TextPreprocessor preprocessor;
  final bool enableDiskCache;
  final int paragraphCacheCapacity;

  /// 翻頁時上一屏留在畫面上的行數，與捲過一屏要多久。
  final int pageTurnOverlap;
  final Duration pageTurnDuration;

  @override
  State<ReaderTextView> createState() => _ReaderTextViewState();
}

class _ReaderTextViewState extends State<ReaderTextView>
    with TickerProviderStateMixin {
  static const String _friendlyErrorMessage = '閱讀內容暫時無法顯示，請稍後再試';
  final GlobalKey _centerKey = GlobalKey(debugLabel: 'text-view-center-sliver');
  final MeasurementStore _measurementStore = MeasurementStore();
  final DocumentIndex _documentIndex = DocumentIndex(
    centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
  );
  final BudgetGovernor _governor = BudgetGovernor();
  final ReaderScrollPhysics _physics = const ReaderScrollPhysics();
  late ChapterTextWindow _chapterRepo;
  late final AdmissionController _admission;
  LayoutDiskCache? _diskCache;

  /// 目前排版世代的排版管線；排版或內容換代時整份換新（見
  /// [_handleEpochRebuild]）。
  late LayoutPipeline _pipeline;
  StreamSubscription<ChapterEvent>? _chapterEventsSub;
  ReaderScrollController? _scrollController;
  Size _viewportSize = Size.zero;

  /// 書籤記號、標註與朗讀高亮的行框，照目前這一代排版管線算。
  late final ReaderMarkGeometry _marks = ReaderMarkGeometry(
    pipeline: () => _pipeline,
    documentIndex: _documentIndex,
    scrollOffset: _effectiveScrollOffset,
  );

  /// 還原已經排好、原生捲動位置還沒套上時要停的錨點。位置不存成數字，
  /// 每次照當下的大小與範圍用 [_restingOffset] 算：等 viewport 的這幾幀
  /// 正文區變了大小，建立捲動時用的也是新的位置。
  ({ScrollAnchor anchor, ChapterBlocks blocks})? _pendingAnchor;

  double? get _pendingScrollOffset {
    final pending = _pendingAnchor;
    return pending == null
        ? null
        : _restingOffset(pending.anchor, pending.blocks);
  }

  ReaderOperationToken? _demandOwner;
  int _windowCenter = 0;
  int _lastLayoutGeneration = 0;
  int _lastContentGeneration = 0;
  int _runtimeLocationRevision = 0;

  /// 視窗還原的世代：只有新的還原與排版世代重建會讓進行中的還原作廢。
  /// 使用者捲動或停止自動捲動不會；跳轉被使用者捲動取代時，由 Runtime
  /// 放棄該操作。
  int _restoreRevision = 0;
  ReaderLocation? _lastReportedLocation;

  /// 最近一次還原到的位置，畫面還沒離開它之前量到的位置就是它
  /// （[_unmovedRestoredLocation]）；畫面一離開就清掉。
  ReaderLocation? _restoredLocation;

  /// 正文現在在哪一段：排版中、等掀紙、在畫面上（[_TextStage]）。
  _TextStage _stage = const _LayingOut();

  /// 正文照目前的排版排好了（等掀紙或在畫面上）。
  bool get _textLaidOut => _stage is! _LayingOut;

  /// 手指對正文做什麼；正文回到排版中時一律是沒有。
  _FingerScroll _finger = _FingerScroll.none;

  /// 進行中的還原要的排版預算與是哪一次還原；沒有時照 [_finger]。
  ({bool Function() owner, PumpState state})? _restoreBudget;

  /// 紙現在歸誰：等正文的跳章（[_syncJumpVeil]）、進行中的還原
  /// （[_restoreCore]）、重新還原最後的穩定位置（[_syncStableWorld]）；都沒有
  /// 時由 [_releasePaper] 掀紙或重新還原。
  final PaperOwners _paper = PaperOwners();

  /// 紙開始蓋住正文那一刻的捲動位置；紙下的正文停在這裡，蓋紙的操作
  /// 取消或失敗、掀開紙回到的就是這個位置（見 [_veilHoldsText]）。
  double? _veilHoldOffset;
  late final LoadingVeilController _veil = LoadingVeilController(
    vsync: this,
    breath: widget.skeletonBreath,
    onHidden: () {
      // 紙掀完了；下一次蓋紙另外決定照什麼畫骨架。
      _openingPage = null;
      _veilPage = null;
      if (mounted) setState(() {});
    },
  );

  /// 舊正文還在畫面上、紙正在淡入蓋住它時，紙停下來（蓋滿或途中掀開）
  /// 後完成；其他時候為 null（見 [_coverText]）。
  Future<void>? _covering;

  /// 開書的位置與版面都和上次記下的那一頁相同時，開書的紙照它畫骨架。
  ReaderSkeletonPage? _openingPage;

  /// 紙上的骨架照這一頁畫：開書時的紀錄，或這次排好的第一頁。紙重新
  /// 蓋上時留著，畫著的骨架照原樣淡完才換（見 [_fadeInPageSkeleton]）。
  PageLines? _veilPage;

  /// App 切到背景時記下目前這一頁（之後可能被系統關掉，不會再走到
  /// [dispose]）。
  late final AppLifecycleListener _lifecycle;

  /// 這一幀結束時已經排了一次重建（[_scheduleRebuild]）、一次量位置
  /// （[_scheduleMotionCapture]）：一幀各只做一次。不是階段，任何階段都可能。
  bool _rebuildQueued = false;
  bool _captureFramePending = false;

  /// 點擊、長按與選字（[ReaderTextTouch]）。
  late final ReaderTextTouch _touch = ReaderTextTouch(
    pipeline: () => _pipeline,
    documentIndex: _documentIndex,
    marks: _marks,
    scrollOffset: _effectiveScrollOffset,
    context: () => context,
    mounted: () => mounted,
    selectionAllowed: () => widget.textSelectionEnabled && !_controlsVisible,
    highlights: () => widget.highlights?.value,
    onHighlightTap: () => widget.onHighlightTap,
    onContentTapUp: () => widget.onContentTapUp,
  );

  @override
  void initState() {
    super.initState();
    _chapterRepo = ChapterTextWindow(
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
    if (_openingPage case final page?) {
      _veilPage = (
        lines: page.lines,
        titleLines: page.titleLines,
        blockLines: page.blockLines,
        spec: widget.runtime.state.layoutSpec,
      );
      _veil.cover();
    } else {
      _coverUntilFirstPage();
    }
    _lifecycle = AppLifecycleListener(onHide: _rememberPage);
    widget.controlsVisible?.addListener(_onControlsVisibleChanged);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreAttachedRuntime();
    });
  }

  void _registerRuntime() {
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.addViewportGeometryListener(_onViewportGeometryChanged);
    widget.runtime.chapterShares.addListener(_publishProgress);
    widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
  }

  void _unregisterRuntime(ReaderRuntime runtime) {
    runtime.removeListener(_onRuntimeChanged);
    runtime.removeViewportGeometryListener(_onViewportGeometryChanged);
    runtime.chapterShares.removeListener(_publishProgress);
    runtime.unregisterVisibleLocationCapture(this);
    runtime.unregisterViewportRestore(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _veil.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _veil.skeletonReveal = SkeletonReveal.of(context);
  }

  @override
  void didUpdateWidget(covariant ReaderTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _unregisterRuntime(oldWidget.runtime);
      _chapterEventsSub?.cancel();
      unawaited(_chapterRepo.dispose());
      _chapterRepo = ChapterTextWindow(
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
    if (!identical(oldWidget.controlsVisible, widget.controlsVisible)) {
      oldWidget.controlsVisible?.removeListener(_onControlsVisibleChanged);
      widget.controlsVisible?.addListener(_onControlsVisibleChanged);
    }
    if (oldWidget.runtime != widget.runtime ||
        !widget.textSelectionEnabled ||
        _controlsVisible) {
      _touch.clear();
    }
  }

  bool get _controlsVisible => widget.controlsVisible?.value ?? false;

  void _onControlsVisibleChanged() {
    if (_controlsVisible) _touch.clear();
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
    widget.controlsVisible?.removeListener(_onControlsVisibleChanged);
    _unregisterRuntime(widget.runtime);
    _detachController(widget.viewportController);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _chapterEventsSub?.cancel();
    _pipeline.dispose();
    unawaited(_chapterRepo.dispose());
    _admission.dispose();
    _scrollController?.dispose();
    _touch.dispose();
    if (_stage case _AwaitingReveal(:final stillGap)) stillGap?.cancel();
    _veil.dispose();
    super.dispose();
  }

  /// 正文照目前的排版排好了沒；排好時走到等掀紙，回到排版中時蓋上 [_veil]、
  /// 手指的捲動跟著正文一起拿掉。
  void _setTextLaidOut(bool laidOut) {
    // 排版流程接手這張紙，等正文的跳章不再另外管它。
    _paper.restoreTookOverJump();
    if (_textLaidOut == laidOut) return;
    if (laidOut) {
      _revealWhenStill();
    } else {
      _cancelPendingReveal();
      _stage = const _LayingOut();
      _setFinger(_FingerScroll.none);
      _coverUntilFirstPage();
    }
  }

  /// 正文排好、要掀紙，照開 App 換場的順序（ADR 0035、0037 策略一、二）：
  /// 骨架的呼吸先收住（每個位置把這一口呼完、停在最深），畫面靜止後才在
  /// 整張蓋著的紙底下建好、畫出正文，畫完再停 [AppMotion.stillGap] 才掀紙；
  /// 掀紙時骨架停在最深不再呼吸，掀紙的每一幀都不做重的工作。2026-11-05
  /// 手機上開書，建正文那一幀主執行緒 12.9ms、第一次畫整頁字的繪製
  /// 25.6ms；原本在呼吸途中把呼吸凍在當下的深淺來建正文，掀紙時再接著
  /// 呼吸，看起來呼吸播到一半就頓住、和字一起出來（使用者 2026-11-07）。
  ///
  /// 從排版中來時正文還沒建在紙底下（開書、跳章、重排後第一次排好）：收住
  /// 的這段期間正文先不建，重建也只畫紙；從在畫面上來時（蓋紙的操作結束、
  /// 掀回舊正文）正文本來就在。
  void _revealWhenStill() {
    final reveal = SkeletonReveal.of(context);
    final awaiting = _AwaitingReveal(textBuilt: _stage is _Shown);
    _stage = awaiting;
    bool current() => mounted && identical(_stage, awaiting);
    unawaited(() async {
      await _veil.settleBreath();
      if (!current()) return;
      if (!awaiting.textBuilt) {
        awaiting.textBuilt = true;
        _scheduleRebuild();
      }
      // 排好的重建在這一幀結束時才 setState，正文在下一幀才建好、畫出：
      // 停頓從那一幀之後才算，不讓建正文的時間吃掉它。
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      awaiting.stillGap = Timer(AppMotion.stillGap, () {
        if (!current()) return;
        _stage = const _Shown();
        _veil.reveal(reveal);
        // 掀開中的紙不攔觸控：紙上那層的攔不攔照重建時的狀態。
        _scheduleRebuild();
      });
    }());
  }

  /// 又要蓋紙：等著掀的那一次作廢，收住的呼吸接著走；還沒建的正文照常
  /// 建在紙底下，之後的流程當它已經在。
  void _cancelPendingReveal() {
    final awaiting = _stage;
    if (awaiting is! _AwaitingReveal) return;
    awaiting.stillGap?.cancel();
    _stage = const _Shown();
    if (!awaiting.textBuilt) _scheduleRebuild();
    _veil.resumeBreath();
  }

  /// 換手指的捲動，排版預算跟著換。
  void _setFinger(_FingerScroll finger) {
    if (_finger == finger) return;
    _finger = finger;
    _syncPumpState();
  }

  /// 這次還原（[owner]）要的排版預算：還原進行中照它，不照手指。
  void _setRestoreBudget(bool Function() owner, PumpState state) {
    _restoreBudget = (owner: owner, state: state);
    _syncPumpState();
  }

  /// [owner] 那次還原結束：預算還是它的就交回手指；已經有接手的還原寫了
  /// 自己的，不動（被取代的還原照手指寫回，會蓋掉接手那次的載入中）。
  void _endRestoreBudget(bool Function() owner) {
    if (!identical(_restoreBudget?.owner, owner)) return;
    _restoreBudget = null;
    _syncPumpState();
  }

  /// 排版每幀的預算（ADR 0018）只在這裡寫：進行中的還原要的，其他時候照
  /// 手指。
  void _syncPumpState() =>
      _pipeline.onScrollStateChanged(_restoreBudget?.state ?? _finger.pump);

  static LayoutDiskCache? _diskCacheFor(ReaderTextView widget) {
    final bookUrl = widget.bookUrl;
    if (!widget.enableDiskCache || bookUrl == null) return null;
    return LayoutDiskCache(bookUrl: bookUrl);
  }

  LayoutPipeline _createPipeline() {
    final state = widget.runtime.state;
    return LayoutPipeline(
      epoch: LayoutEpoch(
        state.layoutGeneration,
        contentGeneration: state.contentGeneration,
      ),
      layoutSpec: () => widget.runtime.state.layoutSpec,
      publishedEpoch: () {
        final state = widget.runtime.state;
        return LayoutEpoch(
          state.layoutGeneration,
          contentGeneration: state.contentGeneration,
        );
      },
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

  /// Runtime 已經發布新的排版或內容世代，排版管線（與畫面上的正文）還是
  /// 舊的：等紙蓋滿才換代（[_handleEpochRebuild]），換代會拿掉舊正文。
  bool get _textOutdated {
    final state = widget.runtime.state;
    final epoch = _pipeline.epoch;
    return epoch.value != state.layoutGeneration ||
        epoch.contentGeneration != state.contentGeneration;
  }

  void _handleEpochRebuild() {
    _runtimeLocationRevision += 1;
    _restoreRevision += 1;
    _setTextLaidOut(false);
    _pipeline.dispose();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _documentIndex.reset(centerKey: _documentIndex.centerKey);
    _pipeline = _createPipeline();
  }

  /// 還原到 [location]，期間紙歸這次還原管。沒有完成（作廢或失敗）時交給
  /// [_releasePaper]：沒有操作接手就掀紙回到舊正文，舊正文已經拆掉時重新
  /// 還原最後的穩定位置。
  Future<bool> _restoreCore(
    ReaderLocation location, {
    required bool Function() isCurrent,
    ReaderOperationKind? operationKind,
  }) async {
    if (!isCurrent() || widget.runtime.chapterCount <= 0) return false;
    _paper.beginRestore(isCurrent);
    var restored = false;
    try {
      restored = await _runRestore(
        location,
        isCurrent: isCurrent,
        operationKind: operationKind,
      );
      return restored;
    } finally {
      _paper.endRestore(isCurrent);
      if (!restored) _releasePaper();
    }
  }

  Future<bool> _runRestore(
    ReaderLocation location, {
    required bool Function() isCurrent,
    ReaderOperationKind? operationKind,
  }) async {
    // 舊正文還在畫面上（例如朗讀念到還沒載入的一章）：紙先淡入蓋住，蓋滿
    // 才開始排版（ADR 0018）。
    _coverText();
    if (!await _awaitCovered() || !isCurrent()) return false;
    // 開書、跳章與重新定位都是使用者的動作：之前取不到的章節都再試一次。
    _chapterRepo.forgetFailures();
    final pipeline = _pipeline;
    final chapter = location.chapterIndex
        .clamp(0, widget.runtime.chapterCount - 1)
        .toInt();
    _windowCenter = chapter;
    pipeline.demandAround(chapter);
    pipeline.clearPendingLayouts();
    _setRestoreBudget(
      isCurrent,
      _textLaidOut ? PumpState.rebuilding : PumpState.loading,
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
          operationKind == ReaderOperationKind.open ||
          operationKind == ReaderOperationKind.jump;

      final normalized = location.normalized(
        chapterCount: widget.runtime.chapterCount,
        chapterLength: blocks.displayText.length,
      );
      final anchor = ScrollAnchor.fromLocation(normalized, blocks);
      _setTextLaidOut(false);
      // 只有開書時位置、版面與正文都和紀錄相同才照紀錄畫；其他還原（包括
      // 取代了還沒排完的開書或另一個還原）一律重新等自己的第一頁。
      final opening = _openingPage;
      final keepsOpeningPage =
          opening != null &&
          opening.contentHash == blocks.contentHash &&
          opening.layout == ReaderSkeletonPage.layoutKeyOf(pipeline.layoutSpec);
      if (!keepsOpeningPage) _coverUntilFirstPage();
      _setRestoreBudget(isCurrent, PumpState.loading);
      _scheduleRebuild();
      pipeline.resetDocument(anchor.blockKey);
      if (!keepsOpeningPage &&
          !await _showFirstPage(anchor, blocks, isCurrent: isCurrent)) {
        return false;
      }
      Future<bool> layOut() async {
        final target = await _layOutAround(
          anchor,
          blocks,
          withLead: operationOwnsReadyWorld,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return false;
        if (target == null) {
          throw StateError(
            'Text view restore target has no admitted anchor geometry after '
            'materialization completed.',
          );
        }
        return true;
      }

      if (!await layOut()) return false;
      var laidOutFor = _viewportSize;
      _pendingAnchor = (anchor: anchor, blocks: blocks);
      _lastReportedLocation = normalized;
      _setTextLaidOut(true);
      _setRestoreBudget(isCurrent, PumpState.rebuilding);
      _scheduleRebuild();
      while (true) {
        // Return only after the native viewport exists and has applied the
        // position. This is a Flutter frame transaction, not a prefetch
        // barrier.
        do {
          await _nextFrame();
          if (!isCurrent()) return false;
        } while (_rebuildQueued || !(_scrollController?.hasClients ?? false));
        if (_viewportSize == laidOutFor) break;
        // 等這幾幀時正文區的大小變了：要排好的範圍跟著高度走，照新的大小
        // 排好、等 viewport 套上新的範圍再提交。
        laidOutFor = _viewportSize;
        if (!await layOut()) return false;
      }
      // 照提交這一刻的大小與範圍算停住的位置，不用再夾。
      _scrollController!.position.jumpTo(_restingOffset(anchor, blocks)!);
      _pendingAnchor = null;
      await _nextFrame();
      if (!isCurrent()) return false;
      _reconcileVisibleWindow();
      _publishProgress();
      return true;
    } finally {
      if (mounted) _endRestoreBudget(isCurrent);
    }
  }

  /// 還原到 [anchor] 時捲動最後停住的位置：錨點那一行對到錨線的位置，在
  /// 正文不會再變多的一側（[LayoutPipeline.edgeFinal]）夾進可捲的
  /// 範圍，和 viewport 自己夾的一樣（有中心 sliver：最小
  /// min(0, −beforeExtent)，最大 max(0, afterExtent − 高)）。還會排進正文
  /// 的一側不夾，範圍還會變大。第一頁的骨架、還原前要排好的範圍與最後的
  /// `jumpTo` 都照這個位置，錨點還沒排進來時回傳 null。
  double? _restingOffset(ScrollAnchor anchor, ChapterBlocks blocks) {
    final offset = _offsetForAnchor(anchor, blocks);
    if (offset == null) return null;
    var result = offset;
    if (_pipeline.edgeFinal(forward: true)) {
      result = math.min(
        result,
        math.max(0.0, _documentIndex.afterExtent - _viewportSize.height),
      );
    }
    if (_pipeline.edgeFinal(forward: false)) {
      result = math.max(result, math.min(0.0, -_documentIndex.beforeExtent));
    }
    return result;
  }

  /// 捲動停在 [resting] 時還原完成前要排好的範圍：那一屏；[withLead] 時
  /// 再加上前後的領先量（開書與跳章，和平常捲動時相同，第一個能操作的
  /// 畫面不用等手勢再補）。正文不會再變多的一側只到排好的邊緣為止。
  ({double top, double bottom}) _readyWindow(
    double resting, {
    required bool withLead,
  }) {
    var top = resting;
    var bottom = resting + math.max(1, _viewportSize.height);
    if (withLead) {
      top -= _admission.backwardGuaranteedWindow;
      bottom += _admission.guaranteedWindow;
    }
    if (_pipeline.edgeFinal(forward: false)) {
      top = math.max(top, -_documentIndex.beforeExtent);
    }
    if (_pipeline.edgeFinal(forward: true)) {
      bottom = math.min(bottom, _documentIndex.afterExtent);
    }
    return (top: top, bottom: bottom);
  }

  /// 排到捲動停在 [anchor] 時 [_readyWindow] 的正文都排好，回傳停住的位置。
  /// 剛取不到的章節讓那一側不再變多、停住的位置跟著移動時，照新的位置
  /// 再排；再也排不進更多時照已經排好的回傳。錨點一直沒排進來或作廢時
  /// 回傳 null。
  Future<double?> _layOutAround(
    ScrollAnchor anchor,
    ChapterBlocks blocks, {
    required bool withLead,
    required bool Function() isCurrent,
  }) async {
    final pipeline = _pipeline;
    while (isCurrent()) {
      final revision = _documentIndex.revisionNumber;
      final requested = _readyWindow(
        _restingOffset(anchor, blocks) ?? 0,
        withLead: withLead,
      );
      pipeline.requestWindow(
        requested.top,
        requested.bottom,
        anchorKey: anchor.blockKey,
      );
      final resting = _restingOffset(anchor, blocks);
      if (resting != null) {
        final ready = _readyWindow(resting, withLead: withLead);
        if (pipeline.windowReady(ready.top, ready.bottom)) return resting;
      }
      // Cached exact metrics may advance admission synchronously, without
      // creating a layout task. Re-evaluate that progress before waiting.
      if (_documentIndex.revisionNumber != revision) continue;
      switch (await pipeline.waitForProgress(isCurrent)) {
        case MaterializationWait.progressed:
          continue;
        case MaterializationWait.frontierUnavailable:
          final settled = _restingOffset(anchor, blocks);
          if (settled != null && settled != resting) continue;
          return settled;
        case MaterializationWait.cancelled:
          return null;
      }
    }
    return null;
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
    if (!mounted || !_textLaidOut) return;
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
    if (_veilHoldsText) {
      // 紙蓋上前就按下的手指，在紙下開始拖動：不算使用者接手、不取消
      // 蓋紙的跳章或還原，拖動作廢並回到蓋紙那一刻的位置。
      if (_isDragNotification(notification)) {
        scheduleMicrotask(_holdScrollUnderVeilAgain);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      // 拖動真的推動正文才算使用者接手捲動。正文上只有捲動手勢時，
      // 原生 Scrollable 連單純的點擊也會發出零位移的拖動開始。
      final byFinger = notification.dragDetails != null;
      if (byFinger && _finger != _FingerScroll.dragging) {
        _touch.clear();
        _runtimeLocationRevision += 1;
        widget.runtime.cancelJumpForUserScroll();
        _setFinger(_FingerScroll.dragging);
      } else if (!byFinger && _finger == _FingerScroll.dragging) {
        _setFinger(_FingerScroll.flinging);
      }
      _scheduleMotionCapture();
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      // 停在可捲範圍盡頭再往外拖，正文不動、只有 overscroll；手勢結束時
      // 一樣要檢查那個邊緣是不是取不到的章節。
      if (_finger == _FingerScroll.none) {
        _setFinger(_FingerScroll.pullingAtEdge);
      }
    } else if (notification is ScrollEndNotification) {
      final wasUser = _finger != _FingerScroll.none;
      _setFinger(_FingerScroll.none);
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
    if (position.pixels >= position.maxScrollExtent - minimumViewportMovement) {
      _retryUnavailableFrontier(forward: true);
    }
    if (position.pixels <= position.minScrollExtent + minimumViewportMovement) {
      _retryUnavailableFrontier(forward: false);
    }
  }

  /// 已排好的正文在章節邊緣結束、而相鄰章節取不到時：把取不到的原因
  /// 告訴使用者，並重試一次那一章。只在使用者捲到或翻到這個邊緣時呼叫，
  /// 不會在背景反覆請求。
  void _retryUnavailableFrontier({required bool forward}) {
    final unavailable = _pipeline.unavailableFrontier(forward: forward);
    if (unavailable == null) return;
    if (widget.runtime.chapterAt(unavailable.chapter)?.isLocked ?? false) {
      _skipLockedChapters(from: unavailable.chapter, forward: forward);
      return;
    }
    widget.runtime.emitUserNotice(
      unavailable.failure.message,
      chapterIndex: unavailable.chapter,
    );
    _pipeline.retryChapter(unavailable.chapter);
  }

  /// 捲到或翻到付費章節前（ADR 0057）：這一側還有免費章節就跳過去，
  /// 都是付費章節就停在這裡說明。付費章節不抓，不用重試。
  void _skipLockedChapters({required int from, required bool forward}) {
    final runtime = widget.runtime;
    final target = ReaderChapterNavigationResolver.resolveRelativeTarget(
      currentChapterIndex: from,
      chapterCount: runtime.chapterCount,
      delta: forward ? 1 : -1,
      skip: (index) => runtime.chapterAt(index)?.isLocked ?? false,
    );
    if (target == null) {
      runtime.emitUserNotice(lockedChapterNotice, chapterIndex: from);
      return;
    }
    unawaited(runtime.jumpToChapter(target));
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending || !mounted) return;
    _captureFramePending = true;
    final revision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted || !_textLaidOut || revision != _runtimeLocationRevision) {
        return;
      }
      if (widget.runtime.pendingLocation != null) return;
      final location = _captureAndReport();
      if (location != null) _windowCenter = location.chapterIndex;
      _reconcileVisibleWindow();
      _publishProgress();
    });
  }

  Future<void> _handleScrollSettled() async {
    if (!mounted || !_textLaidOut || widget.runtime.pendingLocation != null) {
      return;
    }
    final location = _captureAndReport();
    if (location != null) _windowCenter = location.chapterIndex;
    _reconcileVisibleWindow();
    _publishProgress();
    await widget.runtime.saveProgress(immediate: true);
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
      // 舊正文還在畫面上時，紙先淡入蓋住，蓋滿才換代（ADR 0018）。
      _coverText();
      if (_covering == null) _handleEpochRebuild();
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
    if (state.hasStableWorld && _textLaidOut) {
      _demandOwner = null;
      _reconcileVisibleWindow();
      _publishProgress();
    }
    // 蓋紙的操作結束了（取不到正文、被取代後接手的操作又失敗），或沒有
    // 操作時內容換代：沒有人接手時掀紙或重新還原。
    _releasePaper();
    _scheduleRebuild();
  }

  /// 跳章一開始就蓋紙：正文還在取得時，舊正文不留在畫面上，紙也攔下捲動。
  /// 排版開始後由 [_restoreCore] 接手；跳章在那之前就結束時，紙交給接手的
  /// 操作，沒有操作接手就由 [_releasePaper] 掀開，舊正文原封不動。
  void _syncJumpVeil(ReaderOperationToken? operation) {
    final jump = operation?.kind == ReaderOperationKind.jump ? operation : null;
    if (!_paper.claimForJump(jump, textShown: _textLaidOut)) {
      return;
    }
    _touch.clear();
    _coverText();
  }

  /// 紙正蓋著畫面上的正文（淡入中或已蓋滿，不是正在掀開）：紙攔下捲動、
  /// 長按與翻頁，紙下的正文停在蓋紙那一刻的位置。
  bool get _veilHoldsText =>
      _textLaidOut && _veil.isVisible && !_veil.isRevealing;

  /// 停住紙下正在跑的捲動（甩動的慣性、已經開始的拖動），固定在蓋紙那一刻
  /// 的位置。`jumpTo` 會結束目前的捲動活動，進行中的拖動也一併作廢。
  void _holdScrollUnderVeil() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    _veilHoldOffset = position.pixels;
    position.jumpTo(position.pixels);
    _setFinger(_FingerScroll.none);
  }

  void _holdScrollUnderVeilAgain() {
    final offset = _veilHoldOffset;
    final controller = _scrollController;
    if (!mounted ||
        !_veilHoldsText ||
        offset == null ||
        controller == null ||
        !controller.hasClients) {
      return;
    }
    controller.position.jumpTo(offset);
  }

  /// 蓋在正文上的紙沒有人要用了：蓋紙的操作或還原結束、作廢，也沒有別的
  /// 操作或還原接手（接手的自己會蓋紙、排版、掀紙，這裡不掀別人的紙）。
  /// 紙下的舊正文仍照目前的排版與內容排著，就掀紙露出它；舊正文已經拆掉
  /// 或過時（新的排版世代已經發布），就重新還原最後的穩定位置再掀紙。
  void _releasePaper() {
    if (!mounted ||
        !_paper.isFree(
          hasOperation: widget.runtime.stateMachine.currentOperation != null,
        )) {
      return;
    }
    if (!_textLaidOut || _textOutdated) {
      _syncStableWorld();
      return;
    }
    if (!_veilHoldsText || _stage is _AwaitingReveal) return;
    _revealWhenStill();
  }

  /// 沒有操作負責正文、Runtime 也有穩定的位置，畫面上卻沒有照目前世代
  /// 排好的正文時（被取代的還原、接手的操作又失敗；沒有操作時內容換代），
  /// 照目前的排版重新還原那個位置：紙先蓋住舊正文、蓋滿才換代，排好再掀紙。
  /// 開始新的操作時這次還原作廢，交給那個操作。
  void _syncStableWorld() {
    final runtime = widget.runtime;
    if (!mounted ||
        !_paper.isFree(
          hasOperation: runtime.stateMachine.currentOperation != null,
        ) ||
        !runtime.state.hasStableWorld ||
        (_textLaidOut && !_textOutdated)) {
      return;
    }
    if (!_paper.beginStableWorld()) return;
    final generations = (
      runtime.state.layoutGeneration,
      runtime.state.contentGeneration,
    );
    unawaited(
      Future<void>.microtask(() async {
        var restored = false;
        try {
          if (mounted &&
              identical(widget.runtime, runtime) &&
              runtime.stateMachine.currentOperation == null) {
            restored = await _restoreToLocation(runtime.state.visibleLocation);
          }
        } finally {
          _paper.endStableWorld();
        }
        // 還原途中又換代（沒有操作時內容換代）而作廢：照新的世代再還原一次。
        // 取不到正文這類失敗不重試，免得一直重抓。
        if (!restored &&
            mounted &&
            identical(widget.runtime, runtime) &&
            generations !=
                (
                  runtime.state.layoutGeneration,
                  runtime.state.contentGeneration,
                )) {
          _syncStableWorld();
        }
      }),
    );
  }

  static bool _isDragNotification(ScrollNotification notification) =>
      (notification is ScrollStartNotification &&
          notification.dragDetails != null) ||
      (notification is ScrollUpdateNotification &&
          notification.dragDetails != null) ||
      (notification is OverscrollNotification &&
          notification.dragDetails != null);

  void _restoreAttachedRuntime() {
    final runtime = widget.runtime;
    if (runtime.state.hasStableWorld) {
      unawaited(runtime.restoreFromLocation(runtime.state.visibleLocation));
    }
  }

  ReaderLocation? _captureForBridge() {
    final location = _captureVisibleLocation();
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  ReaderLocation? _captureVisibleLocation() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return null;
    final anchorLine = AnchorManager.anchorOffsetInViewport(
      _viewportSize.height,
    );
    final unmoved = _unmovedRestoredLocation(offset);
    if (unmoved != null) return unmoved;
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

  /// 還原後畫面沒動過，就回傳還原到的位置。從畫面量位置記的是錨線上那一行
  /// 的行首；還原的位置常在行中間（朗讀的句首、另一台手機或換字級前存的
  /// 進度），沒捲動就重新量會變成行首，進度小幅往回跳，每換一次排版就再
  /// 往回退一點。捲動位置等於還原到它會停的位置，就是沒動過；上方補進
  /// 章節而調整捲動時兩邊一起變，也算沒動過。
  ReaderLocation? _unmovedRestoredLocation(double offset) {
    final restored = _restoredLocation;
    if (restored == null) return null;
    final blocks = _pipeline.blocksOf(restored.chapterIndex);
    // 和還原最後停的位置同一套算法：書首、書尾那一行到不了錨線，還原時
    // 夾進可捲的範圍。
    final expected = blocks == null
        ? null
        : _restingOffset(ScrollAnchor.fromLocation(restored, blocks), blocks);
    if (expected == null || (expected - offset).abs() > 0.5) {
      _restoredLocation = null;
      return null;
    }
    return restored;
  }

  ReaderLocation? _preserveShortChapterAtBoundary({
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

  /// 還原到 [location]。有操作時屬於那個操作；沒有操作時（重新還原穩定
  /// 位置，見 [_syncStableWorld]）一開始新的操作就作廢。
  Future<bool> _restoreToLocation(ReaderLocation location) async {
    final runtime = widget.runtime;
    final operation = runtime.stateMachine.currentOperation;
    bool owned() => operation == null
        ? runtime.stateMachine.currentOperation == null
        : runtime.isCurrentOperationToken(operation);
    // 紙先蓋住畫面上的舊正文；換代等紙蓋滿才做，還原要用換代後的排版管線。
    _coverText();
    if (!await _awaitCovered()) return false;
    if (!identical(widget.runtime, runtime) || !owned()) return false;
    final pipeline = _pipeline;
    _runtimeLocationRevision += 1;
    final revision = ++_restoreRevision;
    bool current() =>
        mounted &&
        identical(widget.runtime, runtime) &&
        identical(_pipeline, pipeline) &&
        revision == _restoreRevision &&
        owned();
    if (!current() || runtime.chapterCount <= 0) return false;
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.position.jumpTo(controller.position.pixels);
    }
    _setFinger(_FingerScroll.none);
    final ok = await _restoreCore(
      location,
      isCurrent: current,
      operationKind: operation?.kind,
    );
    if (!ok || !current()) return false;
    _lastReportedLocation = location;
    _restoredLocation = location;
    _scheduleRebuild();
    return true;
  }

  double? _offsetForAnchor(ScrollAnchor anchor, ChapterBlocks blocks) =>
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

  ReaderLocation? _captureAndReport() {
    final location = widget.runtime.captureVisibleLocation();
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  void _publishProgress() {
    final notifier = widget.progressListenable;
    if (notifier == null) return;

    // Chapter progress is semantic content progress, not materialized layout
    // progress. DocumentIndex intentionally contains only the admitted window.
    final runtimeLocationIsPublished =
        _textLaidOut && widget.runtime.state.hasStableWorld;
    final location = runtimeLocationIsPublished
        ? widget.runtime.state.visibleLocation
        : _captureVisibleLocation();
    if (location == null) return;
    final blocks = _pipeline.blocksOf(location.chapterIndex);
    if (blocks == null) return;

    notifier.value = ProgressCalculator(
      chapterCount: widget.runtime.chapterCount,
      shares: widget.runtime.chapterShares.value,
    ).progressForLocation(location, chapterLength: blocks.displayText.length);
  }

  /// 翻頁、自動捲動、朗讀跟隨與停住捲動（[ViewportCommands]）。
  late final ViewportCommands _viewportCommands = ViewportCommands(
    scroll: () => _scrollController,
    pipeline: () => _pipeline,
    documentIndex: _documentIndex,
    admission: _admission,
    viewportHeight: () => _viewportSize.height,
    scrollOffset: _effectiveScrollOffset,
    runtime: () => widget.runtime,
    isResident: (chapter) => _chapterRepo.isResident(chapter),
    pageTurnOverlap: () => widget.pageTurnOverlap,
    pageTurnDuration: () => widget.pageTurnDuration,
    captureOwner: _captureCommandOwner,
    userScrolling: () => _finger != _FingerScroll.none,
    onStop: () => _runtimeLocationRevision += 1,
    onSettled: _handleScrollSettled,
    onScrolled: () {
      _scheduleMotionCapture();
      _reconcileVisibleWindow();
    },
    onUnreachable: _retryUnavailableFrontier,
    restoreAt: (location, isCurrent) =>
        _restoreCore(location, isCurrent: isCurrent),
  );

  void _attachController() {
    _viewportCommands.attach(widget.viewportController);
    widget.viewportController
      ?..dismissSelection = _touch.dismiss
      ..isTextCovered = _isTextCovered;
  }

  bool _isTextCovered() => _veilHoldsText;

  void _detachController(ReaderViewportController? controller) {
    if (controller == null) return;
    _viewportCommands.detach(controller);
    if (controller.dismissSelection == _touch.dismiss) {
      controller.dismissSelection = null;
    }
    if (controller.isTextCovered == _isTextCovered) {
      controller.isTextCovered = null;
    }
  }

  /// 收到命令那一刻記下這個命令還算不算數（[ViewportCommands]）。
  bool Function() _captureCommandOwner() {
    final runtime = widget.runtime;
    final operation = runtime.stateMachine.currentOperation;
    final pipeline = _pipeline;
    final revision = _runtimeLocationRevision;
    // 紙蓋著正文時不接新的命令；這個命令自己蓋的紙（朗讀跟隨到還沒載入
    // 的一章）不影響它繼續。
    final admitted =
        _textLaidOut && _finger == _FingerScroll.none && !_veilHoldsText;
    return () =>
        admitted &&
        mounted &&
        identical(widget.runtime, runtime) &&
        !runtime.disposed &&
        runtime.state.hasStableWorld &&
        identical(_pipeline, pipeline) &&
        // Runtime 換代後這份管線只留著紙下的舊正文，命令在換代那一刻作廢，
        // 不等紙蓋滿換掉管線。
        pipeline.isCurrentGeneration &&
        revision == _runtimeLocationRevision &&
        identical(runtime.stateMachine.currentOperation, operation) &&
        _finger == _FingerScroll.none &&
        // 等跳章正文時紙下的正文歸那次跳章：翻頁、自動捲動與朗讀跟隨都
        // 不能移動它，跳章結束後再來。
        !_paper.holdsTextForJump;
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
    return controller.position.isScrollingNotifier.value &&
        _finger != _FingerScroll.none;
  }

  Widget _buildVeil(ReaderState state) {
    final page = _veilPage;
    return LoadingVeil(
      controller: _veil,
      // 骨架照量那些行時的版面畫：版面變了也照原樣淡掉。
      spec: page?.spec ?? state.layoutSpec,
      lines: page?.lines,
      titleLines: page?.titleLines ?? const <int>{},
      blockLines: page?.blockLines ?? const <int>{},
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
    );
  }

  /// 蓋上紙，中間先空著（頁首頁尾照樣畫成骨架），等第一頁排好才照它淡入
  /// 骨架（ADR 0016）。畫著的骨架照原樣淡掉。開書照紀錄畫時不走這裡。
  void _coverUntilFirstPage() {
    _cancelPendingReveal();
    _openingPage = null;
    _veil.cover(skeleton: false);
  }

  /// 跳章、改排版、重載內容開始時蓋紙：舊正文還在畫面上時紙以
  /// [AppMotion.fade] 淡入蓋過它，舊正文留著、紙攔下捲動與長按，蓋滿
  /// （[_covering] 完成）才拿掉舊正文、開始排版；這段淡入不和排版疊在一起
  /// （ADR 0018、0023）。紙已經蓋滿時直接蓋上；正文本來就不在畫面上
  /// （開書、排版中）時不動，紙由排版流程管。
  void _coverText() {
    if (!_textLaidOut) return;
    _cancelPendingReveal();
    if (_veil.isCovered && _covering == null) {
      _coverUntilFirstPage();
      return;
    }
    final wasHolding = _veilHoldsText;
    _openingPage = null;
    _veil.cover(skeleton: false, fade: true);
    if (!wasHolding) {
      // 紙從這一幀開始畫在正文上、攔下觸控。
      _touch.clear();
      _holdScrollUnderVeil();
      _scheduleRebuild();
    }
    if (_veil.isCovered || _covering != null) return;
    _covering = _veil.covered.then((covered) {
      _covering = null;
      if (!mounted) return;
      // 蓋滿才換代；途中被掀開時舊正文還在畫面上，不能拆。
      if (covered && _textOutdated) _handleEpochRebuild();
      _scheduleRebuild();
      _releasePaper();
    });
  }

  /// 等紙淡入蓋滿（含蓋滿後的換代）。紙途中被掀開、正文還露在畫面上，
  /// 或這一頁已經拆掉時回傳 false：這次蓋紙取消了。
  Future<bool> _awaitCovered() async {
    for (var covering = _covering; covering != null; covering = _covering) {
      await covering;
      if (!mounted) return false;
    }
    return mounted && (!_textLaidOut || _veil.isCovered);
  }

  /// 先只排第一頁、照它長出骨架，接著排前後其他頁（ADR 0016）。第一頁照
  /// 捲動停住的位置（[_restingOffset]）排，和掀開後的正文一致。
  Future<bool> _showFirstPage(
    ScrollAnchor anchor,
    ChapterBlocks blocks, {
    required bool Function() isCurrent,
  }) async {
    final page = await _layOutAround(
      anchor,
      blocks,
      withLead: false,
      isCurrent: isCurrent,
    );
    if (!isCurrent()) return false;
    // 一行都沒排進來：沒有骨架可畫，交給後面的還原。
    if (page == null) return true;
    return _fadeInPageSkeleton(page, isCurrent);
  }

  /// 紙上的骨架換成捲動位置在 [offset] 時的那一頁：畫著的骨架先淡完，
  /// 再長出新的；開始長就回來。
  Future<bool> _fadeInPageSkeleton(
    double offset,
    bool Function() isCurrent,
  ) async {
    _veil.hideSkeleton();
    while (_veil.hasSkeleton) {
      await _nextFrame();
      if (!isCurrent()) return false;
    }
    setState(() => _veilPage = _pageLinesAt(offset));
    // 骨架長出的同時接著排前後其他頁（每幀限量，ADR 0037 補充）：長完時
    // 正文多半已經排好，不用呼吸就掀紙。長完前排好的，掀紙等它長完
    // （[LoadingVeilController.settleBreath]）。
    _veil.showSkeleton();
    return isCurrent();
  }

  PageLines _pageLinesAt(double offset) => pageLinesAt(
    pipeline: _pipeline,
    documentIndex: _documentIndex,
    offset: offset,
    height: _viewportSize.height,
  );

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
    if (!_textLaidOut || _paper.holdsTextForJump) return;
    final location = _captureVisibleLocation();
    final offset = _effectiveScrollOffset();
    if (location == null || offset == null) return;
    final contentHash = _pipeline.blocksOf(location.chapterIndex)?.contentHash;
    final (:lines, :titleLines, :blockLines, :spec) = _pageLinesAt(offset);
    if (lines.isEmpty || contentHash == null) return;
    unawaited(
      store.write(
        bookUrl,
        ReaderSkeletonPage(
          chapterIndex: location.chapterIndex,
          charOffset: location.charOffset,
          visualOffsetPx: location.visualOffsetPx,
          // 版面和行取自同一代：改排版的紙還在淡入時離開，記下的是舊版面
          // 與舊的行。
          layout: ReaderSkeletonPage.layoutKeyOf(spec),
          contentHash: contentHash,
          lines: lines,
          titleLines: titleLines,
          blockLines: blockLines,
          progress: widget.progressListenable?.value,
        ),
      ),
    );
  }

  Widget _buildLoading(ReaderState state) {
    final unavailable = state.lifecycle == ReaderLifecycle.unavailable;
    final message = unavailable ? _friendlyErrorMessage : '正在準備閱讀內容';
    return ColoredBox(
      color: widget.backgroundColor,
      child: _whileControls(
        (controlsVisible, child) => ReaderPointerTapLayer(
          onTapUp: controlsVisible ? null : widget.onContentTapUp,
          child: child,
        ),
        child: Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label: context.ui(message),
          child: unavailable
              ? ReaderUnavailableMessage(
                  message: message,
                  textColor: widget.textColor,
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
        // 排版中、等掀紙但正文還沒建：只畫紙。
        if (_stage case _LayingOut() || _AwaitingReveal(textBuilt: false)) {
          return _buildLoading(state);
        }
        final controller = _scrollController ??= ReaderScrollController(
          initialScrollOffset: _pendingScrollOffset ?? 0.0,
          keepScrollOffset: false,
        );
        // 排版換代了、舊正文還在紙下時，照舊正文那一代的左右邊距畫，不跟著
        // 新設定先跳一下。
        final textSpec = _pipeline.layoutSpec;
        final visualContent = NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: ReaderScrollView(
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
              left: textSpec.textPaddingLeft,
              right: textSpec.textPaddingRight,
            ),
            physics: _physics,
            // 跨在上下緣的段落畫到正文區外，閱讀頁框架只露出正文與頁首頁尾
            // 之間那段空隙，並在那裡漸隱（ReaderPageShell）。
            clipBehavior: Clip.none,
          ),
        );
        final readerStack = Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            visualContent,
            Positioned.fill(
              child: ReaderMarkLayers(
                geometry: _marks,
                scroll: controller,
                textLeft: textSpec.textPaddingLeft,
                highlightColor: widget.highlightColor,
                highlightStrength: widget.highlightStrength,
                highlights: widget.highlights,
                marks: widget.marks,
                ttsHighlight: widget.ttsHighlight,
              ),
            ),
            // 正文剛排好時，蓋著的紙在上面淡出；等跳章的正文時紙攔下捲動。
            if (_veil.isVisible)
              Positioned.fill(
                child: IgnorePointer(
                  // 紙蓋著正文（淡入中或已蓋滿）時攔下捲動；淡出中的紙
                  // 不攔。
                  ignoring: !_veilHoldsText,
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
            selection: _touch.selection,
            repaint: controller,
            boxesFor: _touch.boxesFor,
            caretAt: _touch.caretAt,
            onHide: widget.onHideText == null
                ? null
                : (selection) => widget.onHideText!(selection.inParagraph),
            onReplace: widget.onReplaceText == null
                ? null
                : (selection) => widget.onReplaceText!(selection.inParagraph),
            onBookmark: widget.onBookmarkText == null
                ? null
                : (selection) => widget.onBookmarkText!(selection.asBookmark),
            onHighlight: widget.onHighlightText == null
                ? null
                : (selection) => widget.onHighlightText!(selection.asHighlight),
            highlightColor: widget.highlightColor,
            child: _whileControls(
              (controlsVisible, child) => ReaderPointerTapLayer(
                onTapUp: widget.onContentTapUp == null || controlsVisible
                    ? null
                    : _touch.handleTapUp,
                suppressTapAtPointerDown: _isUserFlingInProgress,
                child: GestureDetector(
                  onLongPressStart:
                      widget.textSelectionEnabled &&
                          !controlsVisible &&
                          !_veilHoldsText
                      ? (details) =>
                            unawaited(_touch.handleLongPressStart(details))
                      : null,
                  child: child,
                ),
              ),
              child: readerStack,
            ),
          ),
        );
      },
    );
  }

  /// 照閱讀選單開著與否（[ReaderTextView.controlsVisible]）包上點擊
  /// 與長按層；選單開關時只重建 [builder] 這一層，[child] 原封不動。
  Widget _whileControls(
    Widget Function(bool controlsVisible, Widget child) builder, {
    required Widget child,
  }) {
    final controls = widget.controlsVisible;
    if (controls == null) return builder(false, child);
    return ValueListenableBuilder<bool>(
      valueListenable: controls,
      builder: (context, visible, child) => builder(visible, child!),
      child: child,
    );
  }
}

/// 正文現在在哪一段（`docs/state-machines.md`「閱讀器正文捲動」）。紙蓋上、
/// 淡入、掀開的樣子歸 [LoadingVeilController]，紙歸誰管歸 [PaperOwners]；
/// 這裡只管正文排好了沒、建了沒、掀紙了沒。
sealed class _TextStage {
  const _TextStage();
}

/// 正文還沒照目前的排版排好：只畫紙，沒有捲動視圖。
final class _LayingOut extends _TextStage {
  const _LayingOut();
}

/// 正文排好了，紙還蓋著，照開 App 換場的順序等著掀（[_ReaderTextViewState
/// ._revealWhenStill]）。每一次等掀紙是一個新的物件，等待回來時看現在還是
/// 不是它。
final class _AwaitingReveal extends _TextStage {
  _AwaitingReveal({required this.textBuilt});

  /// 正文已經建在紙底下。false 時骨架的呼吸還沒收住，正文先不建、只畫紙。
  bool textBuilt;

  /// 正文建好、畫出之後再停 [AppMotion.stillGap] 的計時。
  Timer? stillGap;
}

/// 正文建在畫面上：紙掀開中、已掀完，或跳章、改排版時又淡入蓋住。
final class _Shown extends _TextStage {
  const _Shown();
}

/// 手指對正文做什麼；只在正文建在畫面上、紙沒蓋著時有。
enum _FingerScroll {
  none(PumpState.idle),

  /// 停在可捲範圍的盡頭往外拉，正文沒動：手指按著，還沒接手捲動（往回推動
  /// 正文時才接手）。
  pullingAtEdge(PumpState.idle),

  /// 拖著正文在動。
  dragging(PumpState.dragging),

  /// 手指放開了，甩出去的慣性還在跑。
  flinging(PumpState.ballistic);

  const _FingerScroll(this.pump);

  /// 沒有還原在進行時，排版每幀的預算（ADR 0018）。
  final PumpState pump;
}
