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
///
/// 背景下載與更新視窗可能同時動到這個目錄，所以清理只刪沒人在用的檔案：
/// 正在下載的那幾版，以及用 [hold] 標記、視窗手上可安裝的 APK 都會留著。
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

  /// 有人在用、清理時要留著的 APK，以路徑為鍵、記持有次數。
  static final _held = <String, int>{};

  /// 下載 [info] 的 APK，回傳下載完成的檔案。拿到的檔案若要留著之後安裝，
  /// 在同一段同步程式碼裡呼叫 [hold]，免得被清理刪掉。
  ///
  /// 同一版已在下載時（例如啟動時的背景下載）直接接上那一份，不會重下；
  /// 別版還在下載時先停掉它，等它收尾後再刪掉它留下的檔案。
  /// [onProgress] 的 `total` 在伺服器沒給長度時是 -1。[cancelToken] 取消時丟出
  /// `DioException`（`CancelToken.isCancel` 為 true）；等這份下載的人都取消了，
  /// 下載本身才會停。被別版取代的下載也以同樣的取消例外結束。
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
    // 換版：只留最新要下的這一版。在登記之前同步取消，兩版同時開始時後來的勝出。
    final superseded = [
      for (final MapEntry(:key, :value) in _inFlight.entries)
        if (key != apk.path) value,
    ];
    for (final other in superseded) {
      other.cancelToken.cancel();
    }
    late final _SharedDownload shared;
    shared = _SharedDownload(
      (shared) async {
        // 被取消的下載還在收尾（刪 .part），等它們結束再清理、開始，免得刪到新檔。
        await previous?.settled;
        await Future.wait([for (final other in superseded) other.settled]);
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
    // 換版或上次沒下完：沒人在用的舊版 APK 與殘留的 .part 都不再需要。
    await _deleteUnused(dir);
    await dir.create(recursive: true);
    final partial = File('${apk.path}$_partSuffix');
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

  /// 刪除不再需要的 APK：已是最新版時清掉裝完留下的安裝檔、忽略某版時清掉它。
  /// 正在下載的與 [hold] 住的檔案留著。
  Future<void> clearDownloads() async =>
      _deleteUnused(await _directoryLoader());

  /// 標記 [apk] 正在使用（例如更新視窗停在可安裝），清理時不刪；用完呼叫 [release]。
  /// 同一個檔案可以被好幾處持有，全部 release 後才會被清理。
  void hold(File apk) =>
      _held.update(apk.path, (count) => count + 1, ifAbsent: () => 1);

  /// 放掉一次 [hold]。
  void release(File apk) {
    final count = _held[apk.path];
    if (count == null) return;
    if (count > 1) {
      _held[apk.path] = count - 1;
    } else {
      _held.remove(apk.path);
    }
  }

  /// 刪掉 [dir] 裡不屬於進行中下載、也沒被 [hold] 的檔案。
  static Future<void> _deleteUnused(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      // 每個檔案刪之前才判斷，列目錄期間開始的下載或剛被持有的檔案也會留下。
      final name = p.basename(entity.path);
      final apkName = name.endsWith(_partSuffix)
          ? name.substring(0, name.length - _partSuffix.length)
          : name;
      final inUse = [
        ..._inFlight.keys,
        ..._held.keys,
      ].any((path) => p.basename(path) == apkName);
      if (inUse) continue;
      try {
        await entity.delete(recursive: true);
      } on PathNotFoundException {
        // 另一次清理或被取消的下載已經刪掉了。
      }
    }
  }

  static const _partSuffix = '.part';

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
