import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/exception/app_exception.dart';

/// 書源程式要使用者操作的事：開網頁讓人操作、看圖填驗證碼、顯示訊息。
///
/// 只有使用者在登入頁按下的動作可以（[runInteractive]）；其他地方——閱讀、
/// 下載、檢查更新、校驗、搜尋——書源程式一呼叫就立刻失敗
/// （[blocked]），背景工作從不停下來等人（ADR 0038）。閱讀器在失敗提示旁
/// 給「前往驗證」，使用者點了才開書源要的那一頁（[verificationFor]）。
///
/// 書源程式在書源 isolate 執行，畫面在主 isolate：要等使用者的請求經過
/// 網路 isolate 送到主 isolate（[delegate]），由開著的登入頁接手
/// （[handler]）；訊息不用等，直接送過去（[messageDelegate]）。
abstract final class SourceInteraction {
  static final Object _allowedKey = Object();

  /// 目前執行的書源程式可以要使用者操作。
  static bool get allowed => Zone.current[_allowedKey] == true;

  /// 讓 [body] 裡的書源程式可以要使用者操作。
  static Future<R> runInteractive<R>(Future<R> Function() body) =>
      runZoned(body, zoneValues: {_allowedKey: true});

  /// 主 isolate：開著的登入頁。
  static SourceInteractionHandler? handler;

  /// 書源 isolate 與網路 isolate：把請求送到主 isolate。主 isolate 是 null，
  /// 直接交給 [handler]。
  static Future<Object?> Function(SourceInteractionRequest request)? delegate;

  /// 書源 isolate：把訊息送到主 isolate。
  static void Function(SourceMessage message)? messageDelegate;

  /// 請使用者做 [request]，傳回結果（見各請求的說明）。
  static Future<Object?> request(SourceInteractionRequest request) =>
      (delegate ?? serve)(request);

  /// 主 isolate 收到請求：交給開著的登入頁。
  static Future<Object?> serve(SourceInteractionRequest request) {
    final handler = SourceInteraction.handler;
    if (handler == null) {
      throw const SourceInteractionBlockedException('登入頁已經關閉');
    }
    return switch (request) {
      final SourceBrowseRequest browse => handler.browse(browse),
      final SourceCodeRequest code => handler.verificationCode(code),
    };
  }

  /// 書源程式要顯示的訊息。只有可以要使用者操作的程式會送到登入頁，其他
  /// 地方的照舊只記在日誌（Legado 是跳出系統提示，夜讀不從背景跳出東西）。
  static void show(SourceMessage message) {
    final send = messageDelegate;
    if (send != null) {
      send(message);
    } else {
      deliver(message);
    }
  }

  /// 主 isolate 收到訊息：交給開著的登入頁；已經關了就丟掉。
  static void deliver(SourceMessage message) => handler?.message(message);

  // ── 不能要使用者操作的地方，書源要驗證 ──────────────────────────────

  static final Object _watchKey = Object();

  /// 書源程式要使用者驗證（`java.startBrowserAwait` 的網頁 [request]，或
  /// `getVerificationCode` 時是 null），但現在不能要使用者操作：記在執行中
  /// 的書源工作上（[watchVerification]），丟出給規則。
  static Never blocked(SourceBrowseRequest? request) {
    for (
      var watch = Zone.current[_watchKey] as _VerificationWatch?;
      watch != null;
      watch = watch.parent
    ) {
      watch.record(request);
    }
    throw SourceVerificationException(request);
  }

  /// 執行一件書源工作 [body]。裡面的書源程式要驗證而被擋下（[blocked]）、
  /// 這件工作又失敗了，失敗就是因為要驗證，改丟 [SourceVerificationException]：
  /// 規則多半沒接住這個錯誤，它被包成「解析失敗」；接住了的，也常因此抓不到
  /// 東西。規則接住後照樣做完的，照常傳回；取消照原樣丟出。
  static Future<R> watchVerification<R>(Future<R> Function() body) async {
    final watch = _VerificationWatch(
      Zone.current[_watchKey] as _VerificationWatch?,
    );
    try {
      return await runZoned(body, zoneValues: {_watchKey: watch});
    } catch (error) {
      if (!watch.blocked ||
          error is SourceVerificationException ||
          (error is DioException && error.type == DioExceptionType.cancel)) {
        rethrow;
      }
      throw SourceVerificationException(watch.request);
    }
  }

  /// 執行中的書源工作沒有失敗、卻什麼都沒抓到（例如正文是空的）時呼叫：
  /// 裡面的書源程式要驗證而被擋下，就是因為要驗證才抓不到，丟出
  /// [SourceVerificationException]。
  static void failIfVerificationBlocked() {
    final watch = Zone.current[_watchKey] as _VerificationWatch?;
    if (watch != null && watch.blocked) {
      throw SourceVerificationException(watch.request);
    }
  }

  static final Map<String, SourceBrowseRequest> _verifications = {};

  /// 主 isolate：書源 [sourceUrl] 的工作因為要在網頁上驗證而失敗時，記下
  /// 那一頁；閱讀器的「前往驗證」開它。同一個書源只記最近一次。
  static void rememberVerification(
    String sourceUrl,
    SourceBrowseRequest request,
  ) => _verifications[sourceUrl] = request;

  /// 書源 [sourceUrl] 最近一次要使用者驗證的網頁；沒有時是 null。
  static SourceBrowseRequest? verificationFor(String sourceUrl) =>
      _verifications[sourceUrl];

  /// 使用者去過那一頁了：之後的失敗再記新的。
  static void forgetVerification(String sourceUrl) =>
      _verifications.remove(sourceUrl);
}

/// 一件書源工作裡有沒有書源程式要驗證而被擋下。工作裡又跑書源工作時，
/// 外層也記上（[parent]）：裡面那件的失敗被規則接住，外層照樣認得。
final class _VerificationWatch {
  _VerificationWatch(this.parent);

  final _VerificationWatch? parent;
  bool blocked = false;

  /// 要開的網頁，第一個要開網頁的為準。
  SourceBrowseRequest? request;

  void record(SourceBrowseRequest? request) {
    blocked = true;
    this.request ??= request;
  }
}

/// 開著的登入頁怎麼處理書源的請求。
abstract interface class SourceInteractionHandler {
  /// 開網頁讓使用者操作。使用者按完成時傳回網頁內容（`outerHTML`），沒按
  /// 完成就離開時傳回 null。
  Future<String?> browse(SourceBrowseRequest request);

  /// 讓使用者看圖填驗證碼，傳回填的字；取消時傳回 null。
  Future<String?> verificationCode(SourceCodeRequest request);

  void message(SourceMessage message);
}

/// 要使用者做的事；會送過 isolate，只帶資料。
sealed class SourceInteractionRequest {
  const SourceInteractionRequest();
}

/// `java.startBrowser`／`startBrowserAwait`：開 [url] 讓使用者操作。
final class SourceBrowseRequest extends SourceInteractionRequest {
  const SourceBrowseRequest({
    required this.url,
    required this.title,
    required this.headers,
  });

  final String url;
  final String title;

  /// 書源的標頭（含登入標頭），開網頁時帶上，網站才認得是同一個裝置。
  final Map<String, String> headers;
}

/// `java.getVerificationCode`：讓使用者看 [image] 填驗證碼。圖片由書源
/// isolate 照書源的請求抓好（同一個登入中的 Cookie），不由畫面另外下載。
final class SourceCodeRequest extends SourceInteractionRequest {
  const SourceCodeRequest({required this.image});

  final Uint8List image;
}

/// `java.toast`／`java.longToast` 的訊息。
final class SourceMessage {
  const SourceMessage(this.text, {required this.long});

  final String text;

  /// `longToast`：書源要它停久一點，多半是說明文字。
  final bool long;
}

/// 書源要使用者驗證才抓得到，但現在不是使用者在登入頁按下的動作
/// （[SourceInteraction.blocked]）。要開網頁的訊息一律含 [marker]：閱讀器
/// 拿到的失敗是存起來的文字，靠它認出要給「前往驗證」的路（[describes]）。
class SourceVerificationException extends AppException {
  SourceVerificationException(this.request)
    : super(request == null ? '需要輸入驗證碼' : marker);

  /// 書源要使用者操作的網頁；看圖填驗證碼時是 null。
  final SourceBrowseRequest? request;

  static const String marker = '需要在網頁上驗證';

  /// [message] 是因為要在網頁上驗證才失敗的。
  static bool describes(String message) => message.contains(marker);
}

/// 登入頁已經關了，書源程式還要使用者操作。
class SourceInteractionBlockedException implements Exception {
  const SourceInteractionBlockedException(this.message);

  final String message;

  @override
  String toString() => message;
}
