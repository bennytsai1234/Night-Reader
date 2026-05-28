import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewDataService {
  WebViewDataService({
    CookieStore? cookieStore,
    NetworkService? networkService,
    WebViewCookieManager? webViewCookieManager,
  }) : _cookieStore = cookieStore ?? CookieStore(),
       _networkService = networkService ?? NetworkService(),
       _webViewCookieManager = webViewCookieManager ?? WebViewCookieManager();

  final CookieStore _cookieStore;
  final NetworkService _networkService;
  final WebViewCookieManager _webViewCookieManager;

  Future<bool> clearAllCookies() async {
    await _cookieStore.clearAll();
    await _networkService.cookieJar.deleteAll();
    return _webViewCookieManager.clearCookies();
  }

  Future<void> clearWebViewLocalStorage() async {
    final controller = WebViewController();
    await controller.clearLocalStorage();
  }

  Future<void> clearWebViewCache() async {
    final controller = WebViewController();
    await controller.clearCache();
  }
}
