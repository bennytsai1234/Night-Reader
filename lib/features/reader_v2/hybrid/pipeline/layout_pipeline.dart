import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import '../core/chapter_layout_plan.dart';
import '../core/hybrid_contracts.dart';
import '../core/hybrid_types.dart';
import '../geometry/text_geometry.dart';
import '../measure/document_index.dart';
import '../measure/measurement_store.dart';
import '../paragraph/paragraph_cache.dart';
import '../pump/budget_governor.dart';
import '../pump/layout_pump.dart';
import '../text/hybrid_chapter_repository.dart';
import '../view/admission_controller.dart';
import 'layout_disk_cache.dart';

/// [HybridLayoutPipeline.waitForProgress] 等到的結果。
enum MaterializationWait {
  /// 有新的正文排好或取得了，再檢查一次。
  progressed,

  /// 剩下的工作只有取不到的相鄰章節，再等也不會有進展。
  frontierUnavailable,

  /// 呼叫端的操作已經作廢。
  cancelled,
}

/// 一個排版世代的排版管線：取得章節正文、切成 block 並排出換行計畫，
/// 視窗需要的 block 交給 [LayoutPump] 量測、畫成段落，量好的交給
/// admission 依序放進文件索引。
///
/// 一份只對應一個排版世代：字級、樣式或內容換代時丟掉整份換新的。
/// [dispose] 後進行中的工作都作廢，結果不會再寫進共用的量測、文件索引
/// 與 admission。換行計畫與段落尺寸會讀寫 [diskCache]，丟掉時把這個
/// 世代量到的尺寸存回去。
final class HybridLayoutPipeline {
  HybridLayoutPipeline({
    required this._epoch,
    required this._layoutSpec,
    required this._measurementStore,
    required this._documentIndex,
    required this._admission,
    required this._governor,
    required this._chapters,
    required this._preprocessor,
    required this._diskCache,
    required int paragraphCacheCapacity,
    required this._chapterCount,
    required this._textColor,
    required this._onProgress,
  }) {
    _namespace = MeasurementNamespace(
      epoch: _epoch,
      fingerprint: _fingerprintFor(_layoutSpec()),
    );
    _paragraphCache = ParagraphCache(capacity: paragraphCacheCapacity);
    _pump = LayoutPump(
      paragraphCache: _paragraphCache,
      measurementStore: _measurementStore,
      namespace: _namespace,
      governor: _governor,
    );
    _geometry = HybridTextGeometry(
      paragraphCache: _paragraphCache,
      epoch: _epoch,
      documentIndex: _documentIndex,
      blocksOf: blocksOf,
      layoutSpec: _layoutSpec,
    );
    _admission.reset(epoch: _epoch, chapterCount: _chapterCount());
    _admission.attach(_pump.completed);
    _pumpEventsSub = _pump.completed.listen((_) {
      // Admission has consumed this result before demand is advanced. Newly
      // measured frontier blocks can therefore supply the same native frame.
      _onProgress();
    });
  }

  final LayoutEpoch _epoch;
  final ReaderV2LayoutSpec Function() _layoutSpec;
  final MeasurementStore _measurementStore;
  final DocumentIndex _documentIndex;
  final AdmissionController _admission;
  final BudgetGovernor _governor;
  final HybridChapterRepository _chapters;
  final HybridTextPreprocessor _preprocessor;
  final HybridLayoutDiskCache? _diskCache;
  final int Function() _chapterCount;
  final Color Function() _textColor;

  /// 有 block 量好、或有章節排好時呼叫，讓呼叫端重新對齊視窗需求。
  final VoidCallback _onProgress;
  late final MeasurementNamespace _namespace;
  late final ParagraphCache _paragraphCache;
  late final LayoutPump _pump;
  late final HybridTextGeometry _geometry;
  late final StreamSubscription<BlockReady> _pumpEventsSub;
  final Map<int, ChapterLayoutPlan> _layoutPlans = <int, ChapterLayoutPlan>{};
  final Map<int, ChapterBlocks> _blocks = {};
  final Map<int, _ChapterMaterialization> _blocksInFlight = {};
  final Map<BlockKey, ParagraphLease> _viewportLeases = {};
  final Set<({int chapter, String layoutIdentity})> _warmedChapters = {};
  bool _disposed = false;

  LayoutEpoch get epoch => _epoch;
  MeasurementNamespace get namespace => _namespace;
  ParagraphCache get paragraphCache => _paragraphCache;
  HybridTextGeometry get geometry => _geometry;

  /// 已排出換行計畫、正文還留在記憶體裡的章節。
  ChapterBlocks? blocksOf(int chapter) => _blocks[chapter];

  /// 取得 [chapter] 並排出換行計畫。同一章同時只排一次，後到的請求共用
  /// 結果並可提高優先順序。取不到正文時丟出
  /// [ReaderV2ContentUnavailableException]；世代作廢時回傳 null。
  Future<ChapterBlocks?> ensureChapter(
    int chapter, {
    LayoutTaskPriority priority = LayoutTaskPriority.prefetch,
  }) {
    final cached = _blocks[chapter];
    if (cached != null) return Future.value(cached);

    final pending = _blocksInFlight[chapter];
    if (pending != null) {
      pending.promote(priority);
      _pump.promoteChapterVisualLines(chapter, pending.priority);
      return pending.future;
    }

    final repository = _chapters;
    final preprocessor = _preprocessor;
    final maxBlockChars = _pump.maxCharsForBudget(
      _governor.ballisticSliceBudget,
    );
    final materialization = _ChapterMaterialization(priority);
    bool current() =>
        !_disposed && identical(_blocksInFlight[chapter], materialization);
    late final Future<ChapterBlocks?> task;
    task = () async {
      final text = await repository.load(chapter);
      if (!current()) return null;
      final plan = _layoutPlans[chapter];
      if (plan != null) {
        final restored = plan.materialize(text);
        _blocks[chapter] = restored;
        _admission.registerChapter(restored);
        return restored;
      }
      final spec = _layoutSpec();
      final fingerprint = _fingerprintFor(spec);
      final stored = await _diskCache?.readPlan(text, fingerprint);
      if (!current()) return null;
      if (stored != null) {
        _layoutPlans[chapter] = ChapterLayoutPlan(stored);
        _blocks[chapter] = stored;
        _admission.registerChapter(stored);
        unawaited(_warmDiskMetricsForChapter(stored));
        return stored;
      }
      final rough = await preprocessor.process(
        text,
        maxBlockChars: maxBlockChars,
      );
      if (!current()) return null;
      final blocks = await _pump.planChapterVisualLines(
        rough,
        maxBlockChars: maxBlockChars,
        bodyStyle: HybridBlockTextStyle.fromLayoutStyle(spec.style),
        titleStyle: HybridBlockTextStyle.fromLayoutStyle(
          spec.style,
          isTitle: true,
        ),
        contentWidth: spec.textLayoutFrame.width,
        cellWidth: spec.cellWidth,
        textIndent: spec.style.textIndent.clamp(0, 8).toInt(),
        priority: materialization.priority,
      );
      if (blocks == null || !current()) return null;
      _layoutPlans[chapter] = ChapterLayoutPlan(blocks);
      _blocks[chapter] = blocks;
      _admission.registerChapter(blocks);
      // Disk reads may improve later reuse; neither first paint nor command
      // completion waits for this optional cache.
      unawaited(_warmDiskMetricsForChapter(blocks));
      unawaited(_diskCache?.writePlan(blocks, fingerprint));
      return blocks;
    }();
    materialization.attach(task);
    _blocksInFlight[chapter] = materialization;
    void cleanUp() {
      if (identical(_blocksInFlight[chapter], materialization)) {
        _blocksInFlight.remove(chapter);
      }
    }

    // Cleanup observes completion only. It never changes the original task's
    // success/error semantics seen by the operation or prefetch owner.
    unawaited(task.then<void>((_) => cleanUp(), onError: (_, _) => cleanUp()));
    return task;
  }

  /// 以 [chapter] 為中心、前後各留 [HybridChapterRepository.windowRadius]
  /// 章的需求範圍。
  void demandAround(int chapter) {
    _setDemandRange(
      math.max(0, chapter - _chapters.windowRadius),
      math.min(_chapterCount() - 1, chapter + _chapters.windowRadius),
    );
  }

  /// 依目前看到的正文範圍 [top, bottom]（文件座標，已含前後領先量）調整
  /// 要留在記憶體的章節，並請求這個範圍內還沒排好的 block。
  void reconcile({
    required double top,
    required double bottom,
    required int windowCenter,
  }) {
    final keys = _documentIndex
        .keysInRange(top, bottom)
        .toList(growable: false);
    var first = math.max(0, windowCenter - _chapters.windowRadius);
    var last = math.min(
      _chapterCount() - 1,
      windowCenter + _chapters.windowRadius,
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
          _chapterCount() - 1,
          (_documentIndex.forwardEdgeKey?.chapterIndex ?? windowCenter) + 1,
        ),
      );
    }
    if (-_documentIndex.beforeExtent > top && !_isBookStartAdmitted()) {
      first = math.min(
        first,
        math.max(
          0,
          (_documentIndex.backwardEdgeKey?.chapterIndex ?? windowCenter) - 1,
        ),
      );
    }
    _setDemandRange(first, last);
    requestWindow(top, bottom);
  }

  /// 請求 [top, bottom] 內與緊接在已放行邊緣之外的 block；[anchorKey]
  /// 最優先。視窗外的 block 不再保留段落。
  void requestWindow(double top, double bottom, {BlockKey? anchorKey}) {
    final needed = <BlockKey>{};
    final groups = <BlockKey>{};
    void request(BlockKey key, {bool anchor = false}) {
      final blocks = _blocks[key.chapterIndex];
      if (blocks == null) {
        _requestChapter(
          key.chapterIndex,
          priority: anchor
              ? LayoutTaskPriority.anchor
              : LayoutTaskPriority.visible,
        );
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
            _paragraphCache.containsFresh(block.key, _epoch, _textColor()),
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

  /// [top, bottom] 是否已經全部放進文件索引、段落也都畫好；超出書首或
  /// 書尾的部分不用等。
  bool windowReady(double top, double bottom) {
    if (_documentIndex.admittedCount == 0) return false;
    if (-_documentIndex.beforeExtent > top + 0.001 && !_isBookStartAdmitted()) {
      return false;
    }
    if (_documentIndex.afterExtent < bottom - 0.001 && !_isBookEndAdmitted()) {
      return false;
    }
    return _documentIndex
        .keysInRange(top, bottom)
        .every((key) => _paragraphCache.contains(key, _epoch));
  }

  /// 等到下一個進展：還有排版工作就等一幀，否則等任一章取得完成。完全
  /// 沒有工作在跑時代表呼叫端的等待永遠不會結束，直接丟出錯誤。
  Future<MaterializationWait> waitForProgress(bool Function() isCurrent) async {
    if (!isCurrent()) return MaterializationWait.cancelled;
    if (_pump.queueDepth > 0) {
      await _nextFrame();
      return isCurrent()
          ? MaterializationWait.progressed
          : MaterializationWait.cancelled;
    }

    final pending = <int, Future<({int chapter, bool unavailable})>>{
      for (final entry in _blocksInFlight.entries)
        entry.key: _observeSpeculativeMaterialization(
          entry.key,
          entry.value.future,
        ),
    };
    if (pending.isEmpty) {
      throw StateError(
        'Hybrid restore stalled with no layout work or chapter acquisition in flight.',
      );
    }

    while (pending.isNotEmpty) {
      final outcome = await Future.any(pending.values);
      unawaited(pending.remove(outcome.chapter));
      if (!isCurrent()) return MaterializationWait.cancelled;
      if (!outcome.unavailable) return MaterializationWait.progressed;
    }
    return MaterializationWait.frontierUnavailable;
  }

  /// 把 [blocks] 裡 [start, end) 涵蓋的段落排好並保留，直到呼叫端釋放
  /// 回傳的 lease。
  Future<List<ParagraphLease>> retainRange(
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
        if (!_paragraphCache.containsFresh(block.key, _epoch, _textColor())) {
          final group = blocks.groupContaining(block.key);
          if (groups.add(group.first.key)) {
            _submitGroupTask(blocks, group, anchor: true);
          }
        }
      }
      while (isCurrent() &&
          !targets.every(
            (block) =>
                _paragraphCache.containsFresh(block.key, _epoch, _textColor()),
          )) {
        final wait = await waitForProgress(isCurrent);
        switch (wait) {
          case MaterializationWait.progressed:
            continue;
          case MaterializationWait.cancelled:
            break;
          case MaterializationWait.frontierUnavailable:
            throw StateError(
              'Hybrid target range is not materialized and only unavailable '
              'speculative frontier work remains.',
            );
        }
      }
      return leases;
    } catch (_) {
      for (final lease in leases) {
        lease.release();
      }
      rethrow;
    }
  }

  /// 已排好的正文在章節邊緣結束、而相鄰章節取不到時，那一章與取不到的
  /// 原因；不在邊緣或那一章沒有失敗時回傳 null。
  ({int chapter, ReaderV2ContentUnavailableException failure})?
  unavailableFrontier({required bool forward}) {
    final edge = forward
        ? _documentIndex.forwardEdgeKey
        : _documentIndex.backwardEdgeKey;
    if (edge == null) return null;
    final blocks = _blocks[edge.chapterIndex];
    if (blocks == null || blocks.blocks.isEmpty) return null;
    final atChapterEdge = forward
        ? edge == blocks.blocks.last.key
        : edge.blockIndex == 0;
    if (!atChapterEdge) return null;
    final chapter = edge.chapterIndex + (forward ? 1 : -1);
    if (chapter < 0 || chapter >= _chapterCount()) return null;
    final failure = _chapters.failureOf(chapter);
    if (failure == null) return null;
    return (chapter: chapter, failure: failure);
  }

  /// 忘掉 [chapter] 上次取不到的紀錄，馬上再取一次。
  void retryChapter(int chapter) {
    _chapters.forgetFailure(chapter);
    // 還在進行中的那次取得讀的是記下來的失敗，一定會失敗；不要讓重試併進去。
    _blocksInFlight.remove(chapter);
    _requestChapter(chapter, priority: LayoutTaskPriority.visible);
  }

  /// 文件索引改以 [centerKey] 為中心重新開始放行；不在記憶體範圍內的
  /// 章節連換行計畫一起放掉。
  void resetDocument(BlockKey centerKey) {
    _releaseViewportLeases();
    _documentIndex.reset(centerKey: centerKey);
    _admission.reset(epoch: _epoch, chapterCount: _chapterCount());
    // Only a document reset relinquishes the old world. Raw-cache eviction
    // never removes coordinates underneath a mounted viewport.
    for (final oldChapter in _layoutPlans.keys.toList(growable: false)) {
      if (!_chapters.isResident(oldChapter)) _releaseChapter(oldChapter);
    }
    for (final shape in _blocks.values) {
      _admission.registerChapter(shape);
    }
  }

  /// 處理章節正文的載入、釋放與失效；回傳畫面是否要重建。
  bool handleChapterEvent(ChapterEvent event) {
    if (_disposed) return false;
    switch (event.kind) {
      case ChapterEventKind.loaded:
        if (_chapters.isResident(event.chapterId)) {
          _requestChapter(event.chapterId);
        }
        return false;
      case ChapterEventKind.evicted:
        // The active document keeps only text-free boundaries and metrics.
        // Raw text can be released without reinterpreting its geometry.
        if (!_chapters.isResident(event.chapterId)) {
          _blocks.remove(event.chapterId);
          _blocksInFlight.remove(event.chapterId);
        }
        return false;
      case ChapterEventKind.invalidated:
        _releaseChapter(event.chapterId);
        _documentIndex.invalidateChapter(event.chapterId);
        return true;
    }
  }

  /// 丟掉還沒開始的段落排版（章節換行計畫照常進行）。
  void clearPendingLayouts() => _pump.clearPendingLayouts();

  void onScrollStateChanged(PumpState state) =>
      _pump.onScrollStateChanged(state);

  /// 作廢這個世代：放掉段落與排版工作，把量到的段落尺寸存進磁碟快取。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final snapshot = _measurementStore.snapshot(_namespace);
    final diskCache = _diskCache;
    if (diskCache != null) {
      unawaited(
        diskCache.writeMetrics(
          snapshot,
          fingerprint: _namespace.fingerprint,
          chapterLayoutIdentities: <int, String>{
            for (final plan in _layoutPlans.values)
              plan.chapterIndex: plan.layoutIdentity,
          },
        ),
      );
    }
    _releaseViewportLeases();
    _pumpEventsSub.cancel();
    _pump.dispose();
    _paragraphCache.dispose();
    _measurementStore.invalidateNamespace(_namespace);
  }

  void _setDemandRange(int first, int last) {
    _pump.setDemandRange(first, last);
    if (_chapters.residentFirst == first && _chapters.residentLast == last) {
      return;
    }
    _chapters.setResidentRange(first, last);
  }

  void _requestChapter(
    int chapter, {
    LayoutTaskPriority priority = LayoutTaskPriority.prefetch,
  }) {
    if (chapter < 0 || chapter >= _chapterCount()) return;
    final first = math.min(_chapters.residentFirst ?? chapter, chapter);
    final last = math.max(_chapters.residentLast ?? chapter, chapter);
    _setDemandRange(first, last);
    unawaited(_materializeChapter(chapter, priority));
  }

  Future<void> _materializeChapter(
    int chapter,
    LayoutTaskPriority priority,
  ) async {
    try {
      final blocks = await ensureChapter(chapter, priority: priority);
      if (blocks != null && !_disposed) _onProgress();
    } on ReaderV2ContentUnavailableException {
      // Speculative neighbor acquisition may be unavailable. This is neither
      // operation cancellation nor a Hybrid deterministic-core failure.
    }
  }

  Future<({int chapter, bool unavailable})> _observeSpeculativeMaterialization(
    int chapter,
    Future<ChapterBlocks?> load,
  ) async {
    try {
      await load;
      return (chapter: chapter, unavailable: false);
    } on ReaderV2ContentUnavailableException {
      // The operation target was acquired before this wait. A neighboring
      // speculative chapter being unavailable is a bounded external frontier,
      // not cancellation and not a failure of the target or Hybrid core.
      return (chapter: chapter, unavailable: true);
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

  BlockKey? _frontierKey({required bool forward}) {
    final edge =
        (forward
            ? _documentIndex.forwardEdgeKey
            : _documentIndex.backwardEdgeKey) ??
        _documentIndex.centerKey;
    final blocks = _blocks[edge.chapterIndex];
    if (blocks == null) {
      _requestChapter(edge.chapterIndex, priority: LayoutTaskPriority.visible);
      return null;
    }
    final index = edge.blockIndex + (forward ? 1 : -1);
    if (index >= 0 && index < blocks.blocks.length) {
      return blocks.blocks[index].key;
    }
    final chapter = edge.chapterIndex + (forward ? 1 : -1);
    if (chapter < 0 || chapter >= _chapterCount()) return null;
    final neighbor = _blocks[chapter];
    if (neighbor == null) {
      _requestChapter(chapter, priority: LayoutTaskPriority.visible);
      return null;
    }
    return (forward ? neighbor.blocks.first : neighbor.blocks.last).key;
  }

  bool _isBookStartAdmitted() {
    const first = BlockKey(chapterIndex: 0, blockIndex: 0);
    return _documentIndex.metricsFor(first) != null;
  }

  bool _isBookEndAdmitted() {
    final lastChapter = _chapterCount() - 1;
    if (lastChapter < 0) return true;
    final blocks = _blocks[lastChapter];
    if (blocks == null || blocks.blocks.isEmpty) return false;
    return _documentIndex.metricsFor(blocks.blocks.last.key) != null;
  }

  void _submitGroupTask(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    bool anchor = false,
  }) {
    final head = group.first;
    final headKey = head.key;
    final last = group.last;
    final spec = _layoutSpec();
    _pump.submit(
      LayoutTask(
        block: head,
        continuationBlocks: group.length > 1
            ? group.sublist(1)
            : const <ChapterBlock>[],
        epoch: _epoch,
        fingerprint: _namespace.fingerprint,
        textStyle: HybridBlockTextStyle.fromLayoutStyle(
          spec.style,
          isTitle: head.isTitle,
        ),
        contentWidth: spec.textLayoutFrame.width,
        cellWidth: spec.cellWidth,
        textColor: _textColor(),
        priority: _priorityFor(headKey, anchor: anchor),
        direction: headKey < _documentIndex.centerKey
            ? HybridScrollDirection.backward
            : HybridScrollDirection.forward,
        indentChars: hybridIndentCharsFor(head, spec),
        trailingSpacing: _trailingSpacingFor(blocks, last, spec),
        readerOwnedLinePlan: true,
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

  static double _trailingSpacingFor(
    ChapterBlocks blocks,
    ChapterBlock block,
    ReaderV2LayoutSpec spec,
  ) {
    final nextIndex = block.blockIndex + 1;
    final isChapterEnd = nextIndex >= blocks.blocks.length;
    if (!isChapterEnd) {
      final next = blocks.blocks[nextIndex];
      if (next.isContinuation &&
          next.sourceParagraphIndex == block.sourceParagraphIndex) {
        return 0.0;
      }
    }
    return readerV2BlockTrailingSpacing(
      spec.style,
      isTitle: block.isTitle,
      isChapterEnd: isChapterEnd,
    );
  }

  Future<void> _warmDiskMetricsForChapter(ChapterBlocks blocks) async {
    final diskCache = _diskCache;
    if (diskCache == null) return;
    final warmKey = (
      chapter: blocks.chapterIndex,
      layoutIdentity: blocks.layoutIdentity,
    );
    if (!_warmedChapters.add(warmKey)) return;
    await diskCache.warmMetrics(
      blocks,
      namespace: _namespace,
      put: (key, metrics) {
        if (!_disposed &&
            _warmedChapters.contains(warmKey) &&
            _measurementStore.get(_namespace, key) == null) {
          _measurementStore.put(_namespace, key, metrics);
        }
      },
    );
  }

  static StyleFingerprint _fingerprintFor(ReaderV2LayoutSpec spec) {
    return StyleFingerprint.fromLayoutSpec(
      spec,
      platformFontSignature:
          '${defaultTargetPlatform.name}:${io.Platform.operatingSystemVersion}',
    );
  }
}

Future<void> _nextFrame() {
  WidgetsBinding.instance.ensureVisualUpdate();
  return WidgetsBinding.instance.endOfFrame;
}

final class _ChapterMaterialization {
  _ChapterMaterialization(this.priority);

  LayoutTaskPriority priority;
  late final Future<ChapterBlocks?> future;

  void attach(Future<ChapterBlocks?> task) {
    future = task;
  }

  void promote(LayoutTaskPriority next) {
    if (next.index < priority.index) priority = next;
  }
}
