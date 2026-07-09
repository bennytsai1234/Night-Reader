import 'dart:collection';
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class ParagraphCache implements HybridParagraphCache {
  ParagraphCache({this.capacity = 160}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<_ParagraphCacheKey, ui.Paragraph> _entries =
      LinkedHashMap<_ParagraphCacheKey, ui.Paragraph>();
  final Set<_ParagraphCacheKey> _pinned = <_ParagraphCacheKey>{};

  int get length => _entries.length;

  @override
  ui.Paragraph? acquire(BlockKey key, LayoutEpoch epoch) {
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final paragraph = _entries.remove(cacheKey);
    if (paragraph == null) return null;
    _entries[cacheKey] = paragraph;
    return paragraph;
  }

  @override
  void put(BlockKey key, LayoutEpoch epoch, ui.Paragraph paragraph) {
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final previous = _entries.remove(cacheKey);
    previous?.dispose();
    _entries[cacheKey] = paragraph;
    _evictIfNeeded();
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
    for (final paragraph in _entries.values) {
      paragraph.dispose();
    }
    _entries.clear();
    _pinned.clear();
  }

  bool contains(BlockKey key, LayoutEpoch epoch) {
    return _entries.containsKey(_ParagraphCacheKey(key, epoch));
  }

  void _evictIfNeeded() {
    while (_entries.length > capacity) {
      final evictKey = _entries.keys.firstWhere(
        (key) => !_pinned.contains(key),
        orElse: () => _entries.keys.first,
      );
      if (_pinned.contains(evictKey)) break;
      final paragraph = _entries.remove(evictKey);
      paragraph?.dispose();
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
