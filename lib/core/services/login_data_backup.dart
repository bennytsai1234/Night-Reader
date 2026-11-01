import 'dart:convert';
import 'dart:io' as io;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/models/cookie.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/network_service.dart';

typedef _CookiesByDomain =
    Map<String, Map<String, Map<String, SerializableCookie>>>;

/// 備份裡的登入資料，換一台手機還原後不用重新登入（ADR 0039）：
///
/// - [cacheFile]：書源快取裡還沒過期的內容：登入表單、登入標頭、書源變數，
///   以及書源程式用 `cache.put` 存的通行證。
/// - [cookieFile]：書源網站的 Cookie（網頁登入存的、規則 `cookie.setCookie`
///   存的），每次抓取併進請求。
/// - [cookieJarFile]：網路請求收到、存在 Cookie 檔裡的 Cookie。
///
/// 過期由網站或書源自己定：快取的保存期限是書源程式存的時候給的（沒給就
/// 永久），Cookie 的到期時間是網站給的（沒給就一直留著）；已經過期的不帶。
abstract final class LoginDataBackup {
  static const cacheFile = 'cache.json';
  static const cookieFile = 'cookie.json';
  static const cookieJarFile = 'cookieJar.json';
  static const files = {cacheFile, cookieFile, cookieJarFile};

  static Future<List<Map<String, dynamic>>> exportCache() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final entry in await getIt<CacheDao>().getLive(now))
        if (entry.value != null) entry.toJson(),
    ];
  }

  static Future<List<Map<String, dynamic>>> exportCookies() async => [
    for (final cookie in await getIt<CookieDao>().getAll()) cookie.toJson(),
  ];

  /// Cookie 檔裡每一筆還沒過期的 Cookie：`url` 是存它的網域與路徑，`cookie`
  /// 是 `Set-Cookie` 的寫法，期限一律寫成到期時刻，還原那天不重新起算。
  ///
  /// 直接讀 Cookie 檔，不經 [PersistCookieJar] 載入：它讀到壞掉的檔會刪掉，
  /// 備份不該動到來源。讀不懂的檔記在日誌、略過（App 本來也用不了它）。
  static Future<List<Map<String, String>>> exportCookieJar([
    CookieJar? cookieJar,
  ]) async {
    final jar = cookieJar ?? NetworkService().cookieJar;
    final (domainCookies, hostCookies) = switch (jar) {
      PersistCookieJar() => await _readPersisted(jar),
      DefaultCookieJar() => (jar.domainCookies, jar.hostCookies),
      _ => (const <String, Never>{}, const <String, Never>{}),
    };
    final entries = <Map<String, String>>[];
    for (final byDomain in [domainCookies, hostCookies]) {
      byDomain.forEach((domain, byPath) {
        byPath.forEach((path, byName) {
          for (final stored in byName.values) {
            if (stored.isExpired()) continue;
            final cookie = _withAbsoluteExpiry(stored, path);
            if (cookie == null) continue;
            entries.add({
              'url': Uri(scheme: 'https', host: domain, path: path).toString(),
              'cookie': cookie.toString(),
            });
          }
        });
      });
    }
    return entries;
  }

  /// 還原 [LoginDataBackup.files] 其中一個檔：先整份檢查完再寫，有一筆格式
  /// 不對就丟出 [FormatException]、什麼都不寫，由呼叫端記為失敗。已經過期
  /// 的照常略過，不算格式不對。
  static Future<bool> restore(
    String fileName,
    List<dynamic> items, {
    CookieJar? cookieJar,
  }) async {
    switch (fileName) {
      case cacheFile:
        final entries = items.map(_parseCache).toList();
        for (final entry in entries) {
          // 前面幾筆寫入時時間在走，輪到這筆才看有沒有過期。
          final now = DateTime.now().millisecondsSinceEpoch;
          if (entry.deadline != 0 && entry.deadline <= now) continue;
          await CacheManager().put(
            entry.key,
            entry.value!,
            deadline: entry.deadline,
          );
        }
      case cookieFile:
        await CookieStore().restoreAll(items.map(_parseCookie).toList());
      case cookieJarFile:
        final cookies = items.map(_parseJarEntry).toList();
        final jar = cookieJar ?? NetworkService().cookieJar;
        // PersistCookieJar 寫一個網站時整份檔重寫成記憶體裡的內容，網站的檔
        // 還沒讀進來就寫，原本存的 Cookie 會被蓋掉；先讀進來再合併。
        if (jar is PersistCookieJar) {
          for (final host in {for (final (uri, _) in cookies) uri.host}) {
            await jar.loadForRequest(Uri(scheme: 'https', host: host));
          }
        }
        for (final (uri, cookie) in cookies) {
          await jar.saveFromResponse(uri, [cookie]);
        }
      default:
        return false;
    }
    return true;
  }

  static Future<(_CookiesByDomain, _CookiesByDomain)> _readPersisted(
    PersistCookieJar jar,
  ) async {
    final storage = jar.storage;
    // 只決定資料夾位置（沒有就建），不讀不刪；App 啟動後還沒發過請求時
    // 存放處還沒準備好。
    await storage.init(jar.persistSession, jar.ignoreExpires);
    // 檔名與格式照 cookie_jar 4.x 的 PersistCookieJar：`.domains` 是帶
    // Domain 的 Cookie，`.index` 列出存了哪些網站，每個網站一個檔。
    final domains = <String, Map<String, Map<String, SerializableCookie>>>{};
    final rawDomains = _decodeJsonFile(
      await storage.read('.domains'),
      '.domains',
    );
    if (rawDomains is Map) {
      rawDomains.forEach((domain, byPath) {
        if (_decodeByPath(byPath, '.domains') case final decoded?) {
          domains[domain.toString()] = decoded;
        }
      });
    }
    final hosts = <String, Map<String, Map<String, SerializableCookie>>>{};
    final index = _decodeJsonFile(await storage.read('.index'), '.index');
    for (final host in index is List ? index.whereType<String>() : <String>[]) {
      final raw = _decodeJsonFile(await storage.read(host), host);
      if (_decodeByPath(raw, host) case final decoded?) hosts[host] = decoded;
    }
    return (domains, hosts);
  }

  static Object? _decodeJsonFile(String? raw, String name) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      AppLog.w('備份略過讀不懂的 Cookie 檔 $name: $error');
      return null;
    }
  }

  static Map<String, Map<String, SerializableCookie>>? _decodeByPath(
    Object? raw,
    String name,
  ) {
    if (raw is! Map) return null;
    try {
      return {
        for (final MapEntry(key: path, value: byName) in raw.entries)
          path.toString(): {
            for (final MapEntry(key: cookieName, value: value)
                in (byName as Map).entries)
              cookieName.toString(): SerializableCookie.fromJson(
                value as String,
              ),
          },
      };
    } on Object catch (error) {
      // 型別不對、Cookie 寫法壞掉（FormatException、HttpException）。
      AppLog.w('備份略過讀不懂的 Cookie 檔 $name: $error');
      return null;
    }
  }

  /// 還原後和現在的 Cookie 檔同一天到期：存活秒數與到期時刻都有時，照
  /// [SerializableCookie.isExpired] 取先到的那個。
  static io.Cookie? _withAbsoluteExpiry(
    SerializableCookie stored,
    String path,
  ) {
    final source = stored.cookie;
    final maxAge = source.maxAge;
    final maxAgeExpiry = maxAge == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (stored.createTimeStamp + maxAge) * 1000,
          );
    final expires = source.expires;
    try {
      return io.Cookie(source.name, source.value)
        ..domain = source.domain
        ..path = source.path ?? path
        ..secure = source.secure
        ..httpOnly = source.httpOnly
        ..sameSite = source.sameSite
        ..expires = switch ((expires, maxAgeExpiry)) {
          (final a?, final b?) => a.isBefore(b) ? a : b,
          (final a, final b) => a ?? b,
        };
    } on FormatException {
      // 存得進 Cookie 檔的名稱與值，重建時理應照樣通過；萬一不行就不帶。
      return null;
    }
  }

  static Cache _parseCache(Object? item) {
    if (item
        case {
          'key': final String key,
          'value': final String value,
          'deadline': final int deadline,
        }
        when key.isNotEmpty) {
      return Cache(key: key, value: value, deadline: deadline);
    }
    throw FormatException('$cacheFile 有一筆格式不對', item);
  }

  static Cookie _parseCookie(Object? item) {
    if (item case {'url': final String url, 'cookie': final String cookie}
        when url.isNotEmpty && cookie.isNotEmpty) {
      return Cookie(url: url, cookie: cookie);
    }
    throw FormatException('$cookieFile 有一筆格式不對', item);
  }

  static (Uri, io.Cookie) _parseJarEntry(Object? item) {
    if (item case {'url': final String url, 'cookie': final String raw}) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        try {
          return (uri, io.Cookie.fromSetCookieValue(raw));
        } on FormatException {
          // 下面一起丟出。
        } on io.HttpException {
          // 下面一起丟出。
        }
      }
    }
    throw FormatException('$cookieJarFile 有一筆格式不對', item);
  }
}
