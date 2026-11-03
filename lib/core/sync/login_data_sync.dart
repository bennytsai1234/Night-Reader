import 'dart:io' as io;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/network/interceptors/cloudflare_interceptor.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/login_data_backup.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 登入資料的同步，和備份帶的是同一些（[LoginDataBackup]，ADR 0039）：
/// 書源快取裡還沒過期的內容、書源網站的 Cookie、網路請求收到的 Cookie。
/// 不帶 Cloudflare 的通行 Cookie（[CloudflareInterceptor.isCloudflareCookie]）。
///
/// 登出或過期只在這台：這台沒有了不讓別台跟著刪，別台之後重新登入、內容
/// 變了才再套用過來。
abstract class LoginDataSync extends SyncKind {
  static List<SyncKind> kinds() => [
    LoginCacheSync(),
    LoginCookieSync(),
    LoginCookieJarSync(),
  ];

  @override
  bool get syncsDeletion => false;

  /// 套用後這台的樣子；套用時被略過的（已經過期）不在裡面，上次同步的
  /// 紀錄留著。
  Future<Map<String, SyncRecord>> _appliedFrom(Iterable<String> keys) async {
    final after = await local();
    return {for (final key in keys) key: ?after[key]};
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;
}

/// 書源快取：登入表單、登入標頭、書源變數、書源程式存的通行證。
class LoginCacheSync extends LoginDataSync {
  @override
  String get name => 'login_cache';

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final entry in await LoginDataBackup.exportCache())
      entry['key'] as String: SyncRecord(
        time: 0,
        data: {'value': entry['value'], 'deadline': entry['deadline']},
      ),
  };

  @override
  SyncPrune get prune => _pruneExpired;

  static Map<String, SyncRecord> _pruneExpired(Map<String, SyncRecord> remote) {
    final now = LoginDataSync._now;
    return {
      for (final entry in remote.entries)
        if (entry.value.data
            case {'value': String _, 'deadline': final int deadline}
            when entry.key.isNotEmpty && (deadline == 0 || deadline > now))
          entry.key: entry.value,
    };
  }

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    await LoginDataBackup.restore(LoginDataBackup.cacheFile, [
      for (final MapEntry(:key, value: record) in remote.entries)
        if (!record.deleted) {'key': key, ...record.data},
    ]);
    return _appliedFrom(remote.keys);
  }
}

/// 書源網站的 Cookie（網頁登入存的、規則存的），一個網域一筆。
class LoginCookieSync extends LoginDataSync {
  LoginCookieSync({this._dao});

  final CookieDao? _dao;

  CookieDao get _cookies => _dao ?? getIt<CookieDao>();

  @override
  String get name => 'login_cookies';

  static Map<String, String> _split(String cookie) =>
      CookieStore().cookieToMap(cookie);

  static String _withoutCloudflare(String cookie) => CookieStore().mapToCookie(
    _split(
      cookie,
    )..removeWhere((name, _) => CloudflareInterceptor.isCloudflareCookie(name)),
  );

  @override
  Future<Map<String, SyncRecord>> local() async {
    final records = <String, SyncRecord>{};
    for (final entry in await _cookies.getAll()) {
      final cookie = _withoutCloudflare(entry.cookie);
      if (entry.url.isEmpty || cookie.isEmpty) continue;
      records[entry.url] = SyncRecord(time: 0, data: {'cookie': cookie});
    }
    return records;
  }

  /// 雲端的 Cookie 換上去，這台自己的 Cloudflare 通行 Cookie 留著。
  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final items = <Map<String, String>>[];
    for (final MapEntry(:key, value: record) in remote.entries) {
      final incoming = record.data['cookie'];
      if (record.deleted || incoming is! String || incoming.isEmpty) continue;
      final current = (await _cookies.getByUrl(key))?.cookie ?? '';
      final merged = _split(incoming)
        ..addAll({
          for (final entry in _split(current).entries)
            if (CloudflareInterceptor.isCloudflareCookie(entry.key))
              entry.key: entry.value,
        });
      items.add({'url': key, 'cookie': CookieStore().mapToCookie(merged)});
    }
    await LoginDataBackup.restore(LoginDataBackup.cookieFile, items);
    return _appliedFrom(remote.keys);
  }
}

/// 網路請求收到、存在 Cookie 檔裡的 Cookie，一個 Cookie 一筆。
///
/// 一筆的身分是存放的網域與路徑、名稱，加上適用範圍：只給這個主機用的，
/// 或帶 Domain 屬性、子網域也帶得出去的。同名同路徑的兩種可以同時存在
/// （Cookie 檔分開存），所以適用範圍也在鍵裡，不然其中一筆會被蓋掉。
class LoginCookieJarSync extends LoginDataSync {
  LoginCookieJarSync({CookieJar? cookieJar}) : _jar = cookieJar;

  final CookieJar? _jar;

  @override
  String get name => 'login_cookie_jar';

  static io.Cookie? _parse(Object? raw) {
    if (raw is! String) return null;
    try {
      return io.Cookie.fromSetCookieValue(raw);
    } on FormatException {
      return null;
    } on io.HttpException {
      return null;
    }
  }

  static bool _validUrl(Object? url) {
    final uri = url is String ? Uri.tryParse(url) : null;
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// 主機限定的鍵維持 `網址|名稱`，和舊版一樣，已經上傳的紀錄照樣對得上；
  /// 帶 Domain 屬性的多一段 `|domain=網域`。
  static String keyOf(String url, io.Cookie cookie) {
    final domain = cookie.domain?.toLowerCase().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    return domain == null || domain.isEmpty
        ? '$url|${cookie.name}'
        : '$url|${cookie.name}|domain=$domain';
  }

  @override
  Future<Map<String, SyncRecord>> local() async {
    final records = <String, SyncRecord>{};
    for (final entry in await LoginDataBackup.exportCookieJar(_jar)) {
      final cookie = _parse(entry['cookie']);
      if (cookie == null ||
          CloudflareInterceptor.isCloudflareCookie(cookie.name)) {
        continue;
      }
      records[keyOf(entry['url']!, cookie)] = SyncRecord(
        time: 0,
        data: {'url': entry['url'], 'cookie': entry['cookie']},
      );
    }
    return records;
  }

  /// 拿掉過期的，並把鍵換成現在的寫法：舊版的鍵不分適用範圍，雲端上
  /// 帶 Domain 的 Cookie 可能還放在 `網址|名稱`；不換的話，它會被當成另一筆
  /// 套用，把比較舊的內容蓋到這台已有的同一個 Cookie 上。同一個 Cookie 在
  /// 雲端有新舊兩個鍵時留時間新的，一樣新就留已經是新鍵的那筆。
  @override
  SyncPrune get prune => _pruneExpired;

  static Map<String, SyncRecord> _pruneExpired(Map<String, SyncRecord> remote) {
    final now = DateTime.now();
    final pruned = <String, SyncRecord>{};
    for (final MapEntry(key: oldKey, value: record) in remote.entries) {
      if (record.data
          case {'url': final String url, 'cookie': final Object? raw}
          when _validUrl(url)) {
        final cookie = _parse(raw);
        if (cookie == null ||
            (cookie.expires != null && !cookie.expires!.isAfter(now))) {
          continue;
        }
        final key = keyOf(url, cookie);
        final kept = pruned[key];
        if (kept == null ||
            record.time > kept.time ||
            (record.time == kept.time && oldKey == key)) {
          pruned[key] = record;
        }
      }
    }
    return pruned;
  }

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    await LoginDataBackup.restore(LoginDataBackup.cookieJarFile, [
      for (final record in remote.values)
        if (!record.deleted) Map<String, Object?>.of(record.data),
    ], cookieJar: _jar);
    return _appliedFrom(remote.keys);
  }
}
