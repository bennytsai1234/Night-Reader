import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/services.dart' show PlatformException;
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/services/app_log_service.dart';

/// 「[action]失敗：原因」給畫面用，原始錯誤寫進 App 日誌。
///
/// 呼叫端自己已經寫過日誌時改用 [userErrorReason]，免得同一個錯誤記兩次。
String failureMessage(String action, Object error, [StackTrace? stackTrace]) {
  AppLog.e('$action失敗: $error', error: error, stackTrace: stackTrace);
  return '$action失敗：${userErrorReason(error)}';
}

/// 給使用者看的一句錯誤原因。
///
/// 書源與 App 自己丟出的錯誤本來就是中文，照原文；網路、檔案、格式與
/// 資料庫這類系統錯誤的原文是英文技術訊息，換成固定的白話說法；其他
/// 認不出的一律「發生未預期的錯誤」，細節看日誌。
String userErrorReason(Object error) {
  return switch (error) {
    AppException(:final message) => message,
    DioException() => _networkReason(error),
    SocketException() || HttpException() || HandshakeException() => '網路連線失敗',
    TimeoutException() => '連線逾時',
    FormatException() => '資料格式不對',
    FileSystemException() => '讀寫檔案失敗',
    SqliteException() || DriftWrappedException() => '資料庫存取失敗',
    PlatformException() => '系統功能呼叫失敗',
    _ => _chineseMessage(error) ?? '發生未預期的錯誤',
  };
}

String _networkReason(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => '連線逾時',
    DioExceptionType.connectionError => '網路連線失敗',
    DioExceptionType.badCertificate => '網站憑證有問題',
    DioExceptionType.badResponse => switch (error.response?.statusCode) {
      final code? => '伺服器回應錯誤（$code）',
      null => '伺服器回應錯誤',
    },
    DioExceptionType.cancel => '已取消',
    DioExceptionType.unknown => switch (error.error) {
      final Object inner when inner is! DioException => userErrorReason(inner),
      _ => '網路錯誤',
    },
  };
}

/// 程式裡 `throw Exception('中文')`、`StateError('中文')` 這類訊息：去掉
/// Dart 加上的英文前綴後，有中文就照用。
String? _chineseMessage(Object error) {
  final text = error.toString().replaceFirst(_dartPrefix, '').trim();
  return _cjk.hasMatch(text) ? text : null;
}

final RegExp _dartPrefix = RegExp(
  r'^(Exception|Bad state|Invalid argument\(s\)|Unsupported operation)'
  r'(\s*\([^)]*\))?:\s*',
);
final RegExp _cjk = RegExp(r'[㐀-鿿]');
