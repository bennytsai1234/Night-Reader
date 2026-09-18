import 'dart:collection';
import 'dart:ui' as ui;

import '../core/hybrid_contracts.dart';
import '../core/hybrid_types.dart';

final class _SharedParagraph {
  _SharedParagraph(this.paragraph, this.references);
  final ui.Paragraph paragraph;
  int references;

  void retain() => references += 1;

  void release() {
    assert(references > 0);
    references -= 1;
    if (references == 0) paragraph.dispose();
  }
}

final class ParagraphEntry {
  ParagraphEntry._(this._shared, this.bakedColor, this.localTop);
  final _SharedParagraph _shared;
  final ui.Color bakedColor;
  final double localTop;
  ui.Paragraph get paragraph => _shared.paragraph;
}

/// A consumer owns the drawable until it releases this lease. LRU eviction
/// only releases the cache's reference; it cannot invalidate a mounted render
/// object or a viewport transaction that is still using the paragraph.
final class ParagraphLease {
  ParagraphLease._(this._cache, this._key, this._onChanged);
  ParagraphCache? _cache;
  final _ParagraphCacheKey _key;
  final ui.VoidCallback? _onChanged;
  ParagraphEntry? _entry;

  ParagraphEntry? get entry => _entry;

  void _replace(ParagraphEntry? value) {
    if (identical(_entry, value)) return;
    value?._shared.retain();
    final previous = _entry;
    _entry = value;
    previous?._shared.release();
    _onChanged?.call();
  }

  void release() {
    final cache = _cache;
    if (cache == null) return;
    _cache = null;
    cache._releaseLease(this);
    _entry?._shared.release();
    _entry = null;
  }
}

/// The cache owns only reusable entries. Live consumers explicitly retain
/// entries, including an as-yet-unbuilt entry, and observe replacements for
/// their entire lifetime rather than racing a one-shot paint waiter.
final class ParagraphCache implements HybridParagraphCache {
  ParagraphCache({this.capacity = 512}) : assert(capacity > 0);
  final int capacity;
  final LinkedHashMap<_ParagraphCacheKey, ParagraphEntry> _entries =
      LinkedHashMap<_ParagraphCacheKey, ParagraphEntry>();
  final Map<_ParagraphCacheKey, Set<ParagraphLease>> _consumers = {};
  bool _disposed = false;

  int get length => _entries.length;

  ParagraphLease retain(
    BlockKey key,
    LayoutEpoch epoch, {
    ui.VoidCallback? onChanged,
  }) {
    if (_disposed) throw StateError('ParagraphCache has been disposed.');
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final lease = ParagraphLease._(this, cacheKey, onChanged);
    final entry = acquireEntry(key, epoch);
    _consumers.putIfAbsent(cacheKey, () => <ParagraphLease>{}).add(lease);
    // Initial acquisition does not notify a consumer that is still attaching.
    lease._entry = entry;
    entry?._shared.retain();
    return lease;
  }

  void _releaseLease(ParagraphLease lease) {
    final consumers = _consumers[lease._key];
    consumers?.remove(lease);
    if (consumers?.isEmpty ?? false) _consumers.remove(lease._key);
  }

  @override
  ui.Paragraph? acquire(BlockKey key, LayoutEpoch epoch) =>
      acquireEntry(key, epoch)?.paragraph;

  /// Borrow for a synchronous geometry query. Asynchronous consumers and
  /// render objects must hold a lease instead.
  ParagraphEntry? acquireEntry(BlockKey key, LayoutEpoch epoch) {
    final cacheKey = _ParagraphCacheKey(key, epoch);
    final entry = _entries.remove(cacheKey);
    if (entry != null) {
      _entries[cacheKey] = entry;
      return entry;
    }
    return _consumers[cacheKey]?.firstOrNull?.entry;
  }

  @override
  void put(
    BlockKey key,
    LayoutEpoch epoch,
    ui.Paragraph paragraph, {
    ui.Color bakedColor = const ui.Color(0xFF000000),
  }) => putGroup([key], const [0.0], epoch, paragraph, bakedColor: bakedColor);

  void putGroup(
    List<BlockKey> keys,
    List<double> localTops,
    LayoutEpoch epoch,
    ui.Paragraph paragraph, {
    ui.Color bakedColor = const ui.Color(0xFF000000),
  }) {
    if (_disposed) {
      paragraph.dispose();
      return;
    }
    assert(keys.isNotEmpty && keys.length == localTops.length);
    final shared = _SharedParagraph(paragraph, keys.length);
    for (var i = 0; i < keys.length; i += 1) {
      final cacheKey = _ParagraphCacheKey(keys[i], epoch);
      final entry = ParagraphEntry._(shared, bakedColor, localTops[i]);
      final previous = _entries.remove(cacheKey);
      _entries[cacheKey] = entry;
      // Acquire consumer references before releasing cache ownership or
      // enforcing capacity. A large group may exceed the idle cache budget.
      for (final consumer in List<ParagraphLease>.of(
        _consumers[cacheKey] ?? const <ParagraphLease>{},
      )) {
        consumer._replace(entry);
      }
      previous?._shared.release();
    }
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)?._shared.release();
    }
  }

  bool contains(BlockKey key, LayoutEpoch epoch) =>
      acquireEntry(key, epoch) != null;

  bool containsFresh(BlockKey key, LayoutEpoch epoch, ui.Color color) =>
      acquireEntry(key, epoch)?.bakedColor == color;

  /// Semantic invalidation, not eviction. Consumers must stop drawing content
  /// whose identity was explicitly revoked by the document owner.
  void invalidateChapter(int chapterIndex) {
    final keys = {..._entries.keys, ..._consumers.keys}
        .where((key) => key.blockKey.chapterIndex == chapterIndex)
        .toList(growable: false);
    for (final key in keys) {
      for (final consumer in List<ParagraphLease>.of(
        _consumers[key] ?? const <ParagraphLease>{},
      )) {
        consumer._replace(null);
      }
      _entries.remove(key)?._shared.release();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _entries.values) {
      entry._shared.release();
    }
    _entries.clear();
    // A render object can detach on the next Flutter frame. Its lease, not
    // cache disposal timing, owns the final native Paragraph reference.
  }
}

final class _ParagraphCacheKey {
  const _ParagraphCacheKey(this.blockKey, this.epoch);
  final BlockKey blockKey;
  final LayoutEpoch epoch;
  @override
  bool operator ==(Object other) =>
      other is _ParagraphCacheKey &&
      other.blockKey == blockKey &&
      other.epoch == epoch;
  @override
  int get hashCode => Object.hash(blockKey, epoch);
}
