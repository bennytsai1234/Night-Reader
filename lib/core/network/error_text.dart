import 'dart:io';

import 'package:dio/dio.dart';

/// 錯誤的原文，給日誌與書源校驗的紀錄用（給使用者看的白話原因是
/// `userErrorReason`）。dio 包住底層錯誤（憑證、DNS、連線被拒）時 message 是
/// null 或一句「The connection errored」，原因放在 `error`，`toString()` 的
/// 第一行看不到原因；這裡把原因接在同一行。
String errorText(Object error) => switch (error) {
  DioException(error: final Object cause, :final type, :final requestOptions)
      when cause is SocketException || error.message == null =>
    'DioException [${type.name}]: ${_causeText(cause, requestOptions.uri)}',
  _ => '$error',
};

/// Dart 連線失敗時 SocketException 寫的 port 是本機這一端的臨時埠，每次都
/// 不同，不是網站的埠（2026-11-13 AI 看到 54550、36782 以為被劫持）；改寫
/// 成連的是哪個網站的哪個埠。
String _causeText(Object cause, Uri uri) => switch (cause) {
  SocketException(:final message, :final osError, :final address)
      when address != null =>
    'SocketException: $message'
        '${osError == null ? '' : ' (OS Error: ${osError.message}, '
                  'errno = ${osError.errorCode})'}'
        '，連到 ${uri.host}:${uri.port}（${address.address}）',
  _ => '$cause',
};
