import 'dart:collection';

/// 照最近使用排序的快取：放不下時先丟最久沒用的。
///
/// 上限 [maxSize] 預設算筆數；給了 [sizeOf] 就算每筆大小的加總，單筆就超過
/// 上限的不存（同一個鍵原本的值也一起拿掉）。讀取（`[]`、[putIfAbsent]）與
/// 寫入都算用過，排到最後；存的是 null 也一樣。
class LruMap<K, V> {
  final int maxSize;
  final int Function(V value) _sizeOf;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();
  int _size = 0;

  LruMap({this.maxSize = 200, int Function(V value)? sizeOf})
    : assert(maxSize > 0),
      _sizeOf = sizeOf ?? _one;

  static int _one(Object? _) => 1;

  /// 存了幾筆。
  int get length => _map.length;

  /// 從最久沒用的排到最近用過的；看這裡不算用過。
  Iterable<K> get keys => _map.keys;

  bool containsKey(K key) => _map.containsKey(key);

  /// [key] 存的值，並排到最後；沒有時是 null。
  V? operator [](K key) {
    if (!_map.containsKey(key)) return null;
    final value = _map.remove(key) as V;
    _map[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    remove(key);
    final size = _sizeOf(value);
    if (size > maxSize) return;
    while (_size + size > maxSize && _map.isNotEmpty) {
      remove(_map.keys.first);
    }
    _map[key] = value;
    _size += size;
  }

  /// 有 [key] 就回傳存的值並排到最後；沒有就用 [ifAbsent] 做一個存起來。
  V putIfAbsent(K key, V Function() ifAbsent) {
    if (_map.containsKey(key)) return this[key] as V;
    final value = ifAbsent();
    this[key] = value;
    return value;
  }

  /// 拿掉 [key]，回傳原本存的值；沒有時是 null。
  V? remove(K key) {
    if (!_map.containsKey(key)) return null;
    final value = _map.remove(key) as V;
    _size -= _sizeOf(value);
    return value;
  }

  void clear() {
    _map.clear();
    _size = 0;
  }
}
