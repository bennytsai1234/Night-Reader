import 'dart:collection';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../di/injection.dart';
import 'crash_trail.dart';

/// AppLog - 全域日誌記錄器 (原 Android constant/AppLog.kt)
class AppLog {
  AppLog._();

  static final _logs = Queue<LogEntry>();
  static const int _maxLogs = 100;

  static final _toastController = StreamController<String>.broadcast();

  /// 設定後紀錄改交給它，不在這個 isolate 記：書源 isolate 把紀錄與提示
  /// 送回主 isolate，畫面才收得到提示。
  static void Function(
    String message,
    Object? error,
    StackTrace? stackTrace,
    bool toast,
    bool isError,
  )?
  delegate;

  /// 記錄日誌 (原 Android AppLog.kt)。[isError] 或帶著 [error] 的記成錯誤
  /// （App 日誌的「最近的錯誤」，崩潰日誌也附上），其他的是一般日誌。
  static void put(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool toast = false,
    bool isError = false,
  }) {
    final delegate = AppLog.delegate;
    if (delegate != null) {
      delegate(message, error, stackTrace, toast, isError);
      return;
    }
    if (_logs.length >= _maxLogs) {
      _logs.removeLast();
    }

    final entry = LogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    _logs.addFirst(entry);
    final line = error == null ? message : '$message: $error';
    if (isError || error != null) {
      CrashTrail.error(line, stackTrace: stackTrace);
    } else {
      CrashTrail.log(line);
    }

    if (kDebugMode) {
      if (getIt.isRegistered<Logger>()) {
        if (error != null) {
          getIt<Logger>().e(message, error: error, stackTrace: stackTrace);
        } else {
          getIt<Logger>().d(message);
        }
      } else {
        // 如果 GetIt 還沒準備好，或者是啟動階段，使用 print
        print('>>> [AppLog] $message ${error ?? ""}');
      }
    }

    if (toast) {
      _toastController.add(message);
    }
  }

  static void i(String message, {bool toast = false}) =>
      put(message, toast: toast);
  static void d(String message, {bool toast = false}) =>
      put(message, toast: toast);
  static void w(String message, {bool toast = false}) =>
      put(message, toast: toast);
  static void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool toast = false,
  }) => put(
    message,
    error: error,
    stackTrace: stackTrace,
    toast: toast,
    isError: true,
  );
}

class LogEntry {
  final int timestamp;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.message,
    this.error,
    this.stackTrace,
  });
}
