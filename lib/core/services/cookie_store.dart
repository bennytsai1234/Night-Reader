import 'package:reader/core/di/injection.dart';
import 'package:reader/core/database/dao/cookie_dao.dart';
import 'package:reader/core/models/cookie.dart';

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
    await _cookieDao?.upsert(Cookie(url: domain, cookie: cookie));
  }

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
    await _cookieDao?.deleteByUrl(domain);
  }

  /// 清除所有由 App 自行保存的 Cookie
  Future<void> clearAll() async {
    _memoryCache.clear();
    await _cookieDao?.clearAll();
  }

  /// 將 Cookie 字串轉換為 Map
  Map<String, String> cookieToMap(String cookie) {
    final cookieMap = <String, String>{};
    if (cookie.isEmpty) return cookieMap;

    final pairs = cookie.split(RegExp(r';\s*'));
    for (var pair in pairs) {
      final parts = pair.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        if (value.isNotEmpty) {
          cookieMap[key] = value;
        }
      }
    }
    return cookieMap;
  }

  /// 將 Map 轉換為 Cookie 字串
  String mapToCookie(Map<String, String> map) {
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
