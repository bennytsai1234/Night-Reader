import 'package:dio/dio.dart';

/// StrResponse - 對標 Android help/http/StrResponse.kt
class StrResponse {
  final String url;
  final String body;
  final Map<String, List<String>> headers;
  final Response raw;

  StrResponse({
    required this.url,
    required this.body,
    required this.headers,
    required this.raw,
  });

  List<String> get redirectChain =>
      ((raw.extra['_manualRedirectChain'] as List?) ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList();

  bool get isRedirect => raw.redirects.isNotEmpty || redirectChain.isNotEmpty;

  /// 網址或內容帶有「需要登入」的字樣（不分大小寫）。每個書源回應都會檢查，
  /// 整頁網頁可能上百 KB，所以直接比對原文，不先轉小寫再逐一搜尋。
  bool get looksLikeLoginRequired =>
      _loginRequiredMarker.hasMatch(url) || _loginRequiredMarker.hasMatch(body);

  static final RegExp _loginRequiredMarker = RegExp(
    'permissionlimit|loginrequired|需要你登录后阅读|需要你登入後閱讀|'
    '登录后阅读|登入後閱讀|請先登錄|请先登录',
    caseSensitive: false,
  );
}
