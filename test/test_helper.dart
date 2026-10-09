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
DynamicLibrary? _quickJsLibrary;

/// 在桌面上跑 QuickJS 的測試用橋接函式庫（App 在 Android 上用的是 flutter_js
/// 依賴帶的 libfastdev_quickjs_runtime.so）。flutter_js 在 FLUTTER_TEST 下以檔名
/// 開啟它，這裡先用完整路徑載入，之後以檔名開啟就會拿到同一份。
/// Linux 與 Windows 以外沒有對應的函式庫，回傳跳過原因；函式庫缺漏則直接失敗。
String? quickJsUnavailableReason() {
  final cached = _quickJsUnavailableReasonCache;
  if (cached != null) {
    return cached.isEmpty ? null : cached;
  }

  final String fileName;
  if (Platform.isLinux) {
    fileName = 'libquickjs_c_bridge_plugin.so';
  } else if (Platform.isWindows) {
    fileName = 'quickjs_c_bridge.dll';
  } else {
    return _quickJsUnavailableReasonCache =
        'QuickJS test library is only provided for Linux and Windows';
  }

  _quickJsLibrary ??= DynamicLibrary.open(
    File('test/fixtures/quickjs/$fileName').absolute.path,
  );
  _quickJsUnavailableReasonCache = '';
  return null;
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
