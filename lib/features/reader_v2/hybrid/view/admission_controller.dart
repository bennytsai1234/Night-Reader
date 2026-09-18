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
  double _latestForwardLead = double.infinity;
  double _latestBackwardLead = double.infinity;
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

  void reset({required LayoutEpoch epoch, required int chapterCount}) {
    _epoch = epoch;
    _chapterCount = chapterCount;
    _pending.clear();
    _chapterBlockCounts.clear();
    _latestForwardLead = double.infinity;
    _latestBackwardLead = double.infinity;
  }

  void registerChapter(ChapterBlocks blocks) {
    _chapterBlockCounts[blocks.chapterIndex] = blocks.blocks.length;
    _flushPending();
  }

  /// 章節 evicted／invalidated 後清掉 admission 端記住的舊章節形狀（block
  /// 數）與尚未 admit 的殘留 pending metrics。不清的話，重新載入前若
  /// `_nextForwardKey`/`_nextBackwardKey` 沿用舊 block 數走訪，會算出新
  /// segmentation 下已不存在（或指向不同文字）的 BlockKey；重新載入後
  /// [registerChapter] 會覆寫新的 block 數，但殘留的舊 pending 條目不會
  /// 自動清除。
  void invalidateChapter(int chapterIndex) {
    _chapterBlockCounts.remove(chapterIndex);
    _pending.removeWhere((key, _) => key.chapterIndex == chapterIndex);
  }

  void attach(Stream<BlockReady> completed) {
    _subscription?.cancel();
    _subscription = completed.listen(offer);
  }

  void offer(BlockReady ready) {
    if (ready.epoch != _epoch) return;
    final existing = documentIndex.metricsFor(ready.key);
    if (existing != null) {
      // Paragraph 可能因 LRU、換色或重建而再次量測。若幾何真的改變，不能
      // 只替換 Paragraph 卻保留舊 extent，否則下一個 block 仍會從舊座標
      // 開始而造成重疊／裁字。DocumentIndex 會重建 Fenwick 座標並通知
      // sliver relayout；相同 metrics 則零成本返回。
      if (existing != ready.metrics) {
        documentIndex.admit(ready.key, ready.metrics);
        _notifyGeometryChanged();
      }
      return;
    }
    _pending[ready.key] = ready.metrics;
    _flushPending();
  }

  void activateViewport({
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

  void _flushPending() {
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
    if (changed) _notifyGeometryChanged();
  }

  void _notifyGeometryChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  bool _admitIfReady(BlockKey key) {
    final metrics = _pending[key];
    if (metrics == null) return false;
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
    _latestForwardLead =
        documentIndex.scrollableAfterExtent - viewportBottom;
    _latestBackwardLead =
        documentIndex.scrollableBeforeExtent + viewportTop;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
