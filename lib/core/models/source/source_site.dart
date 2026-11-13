import 'package:night_reader/core/models/book_source.dart';

/// 書源網址的開頭（`https://www.site.com`）；不是 http(s) 的是 null。
String? siteOrigin(String sourceUrl) {
  final match = RegExp(
    r'^(https?://[^/#?,\s]+)',
    caseSensitive: false,
  ).firstMatch(sourceUrl.trim());
  return match?.group(1);
}

/// 書源屬於哪個網站：網址的主機，和書源管理「按域名分組」同一個分法
/// （`m.site.com` 與 `www.site.com` 算兩個：手機版與電腦版的網頁常不一樣）。
/// 網址不是 http(s) 的，各自算一個網站（傳回書源網址）。
String siteKey(BookSource source) {
  final origin = siteOrigin(source.bookSourceUrl);
  final host = origin == null ? null : Uri.tryParse(origin)?.host;
  if (host == null || host.isEmpty) return source.bookSourceUrl;
  return host.toLowerCase();
}
