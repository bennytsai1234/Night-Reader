import 'dart:collection';

/// A simple LRU (Least Recently Used) cache backed by a [LinkedHashMap].
///
/// When the number of entries exceeds [maxSize], the oldest (least recently
/// used) entry is evicted. Accessing an entry via [[]] promotes it to the
/// most-recent position.
class LruMap<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  LruMap({this.maxSize = 200}) : assert(maxSize > 0);

  /// Returns the number of entries in the cache.
  int get length => _map.length;

  /// Whether the cache contains the given [key].
  bool containsKey(K key) => _map.containsKey(key);

  /// Retrieves the value for [key], promoting it to most-recent.
  /// Returns `null` if the key is absent.
  V? operator [](K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  /// Inserts or updates [key] with [value], evicting the oldest entry if the
  /// cache exceeds [maxSize].
  void operator []=(K key, V value) {
    // Remove first so re-insertion places it at the end.
    _map.remove(key);
    _map[key] = value;
    if (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }

  /// If [key] is absent, calls [ifAbsent] to produce a value, inserts it, and
  /// returns it. If [key] is present, promotes it and returns the existing
  /// value.
  V putIfAbsent(K key, V Function() ifAbsent) {
    if (_map.containsKey(key)) {
      // Promote to most-recent.
      final value = _map.remove(key) as V;
      _map[key] = value;
      return value;
    }
    final value = ifAbsent();
    this[key] = value;
    return value;
  }

  /// Removes all entries.
  void clear() => _map.clear();
}
