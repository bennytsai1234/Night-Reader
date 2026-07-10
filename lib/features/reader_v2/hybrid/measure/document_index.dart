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

/// 增量式雙 Fenwick 文檔索引。
///
/// I2 保證 admission 恆為「由 center 向兩側的連續邊緣」，因此 admit 是
/// 兩側 list/Fenwick 的 append——熱路徑上沒有排序、沒有全量重建。
/// 亂序 admit（理論上不發生）以 debug assert 攔截並 fallback 全量重建。
final class DocumentIndex implements HybridDocumentIndex {
  DocumentIndex({required BlockKey centerKey}) : _centerKey = centerKey;

  BlockKey _centerKey;
  final Map<BlockKey, BlockMetrics> _metrics = <BlockKey, BlockMetrics>{};

  /// center 之上，index 0 = 最接近 center，索引向上（key 遞減）。
  final List<BlockKey> _beforeCenter = <BlockKey>[];

  /// center 與其下，index 0 = center，key 遞增。
  final List<BlockKey> _centerAndAfter = <BlockKey>[];
  final Map<BlockKey, int> _beforePositions = <BlockKey, int>{};
  final Map<BlockKey, int> _afterPositions = <BlockKey, int>{};
  final _FenwickTree _beforeTree = _FenwickTree();
  final _FenwickTree _afterTree = _FenwickTree();

  BlockKey get centerKey => _centerKey;
  int get admittedCount => _metrics.length;
  double get beforeExtent => _beforeTree.total;
  double get afterExtent => _afterTree.total;
  int get beforeCount => _beforeCenter.length;
  int get centerAndAfterCount => _centerAndAfter.length;

  /// 最上緣（最小）已放行 key；before 側為空時為 null。
  BlockKey? get backwardEdgeKey =>
      _beforeCenter.isEmpty ? null : _beforeCenter.last;

  /// 最下緣（最大）已放行 key；after 側為空時為 null。
  BlockKey? get forwardEdgeKey =>
      _centerAndAfter.isEmpty ? null : _centerAndAfter.last;

  /// 已放行 key 由上而下（遞增）——天然有序，零排序零複製。
  Iterable<BlockKey> get keys sync* {
    for (var i = _beforeCenter.length - 1; i >= 0; i -= 1) {
      yield _beforeCenter[i];
    }
    yield* _centerAndAfter;
  }

  void reset({required BlockKey centerKey}) {
    _centerKey = centerKey;
    _metrics.clear();
    _rebuildAll();
  }

  void admit(BlockKey key, BlockMetrics metrics) {
    final existing = _metrics[key];
    if (existing != null) {
      if (existing == metrics) return;
      // 已放行 block 的高度變更會移動既有座標（I3 禁止，理論上不發生）；
      // 保守走全量重建維持索引一致。
      _metrics[key] = metrics;
      _rebuildAll();
      return;
    }
    _metrics[key] = metrics;
    if (key < _centerKey) {
      final inOrder = _beforeCenter.isEmpty || key < _beforeCenter.last;
      assert(inOrder, 'I2: backward admit $key is not at the contiguous edge.');
      if (!inOrder) {
        _rebuildAll();
        return;
      }
      _beforePositions[key] = _beforeCenter.length;
      _beforeCenter.add(key);
      _beforeTree.append(metrics.height);
    } else {
      final inOrder = _centerAndAfter.isEmpty || key > _centerAndAfter.last;
      assert(inOrder, 'I2: forward admit $key is not at the contiguous edge.');
      if (!inOrder) {
        _rebuildAll();
        return;
      }
      _afterPositions[key] = _centerAndAfter.length;
      _centerAndAfter.add(key);
      _afterTree.append(metrics.height);
    }
  }

  void admitAll(Map<BlockKey, BlockMetrics> metrics) {
    _metrics.addAll(metrics);
    _rebuildAll();
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

  // ---- sliver 幾何查詢（供 RenderHybridBlockSliver 覆寫框架線性掃描） ----
  //
  // 框架 RenderSliverFixedExtentBoxAdaptor 在 itemExtentBuilder 模式下的
  // offset↔index 換算是從 0 線性累加（O(n)/O(n×v) 每幀）；以下三個查詢
  // 以 Fenwick 前綴和提供逐點等價的 O(log n) 版本。座標皆為該側 sliver
  // 自身的 layout offset（index 0 起、無縫隙），與框架語意一致。

  /// 該側全部已放行 block 的總 extent（= computeMaxScrollOffset）。
  double sliverScrollExtent({required bool beforeCenter}) {
    return beforeCenter ? _beforeTree.total : _afterTree.total;
  }

  /// 第 [index] 個子項的 layout offset（= 前 index 個 extent 之和）。
  /// index 超出已放行數量時回傳總 extent（框架在 run-out 時同樣落在尾端）。
  double sliverLayoutOffset({required bool beforeCenter, required int index}) {
    final tree = beforeCenter ? _beforeTree : _afterTree;
    if (index <= 0) return 0.0;
    return tree.prefixSum(index - 1);
  }

  /// scrollOffset 落點的子項 index。逐點對齊框架
  /// `_getChildIndexForScrollOffset`：offset 0 → 0；恰在邊界屬前一子項；
  /// 超過總 extent → 最後一個 index；空側且 offset>0 → -1。
  int sliverIndexForScrollOffset({
    required bool beforeCenter,
    required double scrollOffset,
  }) {
    if (scrollOffset <= 0.0) return 0;
    final tree = beforeCenter ? _beforeTree : _afterTree;
    if (tree.length == 0) return -1;
    if (scrollOffset >= tree.total) return tree.length - 1;
    return tree.firstPrefixGreaterOrEqual(scrollOffset) ?? tree.length - 1;
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

  /// 與 [top, bottom) 相交的已放行 block，由上而下。
  /// Fenwick 定位起點 O(log n)，之後只走訪範圍內的 k 個 block。
  List<BlockKey> keysInRange(double top, double bottom) {
    final result = <BlockKey>[];
    if (bottom <= top) return result;
    // before 側：block i 佔據 [-prefix(i), -prefix(i-1))。
    if (top < 0 && _beforeCenter.isNotEmpty) {
      final startDistance = -bottom;
      final int startIndex;
      if (startDistance < 0) {
        startIndex = 0;
      } else {
        startIndex =
            _beforeTree.firstPrefixGreaterThan(startDistance) ??
            _beforeCenter.length;
      }
      // blockBottom 追蹤第 i 個 block 的 bottom（= -prefix(i-1)），
      // 超出上緣（bottom <= top 查詢值）即停。
      var blockBottom = -_beforeTree.prefixSum(startIndex - 1);
      final collected = <BlockKey>[];
      for (var i = startIndex; i < _beforeCenter.length; i += 1) {
        if (blockBottom <= top) break;
        final key = _beforeCenter[i];
        collected.add(key);
        blockBottom -= _metrics[key]!.height;
      }
      // before 側索引由近而遠（文檔序由下而上），反轉成由上而下。
      result.addAll(collected.reversed);
    }
    // after 側：block j 佔據 [prefix(j-1), prefix(j))。
    if (bottom > 0 && _centerAndAfter.isNotEmpty) {
      final lo = top < 0 ? 0.0 : top;
      final startIndex = _afterTree.firstPrefixGreaterThan(lo);
      if (startIndex != null) {
        var blockTop =
            startIndex == 0 ? 0.0 : _afterTree.prefixSum(startIndex - 1);
        for (var j = startIndex; j < _centerAndAfter.length; j += 1) {
          if (blockTop >= bottom) break;
          final key = _centerAndAfter[j];
          result.add(key);
          blockTop += _metrics[key]!.height;
        }
      }
    }
    return result;
  }

  @override
  double chapterExtent(int chapterIndex) {
    return chapterRange(chapterIndex)?.extent ?? 0.0;
  }

  /// 章節在文檔座標的範圍。同章 key 在兩側各自連續，二分定位 O(log n)。
  ChapterOffsetRange? chapterRange(int chapterIndex) {
    double? top;
    double? bottom;
    // after 側（遞增）：章首 = lowerBound(chapter, 0)。
    final afterFirst = _lowerBound(
      _centerAndAfter,
      BlockKey(chapterIndex: chapterIndex, blockIndex: 0),
      ascending: true,
    );
    if (afterFirst < _centerAndAfter.length &&
        _centerAndAfter[afterFirst].chapterIndex == chapterIndex) {
      final afterEnd = _lowerBound(
        _centerAndAfter,
        BlockKey(chapterIndex: chapterIndex + 1, blockIndex: 0),
        ascending: true,
      );
      top = topOf(_centerAndAfter[afterFirst]);
      bottom = bottomOf(_centerAndAfter[afterEnd - 1]);
    }
    // before 側（遞減）：同章 key 仍連續。
    final beforeFirst = _lowerBound(
      _beforeCenter,
      BlockKey(chapterIndex: chapterIndex + 1, blockIndex: 0),
      ascending: false,
    );
    if (beforeFirst < _beforeCenter.length &&
        _beforeCenter[beforeFirst].chapterIndex == chapterIndex) {
      final beforeEnd = _lowerBound(
        _beforeCenter,
        BlockKey(chapterIndex: chapterIndex, blockIndex: 0),
        ascending: false,
      );
      // before 側 index 越大越靠上——beforeEnd-1 是章內最上緣。
      final chapterTop = topOf(_beforeCenter[beforeEnd - 1]);
      final chapterBottom = bottomOf(_beforeCenter[beforeFirst]);
      if (chapterTop != null && (top == null || chapterTop < top)) {
        top = chapterTop;
      }
      if (chapterBottom != null && (bottom == null || chapterBottom > bottom)) {
        bottom = chapterBottom;
      }
    }
    if (top == null || bottom == null) return null;
    return ChapterOffsetRange(top: top, bottom: bottom);
  }

  /// ascending：回傳第一個 >= target 的索引；
  /// descending（before 側）：list 遞減，回傳第一個 < target 的索引。
  int _lowerBound(
    List<BlockKey> list,
    BlockKey target, {
    required bool ascending,
  }) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final goRight = ascending ? list[mid] < target : list[mid] >= target;
      if (goRight) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _rebuildAll() {
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
    _beforeCenter
      ..clear()
      ..addAll(before);
    _centerAndAfter
      ..clear()
      ..addAll(after);
    _beforePositions.clear();
    for (var i = 0; i < before.length; i += 1) {
      _beforePositions[before[i]] = i;
    }
    _afterPositions.clear();
    for (var i = 0; i < after.length; i += 1) {
      _afterPositions[after[i]] = i;
    }
    _beforeTree.rebuild(
      before.map((key) => _metrics[key]!.height).toList(growable: false),
    );
    _afterTree.rebuild(
      after.map((key) => _metrics[key]!.height).toList(growable: false),
    );
  }
}

/// 可增量 append 的 Fenwick tree：append 攤銷 O(log n)（容量翻倍時全量重建）。
final class _FenwickTree {
  final List<double> _values = <double>[];
  List<double> _tree = <double>[0.0];
  double _total = 0.0;

  int get length => _values.length;
  double get total => _total;

  void append(double value) {
    _values.add(value);
    _total += value;
    if (_values.length + 1 > _tree.length) {
      _regrow();
    } else {
      _add(_values.length - 1, value);
    }
  }

  void rebuild(List<double> values) {
    _values
      ..clear()
      ..addAll(values);
    _total = 0.0;
    for (final value in values) {
      _total += value;
    }
    _regrow();
  }

  void _regrow() {
    var capacity = 8;
    while (capacity < _values.length + 1) {
      capacity <<= 1;
    }
    _tree = List<double>.filled(capacity, 0.0);
    for (var i = 0; i < _values.length; i += 1) {
      _add(i, _values[i]);
    }
  }

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
      if (next <= length) {
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
