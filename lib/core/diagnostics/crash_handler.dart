import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_trail.dart';
import 'process_exits.dart';

/// CrashHandler - 全域異常捕獲與日誌記錄
/// (原 Android help/CrashHandler.kt)
///
/// 崩潰日誌只寫 App 出事的時候：主 isolate 沒接住的 Dart 錯誤與啟動失敗
/// 當場寫；系統層的結束（原生崩潰、使用中記憶體不足、沒有回應）夜讀來不及
/// 寫，下次開啟時照系統記的原因寫（[recordPreviousExits]）。都附上出事前最近
/// 的動作與錯誤（[CrashTrail.renderForCrash]），一般日誌只在 App 日誌裡。背景
/// isolate 的錯誤（書源、書源校驗）App 沒有閃退，只記成錯誤（`AppLog.e`）。
/// 寫檔與讀出時都遮掉登入資料（[CrashTrail.redact]）：錯誤訊息與系統追蹤
/// 可能帶著網址或標頭，日誌會被複製、分享出去。
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

  static const String _trailHeader = '=== 最近的動作與錯誤（完整的紀錄在「關於夜讀 → App 日誌」） ===';

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
      ..writeln('\n$_trailHeader')
      ..writeln(CrashTrail.renderForCrash());
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
      var handled = exits
          .map((exit) => exit.timestamp)
          .reduce((a, b) => a > b ? a : b);
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
            ..writeln('\n=== 結束前的動作與錯誤 ===')
            ..writeln(CrashTrail.withoutLogs(previous.text));
        }
        final written = await _writeLog(
          DateTime.fromMillisecondsSinceEpoch(exit.timestamp),
          body.toString(),
        );
        if (!written) {
          // 寫不進去的這一筆與之後的，下次開 App 再寫；寫過的檔名照結束時間，
          // 再寫一次是同一份。
          handled = exit.timestamp - 1;
          break;
        }
      }
      // 寫完才記下處理到哪：先記的話，這次寫不進去的就永遠不會再寫。
      if (handled > seen) await prefs.setInt(exitsSeenKey, handled);
    } catch (error, stack) {
      AppLog.e('讀系統的結束紀錄失敗: $error', error: error, stackTrace: stack);
    }
  }

  /// 寫一份崩潰日誌：檔名照 [time] 排，崩潰日誌頁照檔名從新到舊列。
  /// [memory] 是現在這個程序用的記憶體，系統層的結束寫的是當時的，不附。
  /// 傳回寫進去了沒有。
  static Future<bool> _writeLog(
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
      final text = CrashTrail.redact(buffer.toString());

      await file.writeAsString(text, flush: true);

      // 同時保留一個最新的日誌索引
      final latestFile = File('${directory.path}/crash_log.txt');
      await latestFile.writeAsString(text, flush: true);
      await _pruneLogs(directory);

      AppLog.d('Crash log saved to: ${file.path}');
      return true;
    } catch (e) {
      AppLog.e('Failed to save crash log: $e', error: e);
      return false;
    }
  }

  /// 留著的崩潰日誌從新到舊接成一份，切成給頁面一段段排版的片段
  /// （[logChunks]；接回整份用 `join()`）。留滿時約百萬字，讀檔與切段在背景
  /// isolate。沒有任何紀錄時回傳空清單，讀取失敗時丟出例外，讓日誌頁顯示
  /// 對應的空狀態或錯誤狀態。
  static Future<List<String>> readLogs() async {
    final path = (await _logDirectory()).path;
    return Isolate.run(() => logChunks(_readAll(path)));
  }

  static String _readAll(String path) {
    final buffer = StringBuffer();
    for (final file in _logsNewestFirst(Directory(path))) {
      // 這一版之前寫的沒遮過。
      buffer.writeln(CrashTrail.redact(file.readAsStringSync()));
    }
    return buffer.toString().trimRight();
  }

  /// 頁面一次排版一段的長度上限（字）。整份放進同一段字，留滿 50 份時排
  /// 一次要好幾秒（2026-11-18 量到一幀 2 秒）。
  static const int displayChunkChars = 800;

  /// 把 [text] 切成依序接起來就是原文的片段，每段扣掉結尾的換行最多
  /// [maxChars] 字，盡量切在換行之後；一行比上限長時從中間切（不切開代理對）。
  static List<String> logChunks(
    String text, {
    int maxChars = displayChunkChars,
  }) {
    assert(maxChars >= 2, '每段至少要放得下一個代理對');
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = start + maxChars;
      if (end >= text.length) {
        chunks.add(text.substring(start));
        break;
      }
      // 從 end 本身找起：剛好在上限之後的換行也跟著這段，下一段不會從換行
      // 開始、多畫一行空白。
      // 片頭就是換行（空白行後面接一行超長的）時不切在那裡：只有換行的一片
      // 畫出來是空字，選取取不到它；這個換行留在下一片開頭，畫成空白行。
      final newline = text.lastIndexOf('\n', end);
      if (newline > start) {
        end = newline + 1;
      } else if (_isLeadSurrogate(text.codeUnitAt(end - 1))) {
        end -= 1;
      }
      chunks.add(text.substring(start, end));
      start = end;
    }
    return chunks;
  }

  static bool _isLeadSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

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
