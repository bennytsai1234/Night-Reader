import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_trail.dart';
import 'process_exits.dart';

/// CrashHandler - 全域異常捕獲與日誌記錄
/// (原 Android help/CrashHandler.kt)
///
/// 寫兩種崩潰日誌：Dart 的錯誤當場寫；系統層的結束（原生崩潰、記憶體不足、
/// 沒有回應）夜讀來不及寫，下次開啟時照系統記的原因寫（[recordPreviousExits]）。
/// 兩種都附上崩潰前的紀錄（[CrashTrail]）。
class CrashHandler {
  static const _errorDeduplicationWindow = Duration(seconds: 2);
  static const _maxRecentErrorFingerprints = 64;

  /// 最多留幾份崩潰日誌，多的從最舊的刪起。
  static const _maxLogFiles = 50;

  /// 第一次讀系統的結束紀錄時，寫進崩潰日誌的最遠到幾天前。
  static const Duration _firstExitWindow = Duration(days: 14);

  /// 系統的結束紀錄讀到哪個時刻（毫秒），之前的不再寫。
  static const String exitsSeenKey = 'crash_process_exits_seen_at';

  static PackageInfo? _packageInfo;
  static final Map<String, DateTime> _recentErrorFingerprints =
      <String, DateTime>{};
  static AppLifecycleListener? _lifecycle;

  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      recordFlutterError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordError(error, stack);
      return true;
    };

    // 進出背景記成動作：系統常在背景時收掉夜讀，看得出當時在不在前景。
    _lifecycle ??= AppLifecycleListener(
      onResume: () => CrashTrail.action('回到前景'),
      onPause: () => CrashTrail.action('進到背景'),
    );
    try {
      await CrashTrail.start(await _logDirectory());
    } catch (_) {}
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
    final now = DateTime.now();
    final body = StringBuffer()
      ..writeln('=== Error Info ===')
      ..writeln('Crash Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}')
      ..writeln('Error: $error');
    if (stack != null) {
      body
        ..writeln('\n=== StackTrace ===')
        ..writeln(stack.toString());
    }
    body
      ..writeln('\n=== 最近的紀錄 ===')
      ..writeln(CrashTrail.render());
    await _writeLog(now, body.toString(), memory: true);
  }

  /// 讀系統記下的上次結束，該寫的寫成崩潰日誌：開 App 的進場播完後呼叫。
  /// 最新的那一次附上上次開啟留下的紀錄。
  static Future<void> recordPreviousExits({
    ProcessExitSource? source,
    SharedPreferences? preferences,
    DateTime? now,
  }) async {
    try {
      final exits = await (source ?? ProcessExitSource.platform).recent();
      if (exits.isEmpty) return;
      final prefs = preferences ?? await SharedPreferences.getInstance();
      final seen =
          prefs.getInt(exitsSeenKey) ??
          (now ?? DateTime.now())
              .subtract(_firstExitWindow)
              .millisecondsSinceEpoch;
      final latest = exits
          .map((exit) => exit.timestamp)
          .reduce((a, b) => a > b ? a : b);
      await prefs.setInt(exitsSeenKey, latest > seen ? latest : seen);
      final reportable =
          exits
              .where((exit) => exit.timestamp > seen && exit.isReportable)
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final previous = CrashTrail.previous;
      for (final exit in reportable) {
        final body = StringBuffer()
          ..writeln('=== 上次結束（系統記的） ===')
          ..writeln('（上面的版本是寫這份日誌時的，結束時可能是更早的版本）')
          ..writeln(exit.render());
        if (identical(exit, reportable.last) &&
            previous != null &&
            previous.start <= exit.timestamp) {
          body
            ..writeln('\n=== 結束前的紀錄 ===')
            ..writeln(previous.text);
        }
        await _writeLog(
          DateTime.fromMillisecondsSinceEpoch(exit.timestamp),
          body.toString(),
        );
      }
    } catch (error, stack) {
      AppLog.e('讀系統的結束紀錄失敗: $error', error: error, stackTrace: stack);
    }
  }

  /// 寫一份崩潰日誌：檔名照 [time] 排，崩潰日誌頁照檔名從新到舊列。
  /// [memory] 是現在這個程序用的記憶體，系統層的結束寫的是當時的，不附。
  static Future<void> _writeLog(
    DateTime time,
    String body, {
    bool memory = false,
  }) async {
    try {
      final directory = await _logDirectory();
      final timeStr = DateFormat('yyyy-MM-dd-HH-mm-ss').format(time);
      final file = File(
        '${directory.path}/crash-$timeStr-${time.millisecondsSinceEpoch}.log',
      );

      final buffer = StringBuffer();
      buffer.writeln('=== Device & App Info ===');
      if (_packageInfo != null) {
        buffer.writeln('Package: ${_packageInfo!.packageName}');
        buffer.writeln('Version: ${_packageInfo!.version}');
        buffer.writeln('Build: ${_packageInfo!.buildNumber}');
      }
      buffer.writeln('Platform: ${Platform.operatingSystem}');
      buffer.writeln('OS Version: ${Platform.operatingSystemVersion}');
      if (memory) {
        buffer.writeln(
          'Memory Usage: ${ProcessInfo.currentRss ~/ (1024 * 1024)} MB',
        );
      }
      buffer
        ..writeln()
        ..write(body.trimRight())
        ..writeln('\n========================================\n');

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
    for (final file in _logsNewestFirst(await _logDirectory())) {
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
