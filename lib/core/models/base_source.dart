import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';

/// BaseSource - 資源來源基礎介面
/// (原 Android data/entities/BaseSource.kt)
abstract class BaseSource {
  String? get jsLib;
  bool? get enabledCookieJar;
  String? get concurrentRate;
  String? get header;
  String? get loginUrl;
  String? get loginUi;
  String? get loginCheckJs;

  String getTag();
  String getKey();

  String? getLoginJs() => BaseSourceLoginHelper.extractLoginJs(loginUrl);

  List<Map<String, dynamic>>? loginUiConfig() {
    final raw = loginUi;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList();
      }
    } catch (_) {}
    return null;
  }

  // 以書源身分（[getKey]）存在快取（[CacheManager]）裡的資料各自的鍵。
  static String _loginInfoKey(String key) => 'userInfo_$key';
  static String _variableKey(String key) => 'sourceVariable_$key';
  static String _loginHeaderKey(String key) => 'loginHeader_$key';
  static String _ruleVariablePrefix(String key) => 'v_${key}_';

  String get loginInfoCacheKey => _loginInfoKey(getKey());
  String get variableCacheKey => _variableKey(getKey());
  String get loginHeaderCacheKey => _loginHeaderKey(getKey());

  /// 規則 JS 用 `source.put`、`java.put` 存的變數 [name]。
  String ruleVariableCacheKey(String name) =>
      '${_ruleVariablePrefix(getKey())}$name';

  /// 書源換了身分（[getKey] 從 [from] 變成 [to]，例如書源改了網址）：以舊身分
  /// 存的登入資訊、登入標頭、書源變數與規則變數搬到新身分，不用重新登入。
  static Future<void> moveCachedIdentity(String from, String to) async {
    final cache = CacheManager();
    for (final keyOf in [_loginInfoKey, _variableKey, _loginHeaderKey]) {
      await cache.move(keyOf(from), keyOf(to));
    }
    await cache.movePrefix(_ruleVariablePrefix(from), _ruleVariablePrefix(to));
  }

  Future<void> putLoginInfo(String info) {
    return CacheManager().put(loginInfoCacheKey, info);
  }

  Future<String?> getLoginInfo() {
    return CacheManager().get(loginInfoCacheKey);
  }

  Future<Map<String, String>?> getLoginInfoMap() async {
    final info = await getLoginInfo();
    if (info == null || info.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(info);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> removeLoginInfo() {
    return CacheManager().delete(loginInfoCacheKey);
  }

  Future<void> putLoginHeader(String header) async {
    await CacheManager().put(loginHeaderCacheKey, header);
    try {
      final decoded = jsonDecode(header);
      if (decoded is Map) {
        final cookie = decoded['cookie'] ?? decoded['Cookie'];
        if (cookie != null && cookie.toString().isNotEmpty) {
          await CookieStore().setCookie(getKey(), cookie.toString());
        }
      }
    } catch (_) {}
  }

  Future<String?> getLoginHeader() {
    return CacheManager().get(loginHeaderCacheKey);
  }

  Future<void> removeLoginHeader() {
    return CacheManager().delete(loginHeaderCacheKey);
  }

  Future<void> setVariable(String? variable) {
    if (variable == null) {
      return CacheManager().delete(variableCacheKey);
    }
    return CacheManager().put(variableCacheKey, variable);
  }

  Future<String> getVariable() async {
    return await CacheManager().get(variableCacheKey) ?? '';
  }

  void setVariableSync(String? variable) {
    final cacheManager = CacheManager();
    final cacheKey = variableCacheKey;
    if (variable == null) {
      cacheManager.deleteMemory(cacheKey);
      unawaited(cacheManager.delete(cacheKey));
      return;
    }
    cacheManager.putMemory(cacheKey, variable);
    unawaited(cacheManager.put(cacheKey, variable));
  }

  String getVariableSync() {
    return CacheManager().getFromMemory(variableCacheKey)?.toString() ?? '';
  }

  Map<String, String> getHeaderMapSync({bool hasLoginHeader = true}) {
    final headerMap = <String, String>{};
    final rawHeader = header;
    if (rawHeader != null && rawHeader.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHeader);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            headerMap[key.toString()] = value.toString();
          });
        }
      } catch (_) {}
    }

    if (hasLoginHeader) {
      final loginHeaderRaw = CacheManager()
          .getFromMemory(loginHeaderCacheKey)
          ?.toString();
      if (loginHeaderRaw != null && loginHeaderRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(loginHeaderRaw);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              headerMap[key.toString()] = value.toString();
            });
          }
        } catch (_) {}
      }
    }
    return headerMap;
  }
}

class BaseSourceLoginHelper {
  static String? extractLoginJs(String? rawLoginUrl) {
    if (rawLoginUrl == null || rawLoginUrl.isEmpty) {
      return null;
    }
    if (rawLoginUrl.startsWith('@js:')) {
      return rawLoginUrl.substring(4);
    }
    if (rawLoginUrl.startsWith('<js>')) {
      final end = rawLoginUrl.toLowerCase().lastIndexOf('</js>');
      return end >= 4
          ? rawLoginUrl.substring(4, end)
          : rawLoginUrl.substring(4);
    }
    return null;
  }
}
