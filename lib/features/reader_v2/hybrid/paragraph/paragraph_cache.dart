import 'dart:collection';
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

/// 快取條目：Paragraph 連同建置時烘入的文字色。
/// paint 熱路徑以色相等與否決定「直繪」或「過渡 tint」。
final class ParagraphEntry {
  const ParagraphEntry(this.paragraph, this.bakedColor);

  final ui.Paragraph paragraph;
  final ui.Color bakedColor;
}

final class ParagraphCache implements HybridParagraphCache {
  ParagraphCache({this.capacity = 512}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<_ParagraphCacheKey, ParagraphEntry> _entries =
      LinkedHashMap<_ParagraphCacheKey, ParagraphEntry>();
  final Set<_ParagraphCacheKey> _pinned = <_ParagraphCacheKey>{};
  final Map<_ParagraphCacheKey, List<ui.VoidCallback>> _putWaiters =
      <_ParagraphCacheKey, List<ui.VoidCallback>>{};

  int get length => _entries.length;

  @override
  ui.Paragraph? acquire(BlockKey key, LayoutEpoch epoch) {
    return acquireEntry(key, epoch)?.paragraph;
  }

  /// LRU touch 並回傳條目（含烘色），供 paint 熱路徑單次查表取得兩者。
  ParagraphEntry? acquireEntry(BlockKey key, LayoutEpoch epoch) {
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final entry = _entries.remove(cacheKey);
    if (entry == null) return null;
    _entries[cacheKey] = entry;
    return entry;
  }

  @override
  void put(
    BlockKey key,
    LayoutEpoch epoch,
    ui.Paragraph paragraph, {
    ui.Color bakedColor = const ui.Color(0xFF000000),
  }) {
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final previous = _entries.remove(cacheKey);
    previous?.paragraph.dispose();
    _entries[cacheKey] = ParagraphEntry(paragraph, bakedColor);
    _evictIfNeeded();
    // 一次性消費：paint 撲空而空白的 render object 靠這裡收到重繪信號；
    // 除此之外沒有任何管道能讓「補建完成的段落」回到畫面上。
    final waiters = _putWaiters.remove(cacheKey);
    if (waiters != null) {
      for (final callback in waiters) {
        callback();
      }
    }
  }

  /// paint 撲空時註冊：該 key 的 Paragraph 進快取後回呼一次（一次性，
  /// put 時整組消費移除）。
  void addPutWaiter(BlockKey key, LayoutEpoch epoch, ui.VoidCallback callback) {
    _putWaiters
        .putIfAbsent(_ParagraphCacheKey(key, epoch), () => <ui.VoidCallback>[])
        .add(callback);
  }

  void removePutWaiter(
    BlockKey key,
    LayoutEpoch epoch,
    ui.VoidCallback callback,
  ) {
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final waiters = _putWaiters[cacheKey];
    if (waiters == null) return;
    waiters.remove(callback);
    if (waiters.isEmpty) _putWaiters.remove(cacheKey);
  }

  @override
  void pinRange(BlockRange range) {
    for (final key in _entries.keys) {
      if (range.contains(key.blockKey)) _pinned.add(key);
    }
  }

  void pinKeys(Iterable<BlockKey> keys, LayoutEpoch epoch) {
    for (final key in keys) {
      _pinned.add(_ParagraphCacheKey(key, epoch));
    }
  }

  @override
  void unpinAll() {
    _pinned.clear();
  }

  @override
  void dispose() {
    for (final entry in _entries.values) {
      entry.paragraph.dispose();
    }
    _entries.clear();
    _pinned.clear();
    _putWaiters.clear();
  }

  bool contains(BlockKey key, LayoutEpoch epoch) {
    return _entries.containsKey(_ParagraphCacheKey(key, epoch));
  }

  /// 存在且烘色與當前文字色一致。換色後回傳 false，讓視窗掃描重投
  /// LayoutTask 以新色漸進重建。
  bool containsFresh(BlockKey key, LayoutEpoch epoch, ui.Color color) {
    final entry = _entries[_ParagraphCacheKey(key, epoch)];
    return entry != null && entry.bakedColor == color;
  }

  void invalidateChapter(int chapterIndex) {
    final keys = _entries.keys
        .where((key) => key.blockKey.chapterIndex == chapterIndex)
        .toList(growable: false);
    for (final key in keys) {
      _pinned.remove(key);
      _entries.remove(key)?.paragraph.dispose();
    }
  }

  void _evictIfNeeded() {
    while (_entries.length > capacity) {
      final evictKey = _entries.keys.firstWhere(
        (key) => !_pinned.contains(key),
        orElse: () => _entries.keys.first,
      );
      if (_pinned.contains(evictKey)) break;
      final entry = _entries.remove(evictKey);
      entry?.paragraph.dispose();
    }
  }
}

final class _ParagraphCacheKey {
  const _ParagraphCacheKey(this.blockKey, this.epoch);

  final BlockKey blockKey;
  final LayoutEpoch epoch;

  @override
  bool operator ==(Object other) {
    return other is _ParagraphCacheKey &&
        other.blockKey == blockKey &&
        other.epoch == epoch;
  }

  @override
  int get hashCode => Object.hash(blockKey, epoch);
}
