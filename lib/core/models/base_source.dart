import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/core/services/app_log_service.dart';
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

  /// 有登入：填了登入網址或登入程式（`loginUrl`），同 Legado 顯示「登入」的
  /// 條件。
  bool get hasLogin => loginUrl?.trim().isNotEmpty ?? false;

  /// 書源的登入程式，同 Legado：`@js:`、`<js>` 包住的取裡面，其他照原樣
  /// （有表單的書源常不加前綴直接寫函式）。
  String? getLoginJs() => BaseSourceLoginHelper.extractLoginJs(loginUrl);

  /// 登入表單；null 是沒有表單，登入用網頁開 [loginUrl]。
  SourceLoginUi? get loginForm => SourceLoginUi.parse(loginUi);

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
  ///
  /// 快取和資料庫不在同一個交易裡，所以先複製到新身分，[commit]（存資料庫）
  /// 成功才刪舊的：[commit] 失敗時刪掉複製的，舊身分的資料原封不動；刪舊的
  /// 失敗只記下來，不算存檔失敗（舊身分已經沒有書源用它）。
  ///
  /// 規則變數的鍵是「`v_`＋身分＋`_`＋名稱」，另一個身分剛好以「[from]＋`_`」
  /// 開頭時，它的變數也落在同一個開頭底下；[otherKeys]（其他書源的身分）的
  /// 變數不搬。
  static Future<void> moveCachedIdentity(
    String from,
    String to, {
    required Future<void> Function() commit,
    Iterable<String> otherKeys = const [],
  }) async {
    final cache = CacheManager();
    final fromPrefix = _ruleVariablePrefix(from);
    final nested = [
      for (final other in otherKeys)
        if (other != from && other.startsWith('${from}_'))
          _ruleVariablePrefix(other),
    ];
    final moves = <(String, String)>[
      for (final keyOf in [_loginInfoKey, _variableKey, _loginHeaderKey])
        (keyOf(from), keyOf(to)),
      for (final key in await cache.keysStartingWith(fromPrefix))
        if (!nested.any(key.startsWith))
          (
            key,
            '${_ruleVariablePrefix(to)}${key.substring(fromPrefix.length)}',
          ),
    ];
    final copied = <String>[];
    try {
      for (final (old, next) in moves) {
        if (await cache.copy(old, next)) copied.add(next);
      }
      await commit();
    } catch (_) {
      for (final key in copied) {
        await cache.delete(key);
      }
      rethrow;
    }
    for (final (old, _) in moves) {
      try {
        await cache.delete(old);
      } catch (error) {
        AppLog.w('書源換了網址，舊網址的快取 $old 沒刪掉: $error');
      }
    }
  }

  /// 書源刪掉了：以它的身分（[key]）存的登入資訊、登入標頭、書源變數與
  /// 規則變數一起刪。網站的 Cookie 留著：同一個網站的其他書源可能也在用。
  /// [otherKeys] 是還在的書源，同 [moveCachedIdentity]，身分剛好以
  /// 「[key]＋`_`」開頭的書源的變數不刪。
  static Future<void> forgetCachedIdentity(
    String key, {
    Iterable<String> otherKeys = const [],
  }) async {
    final cache = CacheManager();
    final prefix = _ruleVariablePrefix(key);
    final nested = [
      for (final other in otherKeys)
        if (other != key && other.startsWith('${key}_'))
          _ruleVariablePrefix(other),
    ];
    for (final keyOf in [_loginInfoKey, _variableKey, _loginHeaderKey]) {
      await cache.delete(keyOf(key));
    }
    for (final variable in await cache.keysStartingWith(prefix)) {
      if (!nested.any(variable.startsWith)) await cache.delete(variable);
    }
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

  /// 這個書源存過任何登入資料：表單內容、登入標頭或網站的 Cookie。
  Future<bool> hasLoginData() async =>
      (await getLoginInfo() ?? '').isNotEmpty ||
      (await getLoginHeader() ?? '').isNotEmpty ||
      (await CookieStore().getCookie(getKey())).isNotEmpty;

  /// 清掉這個書源的登入資料：表單內容、登入標頭與夜讀存的網站 Cookie。
  /// 手機瀏覽器裡的 Cookie 由呼叫端另外清（只有主 isolate 碰得到瀏覽器）。
  Future<void> clearLoginData() async {
    await removeLoginInfo();
    await removeLoginHeader();
    await CookieStore().removeCookie(getKey());
  }

  /// 登入標頭解成的標頭；沒有或格式不對時是空的。
  static Map<String, String> decodeLoginHeader(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
        };
      }
    } catch (_) {}
    return const {};
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
      headerMap.addAll(
        decodeLoginHeader(
          CacheManager().getFromMemory(loginHeaderCacheKey)?.toString(),
        ),
      );
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
    return rawLoginUrl;
  }
}
