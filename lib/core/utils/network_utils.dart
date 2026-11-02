import 'dart:io';

import 'idna.dart';
import 'public_suffix.dart';

/// NetworkUtils - 網路輔助工具 (原 Android utils/NetworkUtils.kt)
class NetworkUtils {
  NetworkUtils._();

  static final RegExp _analyzeUrlParamSplitRegex = RegExp(r'\s*,\s*(?=\{)');

  static final RegExp _authority = RegExp(
    r'^([A-Za-z][A-Za-z0-9+.-]*://)([^/?#]*)(.*)$',
    dotAll: true,
  );

  /// [url] 的主機名有中文這類非 ASCII 字時換成 punycode（`xn--…`），其他照舊。
  /// 同 Legado 用的 OkHttp `HttpUrl`；Dart 的 `Uri` 會把這種主機名百分比編碼
  /// （組相對網址時也會），連線時查不到網域，所以編碼過的也還原再換。
  static String toAsciiHost(String url) {
    final match = _authority.firstMatch(url);
    if (match == null) return url;
    final authority = match.group(2)!;
    final at = authority.lastIndexOf('@');
    final userInfo = at < 0 ? '' : authority.substring(0, at + 1);
    final hostPort = authority.substring(at + 1);
    final colon = hostPort.lastIndexOf(':');
    final hasPort = colon >= 0 && !hostPort.startsWith('[');
    var host = hasPort ? hostPort.substring(0, colon) : hostPort;
    if (host.contains('%') && !host.startsWith('[')) {
      try {
        host = Uri.decodeComponent(host);
      } catch (_) {
        // 不合法的百分比編碼或不是 UTF-8：不是中文網域，照原樣送。
        return url;
      }
    }
    if (!host.runes.any((c) => c > 0x7f)) return url;
    // 換出來不是合法主機名（例如全形的「＠」「／」對應成 @、/）時照原樣送，
    // 請求照樣失敗，不會被拼成另一個主機或路徑；OkHttp 也是丟錯不送。
    final ascii = idnaToAscii(host);
    if (ascii == null) return url;
    final port = hasPort ? hostPort.substring(colon) : '';
    return '${match.group(1)}$userInfo$ascii$port${match.group(3)}';
  }

  /// 獲取絕對地址 (對標 getAbsoluteURL)
  static String getAbsoluteURL(String? baseURL, String relativePath) {
    if (baseURL == null || baseURL.isEmpty) return relativePath.trim();
    final relativePathTrim = relativePath.trim();

    if (relativePathTrim.startsWith('http://') ||
        relativePathTrim.startsWith('https://') ||
        relativePathTrim.startsWith('data:')) {
      return relativePathTrim;
    }

    if (relativePathTrim.startsWith('javascript')) return '';

    final relativeParts = _splitAnalyzeUrl(relativePathTrim);
    final relativeUrl = relativeParts.$1;
    final relativeOptions = relativeParts.$2;
    if (relativeUrl.isEmpty) {
      return relativePathTrim;
    }

    try {
      // 同 Legado 用的 java.net.URL：網址頭尾的空白不算（書源網址常多打一格）。
      final baseUri = Uri.parse(_splitAnalyzeUrl(baseURL).$1.trim());
      final absoluteUri = baseUri.resolve(relativeUrl);
      return '${absoluteUri.toString()}$relativeOptions';
    } catch (_) {
      return relativePathTrim;
    }
  }

  static (String, String) _splitAnalyzeUrl(String value) {
    final match = _analyzeUrlParamSplitRegex.firstMatch(value);
    if (match == null) {
      return (value, '');
    }
    return (
      value.substring(0, match.start).trim(),
      value.substring(match.start).trimLeft(),
    );
  }

  /// 獲取 Base URL (例如 http://example.com)
  static String? getBaseUrl(String? url) {
    if (url == null) return null;
    try {
      final uri = Uri.parse(url);
      return "${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}";
    } catch (_) {
      return null;
    }
  }

  /// 檢查字串是否為 IP 地址
  static bool isIPAddress(String input) {
    try {
      InternetAddress(input);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 書源 Cookie 存放用的網域，同 Legado `NetworkUtils.getSubDomain`：
  /// `https://www.biquge.com.cn/x` → `biquge.com.cn`（照公共字尾表，
  /// [registrableDomain]），IP 位址照原樣；不是 http／https 網址或解析失敗時
  /// 傳回 [url] 本身。
  static String getSubDomain(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return url;
    }
    final String host;
    try {
      host = Uri.parse(url).host;
    } on FormatException {
      return url;
    }
    if (host.isEmpty) return url;
    if (isIPAddress(host)) return host;
    return registrableDomain(host) ?? host;
  }
}
