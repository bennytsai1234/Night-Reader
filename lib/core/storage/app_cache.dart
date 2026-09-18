import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../services/app_log_service.dart';
import 'app_storage_paths.dart';

/// AppCache - 磁碟快取工具 (原 Android utils/ACache.kt)
/// 支援 String, JSON, Bytes 與過期時間管理
class AppCache {
  static const int timeHour = 3600;
  static const int timeDay = timeHour * 24;
  static const int maxSize = 1000 * 1000 * 50; // 50 MB
  static const int maxCount = 1000000;

  static final Map<String, AppCache> _instances = {};

  final Directory cacheDir;
  final int limitSize;
  final int limitCount;
  bool _isTrimming = false;
  Completer<void>? _trimCompleted;

  AppCache._(this.cacheDir, this.limitSize, this.limitCount);

  static Future<AppCache> get({
    String cacheName = 'AppCache',
    int maxSize = maxSize,
    int maxCount = maxCount,
  }) async {
    final root = await AppStoragePaths.temporaryDir();
    final dir = Directory(p.join(root.path, cacheName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final path = dir.path;
    if (!_instances.containsKey(path)) {
      _instances[path] = AppCache._(dir, maxSize, maxCount);
    }
    return _instances[path]!;
  }

  // =======================================
  // ============ String 資料 讀寫 ============
  // =======================================

  Future<void> put(String key, String value, [int? saveTime]) async {
    final file = _getFile(key);
    var content = value;
    if (saveTime != null && saveTime > 0) {
      content = _createDateInfo(saveTime) + value;
    }
    await file.writeAsString(content);
    await _trimCache();
  }

  Future<String?> getAsString(String key) async {
    final file = _getFile(key);
    if (!file.existsSync()) return null;

    try {
      final text = await file.readAsString();
      if (!_isDue(text)) {
        return _clearDateInfo(text);
      } else {
        await file.delete();
      }
    } catch (e, s) {
      AppLog.put('Unexpected Error', error: e, stackTrace: s);
    }
    return null;
  }

  Future<void> remove(String key) async {
    final file = _getFile(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // =======================================
  // ============ 內部輔助方法 ============
  // =======================================

  File _getFile(String key) {
    final fileName = sha256.convert(utf8.encode(key)).toString();
    return File(p.join(cacheDir.path, fileName));
  }

  String _createDateInfo(int seconds) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return '$currentTime-$seconds ';
  }

  bool _isDue(String str) {
    return _isDueBytes(
      Uint8List.fromList(
        str.substring(0, str.length > 32 ? 32 : str.length).codeUnits,
      ),
    );
  }

  bool _isDueBytes(Uint8List data) {
    try {
      final info = _getDateInfo(data);
      if (info != null) {
        final saveTime = int.parse(info[0]);
        final deleteAfter = int.parse(info[1]);
        if (DateTime.now().millisecondsSinceEpoch >
            saveTime + deleteAfter * 1000) {
          return true;
        }
      }
    } catch (e, s) {
      AppLog.put('Unexpected Error', error: e, stackTrace: s);
    }
    return false;
  }

  List<String>? _getDateInfo(Uint8List data) {
    if (data.length > 15 && data[13] == 45) {
      // '-' is 45
      final spaceIndex = data.indexOf(32); // ' ' is 32
      if (spaceIndex > 14) {
        final saveDate = String.fromCharCodes(data.sublist(0, 13));
        final deleteAfter = String.fromCharCodes(data.sublist(14, spaceIndex));
        if (int.tryParse(saveDate) == null ||
            int.tryParse(deleteAfter) == null) {
          return null;
        }
        return [saveDate, deleteAfter];
      }
    }
    return null;
  }

  String? _clearDateInfo(String str) {
    final prefix = Uint8List.fromList(
      str.substring(0, str.length > 32 ? 32 : str.length).codeUnits,
    );
    if (_getDateInfo(prefix) == null) return str;
    final spaceIndex = str.indexOf(' ');
    if (spaceIndex > 14) {
      return str.substring(spaceIndex + 1);
    }
    return str;
  }

  Future<void> _trimCache() async {
    while (_isTrimming) {
      await _trimCompleted!.future;
    }

    _isTrimming = true;
    final completed = Completer<void>();
    _trimCompleted = completed;
    try {
      final files = <_CacheFile>[];
      var totalSize = 0;
      for (final file in cacheDir.listSync().whereType<File>()) {
        final stat = await file.stat();
        files.add(
          _CacheFile(file: file, size: stat.size, modified: stat.modified),
        );
        totalSize += stat.size;
      }

      files.sort((a, b) {
        final byModified = a.modified.compareTo(b.modified);
        return byModified != 0
            ? byModified
            : a.file.path.compareTo(b.file.path);
      });

      final effectiveLimitCount = limitCount < 0 ? 0 : limitCount;
      final effectiveLimitSize = limitSize < 0 ? 0 : limitSize;
      while (files.length > effectiveLimitCount ||
          totalSize > effectiveLimitSize) {
        final oldest = files.removeAt(0);
        await oldest.file.delete();
        totalSize -= oldest.size;
      }
    } finally {
      _isTrimming = false;
      _trimCompleted = null;
      completed.complete();
    }
  }

  Future<void> clear() async {
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
      await cacheDir.create(recursive: true);
    }
  }
}

class _CacheFile {
  const _CacheFile({
    required this.file,
    required this.size,
    required this.modified,
  });

  final File file;
  final int size;
  final DateTime modified;
}
