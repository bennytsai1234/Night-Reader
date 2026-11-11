import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// 系統記下的夜讀一次結束（Android 11 起，`ProcessExits.kt`）。
class ProcessExit {
  const ProcessExit({
    required this.timestamp,
    required this.reason,
    this.status = 0,
    this.importance = 0,
    this.description,
    this.pssKb = 0,
    this.rssKb = 0,
    this.trace,
  });

  factory ProcessExit.fromMap(Map<Object?, Object?> map) => ProcessExit(
    timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    reason: (map['reason'] as num?)?.toInt() ?? 0,
    status: (map['status'] as num?)?.toInt() ?? 0,
    importance: (map['importance'] as num?)?.toInt() ?? 0,
    description: map['description'] as String?,
    pssKb: (map['pss'] as num?)?.toInt() ?? 0,
    rssKb: (map['rss'] as num?)?.toInt() ?? 0,
    trace: map['trace'] as String?,
  );

  final int timestamp;

  /// `ApplicationExitInfo.REASON_*`。
  final int reason;

  /// 結束碼；被訊號結束時是訊號編號。
  final int status;

  /// 結束時在系統眼中多重要（`RunningAppProcessInfo.IMPORTANCE_*`）：越小
  /// 越在前景。
  final int importance;
  final String? description;
  final int pssKb;
  final int rssKb;

  /// 沒有回應時的執行緒追蹤、原生崩潰的 tombstone 裡的文字。
  final String? trace;

  static const int reasonUnknown = 0;
  static const int reasonExitSelf = 1;
  static const int reasonSignaled = 2;
  static const int reasonLowMemory = 3;
  static const int reasonCrash = 4;
  static const int reasonCrashNative = 5;
  static const int reasonAnr = 6;
  static const int reasonInitializationFailure = 7;
  static const int reasonExcessiveResourceUsage = 9;
  static const int reasonDependencyDied = 12;
  static const int reasonOther = 13;
  static const int reasonFreezer = 14;

  /// 一定是出了問題的結束。
  static const Set<int> _failures = {
    reasonCrash,
    reasonCrashNative,
    reasonAnr,
    reasonInitializationFailure,
    reasonExcessiveResourceUsage,
  };

  /// 被系統收掉：在背景時是平常的事（系統要記憶體），使用者正在用的時候
  /// （前景、看得到、前景服務）才算閃退。
  static const Set<int> _killed = {
    reasonUnknown,
    reasonSignaled,
    reasonLowMemory,
    reasonDependencyDied,
    reasonOther,
    reasonFreezer,
  };

  /// `IMPORTANCE_VISIBLE`：數字不大於它的是使用者看得到的。
  static const int _visible = 200;

  /// 要寫進崩潰日誌：出了問題，或使用者看得到時被收掉。自己結束、使用者
  /// 在設定裡強制停止、更新 App、改權限這些不寫；從最近使用滑掉也不寫。
  bool get isReportable {
    if (_failures.contains(reason)) return true;
    if (!_killed.contains(reason) || importance > _visible) return false;
    return !(description ?? '').contains('remove task');
  }

  String get reasonLabel => switch (reason) {
    reasonCrashNative => '原生程式崩潰（訊號 ${_signal(status)}）',
    reasonCrash => 'Android 程式崩潰',
    reasonAnr => '沒有回應，被系統結束',
    reasonInitializationFailure => '啟動失敗',
    reasonExcessiveResourceUsage => '用了太多資源，被系統結束',
    reasonLowMemory => '記憶體不足，被系統收掉',
    reasonSignaled => '被系統以訊號 ${_signal(status)} 結束',
    reasonDependencyDied => '依賴的程序結束了，跟著結束',
    reasonFreezer => '凍結時被系統結束',
    reasonOther => '被系統結束（其他原因）',
    _ => '原因不明（$reason）',
  };

  String get importanceLabel => switch (importance) {
    100 => '前景',
    125 => '前景服務',
    200 => '看得到',
    230 => '可察覺',
    300 => '服務',
    _ when importance > 300 => '背景',
    _ => '$importance',
  };

  static String _signal(int status) => switch (status) {
    6 => '6 SIGABRT',
    9 => '9 SIGKILL',
    11 => '11 SIGSEGV',
    7 => '7 SIGBUS',
    4 => '4 SIGILL',
    8 => '8 SIGFPE',
    _ => '$status',
  };

  /// 崩潰日誌裡的這一段。
  String render() {
    final time = DateFormat('yyyy-MM-dd HH:mm:ss')
        .format(DateTime.fromMillisecondsSinceEpoch(timestamp));
    final buffer = StringBuffer()
      ..writeln('結束時間: $time')
      ..writeln('原因: $reasonLabel')
      ..writeln('當時: $importanceLabel')
      ..writeln('記憶體: ${pssKb ~/ 1024} MB（PSS）、${rssKb ~/ 1024} MB（RSS）');
    if ((description ?? '').trim().isNotEmpty) {
      buffer.writeln('系統說明: ${description!.trim()}');
    }
    if ((trace ?? '').trim().isNotEmpty) {
      buffer
        ..writeln('\n--- 系統留下的追蹤 ---')
        ..writeln(trace!.trim());
    }
    return buffer.toString().trimRight();
  }
}

/// 讀系統記下的結束；Android 以外、或 Android 11 以前沒有，回空清單。
abstract class ProcessExitSource {
  Future<List<ProcessExit>> recent();

  static ProcessExitSource platform = _ChannelProcessExits();
}

class _ChannelProcessExits implements ProcessExitSource {
  static const MethodChannel _channel = MethodChannel(
    'night_reader/process_exits',
  );

  @override
  Future<List<ProcessExit>> recent() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      final list = await _channel.invokeListMethod<Object?>('recent');
      return [
        for (final item in list ?? const <Object?>[])
          if (item is Map) ProcessExit.fromMap(item),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
