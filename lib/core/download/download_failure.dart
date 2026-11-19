import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:drift/native.dart' show SqliteException;
import 'package:night_reader/core/download/audio_chapter_download.dart';
import 'package:night_reader/core/engine/js/jsoup/jsoup_bridge.dart';
import 'package:night_reader/core/engine/source_isolate/isolate_channel.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/source/source_interaction.dart';

/// 下載抓的是哪一部分，書源抓不到時照它說「抓不到目錄」「抓不到正文」。
enum DownloadPart {
  toc('目錄'),
  content('正文'),
  images('圖片'),
  audio('音訊');

  const DownloadPart(this.label);
  final String label;
}

/// 下載失敗給讀者看的說法：[reason] 是失敗類型（「查看失敗原因」的第一列），
/// [message] 是一句「發生了什麼，可以怎麼處理」，寫在下載佇列那一列的紅字
/// （docs/design/components.md「失敗提示」）。原始錯誤寫進 App 日誌，不印在
/// 畫面上。
///
/// 在書源 isolate 裡、錯誤還保有型別時用 [DownloadFailure.of] 判斷；判斷好
/// 的可以直接丟出（它是 [Exception]，只帶字串，送得回主 isolate）。
final class DownloadFailure implements Exception {
  const DownloadFailure(this.reason, this.message);

  final String reason;
  final String message;

  /// 已經判斷好的原樣回傳；其他照錯誤的種類換成白話說法。
  factory DownloadFailure.of(Object error, {required DownloadPart part}) {
    return switch (error) {
      DownloadFailure() => error,
      DioException() => _dio(error, part),
      SocketException() || HttpException() => unreachable,
      HandshakeException() => badCertificate,
      TimeoutException() => slow,
      LoginCheckException() => loginRequired,
      SourceVerificationException() => verificationRequired,
      HumanVerificationRequiredException() => humanCheck,
      SiteBlockedException() => siteBlocked,
      ChallengeNotPassedException() => challengeFailed,
      ConcurrentException() => rateLimited,
      LockedChapterException(:final message) => DownloadFailure(
        '付費章節',
        message,
      ),
      NetworkException(:final statusCode?) => _status(statusCode, part),
      NetworkException() => unreachable,
      ContentEmptyException() ||
      TocEmptyException() ||
      ParsingException() ||
      RuleJsException() ||
      RegexTimeoutException() ||
      JsoupException() ||
      SourceException() => sourceBroken(part),
      AudioDownloadRefused(:final message) => DownloadFailure('不能下載', message),
      FileSystemException(:final osError) when _noSpace(osError) => noSpace,
      FileSystemException() ||
      SqliteException() ||
      DriftWrappedException() => saveFailed,
      // 錯誤從別的 isolate 只帶回文字：先看是不是上面那幾種說法。
      IsolateTaskError(:final message) => _fromText(message, part),
      _ => appError,
    };
  }

  static const unreachable = DownloadFailure('連不上網站', '連不上網站，檢查網路後重試或換源');
  static const slow = DownloadFailure('網站回應太慢', '網站回應太慢，稍後重試或換源');
  static const badCertificate = DownloadFailure('網站憑證有問題', '網站的安全憑證有問題，換源');
  static const rateLimited = DownloadFailure('網站限制頻率', '網站限制了抓取的頻率，隔一段時間再重試');
  static const loginRequired = DownloadFailure('要登入', '書源要登入，登入書源後重試');
  static const verificationRequired = DownloadFailure(
    '要網頁驗證',
    '書源要在網頁上驗證，打開這本書照提示驗證後重試',
  );
  static const humanCheck = DownloadFailure('網站要真人驗證', '網站要求真人驗證、夜讀不能自動通過，換源');
  static const siteBlocked = DownloadFailure('網站封鎖', '網站封鎖了目前的網路，換個網路後重試或換源');
  static const challengeFailed = DownloadFailure(
    '網站檢查沒過',
    '網站的瀏覽器檢查沒有通過，稍後重試或換源',
  );
  static const sourceDeleted = DownloadFailure('書源已刪除', '這本書的書源已經刪除，換源');
  static const bookRemoved = DownloadFailure('書已移除', '這本書已經從夜讀移除，刪除這個任務');
  static const rangeGone = DownloadFailure('範圍失效', '選的章節已不在目錄裡，重新選擇範圍');
  static const illustrationsMissing = DownloadFailure(
    '插圖抓不到',
    '正文存好了但插圖抓不到，稍後重試',
  );
  static const noSpace = DownloadFailure('空間不足', '手機空間不足，清出空間後重試');
  static const saveFailed = DownloadFailure('存檔失敗', '存進手機時出錯，重試');
  static const appError = DownloadFailure(
    '夜讀出錯',
    '夜讀處理時出錯，重試；一直失敗請到「App 日誌」分享給開發者',
  );

  static DownloadFailure sourceBroken(DownloadPart part) => DownloadFailure(
    '書源抓不到${part.label}',
    '書源抓不到${part.label}，校驗或 AI 修復書源，或換源',
  );

  static DownloadFailure _dio(DioException error, DownloadPart part) {
    final inner = error.error;
    if (inner != null && inner is! DioException) {
      final described = DownloadFailure.of(inner, part: part);
      if (!identical(described, appError)) return described;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => slow,
      DioExceptionType.connectionError => unreachable,
      DioExceptionType.badCertificate => badCertificate,
      DioExceptionType.badResponse => switch (error.response?.statusCode) {
        final code? => _status(code, part),
        null => const DownloadFailure('網站回應錯誤', '網站回應錯誤，稍後重試或換源'),
      },
      // 取消不算失敗，呼叫端先接走；走到這裡當成連不上。
      DioExceptionType.cancel || DioExceptionType.unknown => unreachable,
    };
  }

  static DownloadFailure _status(int code, DownloadPart part) => switch (code) {
    401 => DownloadFailure('要登入', '網站要登入（$code），登入書源後重試'),
    403 => DownloadFailure('網站拒絕', '網站拒絕了夜讀（$code），稍後重試或換源'),
    404 || 410 => DownloadFailure(
      '網站找不到',
      '網站上找不到這個${part == DownloadPart.toc ? '目錄' : '章節'}（$code），'
          '校驗書源或換源',
    ),
    429 => DownloadFailure('網站限制頻率', '網站限制了抓取的頻率（$code），隔一段時間再重試'),
    >= 500 => DownloadFailure('網站出錯', '網站暫時出錯（$code），稍後重試或換源'),
    _ => DownloadFailure('網站回應錯誤', '網站回應錯誤（$code），稍後重試或換源'),
  };

  static bool _noSpace(OSError? error) =>
      error != null &&
      (error.errorCode == 28 || // Linux、Android 的 ENOSPC
          error.errorCode == 112 || // Windows 的 ERROR_DISK_FULL
          error.message.toLowerCase().contains('no space'));

  static DownloadFailure _fromText(String text, DownloadPart part) {
    for (final known in [
      humanCheck,
      siteBlocked,
      challengeFailed,
      loginRequired,
      verificationRequired,
    ]) {
      if (_markers[known]!.any(text.contains)) return known;
    }
    return appError;
  }

  static final Map<DownloadFailure, List<String>> _markers = {
    humanCheck: [HumanVerificationRequiredException().message],
    siteBlocked: [SiteBlockedException().message],
    challengeFailed: [ChallengeNotPassedException().message],
    loginRequired: [LoginCheckException.marker],
    verificationRequired: [SourceVerificationException.marker],
  };

  @override
  String toString() => message;
}
