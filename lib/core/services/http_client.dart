import 'package:dio/dio.dart';
import 'package:reader/core/network/interceptors/lenient_cookie_manager.dart';
import 'package:reader/core/services/network_service.dart';

/// HttpClient - 全域 HTTP 客戶端 (專業升級版)
/// 整合 NetworkService 以支援持久化 Cookie 與反爬蟲攔截
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;
  HttpClient._internal();

  Dio get client => NetworkService().dio;

  /// 手動保存 Cookie (用於 WebView 同步等場景)
  Future<void> saveCookies(String url, String cookieStr) async {
    final uri = Uri.parse(url);
    final cookie = parseSetCookieValueLenient(
      cookieStr,
      ignoreInvalidCookies: true,
    );
    if (cookie == null) return;
    await NetworkService().cookieJar.saveFromResponse(uri, [cookie]);
  }

  /// 獲取特定網站的 Cookie
  Future<String> getCookie(String url) async {
    final uri = Uri.parse(url);
    final cookies = await NetworkService().cookieJar.loadForRequest(uri);
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }
}
