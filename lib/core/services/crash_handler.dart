import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// CrashHandler - 全域異常捕獲與日誌記錄
/// (原 Android help/CrashHandler.kt)
class CrashHandler {
  static const _errorDeduplicationWindow = Duration(seconds: 2);
  static const _maxRecentErrorFingerprints = 64;

  /// 最多留幾份崩潰日誌，多的從最舊的刪起。
  static const _maxLogFiles = 50;

  static String? _userAgent;
  static PackageInfo? _packageInfo;
  static final Map<String, DateTime> _recentErrorFingerprints =
      <String, DateTime>{};

  static Future<void> init() async {
    // 預先加載應用資訊
    _packageInfo = await PackageInfo.fromPlatform();

    // 異步獲取 WebView UA (Android 端對標 WebSettings.getDefaultUserAgent)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        // 在 Flutter 中獲取 UA 通常需要一個隱藏的 WebView 或使用插件
        // 這裡暫時預留接口，或從基礎配置中獲取
      } catch (_) {}
    }

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      recordFlutterError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordError(error, stack);
      return true;
    };
  }

  static void recordFlutterError(FlutterErrorDetails details) {
    recordError(details.exceptionAsString(), details.stack);
  }

  static void recordError(Object error, StackTrace? stack) {
    if (_shouldAbsorb(error)) return;
    if (!_shouldRecordError(error, stack)) return;
    unawaited(_saveLog(error.toString(), stack));
  }

  static bool _shouldRecordError(
    Object error,
    StackTrace? stack, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final fingerprint = _errorFingerprint(error, stack);
    final previous = _recentErrorFingerprints[fingerprint];
    if (previous != null &&
        timestamp.difference(previous) < _errorDeduplicationWindow) {
      return false;
    }

    _recentErrorFingerprints[fingerprint] = timestamp;
    if (_recentErrorFingerprints.length > _maxRecentErrorFingerprints) {
      final oldest = _recentErrorFingerprints.entries.reduce(
        (left, right) => left.value.isBefore(right.value) ? left : right,
      );
      _recentErrorFingerprints.remove(oldest.key);
    }
    return true;
  }

  static String _errorFingerprint(Object error, StackTrace? stack) {
    return '${error.toString()}\n${stack?.toString() ?? '<no stack trace>'}';
  }

  /// 異常吸收邏輯 (原 Android shouldAbsorb)
  /// 避免一些不影響運行但頻繁觸發的系統級異常阻塞日誌
  static bool _shouldAbsorb(Object e) {
    final errorStr = e.toString();
    // 模擬 Android 端吸收廣播或權限異常的行為
    if (errorStr.contains('CannotDeliverBroadcastException') ||
        errorStr.contains('OBSERVE_GRANT_REVOKE_PERMISSIONS')) {
      return true;
    }
    return false;
  }

  static Future<void> _saveLog(String error, StackTrace? stack) async {
    try {
      final directory = await _logDirectory();
      // 檔名加入時間戳 (原 Android crash-yyyy-MM-dd-HH-mm-ss.log)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final timeStr = DateFormat('yyyy-MM-dd-HH-mm-ss').format(DateTime.now());
      final file = File('${directory.path}/crash-$timeStr-$timestamp.log');

      final buffer = StringBuffer();
      buffer.writeln('=== Device & App Info ===');
      if (_packageInfo != null) {
        buffer.writeln('Package: ${_packageInfo!.packageName}');
        buffer.writeln('Version: ${_packageInfo!.version}');
        buffer.writeln('Build: ${_packageInfo!.buildNumber}');
      }
      buffer.writeln('Platform: ${Platform.operatingSystem}');
      buffer.writeln('OS Version: ${Platform.operatingSystemVersion}');
      if (_userAgent != null) {
        buffer.writeln('WebView UA: $_userAgent');
      }
      buffer.writeln(
        'Memory Usage: ${ProcessInfo.currentRss ~/ (1024 * 1024)} MB',
      );

      buffer.writeln('\n=== Error Info ===');
      buffer.writeln(
        'Crash Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
      );
      buffer.writeln('Error: $error');
      if (stack != null) {
        buffer.writeln('\n=== StackTrace ===');
        buffer.writeln(stack.toString());
      }
      buffer.writeln('========================================\n');

      await file.writeAsString(buffer.toString(), flush: true);

      // 同時保留一個最新的日誌索引
      final latestFile = File('${directory.path}/crash_log.txt');
      await latestFile.writeAsString(buffer.toString(), flush: true);
      await _pruneLogs(directory);

      AppLog.d('Crash log saved to: ${file.path}');
    } catch (e) {
      AppLog.e('Failed to save crash log: $e', error: e);
    }
  }

  /// 最近的崩潰日誌；沒有任何紀錄時回傳空字串，讀取失敗時丟出例外，
  /// 讓日誌頁顯示對應的空狀態或錯誤狀態。
  static Future<String> readLogs() async {
    final buffer = StringBuffer();
    for (final file in _logsNewestFirst(await _logDirectory()).take(20)) {
      buffer.writeln(await file.readAsString());
    }
    return buffer.toString().trimRight();
  }

  /// 刪除所有崩潰日誌；失敗時丟出例外，不讓頁面誤報已清除。
  static Future<void> clearLogs() async {
    final directory = await _logDirectory();
    final files = directory.listSync();
    for (var file in files) {
      if (file is File && _isCrashLogFile(file)) {
        await file.delete();
      }
    }
    final latest = File('${directory.path}/crash_log.txt');
    if (await latest.exists()) await latest.delete();
  }

  /// 崩潰日誌與書源校驗診斷放的資料夾：手機上是 App 的外部資料夾，電腦
  /// 接上手機就讀得到。
  static Future<Directory> logDirectory() => _logDirectory();

  static Future<Directory> _platformLogDirectory() async =>
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();

  /// 全域錯誤處理沒有擁有它的物件，資料夾只好放在靜態變數；測試換掉後要
  /// 用 [resetLogDirectoryForTesting] 換回來。
  static Future<Directory> Function() _logDirectory = _platformLogDirectory;

  @visibleForTesting
  static set logDirectoryForTesting(Future<Directory> Function() directory) =>
      _logDirectory = directory;

  @visibleForTesting
  static void resetLogDirectoryForTesting() =>
      _logDirectory = _platformLogDirectory;

  /// 「版本 X (Build N)」；還沒載入 App 資訊時是空的。
  static String get appVersionLine {
    final info = _packageInfo;
    if (info == null) return '';
    return '版本 ${info.version} (Build ${info.buildNumber})';
  }

  static List<File> _logsNewestFirst(Directory directory) =>
      directory.listSync().whereType<File>().where(_isCrashLogFile).toList()
        ..sort((a, b) => b.path.compareTo(a.path));

  static Future<void> _pruneLogs(Directory directory) async {
    for (final old in _logsNewestFirst(directory).skip(_maxLogFiles)) {
      await old.delete();
    }
  }

  @visibleForTesting
  static Future<void> saveLogForTesting(String error) => _saveLog(error, null);

  static bool _isCrashLogFile(File file) {
    final name = file.uri.pathSegments.last;
    return name.startsWith('crash-') && name.endsWith('.log');
  }
}
