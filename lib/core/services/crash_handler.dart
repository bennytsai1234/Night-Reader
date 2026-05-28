import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// CrashHandler - 全域異常捕獲與日誌記錄
/// (原 Android help/CrashHandler.kt)
class CrashHandler {
  static String? _userAgent;
  static PackageInfo? _packageInfo;

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
    unawaited(_saveLog(error.toString(), stack));
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

      AppLog.d('Crash log saved to: ${file.path}');
    } catch (e) {
      AppLog.e('Failed to save crash log: $e', error: e);
    }
  }

  static Future<String> readLogs() async {
    try {
      final directory = await _logDirectory();
      final logs =
          directory
              .listSync()
              .whereType<File>()
              .where((file) => _isCrashLogFile(file))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));

      if (logs.isNotEmpty) {
        final buffer = StringBuffer();
        for (final file in logs.take(20)) {
          buffer.writeln(await file.readAsString());
        }
        return buffer.toString().trimRight();
      }
    } catch (_) {}
    return '尚無日誌記錄';
  }

  static Future<void> clearLogs() async {
    try {
      final directory = await _logDirectory();
      final files = directory.listSync();
      for (var file in files) {
        if (file is File && _isCrashLogFile(file)) {
          await file.delete();
        }
      }
      final latest = File('${directory.path}/crash_log.txt');
      if (await latest.exists()) await latest.delete();
    } catch (_) {}
  }

  static Future<Directory> _logDirectory() async {
    return await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  }

  static bool _isCrashLogFile(File file) {
    final name = file.uri.pathSegments.last;
    return name.startsWith('crash-') && name.endsWith('.log');
  }
}
