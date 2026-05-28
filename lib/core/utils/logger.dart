import 'package:flutter/foundation.dart';

class Logger {
  static void i(String message) {
    debugPrint('[INFO] $message');
  }

  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint('[ERROR] $message');
    if (error != null) debugPrint('Error: $error');
    if (stackTrace != null) debugPrint('StackTrace: $stackTrace');
  }

  static void d(String message) {
    debugPrint('[DEBUG] $message');
  }

  static void w(String message) {
    debugPrint('[WARN] $message');
  }
}
