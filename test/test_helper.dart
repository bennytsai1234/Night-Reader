import 'dart:ffi';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/models/cookie.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCookieDao extends Fake implements CookieDao {
  @override
  Future<Cookie?> getByUrl(String url) async => null;

  @override
  Future<void> upsert(Cookie cookie) async {}

  @override
  Future<void> deleteByUrl(String url) async {}
}

class FakeCacheDao extends Fake implements CacheDao {
  @override
  Future<Cache?> get(String key) async => null;

  @override
  Future<void> upsert(Cache cache) async {}

  @override
  Future<void> deleteByKey(String key) async {}
}

String? _quickJsUnavailableReasonCache;
DynamicLibrary? _quickJsPreloadedLibrary;
String? _quickJsResolvedPathCache;

/// 描述某個桌面平台上，QuickJS 原生橋接函式庫的檔名/在 pub cache 內的子目錄，
/// 以及該平台的動態函式庫搜尋路徑環境變數——讓值測邏輯不必為每個平台各寫一份。
class _QuickJsPlatformInfo {
  const _QuickJsPlatformInfo({
    required this.libraryFileName,
    required this.pubCacheSharedDirSegment,
    required this.pathEnvVar,
    required this.pathSeparator,
  });

  final String libraryFileName;
  final String pubCacheSharedDirSegment;
  final String pathEnvVar;
  final String pathSeparator;
}

_QuickJsPlatformInfo? _currentQuickJsPlatformInfo() {
  if (Platform.isLinux) {
    return const _QuickJsPlatformInfo(
      libraryFileName: 'libquickjs_c_bridge_plugin.so',
      pubCacheSharedDirSegment: '/linux/shared/',
      pathEnvVar: 'LD_LIBRARY_PATH',
      pathSeparator: ':',
    );
  }
  if (Platform.isWindows) {
    return const _QuickJsPlatformInfo(
      libraryFileName: 'quickjs_c_bridge.dll',
      pubCacheSharedDirSegment: '/windows/shared/',
      pathEnvVar: 'PATH',
      pathSeparator: ';',
    );
  }
  return null;
}

String? _quickJsPubCachePath(_QuickJsPlatformInfo info) {
  final candidates = <String>{
    if ((Platform.environment['PUB_CACHE'] ?? '').trim().isNotEmpty)
      Platform.environment['PUB_CACHE']!.trim(),
    if ((Platform.environment['HOME'] ?? '').trim().isNotEmpty)
      '${Platform.environment['HOME']!.trim()}/.pub-cache',
    if ((Platform.environment['LOCALAPPDATA'] ?? '').trim().isNotEmpty)
      '${Platform.environment['LOCALAPPDATA']!.trim()}/Pub/Cache',
  };

  final matches = <String>[];
  for (final rootPath in candidates) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    try {
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final normalizedPath = entity.path.replaceAll('\\', '/');
        if (!normalizedPath.endsWith('/${info.libraryFileName}')) continue;
        if (!normalizedPath.contains('/flutter_js-')) continue;
        if (!normalizedPath.contains(info.pubCacheSharedDirSegment)) continue;
        matches.add(entity.path);
      }
    } on FileSystemException {
      continue;
    }
  }

  if (matches.isEmpty) return null;
  matches.sort();
  return matches.last;
}

bool _hasQuickJsLibraryInPathEnv(_QuickJsPlatformInfo info) {
  final pathEnv = Platform.environment[info.pathEnvVar]?.trim();
  if (pathEnv == null || pathEnv.isEmpty) return false;
  return pathEnv
      .split(info.pathSeparator)
      .where((part) => part.isNotEmpty)
      .any((dir) => File('$dir/${info.libraryFileName}').existsSync());
}

String? _preloadQuickJsFromPubCache(_QuickJsPlatformInfo info) {
  if (_quickJsPreloadedLibrary != null) {
    return _quickJsResolvedPathCache;
  }
  final path = _quickJsPubCachePath(info);
  if (path == null) return null;
  try {
    _quickJsPreloadedLibrary = DynamicLibrary.open(path);
    _quickJsResolvedPathCache = path;
    return path;
  } catch (_) {
    return null;
  }
}

String? quickJsUnavailableReason() {
  final cached = _quickJsUnavailableReasonCache;
  if (cached != null) {
    return cached.isEmpty ? null : cached;
  }

  final explicitPath = Platform.environment['LIBQUICKJSC_TEST_PATH']?.trim();
  if (explicitPath != null && explicitPath.isNotEmpty) {
    if (File(explicitPath).existsSync()) {
      _quickJsUnavailableReasonCache = '';
      return null;
    }
    final reason =
        'QuickJS runtime unavailable: LIBQUICKJSC_TEST_PATH does not exist ($explicitPath)';
    _quickJsUnavailableReasonCache = reason;
    return reason;
  }

  final platformInfo = _currentQuickJsPlatformInfo();
  if (platformInfo == null) {
    // 未知平台（例如 macOS）：沒有對應的值測邏輯，維持原本「假設可用」的保守行為，
    // 避免在沒把握的平台上誤判導致測試被跳過。
    _quickJsUnavailableReasonCache = '';
    return null;
  }

  if (_hasQuickJsLibraryInPathEnv(platformInfo)) {
    _quickJsUnavailableReasonCache = '';
    return null;
  }

  final preloadedPath = _preloadQuickJsFromPubCache(platformInfo);
  if (preloadedPath != null) {
    _quickJsUnavailableReasonCache = '';
    return null;
  }

  final reason =
      'QuickJS runtime unavailable: set LIBQUICKJSC_TEST_PATH or use tool/flutter_test_with_quickjs.sh '
      '(looked for ${platformInfo.libraryFileName})';
  _quickJsUnavailableReasonCache = reason;
  return reason;
}

void setupTestDI() {
  quickJsUnavailableReason();
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<CookieDao>()) {
    getIt.registerLazySingleton<CookieDao>(() => FakeCookieDao());
  }
  if (!getIt.isRegistered<CacheDao>()) {
    getIt.registerLazySingleton<CacheDao>(() => FakeCacheDao());
  }
}
