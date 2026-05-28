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

const _quickJsLibraryFileName = 'libquickjs_c_bridge_plugin.so';

String? _linuxQuickJsPubCachePath() {
  final candidates = <String>{
    if ((Platform.environment['PUB_CACHE'] ?? '').trim().isNotEmpty)
      Platform.environment['PUB_CACHE']!.trim(),
    if ((Platform.environment['HOME'] ?? '').trim().isNotEmpty)
      '${Platform.environment['HOME']!.trim()}/.pub-cache',
  };

  final matches = <String>[];
  for (final rootPath in candidates) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    try {
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final normalizedPath = entity.path.replaceAll('\\', '/');
        if (!normalizedPath.endsWith('/$_quickJsLibraryFileName')) continue;
        if (!normalizedPath.contains('/flutter_js-')) continue;
        if (!normalizedPath.contains('/linux/shared/')) continue;
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

bool _hasQuickJsLibraryInLdPath() {
  final ldLibraryPath = Platform.environment['LD_LIBRARY_PATH']?.trim();
  if (ldLibraryPath == null || ldLibraryPath.isEmpty) return false;
  return ldLibraryPath
      .split(':')
      .where((part) => part.isNotEmpty)
      .any((dir) => File('$dir/$_quickJsLibraryFileName').existsSync());
}

String? _preloadQuickJsFromPubCache() {
  if (!Platform.isLinux) return null;
  if (_quickJsPreloadedLibrary != null) {
    return _quickJsResolvedPathCache;
  }
  final path = _linuxQuickJsPubCachePath();
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

  if (_hasQuickJsLibraryInLdPath()) {
    _quickJsUnavailableReasonCache = '';
    return null;
  }

  if (!Platform.isLinux) {
    _quickJsUnavailableReasonCache = '';
    return null;
  }

  final preloadedPath = _preloadQuickJsFromPubCache();
  if (preloadedPath != null) {
    _quickJsUnavailableReasonCache = '';
    return null;
  }

  const reason =
      'QuickJS runtime unavailable: set LIBQUICKJSC_TEST_PATH or use tool/flutter_test_with_quickjs.sh';
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
