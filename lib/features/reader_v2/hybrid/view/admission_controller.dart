import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';

final class AdmissionController extends ChangeNotifier {
  AdmissionController({
    required this.documentIndex,
    this.guaranteedWindow = 6000,
    this.backwardGuaranteedWindow = 3000,
  });

  final DocumentIndex documentIndex;
  final double guaranteedWindow;
  final double backwardGuaranteedWindow;
  StreamSubscription<BlockReady>? _subscription;
  final Map<BlockKey, BlockMetrics> _pending = <BlockKey, BlockMetrics>{};
  final Map<int, int> _chapterBlockCounts = <int, int>{};
  LayoutEpoch _epoch = LayoutEpoch.initial;
  int _chapterCount = 0;
  bool _initializing = true;
  double? _visibleTop;
  double? _visibleBottom;
  double _cacheExtent = 0;
  double _latestForwardLead = double.infinity;
  double _latestBackwardLead = double.infinity;
  bool _notifyScheduled = false;
  bool _disposed = false;

  double get latestForwardLead => _latestForwardLead;
  double get latestBackwardLead => _latestBackwardLead;

  bool get atForwardBookBoundary {
    final chapter = _chapterCount - 1;
    final count = _chapterBlockCounts[chapter];
    if (chapter < 0 || count == null || count <= 0) return false;
    return documentIndex.metricsFor(
          BlockKey(chapterIndex: chapter, blockIndex: count - 1),
        ) !=
        null;
  }

  bool get atBackwardBookBoundary {
    if (_chapterCount <= 0) return true;
    return documentIndex.metricsFor(
          const BlockKey(chapterIndex: 0, blockIndex: 0),
        ) !=
        null;
  }

  bool get needsForwardFriction =>
      !atForwardBookBoundary && _latestForwardLead < guaranteedWindow;

  bool get needsBackwardFriction =>
      !atBackwardBookBoundary && _latestBackwardLead < backwardGuaranteedWindow;

  bool get hasLeadDeficit => needsForwardFriction || needsBackwardFriction;

  void reset({required LayoutEpoch epoch, required int chapterCount}) {
    _epoch = epoch;
    _chapterCount = chapterCount;
    _pending.clear();
    _chapterBlockCounts.clear();
    _initializing = true;
    _visibleTop = null;
    _visibleBottom = null;
    _cacheExtent = 0;
  }

  void registerChapter(ChapterBlocks blocks) {
    _chapterBlockCounts[blocks.chapterIndex] = blocks.blocks.length;
    _flushPending();
  }

  void attach(Stream<BlockReady> completed) {
    _subscription?.cancel();
    _subscription = completed.listen(offer);
  }

  void offer(BlockReady ready) {
    if (ready.epoch != _epoch) return;
    if (documentIndex.metricsFor(ready.key) != null) return;
    _pending[ready.key] = ready.metrics;
    _flushPending();
  }

  void activateViewport({
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

  bool canAdmitOutsideVisible({
    required BlockKey key,
    required double visibleTop,
    required double visibleBottom,
    required double cacheExtent,
  }) {
    final beforeCenter = key < documentIndex.centerKey;
    final height = _pending[key]?.height ?? 0;
    final double top;
    final double bottom;
    if (beforeCenter) {
      bottom = -documentIndex.beforeExtent;
      top = bottom - height;
    } else {
      top = documentIndex.afterExtent;
      bottom = top + height;
    }
    final safeTop = visibleTop - cacheExtent;
    final safeBottom = visibleBottom + cacheExtent;
    return bottom <= safeTop || top >= safeBottom;
  }

  void _flushPending() {
    // 每個滾動幀都會經 updateViewport 進來；沒有待放行 block 就零成本離開。
    if (_pending.isEmpty) return;
    var changed = false;
    while (true) {
      var admittedThisRound = false;
      final center = documentIndex.centerKey;
      if (documentIndex.metricsFor(center) == null) {
        admittedThisRound = _admitIfReady(center);
      } else {
        final forward = _nextForwardKey();
        if (forward != null) {
          admittedThisRound = _admitIfReady(forward) || admittedThisRound;
        }
        final backward = _nextBackwardKey();
        if (backward != null) {
          admittedThisRound = _admitIfReady(backward) || admittedThisRound;
        }
      }
      if (!admittedThisRound) break;
      changed = true;
    }
    if (changed) _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  bool _admitIfReady(BlockKey key) {
    final metrics = _pending[key];
    if (metrics == null) return false;
    if (!_initializing) {
      final visibleTop = _visibleTop;
      final visibleBottom = _visibleBottom;
      if (visibleTop == null || visibleBottom == null) return false;
      final outsideVisibleCache = canAdmitOutsideVisible(
        key: key,
        visibleTop: visibleTop,
        visibleBottom: visibleBottom,
        cacheExtent: _cacheExtent,
      );
      final outsideVisible = canAdmitOutsideVisible(
        key: key,
        visibleTop: visibleTop,
        visibleBottom: visibleBottom,
        cacheExtent: 0,
      );
      if (!outsideVisible) return false;
      assert(
        outsideVisibleCache || _isContiguousEdge(key),
        'I2: cache recovery is only safe at a contiguous document edge.',
      );
    }
    Map<BlockKey, double>? previousTops;
    assert(() {
      previousTops = <BlockKey, double>{
        for (final existingKey in documentIndex.keys)
          existingKey: documentIndex.topOf(existingKey)!,
      };
      return true;
    }());
    _pending.remove(key);
    documentIndex.admit(key, metrics);
    assert(() {
      final tops = previousTops;
      if (tops == null) return true;
      for (final entry in tops.entries) {
        final currentTop = documentIndex.topOf(entry.key);
        if (currentTop == null || (currentTop - entry.value).abs() > 0.000001) {
          return false;
        }
      }
      return true;
    }(), 'I3: admitting an exact edge block moved existing coordinates.');
    return true;
  }

  bool _isContiguousEdge(BlockKey key) {
    return key < documentIndex.centerKey
        ? _nextBackwardKey() == key
        : _nextForwardKey() == key;
  }

  BlockKey? _nextForwardKey() {
    final edge = documentIndex.forwardEdgeKey ?? documentIndex.centerKey;
    final count = _chapterBlockCounts[edge.chapterIndex];
    if (count == null) return null;
    if (edge.blockIndex + 1 < count) {
      return BlockKey(
        chapterIndex: edge.chapterIndex,
        blockIndex: edge.blockIndex + 1,
      );
    }
    final nextChapter = edge.chapterIndex + 1;
    if (nextChapter >= _chapterCount ||
        !_chapterBlockCounts.containsKey(nextChapter)) {
      return null;
    }
    return BlockKey(chapterIndex: nextChapter, blockIndex: 0);
  }

  BlockKey? _nextBackwardKey() {
    final edge = documentIndex.backwardEdgeKey ?? documentIndex.centerKey;
    if (edge.blockIndex > 0) {
      return BlockKey(
        chapterIndex: edge.chapterIndex,
        blockIndex: edge.blockIndex - 1,
      );
    }
    final previousChapter = edge.chapterIndex - 1;
    final count = _chapterBlockCounts[previousChapter];
    if (previousChapter < 0 || count == null || count <= 0) return null;
    return BlockKey(chapterIndex: previousChapter, blockIndex: count - 1);
  }

  void updateLead({
    required double viewportTop,
    required double viewportBottom,
  }) {
    _latestForwardLead = documentIndex.afterExtent - viewportBottom;
    _latestBackwardLead = documentIndex.beforeExtent + viewportTop;
    assert(
      (atForwardBookBoundary || _latestForwardLead >= 0) &&
          (atBackwardBookBoundary || _latestBackwardLead >= 0),
      'I5: an admitted boundary became physically reachable.',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
