import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:reader/core/services/epub_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ResourceService - 應用內資源管理 (圖片、字體快取)
/// 用於處理 memory:// 等自定義協議資源
class ResourceService {
  static final ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal();

  final Map<String, Uint8Uint8List> _memoryCache = {};

  Future<void> persistMemoryResource(String key, Uint8List data) async {
    _memoryCache[key] = data;
    final file = await _resourceFile(key);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    await file.writeAsBytes(data, flush: true);
  }

  Future<Uint8List?> getMemoryResource(String key) async {
    final cached = _memoryCache[key];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final file = await _resourceFile(key);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _memoryCache[key] = bytes;
      return bytes;
    }

    final restored = await _tryRestoreFromLocalEpub(key);
    if (restored != null && restored.isNotEmpty) {
      _memoryCache[key] = restored;
      return restored;
    }
    return null;
  }

  Future<File> _resourceFile(String key) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupportDir.path, 'resource_cache'));
    final fileName = '${base64Url.encode(utf8.encode(key))}.bin';
    return File(p.join(dir.path, fileName));
  }

  Future<Uint8List?> _tryRestoreFromLocalEpub(String key) async {
    const prefix = 'memory://local://';
    if (!key.startsWith(prefix)) return null;

    final sourcePath = key.substring(prefix.length);
    if (!sourcePath.toLowerCase().endsWith('.epub')) return null;

    final file = File(sourcePath);
    if (!await file.exists()) return null;

    try {
      final meta = await EpubService().parseMetadata(file);
      final bytes = meta.coverBytes;
      if (bytes == null || bytes.isEmpty) return null;
      await persistMemoryResource(key, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

typedef Uint8Uint8List = Uint8List; // Fix for potential naming conflicts
