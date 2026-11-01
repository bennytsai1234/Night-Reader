import 'dart:convert';
import 'dart:io' as io;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/models/cookie.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/network_service.dart';

/// 備份裡的登入資料，換一台手機還原後不用重新登入（ADR 0039）：
///
/// - [cacheFile]：書源快取裡還沒過期的內容：登入表單、登入標頭、書源變數，
///   以及書源程式用 `cache.put` 存的通行證。
/// - [cookieFile]：書源網站的 Cookie（網頁登入存的、規則 `cookie.setCookie`
///   存的），每次抓取併進請求。
/// - [cookieJarFile]：網路請求收到、存在 Cookie 檔裡的 Cookie。
abstract final class LoginDataBackup {
  static const cacheFile = 'cache.json';
  static const cookieFile = 'cookie.json';
  static const cookieJarFile = 'cookieJar.json';
  static const files = {cacheFile, cookieFile, cookieJarFile};

  static Future<List<Map<String, dynamic>>> exportCache() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final entry in await getIt<CacheDao>().getLive(now)) entry.toJson(),
    ];
  }

  static Future<List<Map<String, dynamic>>> exportCookies() async => [
    for (final cookie in await getIt<CookieDao>().getAll()) cookie.toJson(),
  ];

  /// Cookie 檔裡每一筆還沒過期的 Cookie：`url` 是存它的網域與路徑，`cookie`
  /// 是 `Set-Cookie` 的寫法；只給存活秒數的改成到期時間，還原那天不重新起算。
  static Future<List<Map<String, String>>> exportCookieJar() async {
    final jar = NetworkService().cookieJar;
    if (jar is! DefaultCookieJar) return const [];
    // Cookie 檔的網站是用到才讀進記憶體，先全部讀進來。
    if (jar is PersistCookieJar) {
      for (final host in await _persistedHosts(jar)) {
        await jar.loadForRequest(Uri(scheme: 'https', host: host));
      }
    }
    final entries = <Map<String, String>>[];
    for (final byDomain in [jar.domainCookies, jar.hostCookies]) {
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

  /// 還原 [LoginDataBackup.files] 其中一個檔。先整份讀完再寫，格式不對時
  /// 什麼都不寫、丟出例外，由呼叫端記為失敗。
  static Future<bool> restore(String fileName, List<dynamic> items) async {
    final maps = items.whereType<Map<String, dynamic>>().toList();
    switch (fileName) {
      case cacheFile:
        final now = DateTime.now().millisecondsSinceEpoch;
        final entries = [
          for (final map in maps)
            if (Cache.fromJson(map) case final entry
                when entry.key.isNotEmpty &&
                    entry.value != null &&
                    (entry.deadline == 0 || entry.deadline > now))
              entry,
        ];
        for (final entry in entries) {
          await CacheManager().put(
            entry.key,
            entry.value!,
            saveTimeSeconds: entry.deadline == 0
                ? 0
                : ((entry.deadline - now) / 1000).ceil(),
          );
        }
      case cookieFile:
        await CookieStore().restoreAll(maps.map(Cookie.fromJson).toList());
      case cookieJarFile:
        final cookies = <(Uri, io.Cookie)>[
          for (final map in maps) ?_parseJarEntry(map),
        ];
        final jar = NetworkService().cookieJar;
        for (final (uri, cookie) in cookies) {
          await jar.saveFromResponse(uri, [cookie]);
        }
      default:
        return false;
    }
    return true;
  }

  static Future<List<String>> _persistedHosts(PersistCookieJar jar) async {
    // `.index` 是 PersistCookieJar 記錄存了哪些網站的檔（cookie_jar 4.x）。
    final raw = await jar.storage.read('.index');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } on FormatException {
      return const [];
    }
  }

  static io.Cookie? _withAbsoluteExpiry(
    SerializableCookie stored,
    String path,
  ) {
    final source = stored.cookie;
    try {
      final maxAge = source.maxAge;
      return io.Cookie(source.name, source.value)
        ..domain = source.domain
        ..path = source.path ?? path
        ..secure = source.secure
        ..httpOnly = source.httpOnly
        ..sameSite = source.sameSite
        ..expires = maxAge == null
            ? source.expires
            : DateTime.fromMillisecondsSinceEpoch(
                (stored.createTimeStamp + maxAge) * 1000,
              );
    } on FormatException {
      // 存得進 Cookie 檔的名稱與值，重建時理應照樣通過；萬一不行就不帶。
      return null;
    }
  }

  static (Uri, io.Cookie)? _parseJarEntry(Map<String, dynamic> map) {
    final uri = Uri.tryParse(map['url']?.toString() ?? '');
    final raw = map['cookie']?.toString() ?? '';
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || raw.isEmpty) {
      return null;
    }
    try {
      return (uri, io.Cookie.fromSetCookieValue(raw));
    } on FormatException {
      return null;
    }
  }
}
