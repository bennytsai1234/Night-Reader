from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, repl: str, label: str, flags=0) -> str:
    text2, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one regex match, got {count}")
    return text2


# ---------------------------------------------------------------------------
# BudgetGovernor: interaction is scheduling information, never a zero-work gate.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/pump/budget_governor.dart"
s = read(path)
s = s.replace("  bool _leadDeficit = false;\n", "")
s = sub_once(
    s,
    r"\n  void updateLeadDeficit\(bool value\) \{\n    _leadDeficit = value;\n  \}\n",
    "\n",
    "remove lead-deficit state",
)
s = replace_once(
    s,
    """  /// 本幀可用的排版預算（µs）。dragging 恆為 0（I4）；idle/rebuilding
  /// 保底一個標準切片（餓死會讓 restore 與領先量鋪設停擺）；ballistic
  /// 無赤字時允許歸零（該幀已滿載），有赤字時保底（撞牆防護）。
  int frameBudgetMicros(PumpState state) {
    final slice = ballisticSliceBudget.inMicroseconds;
    switch (state) {
      case PumpState.dragging:
        return 0;
      case PumpState.ballistic:
        final budget = _headroomMicros(capMicros: _ballisticCapMicros);
        return _leadDeficit ? math.max(budget, slice) : budget;
      case PumpState.rebuilding:
        return math.max(
          _headroomMicros(capMicros: _rebuildingCapMicros),
          slice,
        );
      case PumpState.idle:
        // 非滾動幀：允許用到約兩個幀週期快速鋪領先量，但保底 4 個標準
        // 切片維持與舊行為相當的暖機速度。
        final cap = (2 * framePeriodMicros).round();
        return math.max(_headroomMicros(capMicros: cap), 4 * slice);
    }
  }
""",
    """  /// 本幀可用的排版預算（µs）。互動狀態只調整每幀工作量，不再關閉
  /// 排版。只要有需求，dragging / ballistic 至少都能完成一個標準切片；
  /// cache/prefetch 是否及時不再決定內容能不能繼續存在或顯示。
  int frameBudgetMicros(PumpState state) {
    final slice = ballisticSliceBudget.inMicroseconds;
    switch (state) {
      case PumpState.dragging:
      case PumpState.ballistic:
        return math.max(
          _headroomMicros(capMicros: _ballisticCapMicros),
          slice,
        );
      case PumpState.rebuilding:
        return math.max(
          _headroomMicros(capMicros: _rebuildingCapMicros),
          slice,
        );
      case PumpState.idle:
        final cap = (2 * framePeriodMicros).round();
        return math.max(_headroomMicros(capMicros: cap), 4 * slice);
    }
  }
""",
    "rewrite frame budgets",
)
write(path, s)


# ---------------------------------------------------------------------------
# LayoutPump: scrolling never revokes layout ownership.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/pump/layout_pump.dart"
s = read(path)
s = s.replace("  int _stateRevision = 0;\n", "")
s = replace_once(
    s,
    """    final ownerRevision = _stateRevision;

    void ensureLayoutOwnership() {
      if (_disposed ||
          _state == PumpState.dragging ||
          _stateRevision != ownerRevision) {
        throw StateError('Reader V2 layout ownership changed during segmentation.');
      }
    }
""",
    """    void ensureLayoutOwnership() {
      if (_disposed) {
        throw StateError('Reader V2 layout pump was disposed during segmentation.');
      }
    }
""",
    "segmentation ownership",
)
s = replace_once(
    s,
    """  void onScrollStateChanged(PumpState state) {
    if (_state == state) return;
    _state = state;
    _stateRevision += 1;
  }
""",
    """  void onScrollStateChanged(PumpState state) {
    _state = state;
  }
""",
    "scroll state ownership",
)
s = sub_once(
    s,
    r"\n    if \(_state == PumpState\.dragging\) \{\n      assert\([\s\S]*?\n      return 0;\n    \}\n    final budgetMicros",
    "\n    final budgetMicros",
    "remove dragging pump gate",
)
s = s.replace("    _stateRevision += 1;\n", "")
write(path, s)


# ---------------------------------------------------------------------------
# AdmissionController: exact geometry is admitted as soon as it exists.
# Viewport position and lead no longer gate admission or add friction state.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/view/admission_controller.dart"
s = read(path)
for line in [
    "  bool _initializing = true;\n",
    "  double? _visibleTop;\n",
    "  double? _visibleBottom;\n",
    "  double _cacheExtent = 0;\n",
    "  bool _forwardFrictionLatched = false;\n",
    "  bool _backwardFrictionLatched = false;\n",
]:
    s = s.replace(line, "")
s = sub_once(
    s,
    r"\n  bool get needsForwardFriction =>[\s\S]*?\n  bool _backwardFrictionLatched = false;\n",
    "\n",
    "remove friction policy block",
) if "_backwardFrictionLatched" in s else s
# The previous field removals can make the broad block unavailable; remove getters/methods independently.
s = sub_once(
    s,
    r"\n  bool get needsForwardFriction =>[\s\S]*?\n  void reset\(",
    "\n  bool get hasLeadDeficit => false;\n\n  double frictionScaleToward({required bool forward}) => 0.0;\n\n  void reset(",
    "replace friction policy with stateless compatibility surface",
)
s = s.replace("    _initializing = true;\n", "")
s = s.replace("    _visibleTop = null;\n", "")
s = s.replace("    _visibleBottom = null;\n", "")
s = s.replace("    _cacheExtent = 0;\n", "")
s = s.replace("    _forwardFrictionLatched = false;\n", "")
s = s.replace("    _backwardFrictionLatched = false;\n", "")
s = replace_once(
    s,
    """  void activateViewport({
    required double visibleTop,
    required double visibleBottom,
    required double cacheExtent,
  }) {
    _initializing = false;
    updateViewport(
      visibleTop: visibleTop,
      visibleBottom: visibleBottom,
      cacheExtent: cacheExtent,
    );
  }

  void updateViewport({
    required double visibleTop,
    required double visibleBottom,
    required double cacheExtent,
  }) {
    _visibleTop = visibleTop;
    _visibleBottom = visibleBottom;
    _cacheExtent = cacheExtent;
    _flushPending();
  }
""",
    """  void activateViewport({
    required double visibleTop,
    required double visibleBottom,
    required double cacheExtent,
  }) {
    _flushPending();
  }

  void updateViewport({
    required double visibleTop,
    required double visibleBottom,
    required double cacheExtent,
  }) {
    _flushPending();
  }
""",
    "viewport must not gate admission",
)
s = sub_once(
    s,
    r"\n  bool canAdmitOutsideVisible\([\s\S]*?\n  void _flushPending\(\) \{",
    "\n  void _flushPending() {",
    "remove visible-admission predicate",
)
s = sub_once(
    s,
    r"  bool _admitIfReady\(BlockKey key\) \{\n    final metrics = _pending\[key\];\n    if \(metrics == null\) return false;\n    if \(!_initializing\) \{[\s\S]*?\n    Map<BlockKey, double>\? previousTops;",
    """  bool _admitIfReady(BlockKey key) {
    final metrics = _pending[key];
    if (metrics == null) return false;
    Map<BlockKey, double>? previousTops;""",
    "remove visible-area admission gate",
)
s = sub_once(
    s,
    r"    _forwardFrictionLatched = _updateFrictionLatch\([\s\S]*?\n    assert\([\s\S]*?\n    \);\n",
    "",
    "remove lead friction latch/assert",
)
write(path, s)


# ---------------------------------------------------------------------------
# Scroll physics: no artificial low-lead friction. Device gets native clamping.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart"
s = read(path)
s = s.replace("import 'admission_controller.dart';\n", "")
s = sub_once(
    s,
    r"/// Clamping 基底的閱讀器捲動物理。[\s\S]*?final class HybridScrollPhysics extends ClampingScrollPhysics \{[\s\S]*?\n\}\n$",
    """/// Reader V2 使用原生 clamping 物理。排版／快取狀態不得修改手指位移或
/// fling；內容準備是 materialization 的責任，不是 scroll physics 的責任。
final class HybridScrollPhysics extends ClampingScrollPhysics {
  const HybridScrollPhysics({super.parent});

  @override
  HybridScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HybridScrollPhysics(parent: buildParent(ancestor));
  }
}
""",
    "simplify scroll physics",
)
write(path, s)


# ---------------------------------------------------------------------------
# Paragraph cache: admitted paragraphs live for the layout epoch. No LRU/pins/
# waiters; a cache miss is not a render state that waits to become ready.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/paragraph/paragraph_cache.dart"
s = read(path)
s = s.replace("  final Set<_ParagraphCacheKey> _pinned = <_ParagraphCacheKey>{};\n", "")
s = sub_once(
    s,
    r"  final Map<_ParagraphCacheKey, List<ui\.VoidCallback>> _putWaiters =\n      <_ParagraphCacheKey, List<ui\.VoidCallback>>\{\};\n",
    "",
    "remove paragraph waiters state",
)
s = sub_once(
    s,
    r"    _evictIfNeeded\(\);\n    // 一次性消費：[\s\S]*?\n    \}\n  \}\n\n  /// paint 撲空時註冊：[\s\S]*?\n  \}\n\n  @override\n  void pinRange\(BlockRange range\) \{[\s\S]*?\n  \}\n\n  void pinKeys\(Iterable<BlockKey> keys, LayoutEpoch epoch\) \{[\s\S]*?\n  \}\n\n  @override\n  void unpinAll\(\) \{[\s\S]*?\n  \}\n\n  /// Removes unpinned entries beyond \[capacity\].[\s\S]*?\n  void trimToCapacity\(\) \{[\s\S]*?\n  \}\n",
    """  }

  @override
  void pinRange(BlockRange range) {}

  void pinKeys(Iterable<BlockKey> keys, LayoutEpoch epoch) {}

  @override
  void unpinAll() {}

  void trimToCapacity() {}
""",
    "remove paragraph readiness/pinning policy",
)
s = s.replace("    _pinned.clear();\n", "")
s = s.replace("    _putWaiters.clear();\n", "")
s = s.replace("      _pinned.remove(key);\n", "")
s = sub_once(
    s,
    r"\n  void _evictIfNeeded\(\) \{[\s\S]*?\n  \}\n\}",
    "\n}",
    "remove paragraph eviction",
)
write(path, s)


# ---------------------------------------------------------------------------
# Cached block paint: admitted block -> paragraph is an invariant, not a wait.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/view/cached_block_widget.dart"
s = read(path)
s = s.replace("    _cancelParagraphWait();\n", "")
s = sub_once(
    s,
    r"\n  /// paint 撲空後是否已向 \[ParagraphCache\] 註冊 put-waiter。[\s\S]*?\n  @override\n  void paint",
    "\n  @override\n  void paint",
    "remove paint waiter state",
)
s = replace_once(
    s,
    """    if (entry == null) {
      // 段落尚未建置或已被 LRU 逐出：extent 由 DocumentIndex 撐著，這幀
      // 只能留白；註冊一次性 waiter，段落補建完成即自動重繪，不再依賴
      // sliver 子項被回收再 materialize 才恢復。
      if (!_waitingForParagraph) {
        _waitingForParagraph = true;
        _paragraphCache.addPutWaiter(_blockKey, _epoch, _handleParagraphReady);
      }
      return;
    }
    _cancelParagraphWait();
""",
    """    if (entry == null) {
      assert(
        false,
        'Reader V2 invariant: an admitted block must already own its Paragraph.',
      );
      return;
    }
""",
    "cache miss is invariant, not wait state",
)
write(path, s)


# ---------------------------------------------------------------------------
# Session preload: interaction never pauses layout.
# Keep compatibility methods stateless so callers can be removed independently.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/session/reader_v2_preload_scheduler.dart"
s = read(path)
s = s.replace("  int _interactiveDepth = 0;\n", "")
s = sub_once(
    s,
    r"\n  bool get isInteractive => _interactiveDepth > 0;[\s\S]*?\n  int bumpGeneration\(\) \{",
    """
  bool get isInteractive => false;

  int get debugInteractiveDepth => 0;

  void beginInteractive() {}

  void endInteractive() {}

  int bumpGeneration() {""",
    "remove interactive pause state",
)
s = sub_once(
    s,
    r"\n    if \(isInteractive\) \{\n      unawaited\(scheduleContent\(safeIndex, priority: priority\)\);\n    \}\n",
    "\n",
    "layout scheduling during interaction",
)
s = s.replace("    if (_disposed || isInteractive) return;", "    if (_disposed) return;")
write(path, s)


# ---------------------------------------------------------------------------
# Hybrid screen: remove restore/prefetch/drag readiness gates and bounded batches.
# ---------------------------------------------------------------------------
path = "lib/features/reader_v2/hybrid/hybrid_reader_screen.dart"
s = read(path)
for line in [
    "  static const int _restoreGroupsPerSide = 8;\n",
    "  static const int _progressiveGroupsPerSide = 8;\n",
    "  int _prefetchGeneration = 0;\n",
    "  bool _restorePrefetchBarrierActive = false;\n",
    "  bool _restoreUserScrollObserved = false;\n",
    "  bool _restorePinning = false;\n",
    "  bool _dragging = false;\n",
    "  bool _sawUserScroll = false;\n",
]:
    s = s.replace(line, "")
s = s.replace("    _physics = HybridScrollPhysics(admission: _admission);", "    _physics = const HybridScrollPhysics();")
for debug_line in [
    "      'dragging': _dragging,\n",
    "      'restoreLocked': _restorePinning,\n",
    "      'restorePrefetchBarrierActive': _restorePrefetchBarrierActive,\n",
    "      'restoreUserScrollObserved': _restoreUserScrollObserved,\n",
]:
    s = s.replace(debug_line, "")
s = s.replace("    _prefetchGeneration += 1;\n", "")
s = s.replace("    _restorePinning = false;\n", "")
s = s.replace("    _dragging = false;\n", "")
s = s.replace("    _sawUserScroll = false;\n", "")
s = s.replace("    _restorePinning = true;\n", "")
s = s.replace("    _restorePrefetchBarrierActive = true;\n", "")
s = s.replace("    _restoreUserScrollObserved = false;\n", "")
s = s.replace("      _paragraphCache\n        ..unpinAll()\n        ..pinKeys(<BlockKey>[anchor.blockKey], _epoch);\n", "")
s = s.replace("restoreOnly: true,\n", "")
s = s.replace("restoreOnly: restoreOnly,\n", "")
s = s.replace("      if (initialWindowReady() && _pump.queueDepth == 0) return true;", "      if (initialWindowReady()) return true;")
s = replace_once(
    s,
    """    } finally {
      if (mounted && identical(_pump, binding) && ticket == _restoreTicket) {
        _pump.onScrollStateChanged(
          _dragging ? PumpState.dragging : PumpState.idle,
        );
      }
    }
""",
    """    } finally {
      if (mounted && identical(_pump, binding) && ticket == _restoreTicket) {
        _pump.onScrollStateChanged(PumpState.idle);
      }
    }
""",
    "restore finalizer",
)
# Replace chapter events wholesale so raw cache eviction cannot erase document geometry.
s = sub_once(
    s,
    r"  void _onChapterEvent\(ChapterEvent event\) \{[\s\S]*?\n  void _shiftWindow\(int chapterIndex\) \{",
    """  void _onChapterEvent(ChapterEvent event) {
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
        return;
    }
  }

  void _shiftWindow(int chapterIndex) {""",
    "chapter event ownership",
)
# Replace the entire gated prefetch block.
s = sub_once(
    s,
    r"  void _ensureWindowTasks\(\{BlockKey\? anchorKey, bool restoreOnly = false\}\) \{[\s\S]*?\n  void _enqueueChapterTasks\(",
    """  void _ensureWindowTasks({BlockKey? anchorKey}) {
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

  void _enqueueChapterTasks(""",
    "remove prefetch gates",
)
s = s.replace("    bool restoreOnly = false,\n", "")
s = sub_once(
    s,
    r"    final batchSize = restoreOnly[\s\S]*?    var forwardBlocked = false;",
    "    var forwardBlocked = false;",
    "remove bounded task batches",
)
s = sub_once(
    s,
    r"\n  List<List<ChapterBlock>> _boundedTaskBatch\([\s\S]*?\n  bool _admitOrSubmitGroup\(",
    "\n  bool _admitOrSubmitGroup(",
    "delete bounded batch helper",
)
s = sub_once(
    s,
    r"    if \(_restorePinning\) \{[\s\S]*?\n    \}\n    final anchor =",
    "    final anchor =",
    "remove restore pinning",
)
s = replace_once(
    s,
    """  bool _isLayoutTaskStillDesired(LayoutTask task) {
    if (task.epoch != _epoch || task.fingerprint != _fingerprint) return false;
    return _chapterRepo.isResident(task.block.key.chapterIndex);
  }
""",
    """  bool _isLayoutTaskStillDesired(LayoutTask task) {
    return task.epoch == _epoch && task.fingerprint == _fingerprint;
  }
""",
    "layout desire ownership",
)
s = sub_once(
    s,
    r"  Future<void> _pumpOnce\(\) async \{[\s\S]*?\n  void _updateLeadTelemetry\(\) \{",
    """  Future<void> _pumpOnce() async {
    await _pump.pumpPending();
    if (!mounted) return;
    if (_pump.queueDepth > 0) {
      _schedulePump();
    } else {
      _updateLeadTelemetry();
    }
  }

  void _updateLeadTelemetry() {""",
    "continuous pump",
)
s = s.replace("    if (!_initialRestoreCompleted || _restorePinning) return;", "    if (!_initialRestoreCompleted) return;")
s = s.replace("    _governor.updateLeadDeficit(_admission.hasLeadDeficit);\n", "")
# Replace scroll state handler: state only tunes budget, never blocks work.
s = sub_once(
    s,
    r"  bool _handleScrollNotification\(ScrollNotification notification\) \{[\s\S]*?\n  void _scheduleMotionCapture\(\) \{",
    """  bool _handleScrollNotification(ScrollNotification notification) {
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

  void _scheduleMotionCapture() {""",
    "scroll state without readiness gates",
)
s = replace_once(
    s,
    """    if (_captureFramePending ||
        !mounted ||
        _restorePinning ||
        widget.runtime.pendingLocation != null) {
""",
    """    if (_captureFramePending ||
        !mounted ||
        widget.runtime.pendingLocation != null) {
""",
    "motion capture guard",
)
s = s.replace("      if (!_initialRestoreCompleted || _restorePinning) return;", "      if (!_initialRestoreCompleted) return;")
# Ensure every motion frame keeps materialization moving.
s = replace_once(
    s,
    """      _publishProgress();
      _updateLeadTelemetry();
      if (location != null && location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      }
""",
    """      _publishProgress();
      _updateLeadTelemetry();
      if (location != null && location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      } else {
        _syncResidentRangeToViewport();
        _ensureWindowTasks();
        _schedulePump();
      }
""",
    "continuous motion materialization",
)
# Replace settle handler, preserving only true restore-ticket ownership.
s = sub_once(
    s,
    r"  Future<void> _handleScrollSettled\(\{bool allowFullPrefetch = false\}\) async \{[\s\S]*?\n  void _publishProgress\(\) \{",
    """  Future<void> _handleScrollSettled({bool allowFullPrefetch = false}) async {
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

  void _publishProgress() {""",
    "settle without restore barrier",
)
s = replace_once(
    s,
    """    final runtimeLocationIsPublished =
        _initialRestoreCompleted &&
        widget.runtime.state.phase == ReaderV2Phase.ready &&
        !_restorePinning;
""",
    """    final runtimeLocationIsPublished =
        _initialRestoreCompleted &&
        widget.runtime.state.phase == ReaderV2Phase.ready;
""",
    "progress publication",
)
# Command ownership follows runtime operation identity, not transient gestures.
s = sub_once(
    s,
    r"  bool Function\(\) _captureCommandOwner\(\) \{[\s\S]*?\n  Future<bool> _enqueueCommand",
    """  bool Function() _captureCommandOwner() {
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

  Future<bool> _enqueueCommand""",
    "command ownership",
)
s = replace_once(
    s,
    """    if (scrolling && !_dragging) {
      _runtimeLocationRevision += 1;
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
      return true;
    }
""",
    """    if (scrolling) {
      _runtimeLocationRevision += 1;
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
      return true;
    }
""",
    "pointer-down ballistic stop",
)
# Paragraphs are epoch-owned now; there is no visible-range pin/trim state.
s = re.sub(r"\n  void _updateParagraphPins\(\) \{[\s\S]*?\n  \}\n\n  Widget _buildLoading", "\n  Widget _buildLoading", s, count=1)
s = s.replace("        _updateParagraphPins();\n", "")
s = s.replace("      _updateParagraphPins();\n", "")
# Any leftovers from old restore-only call formatting are now ordinary demand.
s = re.sub(r",?\s*restoreOnly:\s*(true|false|restoreOnly)", "", s)
write(path, s)


# ---------------------------------------------------------------------------
# Tests: replace the old low-lead friction/zero-drag-budget contract.
# ---------------------------------------------------------------------------
path = "test/features/reader_v2/hybrid/hybrid_scroll_behavior_test.dart"
write(
    path,
    """import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/budget_governor.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';

void main() {
  ui.FrameTiming timing({
    required int buildMicros,
    required int rasterMicros,
    required int spanMicros,
    int vsyncStart = 0,
  }) {
    return ui.FrameTiming(
      vsyncStart: vsyncStart,
      buildStart: vsyncStart,
      buildFinish: vsyncStart + buildMicros,
      rasterStart: vsyncStart + spanMicros - rasterMicros,
      rasterFinish: vsyncStart + spanMicros,
      rasterFinishWallTime: vsyncStart + spanMicros,
    );
  }

  group('BudgetGovernor direct-flow contract', () {
    test('dragging and ballistic never disable layout', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 9000, rasterMicros: 9000, spanMicros: 20000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.dragging), greaterThan(0));
      expect(governor.frameBudgetMicros(PumpState.ballistic), greaterThan(0));
    });

    test('idle and rebuilding also remain live', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 20000, rasterMicros: 20000, spanMicros: 45000),
      ]);
      expect(governor.frameBudgetMicros(PumpState.idle), greaterThan(0));
      expect(governor.frameBudgetMicros(PumpState.rebuilding), greaterThan(0));
    });

    test('pump work is excluded from non-pump headroom estimate', () {
      final governor = BudgetGovernor();
      governor.recordFrameTimings(<ui.FrameTiming>[
        timing(buildMicros: 3000, rasterMicros: 3000, spanMicros: 8000),
      ]);
      final before = governor.frameBudgetMicros(PumpState.ballistic);
      for (var i = 0; i < 40; i += 1) {
        governor.recordPumpWork(const Duration(microseconds: 3000));
      }
      final after = governor.frameBudgetMicros(PumpState.ballistic);
      expect(after, greaterThanOrEqualTo(before));
    });
  });

  group('HybridScrollPhysics direct-flow contract', () {
    ScrollMetrics metricsAt({double pixels = 0}) {
      return FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 100000,
        pixels: pixels,
        viewportDimension: 600,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3.0,
      );
    }

    test('user drag is never attenuated by layout readiness', () {
      const physics = HybridScrollPhysics();
      expect(physics.applyPhysicsToUserOffset(metricsAt(), -10), -10);
      expect(physics.applyPhysicsToUserOffset(metricsAt(), 10), 10);
    });

    test('applyTo preserves the direct clamping physics type', () {
      const physics = HybridScrollPhysics();
      final applied = physics.applyTo(const ClampingScrollPhysics());
      expect(applied, isA<HybridScrollPhysics>());
    });
  });
}
""",
)

print("Reader direct-flow refactor applied")
