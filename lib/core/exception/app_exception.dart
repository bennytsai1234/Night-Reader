/// AppException - 應用程式例外基類 (原 Android exception/NoStackTraceException.kt)
abstract class AppException implements Exception {
  final String message;
  AppException(this.message);

  @override
  String toString() => message;
}

/// ConcurrentException - 併發限制例外 (對標 ConcurrentException.kt)
class ConcurrentException extends AppException {
  final int waitTime;
  ConcurrentException(super.message, this.waitTime);
}

/// ContentEmptyException - 正文解析為空 (對標 ContentEmptyException.kt)
class ContentEmptyException extends AppException {
  ContentEmptyException(super.message);
}

/// TocEmptyException - 目錄解析為空 (對標 TocEmptyException.kt)
class TocEmptyException extends AppException {
  TocEmptyException(super.message);
}

/// RegexTimeoutException - 正規表達式執行超時 (對標 RegexTimeoutException.kt)
class RegexTimeoutException extends AppException {
  RegexTimeoutException(super.message);
}

/// EmptyFileException - 本地文件為空 (對標 EmptyFileException.kt)
class EmptyFileException extends AppException {
  EmptyFileException(super.message);
}

/// EpubFormatException - EPUB 讀不出書名、章節或文字
class EpubFormatException extends AppException {
  EpubFormatException(super.message);
}

/// NoBooksDirException - 找不到書籍目錄 (對標 NoBooksDirException.kt)
class NoBooksDirException extends AppException {
  NoBooksDirException(super.message);
}

/// InvalidBooksDirException - 書籍目錄無效 (對標 InvalidBooksDirException.kt)
class InvalidBooksDirException extends AppException {
  InvalidBooksDirException(super.message);
}

/// NoStackTraceException - 傳統 Legacy 命名對位
class NoStackTraceException extends AppException {
  NoStackTraceException(super.message);
}

/// NetworkException - 網路請求失敗
class NetworkException extends AppException {
  final int? statusCode;
  final String? url;
  NetworkException(super.message, {this.statusCode, this.url});
}

/// ParsingException - 解析規則執行失敗
class ParsingException extends AppException {
  final String? rule;
  final String? mode;
  final String? url;
  final dynamic originalError;

  ParsingException(
    super.message, {
    this.rule,
    this.mode,
    this.url,
    this.originalError,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    if (mode != null) buffer.write('[$mode] ');
    buffer.write(message);
    if (rule != null) buffer.write('\n規則: $rule');
    if (url != null) buffer.write('\nURL: $url');
    if (originalError != null) buffer.write('\n原始錯誤: $originalError');
    return buffer.toString();
  }
}

/// 規則 JS 執行出錯、規則自己沒接住（對標 Rhino 丟出的錯誤）。規則照失敗
/// 處理，錯誤訊息不會被當成正文、網址或分類。
class RuleJsException extends AppException {
  RuleJsException(super.message);
}

/// 書源要登入才讀得到（目錄或正文被登入牆擋住，見 `LoginWall`）。訊息一律
/// 含 [marker]：閱讀器與詳情頁拿到的失敗是存起來的文字，靠它認出要給
/// 「登入」的路（[describes]）。
class LoginCheckException extends AppException {
  final String? sourceUrl;
  LoginCheckException(super.message, {this.sourceUrl})
    : assert(message.contains(marker));

  static const String marker = '需要登入';

  /// [message] 是因為要登入才失敗的。
  static bool describes(String message) => message.contains(marker);
}

/// SourceException - 書源配置錯誤（缺少必要欄位等）
class SourceException extends AppException {
  final String? sourceUrl;
  SourceException(super.message, {this.sourceUrl});
}

/// AdultContentException - 18+ 內容限制
class AdultContentException extends AppException {
  AdultContentException(super.message);
}

/// DownloadException - 下載過程中的錯誤
class DownloadException extends AppException {
  final String? bookUrl;
  final int? chapterIndex;
  DownloadException(super.message, {this.bookUrl, this.chapterIndex});
}
