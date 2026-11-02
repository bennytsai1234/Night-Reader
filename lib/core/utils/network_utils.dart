import 'dart:io';

import 'public_suffix.dart';

/// NetworkUtils - 網路輔助工具 (原 Android utils/NetworkUtils.kt)
class NetworkUtils {
  NetworkUtils._();

  static final RegExp _analyzeUrlParamSplitRegex = RegExp(r'\s*,\s*(?=\{)');

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
      final baseUri = Uri.parse(_splitAnalyzeUrl(baseURL).$1);
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
