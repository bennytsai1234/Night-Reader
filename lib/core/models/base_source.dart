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

  Future<void> putLoginInfo(String info) {
    return CacheManager().put('userInfo_${getKey()}', info);
  }

  Future<String?> getLoginInfo() {
    return CacheManager().get('userInfo_${getKey()}');
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
    return CacheManager().delete('userInfo_${getKey()}');
  }

  Future<void> putLoginHeader(String header) async {
    await CacheManager().put('loginHeader_${getKey()}', header);
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
    return CacheManager().get('loginHeader_${getKey()}');
  }

  Future<void> removeLoginHeader() {
    return CacheManager().delete('loginHeader_${getKey()}');
  }

  Future<void> setVariable(String? variable) {
    if (variable == null) {
      return CacheManager().delete('sourceVariable_${getKey()}');
    }
    return CacheManager().put('sourceVariable_${getKey()}', variable);
  }

  Future<String> getVariable() async {
    return await CacheManager().get('sourceVariable_${getKey()}') ?? '';
  }

  void setVariableSync(String? variable) {
    final cacheManager = CacheManager();
    final cacheKey = 'sourceVariable_${getKey()}';
    if (variable == null) {
      cacheManager.deleteMemory(cacheKey);
      unawaited(cacheManager.delete(cacheKey));
      return;
    }
    cacheManager.putMemory(cacheKey, variable);
    unawaited(cacheManager.put(cacheKey, variable));
  }

  String getVariableSync() {
    return CacheManager()
            .getFromMemory('sourceVariable_${getKey()}')
            ?.toString() ??
        '';
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
      final loginHeaderRaw =
          CacheManager().getFromMemory('loginHeader_${getKey()}')?.toString();
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
