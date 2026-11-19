import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// 最近的紀錄：最近的動作（開始、停止、做完、App 進出背景）、最近的錯誤
/// （`AppLog.e` 與帶錯誤的日誌）與最近的一般日誌，隨時存進 [fileName]。
/// 「關於夜讀 → App 日誌」顯示這次與上次開啟的整份。
///
/// 崩潰日誌只附動作與錯誤（[renderForCrash]）：Dart 的錯誤當場附上這次的；
/// 夜讀在系統層崩潰時自己來不及寫，下次開啟時把上次留下的這份連同系統記的
/// 結束原因一起寫進去（`ProcessExits`）。
///
/// 三種分開留：書源校驗時規則 JS 的訊息一下就幾十則，不能把「按了停止」這種
/// 動作與書源 isolate 的錯誤擠掉。只存在手機上，要使用者自己複製或分享才會
/// 送出；網址裡的帳號密碼、token 這類參數與 Cookie、Authorization 的值先遮掉
/// 再記。
abstract final class CrashTrail {
  static const int maxActions = 30;
  static const int maxErrors = 20;
  static const int maxLogs = 60;

  /// 一則最長幾個字：錯誤訊息可能附上整頁網頁。
  static const int maxLineLength = 300;

  /// 一則錯誤最長幾個字：多留堆疊最上面幾格（[errorFrames]），看得出錯在哪。
  static const int maxErrorLength = 600;
  static const int errorFrames = 3;

  /// 一般日誌隔多久存一次；動作馬上存。
  static const Duration logWriteDelay = Duration(milliseconds: 500);

  static final ListQueue<String> _actions = ListQueue<String>();
  static final ListQueue<String> _errors = ListQueue<String>();
  static final ListQueue<String> _logs = ListQueue<String>();
  static final int _sessionStart = DateTime.now().millisecondsSinceEpoch;
  static DateTime Function() _now = DateTime.now;

  static File? _file;
  static bool _dirty = false;

  /// 還沒存的裡面有動作：寫完正在寫的那次就接著寫，不等日誌的間隔。
  static bool _urgent = false;
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

  /// 錯誤和一般日誌一樣隔 [logWriteDelay] 存：書源出錯時一下就好幾則。
  /// 接著閃退的話，Dart 的錯誤當場從記憶體附進崩潰日誌，不靠這個檔。
  static void error(String text, {StackTrace? stackTrace}) {
    final frames = (stackTrace?.toString() ?? '')
        .split('\n')
        .map((frame) => frame.trim())
        .where((frame) => frame.isNotEmpty)
        .take(errorFrames);
    _add(
      _errors,
      maxErrors,
      [text, ...frames].join(' ← '),
      maxLength: maxErrorLength,
    );
    _schedule();
  }

  static void log(String text) {
    _add(_logs, maxLogs, text);
    _schedule();
  }

  /// 這次開啟到現在的整份紀錄：存進檔案、App 日誌顯示的。
  static String render() => _render(withLogs: true);

  /// 附在崩潰日誌裡的：只有動作與錯誤。
  static String renderForCrash() => _render(withLogs: false);

  static const String _logsHeader = '--- 最近的日誌 ---';

  /// 一般日誌那段的標頭行；每則紀錄前面都有時間，不會整行一樣。
  static final RegExp _logsHeaderLine = RegExp(
    '^${RegExp.escape(_logsHeader)}\$',
    multiLine: true,
  );

  static String _render({required bool withLogs}) {
    final buffer = StringBuffer()
      ..writeln('開啟夜讀：${_format(_sessionStart, full: true)}');
    void section(String header, ListQueue<String> lines) {
      buffer.writeln('\n$header');
      lines.forEach(buffer.writeln);
      if (lines.isEmpty) buffer.writeln('（沒有）');
    }

    section('--- 最近的動作 ---', _actions);
    section('--- 最近的錯誤 ---', _errors);
    if (withLogs) section(_logsHeader, _logs);
    return buffer.toString().trimRight();
  }

  /// [render] 存下的整份去掉一般日誌那段，同 [renderForCrash]：上次開啟
  /// 留下的那份附進崩潰日誌時用。一般日誌在新舊格式裡都是最後一段。
  static String withoutLogs(String text) {
    final header = _logsHeaderLine.firstMatch(text);
    if (header == null) return text;
    return text.substring(0, header.start).trimRight();
  }

  /// 這次開啟還沒記下任何東西。
  static bool get _sessionEmpty =>
      _actions.isEmpty && _errors.isEmpty && _logs.isEmpty;

  /// App 日誌顯示的：這次開啟的整份，接著上次開啟留下的（有的話）；兩次
  /// 都沒有紀錄時是空字串。
  static String renderWithPrevious() {
    if (_sessionEmpty && _previous == null) return '';
    final buffer = StringBuffer()
      ..writeln('=== 這次開啟 ===')
      ..writeln(render());
    final previous = _previous;
    if (previous != null) {
      buffer
        ..writeln('\n=== 上次開啟 ===')
        ..writeln(previous.text);
    }
    return buffer.toString().trimRight();
  }

  /// 清掉這次與上次開啟的紀錄（App 日誌的「清除」）：等檔案改寫好才完成，
  /// 寫不進去時丟出例外，舊的那份下次開啟還會回來。
  static Future<void> clear() async {
    _actions.clear();
    _errors.clear();
    _logs.clear();
    _previous = null;
    if (_file == null) return;
    _dirty = true;
    await _drain();
    if (_lastWriteError case final error?) throw error;
  }

  /// 寫完正在寫的與還沒寫的。
  static Future<void> _drain() async {
    while (_writing != null || _dirty) {
      _timer?.cancel();
      _timer = null;
      await (_writing ?? _write());
    }
  }

  static void _add(
    ListQueue<String> list,
    int max,
    String text, {
    int maxLength = maxLineLength,
  }) {
    var line = redact(text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim());
    if (line.length > maxLength) {
      line = '${line.substring(0, maxLength)}…';
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
      _urgent = true;
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

  /// 同一時間只寫一次。寫的時候又有新的：有動作就接著寫，只有日誌就隔
  /// [logWriteDelay] 再寫。
  static Future<void> _write() => _writing ??= _writeOnce().whenComplete(() {
    _writing = null;
    if (_dirty) _schedule(immediately: _urgent);
  });

  /// 先寫到暫存檔再換掉正式的那份：寫到一半被系統結束或空間不夠時，上一份
  /// 完整的還在。
  static Future<void> _writeOnce() async {
    final file = _file;
    if (file == null) return;
    _dirty = false;
    _urgent = false;
    try {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        '$_sessionTag$_sessionStart\n${render()}\n',
        flush: true,
      );
      await temp.rename(file.path);
      _lastWriteError = null;
    } catch (error) {
      // 存不進去也不影響使用；App 日誌少了上次開啟的那份而已。清除時要知道。
      _lastWriteError = error;
    }
  }

  static Object? _lastWriteError;

  static final RegExp _urlUserInfo = RegExp(r'(\w+://)[^/\s@]+@');
  static final RegExp _secretParameter = RegExp(
    r'([?&;]\s*(?:access_?token|token|auth|password|passwd|pwd|secret|'
    r'session_?id|sid|ticket|sign|signature|api_?key)=)[^&#\s"]*',
    caseSensitive: false,
  );
  static final RegExp _secretHeader = RegExp(
    r'''((?:set-)?cookie|authorization)(["']?\s*[:=]\s*["']?)[^"'\n}]+''',
    caseSensitive: false,
  );

  /// 遮掉 [text] 裡網址的帳號密碼、看起來像登入資料的參數，與 Cookie、
  /// Authorization 的值。崩潰日誌寫檔與讀出時也用它。
  static String redact(String text) => text
      .replaceAllMapped(_urlUserInfo, (m) => '${m[1]}***@')
      .replaceAllMapped(_secretParameter, (m) => '${m[1]}***')
      .replaceAllMapped(_secretHeader, (m) => '${m[1]}${m[2]}***');

  static const String _sessionTag = 'session ';

  static ({int start, String text})? _parse(String content) {
    final newline = content.indexOf('\n');
    if (newline < 0 || !content.startsWith(_sessionTag)) return null;
    final start = int.tryParse(content.substring(_sessionTag.length, newline));
    final text = content.substring(newline + 1).trim();
    if (start == null || !_hasEntries(text)) return null;
    return (start: start, text: text);
  }

  /// [render] 存下的整份裡有沒有任何一則紀錄（不只開啟時間與各段標頭）。
  static bool _hasEntries(String text) => text.split('\n').any((line) {
    final trimmed = line.trim();
    return trimmed.isNotEmpty &&
        trimmed != '（沒有）' &&
        !trimmed.startsWith('開啟夜讀：') &&
        !trimmed.startsWith('--- ');
  });

  static String _format(int ms, {bool full = false}) =>
      DateFormat(full ? 'yyyy-MM-dd HH:mm:ss' : 'HH:mm:ss')
          .format(DateTime.fromMillisecondsSinceEpoch(ms));

  /// 寫完正在寫的那一次（測試用）。
  @visibleForTesting
  static Future<void> flushForTesting() => _drain();

  @visibleForTesting
  static void resetForTesting({DateTime Function()? now}) {
    _actions.clear();
    _errors.clear();
    _logs.clear();
    _file = null;
    _dirty = false;
    _urgent = false;
    _writing = null;
    _timer?.cancel();
    _timer = null;
    _previous = null;
    _lastWriteError = null;
    _now = now ?? DateTime.now;
  }
}
