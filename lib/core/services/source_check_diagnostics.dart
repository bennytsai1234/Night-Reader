import 'dart:async';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/crash_handler.dart';

/// 書源校驗的診斷：最近一次校驗裡每個出問題的書源一段——沒截斷的錯誤、
/// 實際執行的 JS、送出的請求與網站的回應。寫在崩潰日誌旁的
/// [fileName]，不混進崩潰日誌，書源的錯誤就不會擠掉 App 自己的錯誤。
///
/// 每次校驗開始時清空（[begin]），只留最近一次。寫入照呼叫的順序排隊。
abstract final class SourceCheckDiagnostics {
  static const String fileName = 'source-check.log';

  static Future<void> _queue = Future<void>.value();

  /// 新的一次校驗：清掉上一次的診斷，寫上版本與開始時間。
  static Future<void> begin() => _enqueue(
    (file) => file.writeAsString(
      '=== 書源校驗診斷 ${_now()} · ${CrashHandler.appVersionLine} ===\n',
      flush: true,
    ),
  );

  /// 記下一個書源的診斷，[entries] 是它每個問題各一段。
  static Future<void> record({
    required String sourceName,
    required String sourceUrl,
    required String outcome,
    required List<String> entries,
  }) {
    if (entries.isEmpty) return Future<void>.value();
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('--- [$sourceName] ($sourceUrl)')
      ..writeln(
        '${_now()} · $outcome · 記憶體 '
        '${ProcessInfo.currentRss ~/ (1024 * 1024)} MB',
      );
    for (final entry in entries) {
      buffer
        ..writeln()
        ..writeln(entry);
    }
    return _enqueue(
      (file) => file.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      ),
    );
  }

  /// 最近一次校驗的診斷；沒有時是空字串。
  static Future<String> read() async {
    await _queue;
    final file = await _file();
    if (!await file.exists()) return '';
    return (await file.readAsString()).trimRight();
  }

  static Future<void> _enqueue(Future<void> Function(File file) write) {
    final next = _queue.then((_) async {
      try {
        await write(await _file());
      } catch (e, stack) {
        AppLog.e('寫入書源校驗診斷失敗: $e', error: e, stackTrace: stack);
      }
    });
    _queue = next;
    return next;
  }

  static Future<File> _file() async =>
      File('${(await CrashHandler.logDirectory()).path}/$fileName');

  static String _now() =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
}
