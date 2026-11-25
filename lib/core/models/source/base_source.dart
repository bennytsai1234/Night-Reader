import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/utils/cache_manager.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/utils/network_utils.dart';

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
  String get loginHeaderCacheKey => _loginHeaderKey(getKey());

  /// 書源變數（`source.setVariable`）。在草稿裡（[inDraftVariables]）是草稿
  /// 那一份。
  String get variableCacheKey => _variableKey(_variableIdentity(getKey()));

  /// 規則 JS 用 `source.put`、`java.put` 存的變數 [name]。在草稿裡
  /// （[inDraftVariables]）是草稿那一份。
  String ruleVariableCacheKey(String name) =>
      '${_ruleVariablePrefix(_variableIdentity(getKey()))}$name';

  // ── 草稿的變數 ─────────────────────────────────────────────────────
  //
  // AI 修書源拿還沒套用的草稿試抓、解析、跑程式與校驗時，規則存的書源變數
  // 與規則變數寫在草稿自己的一份，修好套用時才換掉書源的（[commitDraftVariables]）；
  // 沒套用就丟掉（[discardDraftVariables]）。登入資訊、登入標頭與 Cookie
  // 照書源的。

  static const Symbol _draftKey = #sourceDraftVariables;

  /// 現在這段程式在哪一份草稿裡（[inDraftVariables]）；不在草稿裡是 null。
  /// 送到書源 isolate 的工作跟著帶過去（`SourceWorker.run`）。
  static String? get draftVariables => Zone.current[_draftKey] as String?;

  /// 在草稿 [draft] 裡跑 [body]：裡面的書源變數與規則變數都是草稿那一份。
  static R inDraftVariables<R>(String draft, R Function() body) =>
      runZoned(body, zoneValues: {_draftKey: draft});

  /// 草稿的變數以這個身分存；一份草稿只修一個書源，不分網址。
  static String _draftIdentity(String draft) => 'draft:$draft';

  static String _variableIdentity(String key) => switch (draftVariables) {
    final draft? => _draftIdentity(draft),
    null => key,
  };

  /// 草稿 [draft] 從書源 [key] 現在的書源變數與規則變數開始；傳回抄進草稿
  /// 的每個鍵與值，套用時只寫回草稿改過的（[commitDraftVariables]）。
  static Future<Map<String, String>> startDraftVariables(
    String draft,
    String key,
  ) async {
    final started = <String, String>{};
    for (final (from, to) in await _variablePairs(key, _draftIdentity(draft))) {
      final cache = CacheManager();
      if (await cache.copy(from, to)) started[to] = (await cache.get(to))!;
    }
    return started;
  }

  /// 修好套用了：草稿 [draft] 改過的變數（和開始時抄進來的 [started] 不同、
  /// 或新存的）寫進書源 [key]（網址換了開頭時是新的網址），再丟掉草稿。
  /// 沒改過的不寫：修復這段時間書源自己存的（開場的校驗與試抓、閱讀）不被
  /// 開始時的舊值蓋回去。
  static Future<void> commitDraftVariables(
    String draft,
    String key, {
    required Map<String, String> started,
  }) async {
    final cache = CacheManager();
    for (final (from, to) in await _variablePairs(_draftIdentity(draft), key)) {
      final value = await cache.get(from);
      if (value == null || started[from] == value) continue;
      await cache.copy(from, to);
    }
    await discardDraftVariables(draft);
  }

  /// 丟掉草稿 [draft] 的變數。
  static Future<void> discardDraftVariables(String draft) async {
    final identity = _draftIdentity(draft);
    final cache = CacheManager();
    await cache.delete(_variableKey(identity));
    for (final key in await cache.keysStartingWith(
      _ruleVariablePrefix(identity),
    )) {
      await cache.delete(key);
    }
  }

  /// 身分 [from] 的書源變數與每個規則變數，各配上身分 [to] 的同一個鍵。
  static Future<List<(String, String)>> _variablePairs(
    String from,
    String to,
  ) async {
    final fromPrefix = _ruleVariablePrefix(from);
    return [
      (_variableKey(from), _variableKey(to)),
      for (final key in await CacheManager().keysStartingWith(fromPrefix))
        (key, '${_ruleVariablePrefix(to)}${key.substring(fromPrefix.length)}'),
    ];
  }

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
          // 併進這個網站原本存的，同名的換新（Legado `replaceCookie`）。
          await CookieStore().replaceCookie(getKey(), cookie.toString());
        }
      }
    } catch (_) {}
  }

  Future<String?> getLoginHeader() {
    return CacheManager().get(loginHeaderCacheKey);
  }

  /// 刪掉登入標頭，連夜讀存的網站 Cookie 一起清（同 Legado
  /// `BaseSource.removeLoginHeader`）；表單內容留著。標頭與 Cookie 兩邊都
  /// 先送出，再一起等：規則 JS 接著寫的新 Cookie 不會被後到的清除刪掉。
  Future<void> removeLoginHeader() async {
    final cookies = removeLoginCookies();
    final header = CacheManager().delete(loginHeaderCacheKey);
    await Future.wait([cookies, header]);
  }

  /// 這個書源存過任何登入資料：表單內容、登入標頭或網站的 Cookie。
  Future<bool> hasLoginData() async =>
      (await getLoginInfo() ?? '').isNotEmpty ||
      (await getLoginHeader() ?? '').isNotEmpty ||
      (await CookieStore().getCookie(getKey())).isNotEmpty;

  /// 清掉夜讀自己存的網站 Cookie 與 Cookie 罐裡這個網域的 Cookie（網站寫
  /// 的）；表單內容與登入標頭不動。
  Future<void> removeLoginCookies() {
    final stored = CookieStore().removeCookie(getKey());
    final jar = _removeCookieJarCookies(getKey());
    return Future.wait([stored, jar]);
  }

  /// Cookie 罐裡這個網域的 Cookie。沒初始化網路層的地方（有些測試、只讀
  /// 資料的呼叫）清不到就記一筆，CookieStore 照清。
  Future<void> _removeCookieJarCookies(String key) async {
    final uri = NetworkUtils.cookieJarUri(key);
    if (uri == null) return;
    try {
      await NetworkService().cookieJar.delete(uri, true);
    } catch (error) {
      AppLog.w('清 Cookie 罐裡的 Cookie 失敗: $error');
    }
  }

  /// 清掉這個書源的登入資料：表單內容、登入標頭與夜讀存的網站 Cookie。
  /// 手機瀏覽器裡的 Cookie 由呼叫端另外清（只有主 isolate 碰得到瀏覽器）。
  Future<void> clearLoginData() async {
    await removeLoginInfo();
    await removeLoginHeader();
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
    // `proxy` 是代理設定（可能含帳號密碼），不是送給網站的標頭。
    headerMap.remove('proxy');

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
