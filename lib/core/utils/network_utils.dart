import 'dart:io';

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

  /// 獲取域名 (對標 getDomain)
  static String getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url;
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

  /// 獲取子域名 (對標 getSubDomain)
  /// 注意：此處為簡易實作，不含 PublicSuffixDatabase
  static String getSubDomain(String url) {
    final host = getDomain(url);
    if (isIPAddress(host)) return host;

    final parts = host.split('.');
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('.');
    }
    return host;
  }
}
