import 'package:night_reader/core/models/book_source.dart';

/// 書源網址的開頭（`https://www.site.com`）；不是 http(s) 的是 null。
String? siteOrigin(String sourceUrl) {
  final match = RegExp(
    r'^(https?://[^/#?,\s]+)',
    caseSensitive: false,
  ).firstMatch(sourceUrl.trim());
  return match?.group(1);
}

/// 書源網址的主機（小寫）；不是 http(s) 的是 null。書源網址後面的
/// `,{…}` 選項與 `@` 前面的使用者資訊不算，連接埠不分。
String? siteHost(String sourceUrl) {
  final head = sourceUrl.trim().split(RegExp(r',\s*\{')).first;
  final match = RegExp(
    r'^https?://([^/#?\s]+)',
    caseSensitive: false,
  ).firstMatch(head);
  if (match == null) return null;
  var authority = match.group(1)!;
  authority = authority.substring(authority.lastIndexOf('@') + 1);
  final host = authority.replaceFirst(RegExp(r':\d*$'), '').toLowerCase();
  return host.isEmpty ? null : host;
}

/// 書源屬於哪個網站（[siteHost]），和書源管理「按域名分組」同一個分法
/// （`m.site.com` 與 `www.site.com` 算兩個：手機版與電腦版的網頁常不一樣）。
/// 網址不是 http(s) 的，各自算一個網站（傳回書源網址）。
String siteKey(BookSource source) =>
    siteHost(source.bookSourceUrl) ?? source.bookSourceUrl;
