import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/models/cookie.dart';

/// CookieStore - Cookie 管理服務
/// (原 Android help/http/CookieStore.kt)
class CookieStore {
  static final CookieStore _instance = CookieStore._internal();
  factory CookieStore() => _instance;
  CookieStore._internal();

  /// 背景 isolate 內 get_it 容器為空，CookieDao 不會被註冊；
  /// 此時退化為純記憶體模式（書源校驗不需要持久化 cookie）。
  CookieDao? get _cookieDao =>
      getIt.isRegistered<CookieDao>() ? getIt<CookieDao>() : null;
  final Map<String, String> _memoryCache = {};

  /// 設定後，記憶體層的每次寫入也交給它：[cookie] 為 null 是刪除，[domain]
  /// 也為 null 是全部清除。主 isolate 與書源 isolate 各有一份記憶體快取，
  /// 讀取時先看記憶體，所以兩邊互相轉送寫入（ADR 0028）。
  static void Function(String? domain, String? cookie)? onMemoryWrite;

  /// 套用另一個 isolate 轉送來的寫入，不再轉送回去。
  void applyMirroredWrite(String? domain, String? cookie) {
    if (domain == null) {
      _memoryCache.clear();
    } else if (cookie == null) {
      _memoryCache.remove(domain);
    } else {
      _memoryCache[domain] = cookie;
    }
  }

  /// 獲取二級域名
  String getSubDomain(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final parts = host.split('.');

      if (parts.length >= 3) {
        final lastPart = parts.last;
        final secondLastPart = parts[parts.length - 2];

        // 處理常見的兩段式後綴 (例如 .com.cn, .co.uk, .org.tw)
        final twoPartSuffixes = ['com', 'co', 'org', 'net', 'edu', 'gov'];
        if (twoPartSuffixes.contains(secondLastPart) && lastPart.length == 2) {
          return parts.sublist(parts.length - 3).join('.');
        }
      }

      if (parts.length >= 2) {
        return parts.sublist(parts.length - 2).join('.');
      }
      return host;
    } catch (e) {
      return url;
    }
  }

  /// 保存 Cookie
  Future<void> setCookie(String url, String? cookie) async {
    if (cookie == null || cookie.isEmpty) return;
    final domain = getSubDomain(url);
    _memoryCache[domain] = cookie;
    onMemoryWrite?.call(domain, cookie);
    await _cookieDao?.upsert(Cookie(url: domain, cookie: cookie));
  }

  /// 從備份還原：每筆的 `url` 已經是存放用的網域，照原樣寫回。
  Future<void> restoreAll(List<Cookie> cookies) async {
    for (final entry in cookies) {
      if (entry.url.isEmpty || entry.cookie.isEmpty) continue;
      _memoryCache[entry.url] = entry.cookie;
      onMemoryWrite?.call(entry.url, entry.cookie);
      await _cookieDao?.upsert(entry);
    }
  }

  /// 記憶體裡 [url] 的 Cookie；沒有時是 null，要連資料庫一起找用 [getCookie]。
  String? getMemoryCookie(String url) => _memoryCache[getSubDomain(url)];

  /// 獲取 Cookie
  Future<String> getCookie(String url) async {
    final domain = getSubDomain(url);

    // 優先從記憶體快取獲取
    if (_memoryCache.containsKey(domain)) {
      return _memoryCache[domain]!;
    }

    final cookieBean = await _cookieDao?.getByUrl(domain);
    if (cookieBean != null) {
      _memoryCache[domain] = cookieBean.cookie;
      return cookieBean.cookie;
    }
    return '';
  }

  /// 替換/合併 Cookie
  Future<void> replaceCookie(String url, String cookie) async {
    final oldCookie = await getCookie(url);
    if (oldCookie.isEmpty) {
      await setCookie(url, cookie);
    } else {
      final oldMap = cookieToMap(oldCookie);
      final newMap = cookieToMap(cookie);
      oldMap.addAll(newMap);
      await setCookie(url, mapToCookie(oldMap));
    }
  }

  /// 移除 Cookie
  Future<void> removeCookie(String url) async {
    final domain = getSubDomain(url);
    _memoryCache.remove(domain);
    onMemoryWrite?.call(domain, null);
    await _cookieDao?.deleteByUrl(domain);
  }

  /// 清除所有由 App 自行保存的 Cookie
  Future<void> clearAll() async {
    _memoryCache.clear();
    onMemoryWrite?.call(null, null);
    await _cookieDao?.clearAll();
  }

  /// 「a=1; b=2」轉成 Map，同 Legado `CookieStore.cookieToMap`：沒有 `=`
  /// 的項目與空值略過。
  Map<String, String> cookieToMap(String cookie) {
    final cookieMap = <String, String>{};
    if (cookie.trim().isEmpty) return cookieMap;

    for (final pair in cookie.split(';')) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      final key = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (value.isNotEmpty) cookieMap[key] = value;
    }
    return cookieMap;
  }

  /// 將 Map 轉換為 Cookie 字串
  String mapToCookie(Map<String, String> map) {
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
