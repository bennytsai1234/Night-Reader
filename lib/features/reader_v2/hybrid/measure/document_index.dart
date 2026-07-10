import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class DocumentOffsetHit {
  const DocumentOffsetHit({
    required this.key,
    required this.blockTop,
    required this.offsetInBlock,
  });

  final BlockKey key;
  final double blockTop;
  final double offsetInBlock;
}

final class ChapterOffsetRange {
  const ChapterOffsetRange({required this.top, required this.bottom})
    : assert(bottom >= top);

  final double top;
  final double bottom;
  double get extent => bottom - top;
}

final class DocumentIndex implements HybridDocumentIndex {
  DocumentIndex({required BlockKey centerKey}) : _centerKey = centerKey;

  BlockKey _centerKey;
  final Map<BlockKey, BlockMetrics> _metrics = <BlockKey, BlockMetrics>{};
  List<BlockKey> _beforeCenter = const <BlockKey>[];
  List<BlockKey> _centerAndAfter = const <BlockKey>[];
  Map<BlockKey, int> _beforePositions = const <BlockKey, int>{};
  Map<BlockKey, int> _afterPositions = const <BlockKey, int>{};
  _FenwickTree _beforeTree = _FenwickTree.empty();
  _FenwickTree _afterTree = _FenwickTree.empty();

  BlockKey get centerKey => _centerKey;
  int get admittedCount => _metrics.length;
  double get beforeExtent => _beforeTree.total;
  double get afterExtent => _afterTree.total;
  int get beforeCount => _beforeCenter.length;
  int get centerAndAfterCount => _centerAndAfter.length;

  Iterable<BlockKey> get keys sync* {
    final sorted = _metrics.keys.toList()..sort();
    yield* sorted;
  }

  void reset({required BlockKey centerKey}) {
    _centerKey = centerKey;
    _metrics.clear();
    _rebuild();
  }

  void admit(BlockKey key, BlockMetrics metrics) {
    _metrics[key] = metrics;
    _rebuild();
  }

  void admitAll(Map<BlockKey, BlockMetrics> metrics) {
    _metrics.addAll(metrics);
    _rebuild();
  }

  BlockMetrics? metricsFor(BlockKey key) => _metrics[key];

  @override
  BlockKey? keyForSliverIndex({
    required bool beforeCenter,
    required int index,
  }) {
    final list = beforeCenter ? _beforeCenter : _centerAndAfter;
    if (index < 0 || index >= list.length) return null;
    return list[index];
  }

  @override
  double? topOf(BlockKey key) {
    if (!_metrics.containsKey(key)) return null;
    if (key < _centerKey) {
      final index = _beforePositions[key];
      if (index == null) return null;
      return -_beforeTree.prefixSum(index);
    }
    final index = _afterPositions[key];
    if (index == null) return null;
    return index == 0 ? 0.0 : _afterTree.prefixSum(index - 1);
  }

  @override
  double? bottomOf(BlockKey key) {
    final top = topOf(key);
    final metrics = _metrics[key];
    if (top == null || metrics == null) return null;
    return top + metrics.height;
  }

  DocumentOffsetHit? hitTest(double offset) {
    final key = blockAtOffset(offset);
    if (key == null) return null;
    final top = topOf(key)!;
    return DocumentOffsetHit(
      key: key,
      blockTop: top,
      offsetInBlock: offset - top,
    );
  }

  @override
  BlockKey? blockAtOffset(double offset) {
    if (offset >= 0) {
      if (_centerAndAfter.isEmpty) return null;
      final index = _afterTree.firstPrefixGreaterThan(offset);
      if (index == null || index >= _centerAndAfter.length) return null;
      return _centerAndAfter[index];
    }
    if (_beforeCenter.isEmpty) return null;
    final distance = -offset;
    final index = _beforeTree.firstPrefixGreaterOrEqual(distance);
    if (index == null || index >= _beforeCenter.length) return null;
    return _beforeCenter[index];
  }

  @override
  double chapterExtent(int chapterIndex) {
    var total = 0.0;
    for (final entry in _metrics.entries) {
      if (entry.key.chapterIndex == chapterIndex) {
        total += entry.value.height;
      }
    }
    return total;
  }

  ChapterOffsetRange? chapterRange(int chapterIndex) {
    double? top;
    double? bottom;
    for (final key in keys) {
      if (key.chapterIndex != chapterIndex) continue;
      final blockTop = topOf(key);
      final blockBottom = bottomOf(key);
      if (blockTop == null || blockBottom == null) continue;
      top = top == null ? blockTop : (blockTop < top ? blockTop : top);
      bottom =
          bottom == null
              ? blockBottom
              : (blockBottom > bottom ? blockBottom : bottom);
    }
    if (top == null || bottom == null) return null;
    return ChapterOffsetRange(top: top, bottom: bottom);
  }

  void _rebuild() {
    final before = <BlockKey>[];
    final after = <BlockKey>[];
    for (final key in _metrics.keys) {
      if (key < _centerKey) {
        before.add(key);
      } else {
        after.add(key);
      }
    }
    before.sort((a, b) => b.compareTo(a));
    after.sort();
    _beforeCenter = List<BlockKey>.unmodifiable(before);
    _centerAndAfter = List<BlockKey>.unmodifiable(after);
    _beforePositions = <BlockKey, int>{
      for (var i = 0; i < before.length; i += 1) before[i]: i,
    };
    _afterPositions = <BlockKey, int>{
      for (var i = 0; i < after.length; i += 1) after[i]: i,
    };
    _beforeTree = _FenwickTree(
      before.map((key) => _metrics[key]!.height).toList(growable: false),
    );
    _afterTree = _FenwickTree(
      after.map((key) => _metrics[key]!.height).toList(growable: false),
    );
  }
}

final class _FenwickTree {
  _FenwickTree(List<double> values)
    : _tree = List<double>.filled(values.length + 1, 0.0) {
    for (var i = 0; i < values.length; i += 1) {
      _add(i, values[i]);
    }
  }

  _FenwickTree.empty() : _tree = <double>[0.0];

  final List<double> _tree;

  int get length => _tree.length - 1;
  double get total => length == 0 ? 0.0 : prefixSum(length - 1);

  double prefixSum(int index) {
    if (index < 0) return 0.0;
    var safeIndex = index >= length ? length : index + 1;
    var sum = 0.0;
    while (safeIndex > 0) {
      sum += _tree[safeIndex];
      safeIndex -= safeIndex & -safeIndex;
    }
    return sum;
  }

  int? firstPrefixGreaterThan(double target) {
    if (target < 0 || length == 0 || target >= total) return null;
    return _lowerBound(target, strict: true);
  }

  int? firstPrefixGreaterOrEqual(double target) {
    if (target <= 0 || length == 0 || target > total) return null;
    return _lowerBound(target, strict: false);
  }

  void _add(int index, double value) {
    var i = index + 1;
    while (i < _tree.length) {
      _tree[i] += value;
      i += i & -i;
    }
  }

  int _lowerBound(double target, {required bool strict}) {
    var index = 0;
    var bitMask = 1;
    while (bitMask < length) {
      bitMask <<= 1;
    }
    var sum = 0.0;
    while (bitMask != 0) {
      final next = index + bitMask;
      if (next < _tree.length) {
        final nextSum = sum + _tree[next];
        final keepGoing = strict ? nextSum <= target : nextSum < target;
        if (keepGoing) {
          index = next;
          sum = nextSum;
        }
      }
      bitMask >>= 1;
    }
    return index;
  }
}
