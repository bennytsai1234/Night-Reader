import 'dart:async';

import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/utils/lru_map.dart';

/// 記憶體快取估算一筆值佔多少位元組：文字照 UTF-16 算，位元組陣列照長度，
/// 其他一律當 1KB。
int estimateMemorySize(Object? value) {
  if (value is String) return value.length * 2;
  if (value is List<int>) return value.length;
  return 1024;
}

/// CacheManager - 記憶體與資料庫兩層的文字快取，期限兩層都記
/// (原 Android help/CacheManager.kt)
class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;

  /// 主 isolate、書源 isolate 與網路 isolate 都註冊了資料庫；只準備記憶體
  /// 的測試沒有註冊，這時只用記憶體。
  CacheDao? get _cacheDao =>
      getIt.isRegistered<CacheDao>() ? getIt<CacheDao>() : null;

  // 記憶體快取 (50MB)
  final LruMap<String, Object?> _memoryCache = LruMap(
    maxSize: 1024 * 1024 * 50,
    sizeOf: estimateMemorySize,
  );
  final Map<String, int> _memoryDeadlines = <String, int>{};

  CacheManager._internal();

  /// 設定後，記憶體層的每次寫入與刪除（[value] 為 null）也交給它。主 isolate
  /// 與書源 isolate 各有一份記憶體快取，書源規則同步讀的變數
  /// （`source.getVariable()`、`@get`）只看記憶體，所以兩邊互相轉送寫入
  /// （ADR 0028）。從資料庫讀進記憶體的不轉送。
  static void Function(String key, Object? value, int deadline)? onMemoryWrite;

  /// 套用另一個 isolate 轉送來的寫入，不再轉送回去。
  void applyMirroredWrite(String key, Object? value, int deadline) {
    if (value == null) {
      _deleteMemory(key);
    } else {
      _putMemory(key, value, deadline: deadline);
    }
  }

  /// 讀取快取文本：先看記憶體，再看資料庫；過期的當作沒有。
  ///
  /// 過期的刪掉但不等它寫完：網路 isolate 替停住的書源 isolate 讀時，寫入
  /// 可能要等那條手上的交易，讀取不能跟著等（ADR 0034）。
  Future<String?> get(String key) async {
    // 1. 記憶體
    if (_isMemoryExpired(key)) {
      unawaited(delete(key));
      return null;
    }
    final mem = getFromMemory(key);
    if (mem is String) return mem;

    // 2. 資料庫
    final cache = await _cacheDao?.get(key);
    if (cache == null) return null;
    if (cache.deadline != 0 &&
        cache.deadline <= DateTime.now().millisecondsSinceEpoch) {
      unawaited(delete(key));
      return null;
    }
    _putMemory(key, cache.value, deadline: cache.deadline);
    return cache.value;
  }

  /// 保存快取文本 (記憶體 + 資料庫)。期限給 [saveTimeSeconds]（從現在
  /// 起算幾秒，0 是永久），或給 [deadline]（到期的時刻，毫秒，0 是永久；從
  /// 備份還原時照原本的時刻）。
  Future<void> put(
    String key,
    String content, {
    int saveTimeSeconds = 0,
    int? deadline,
  }) async {
    deadline ??= saveTimeSeconds == 0
        ? 0
        : DateTime.now().millisecondsSinceEpoch + saveTimeSeconds * 1000;
    _putMemory(key, content, deadline: deadline);
    onMemoryWrite?.call(key, content, deadline);
    await _cacheDao?.upsert(
      Cache(key: key, value: content, deadline: deadline),
    );
  }

  /// 記憶體快取專用介面
  void putMemory(String key, dynamic value) {
    _putMemory(key, value);
    onMemoryWrite?.call(key, value, 0);
  }

  dynamic getFromMemory(String key) => _memoryCache[key];

  /// 記憶體裡還沒過期的文字；沒有時是 null，要連資料庫一起找用 [get]。
  String? getMemoryText(String key) {
    if (_isMemoryExpired(key)) return null;
    final value = _memoryCache[key];
    return value is String ? value : null;
  }

  void deleteMemory(String key) {
    _deleteMemory(key);
    onMemoryWrite?.call(key, null, 0);
  }

  void _deleteMemory(String key) {
    _memoryDeadlines.remove(key);
    _memoryCache.remove(key);
  }

  void _putMemory(String key, dynamic value, {int deadline = 0}) {
    _memoryCache[key] = value;
    if (deadline == 0) {
      _memoryDeadlines.remove(key);
    } else {
      _memoryDeadlines[key] = deadline;
    }
  }

  bool _isMemoryExpired(String key) {
    final deadline = _memoryDeadlines[key];
    return deadline != null &&
        deadline <= DateTime.now().millisecondsSinceEpoch;
  }

  /// 把 [from] 存的內容複製到 [to]（記憶體與資料庫），保留原本的期限；
  /// [from] 照舊。沒有內容或已經過期時不寫，回傳 false。
  Future<bool> copy(String from, String to) async {
    final stored = await _cacheDao?.get(from);
    final deadline = stored?.deadline ?? _memoryDeadlines[from] ?? 0;
    final value = await get(from);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (value == null || (deadline != 0 && deadline <= now)) return false;
    await put(to, value, deadline: deadline);
    return true;
  }

  /// 以 [prefix] 開頭的鍵：資料庫的，加上只在記憶體裡的文字（沒有資料庫
  /// 的測試、還沒讀進記憶體以外的）。
  Future<List<String>> keysStartingWith(String prefix) async => {
    ...?await _cacheDao?.keysStartingWith(prefix),
    // 先抄出鍵再讀值：讀值會把那一筆排到最後，不能邊走邊讀。
    for (final key in [
      for (final key in _memoryCache.keys)
        if (key.startsWith(prefix)) key,
    ])
      if (_memoryCache[key] is String) key,
  }.toList();

  /// 刪除快取 (記憶體 + 資料庫)
  Future<void> delete(String key) async {
    deleteMemory(key);
    await _cacheDao?.deleteByKey(key);
  }
}
