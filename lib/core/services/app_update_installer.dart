import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../storage/app_storage_paths.dart';
import 'http_client.dart';
import 'update_service.dart';

/// 下載新版 APK 並交給系統安裝程式。
///
/// APK 放在快取的 `updates/`，只留目前要裝的那一版。先寫到 `.part`，
/// 大小與 Release 標示的相符才改成正式檔名，所以正式檔存在就代表下載完整，
/// 同一版再按更新時直接沿用。
class AppUpdateInstaller {
  AppUpdateInstaller({
    Dio? dio,
    Future<Directory> Function()? directoryLoader,
    MethodChannel? channel,
  }) : _dio = dio ?? HttpClient().client,
       _directoryLoader = directoryLoader ?? AppStoragePaths.appUpdateDir,
       _channel = channel ?? const MethodChannel('night_reader/app_installer');

  final Dio _dio;
  final Future<Directory> Function() _directoryLoader;
  final MethodChannel _channel;

  /// 下載 [info] 的 APK，回傳下載完成的檔案。
  ///
  /// [onProgress] 的 `total` 在伺服器沒給長度時是 -1。取消時丟出
  /// `DioException`（`CancelToken.isCancel` 為 true）。
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _directoryLoader();
    final apk = File(p.join(dir.path, _fileName(info.tagName)));
    if (await apk.exists()) return apk;

    // 換版或上次沒下完：舊版 APK 與殘留的 .part 都不再需要。
    await clearDownloads();
    await dir.create(recursive: true);
    final partial = File('${apk.path}.part');
    await _dio.download(
      info.downloadUrl,
      partial.path,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
    final length = await partial.length();
    final complete = info.assetSize > 0 ? length == info.assetSize : length > 0;
    if (!complete) {
      await partial.delete();
      throw StateError('APK 大小不符：下載 $length，預期 ${info.assetSize}');
    }
    return partial.rename(apk.path);
  }

  /// 開啟系統安裝程式。安裝成功後系統會結束並替換目前的 App。
  Future<void> install(File apk) {
    return _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  /// 刪除下載過的 APK；已是最新版時呼叫，清掉裝完留下的安裝檔。
  Future<void> clearDownloads() async {
    final dir = await _directoryLoader();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static String _fileName(String tagName) {
    final safeTag = tagName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return 'night-reader-$safeTag.apk';
  }
}
