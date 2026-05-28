import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';
import 'package:reader/core/network/interceptors/app_interceptor.dart';
import 'package:reader/core/network/interceptors/lenient_cookie_manager.dart';

/// NetworkService - 專業網路伺服 (具備反爬蟲對應能力)
/// 封裝全域 Dio 實例並支持 Cookie 持久化與書源併發控制
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  late Dio _dio;
  late CookieJar _cookieJar;
  final Map<String, Lock> _sourceLocks = {}; // 書源併發鎖

  Dio get dio => _dio;
  CookieJar get cookieJar => _cookieJar;

  bool _isInitialized = false;

  /// 獲取書源專屬的鎖 (用於併發控制)
  Lock getSourceLock(String? sourceUrl) {
    if (sourceUrl == null || sourceUrl.isEmpty) return Lock();
    return _sourceLocks.putIfAbsent(sourceUrl, () => Lock());
  }

  Future<void> init({bool ephemeral = false}) async {
    if (_isInitialized) return;

    if (ephemeral) {
      // 背景 isolate：用記憶體 cookie jar，避開 path_provider (platform channel)，
      // 並避免多個校驗 isolate 同時寫入同一個 .cookies 檔造成競爭。
      _cookieJar = CookieJar();
    } else {
      final appDocDir = await _resolveCookieDirectoryRoot();
      final cookiePath = p.join(appDocDir.path, '.cookies');
      final dir = Directory(cookiePath);
      if (!await dir.exists()) await dir.create(recursive: true);

      _cookieJar = PersistCookieJar(storage: FileStorage(cookiePath));
    }

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    _dio.interceptors.add(LenientCookieManager(_cookieJar));
    _dio.interceptors.add(AppInterceptor());

    _isInitialized = true;
  }

  Future<Directory> _resolveCookieDirectoryRoot() async {
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      final fallbackDir = Directory(
        p.join(Directory.systemTemp.path, 'inkpage_reader'),
      );
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      return fallbackDir;
    }
  }

  /// 快速 GET 請求
  Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.get(
      url,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// 快速 POST 請求
  Future<Response> post(String url, {dynamic data, Options? options}) async {
    return await _dio.post(url, data: data, options: options);
  }

  /// 手動保存 Cookie (用於 WebView 同步等場景)
  Future<void> saveCookies(String url, String cookieStr) async {
    final uri = Uri.parse(url);
    final cookie = parseSetCookieValueLenient(
      cookieStr,
      ignoreInvalidCookies: true,
    );
    if (cookie == null) return;
    await _cookieJar.saveFromResponse(uri, [cookie]);
  }
}
