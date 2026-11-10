import 'package:dio/dio.dart';

/// 錯誤的原文，給日誌與書源校驗的紀錄用（給使用者看的白話原因是
/// `userErrorReason`）。dio 包住底層錯誤（憑證、DNS、連線被拒）時 message 是
/// null，原因放在 `error`，`toString()` 的第一行只剩「DioException [unknown]:
/// null」；這裡把原因接在同一行。
String errorText(Object error) => switch (error) {
  DioException(message: null, error: final Object cause, :final type) =>
    'DioException [${type.name}]: $cause',
  _ => '$error',
};
