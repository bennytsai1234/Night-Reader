import 'dart:async';
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

  /// 進行中的下載，以 APK 路徑為鍵。背景下載與更新視窗各自建立 installer，
  /// 所以放在類別上共用。
  static final _inFlight = <String, _SharedDownload>{};

  /// 下載 [info] 的 APK，回傳下載完成的檔案。
  ///
  /// 同一版已在下載時（例如啟動時的背景下載）直接接上那一份，不會重下。
  /// [onProgress] 的 `total` 在伺服器沒給長度時是 -1。[cancelToken] 取消時丟出
  /// `DioException`（`CancelToken.isCancel` 為 true）；等這份下載的人都取消了，
  /// 下載本身才會停。
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _directoryLoader();
    final apk = File(p.join(dir.path, _fileName(info.tagName)));
    if (await apk.exists()) return apk;

    final previous = _inFlight[apk.path];
    if (previous != null && !previous.cancelled) {
      return previous.join(onProgress: onProgress, cancelToken: cancelToken);
    }
    late final _SharedDownload shared;
    shared = _SharedDownload(
      (shared) async {
        // 剛被取消的那份還在收尾（刪 .part），等它結束再開始，免得刪到新檔。
        await previous?.settled;
        return _fetch(info, dir, apk, shared);
      },
      onDone: () {
        if (identical(_inFlight[apk.path], shared)) _inFlight.remove(apk.path);
      },
    );
    _inFlight[apk.path] = shared;
    return shared.join(onProgress: onProgress, cancelToken: cancelToken);
  }

  Future<File> _fetch(
    UpdateInfo info,
    Directory dir,
    File apk,
    _SharedDownload shared,
  ) async {
    // 換版或上次沒下完：舊版 APK 與殘留的 .part 都不再需要。
    await clearDownloads();
    await dir.create(recursive: true);
    final partial = File('${apk.path}.part');
    await _dio.download(
      info.downloadUrl,
      partial.path,
      onReceiveProgress: shared.report,
      cancelToken: shared.cancelToken,
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

  /// 目前的網路是否不計流量（例如 Wi-Fi）。沒有網路、或系統認定計流量時回 false；
  /// 查詢失敗會丟出例外，由呼叫端決定怎麼處理。
  Future<bool> isOnUnmeteredNetwork() async {
    final metered = await _channel.invokeMethod<bool>('isActiveNetworkMetered');
    return metered == false;
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

/// 一份進行中的 APK 下載。可以有好幾個等待者，各自收進度、各自取消；
/// 後來接上的等待者會先收到目前的進度。
class _SharedDownload {
  _SharedDownload(
    Future<File> Function(_SharedDownload shared) fetch, {
    required void Function() onDone,
  }) {
    _result = fetch(this).whenComplete(onDone);
  }

  final cancelToken = CancelToken();
  late final Future<File> _result;
  final _listeners = <void Function(int received, int total)>[];
  int _waiters = 0;
  (int, int)? _progress;

  /// 等的人都取消了；之後要下同一版得重開一份。
  bool get cancelled => cancelToken.isCancelled;

  /// 這份下載結束（不論成敗）時完成，不丟例外。
  Future<void> get settled => _result.then((_) {}, onError: (_) {});

  void report(int received, int total) {
    _progress = (received, total);
    for (final listener in List.of(_listeners)) {
      listener(received, total);
    }
  }

  Future<File> join({
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    _waiters++;
    if (onProgress != null) {
      _listeners.add(onProgress);
      if (_progress case (final received, final total)) {
        onProgress(received, total);
      }
    }
    final completer = Completer<File>();
    void leave() {
      _waiters--;
      if (onProgress != null) _listeners.remove(onProgress);
    }

    _result.then(
      (apk) {
        if (completer.isCompleted) return;
        leave();
        completer.complete(apk);
      },
      onError: (Object error, StackTrace stack) {
        if (completer.isCompleted) return;
        leave();
        completer.completeError(error, stack);
      },
    );
    cancelToken?.whenCancel.then((error) {
      if (completer.isCompleted) return;
      leave();
      completer.completeError(error);
      // 沒有人在等了才真的停下載；背景下載不帶 cancelToken，會一直等到完成。
      if (_waiters == 0) this.cancelToken.cancel();
    });
    return completer.future;
  }
}
