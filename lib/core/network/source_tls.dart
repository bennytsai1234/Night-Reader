import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';

/// 連書源網站的連線不驗憑證：過期、自簽、網域對不上的憑證都照樣連（同
/// Legado：書源的 OkHttp、Jsoup、封面與 WebView 都不驗，ADR 0062）。書源網站
/// 常放著憑證過期不管，驗了書就讀不到。夜讀自己的服務（App 更新、同步、AI）
/// 各用自己的連線，照常驗。
HttpClient sourceHttpClient() =>
    HttpClient()..badCertificateCallback = (_, _, _) => true;

/// 給書源用的 dio 連線（[sourceHttpClient]）。
HttpClientAdapter sourceHttpClientAdapter() =>
    IOHttpClientAdapter(createHttpClient: sourceHttpClient);

/// 網路封面改走 [sourceHttpClient]：在第一張封面載入前換掉
/// [CachedNetworkImageProvider.defaultCacheManager]，快取沿用原本那一份。
/// 開 App 失敗重試時會再呼叫，換上的一直是同一個。
void useSourceConnectionForCovers() {
  CachedNetworkImageProvider.defaultCacheManager = _coverCacheManager;
}

final CacheManager _coverCacheManager = CacheManager(
  Config(
    DefaultCacheManager.key,
    fileService: HttpFileService(httpClient: IOClient(sourceHttpClient())),
  ),
);
