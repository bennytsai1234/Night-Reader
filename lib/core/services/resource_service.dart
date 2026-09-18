import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ResourceService - 應用內資源管理 (圖片、字體快取)
/// 用於處理 memory:// 等自定義協議資源
class ResourceService {
  static final ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal();

  final Map<String, Uint8List> _memoryCache = {};

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

    return null;
  }

  Future<File> _resourceFile(String key) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupportDir.path, 'resource_cache'));
    final fileName = '${base64Url.encode(utf8.encode(key))}.bin';
    return File(p.join(dir.path, fileName));
  }
}
