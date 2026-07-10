import 'package:night_reader/core/di/injection.dart';
import 'dart:io';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';

/// LruMemoryCache - 簡易 LRU 記憶體快取
/// (原 Android LruCache) (String, Any)
class LruMemoryCache {
  final int maxSize;
  int _currentSize = 0;
  final LinkedHashMap<String, dynamic> _cache =
      LinkedHashMap<String, dynamic>();

  LruMemoryCache(this.maxSize);

  void put(String key, dynamic value) {
    _remove(key);
    final size = _estimateSize(value);

    // 若單個物件就超過上限，則不快取
    if (size > maxSize) return;

    while (_currentSize + size > maxSize && _cache.isNotEmpty) {
      final firstKey = _cache.keys.first;
      _remove(firstKey);
    }

    _cache[key] = value;
    _currentSize += size;
  }

  dynamic get(String key) {
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value; // 重新插入以更新排序
    }
    return value;
  }

  void remove(String key) => _remove(key);

  void _remove(String key) {
    final value = _cache.remove(key);
    if (value != null) {
      _currentSize -= _estimateSize(value);
    }
  }

  void clear() {
    _cache.clear();
    _currentSize = 0;
  }

  int _estimateSize(dynamic value) {
    if (value is String) return value.length * 2; // 估算為 UTF-16
    if (value is List<int>) return value.length;
    return 1024; // 預設估算
  }

  Iterable<String> get keys => _cache.keys;
}

/// CacheManager - 檔案與記憶體雙層快取管理器
/// (原 Android help/CacheManager.kt)
class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;

  /// 背景 isolate（書源批量校驗）內 get_it 容器為空，CacheDao 不會被註冊；
  /// 此時退化為記憶體 + 檔案快取（不寫 DB），避免建構或讀寫時拋
  /// 「CacheDao is not registered」。對標 [CookieStore] 的相同處理。
  CacheDao? get _cacheDao =>
      getIt.isRegistered<CacheDao>() ? getIt<CacheDao>() : null;

  // 記憶體快取 (50MB)
  final LruMemoryCache _memoryCache = LruMemoryCache(1024 * 1024 * 50);
  final Map<String, int> _memoryDeadlines = <String, int>{};

  CacheManager._internal();

  /// 獲取快取檔案路徑 (對標 js_cache 目錄)
  Future<String> getCachePath(String key) async {
    final cacheDir = await AppStoragePaths.jsCacheDir();
    final safeKey = key.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return p.join(cacheDir.path, safeKey);
  }

  /// 讀取快取文本 (優先從記憶體，再從磁碟資料庫，最後從檔案系統)
  Future<String?> get(String key) async {
    // 1. 記憶體
    if (_isMemoryExpired(key)) {
      await delete(key);
      return null;
    }
    final mem = getFromMemory(key);
    if (mem is String) return mem;

    // 2. 資料庫 (磁碟快取實體)
    final cacheDao = _cacheDao;
    if (cacheDao != null) {
      final cache = await cacheDao.get(key);
      if (cache != null) {
        if (cache.deadline == 0 ||
            cache.deadline > DateTime.now().millisecondsSinceEpoch) {
          _putMemory(key, cache.value, deadline: cache.deadline);
          return cache.value;
        } else {
          await delete(key); // 已過期，清理
          return null;
        }
      }
    }

    // 3. 檔案系統 (JS 快取)
    final path = await getCachePath(key);
    final file = File(path);
    if (await file.exists()) {
      final content = await file.readAsString();
      putMemory(key, content);
      return content;
    }
    return null;
  }

  /// 保存快取文本 (記憶體 + 資料庫 + 檔案)
  Future<void> put(
    String key,
    String content, {
    int saveTimeSeconds = 0,
  }) async {
    final deadline =
        saveTimeSeconds == 0
            ? 0
            : DateTime.now().millisecondsSinceEpoch + saveTimeSeconds * 1000;
    _putMemory(key, content, deadline: deadline);

    // 儲存至資料庫

    await _cacheDao?.upsert(
      Cache(key: key, value: content, deadline: deadline),
    );

    // 儲存至檔案
    final path = await getCachePath(key);
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(content);
  }

  /// 記憶體快取專用介面
  void putMemory(String key, dynamic value) => _putMemory(key, value);
  dynamic getFromMemory(String key) => _memoryCache.get(key);
  void deleteMemory(String key) {
    _memoryDeadlines.remove(key);
    _memoryCache.remove(key);
  }

  void _putMemory(String key, dynamic value, {int deadline = 0}) {
    _memoryCache.put(key, value);
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

  /// 刪除快取 (記憶體 + 資料庫 + 檔案)
  Future<void> delete(String key) async {
    deleteMemory(key);
    await _cacheDao?.deleteByKey(key);
    final path = await getCachePath(key);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
