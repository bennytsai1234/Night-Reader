import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// 崩潰前的紀錄：最近的動作（開始、停止、做完、App 進出背景）與最近的一般
/// 日誌，隨時存進檔案。夜讀在系統層崩潰時自己來不及寫崩潰日誌，下次開啟
/// 時把上次留下的這份連同系統記的結束原因一起寫進去（`ProcessExits`）；
/// Dart 的錯誤當場附上這次的。
///
/// 動作與日誌分開留：書源校驗時規則 JS 的訊息一下就幾十則，不能把「按了
/// 停止」這種動作擠掉。只存在手機上，要使用者自己複製才會送出。
abstract final class CrashTrail {
  static const int maxActions = 30;
  static const int maxLogs = 60;

  /// 一則最長幾個字：錯誤訊息可能附上整頁網頁。
  static const int maxLineLength = 300;

  /// 一般日誌隔多久存一次；動作馬上存。
  static const Duration logWriteDelay = Duration(milliseconds: 500);

  static final ListQueue<String> _actions = ListQueue<String>();
  static final ListQueue<String> _logs = ListQueue<String>();
  static final int _sessionStart = DateTime.now().millisecondsSinceEpoch;
  static DateTime Function() _now = DateTime.now;

  static File? _file;
  static bool _dirty = false;
  static Future<void>? _writing;
  static Timer? _timer;
  static ({int start, String text})? _previous;

  /// 上次開啟夜讀留下的紀錄與那次開啟的時刻；沒有時是 null。
  static ({int start, String text})? get previous => _previous;

  /// 這次的紀錄存進 [directory]；先讀出上次留下的那份。開始之前記的先留在
  /// 記憶體，開始時一起存。
  static Future<void> start(Directory directory) async {
    final file = File('${directory.path}/$fileName');
    try {
      if (await file.exists()) _previous = _parse(await file.readAsString());
    } catch (_) {}
    _file = file;
    _schedule(immediately: true);
  }

  static const String fileName = 'trail.log';

  static void action(String text) {
    _add(_actions, maxActions, text);
    _schedule(immediately: true);
  }

  static void log(String text) {
    _add(_logs, maxLogs, text);
    _schedule();
  }

  /// 這次開啟到現在的紀錄，附在崩潰日誌裡。
  static String render() {
    final buffer = StringBuffer()
      ..writeln('開啟夜讀：${_format(_sessionStart, full: true)}')
      ..writeln('\n--- 最近的動作 ---');
    _actions.forEach(buffer.writeln);
    if (_actions.isEmpty) buffer.writeln('（沒有）');
    buffer.writeln('\n--- 最近的日誌 ---');
    _logs.forEach(buffer.writeln);
    if (_logs.isEmpty) buffer.writeln('（沒有）');
    return buffer.toString().trimRight();
  }

  static void _add(ListQueue<String> list, int max, String text) {
    var line = text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    if (line.length > maxLineLength) {
      line = '${line.substring(0, maxLineLength)}…';
    }
    list.add('${_format(_now().millisecondsSinceEpoch)} $line');
    while (list.length > max) {
      list.removeFirst();
    }
  }

  static void _schedule({bool immediately = false}) {
    if (_file == null) return;
    _dirty = true;
    if (immediately) {
      _timer?.cancel();
      _timer = null;
      unawaited(_write());
    } else {
      _timer ??= Timer(logWriteDelay, () {
        _timer = null;
        unawaited(_write());
      });
    }
  }

  /// 同一時間只寫一次；寫的時候又有新的，寫完再寫一次。
  static Future<void> _write() => _writing ??= _drain().whenComplete(() {
    _writing = null;
    if (_dirty) unawaited(_write());
  });

  static Future<void> _drain() async {
    final file = _file;
    if (file == null) return;
    try {
      while (_dirty) {
        _dirty = false;
        await file.writeAsString(
          '$_sessionTag$_sessionStart\n${render()}\n',
          flush: true,
        );
      }
    } catch (_) {
      // 存不進去也不影響使用；崩潰日誌少一段紀錄而已。
    }
  }

  static const String _sessionTag = 'session ';

  static ({int start, String text})? _parse(String content) {
    final newline = content.indexOf('\n');
    if (newline < 0 || !content.startsWith(_sessionTag)) return null;
    final start = int.tryParse(content.substring(_sessionTag.length, newline));
    final text = content.substring(newline + 1).trim();
    if (start == null || text.isEmpty) return null;
    return (start: start, text: text);
  }

  static String _format(int ms, {bool full = false}) =>
      DateFormat(full ? 'yyyy-MM-dd HH:mm:ss' : 'HH:mm:ss')
          .format(DateTime.fromMillisecondsSinceEpoch(ms));

  /// 寫完正在寫的那一次（測試用）。
  @visibleForTesting
  static Future<void> flushForTesting() async {
    _timer?.cancel();
    _timer = null;
    await _writing;
    if (_dirty) await _write();
  }

  @visibleForTesting
  static void resetForTesting({DateTime Function()? now}) {
    _actions.clear();
    _logs.clear();
    _file = null;
    _dirty = false;
    _writing = null;
    _timer?.cancel();
    _timer = null;
    _previous = null;
    _now = now ?? DateTime.now;
  }
}
