import 'dart:collection';
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

/// 連續排版 group 的共用 Paragraph：group 內每個 block 各自持有一個
/// [ParagraphEntry] 但共用同一個 [paragraph]，靠參照計數決定何時真正
/// dispose——LRU 只逐出單一 BlockKey 時，其餘仍在快取中的組員必須繼續
/// 能畫，Paragraph 不能被提前釋放。
final class _SharedParagraph {
  _SharedParagraph(this.paragraph, this._refCount);

  final ui.Paragraph paragraph;
  int _refCount;

  void release() {
    _refCount -= 1;
    if (_refCount <= 0) paragraph.dispose();
  }
}

/// 快取條目：Paragraph 連同建置時烘入的文字色，以及此 block 在共用
/// Paragraph 裡自己的 Y 窗起點（非 group 或 group 頭塊為 0）。
/// paint 熱路徑以色相等與否決定「直繪」或「過渡 tint」。
final class ParagraphEntry {
  ParagraphEntry._(this._shared, this.bakedColor, this.localTop);

  final _SharedParagraph _shared;
  final ui.Color bakedColor;

  /// 此 block 自己的內容在 [paragraph] 座標系中的頂端 Y；paint／幾何查詢
  /// 要換算回「此 block 自己 Y 窗」座標時，一律以此為準做平移。
  final double localTop;

  ui.Paragraph get paragraph => _shared.paragraph;
}

final class ParagraphCache implements HybridParagraphCache {
  ParagraphCache({this.capacity = 512}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<_ParagraphCacheKey, ParagraphEntry> _entries =
      LinkedHashMap<_ParagraphCacheKey, ParagraphEntry>();

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
    putGroup(
      <BlockKey>[key],
      const <double>[0.0],
      epoch,
      paragraph,
      bakedColor: bakedColor,
    );
  }

  /// 一次放入一個連續排版 group 的所有 block：[keys] 與 [localTops] 一一
  /// 對應，全部共用同一個 [paragraph]（靠參照計數延後 dispose）。單一
  /// block（非 group）走這條路徑時等同舊版 [put]。
  void putGroup(
    List<BlockKey> keys,
    List<double> localTops,
    LayoutEpoch epoch,
    ui.Paragraph paragraph, {
    ui.Color bakedColor = const ui.Color(0xFF000000),
  }) {
    assert(keys.isNotEmpty);
    assert(keys.length == localTops.length);
    final shared = _SharedParagraph(paragraph, keys.length);
    final touchedWaiterKeys = <_ParagraphCacheKey>[];
    for (var i = 0; i < keys.length; i += 1) {
      final cacheKey = _ParagraphCacheKey(keys[i], epoch);
      final previous = _entries.remove(cacheKey);
      previous?._shared.release();
      _entries[cacheKey] = ParagraphEntry._(shared, bakedColor, localTops[i]);
      touchedWaiterKeys.add(cacheKey);
    }
  }

  @override
  void pinRange(BlockRange range) {}

  void pinKeys(Iterable<BlockKey> keys, LayoutEpoch epoch) {}

  @override
  void unpinAll() {}

  void trimToCapacity() {}

  @override
  void dispose() {
    for (final entry in _entries.values) {
      entry._shared.release();
    }
    _entries.clear();
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
      _entries.remove(key)?._shared.release();
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
