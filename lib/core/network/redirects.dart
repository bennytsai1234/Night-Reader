import 'package:dio/dio.dart';

/// HTTP 套件自己跟著走的轉址（GET 的 301、302 這類）換算成完整網址。
///
/// Dio 的 `realUri` 直接給最後一個 Location 的原文，相對網址（例如
/// `/down`）不會換算；每一跳的 Location 要以前一跳的網址為準。
extension ResponseRedirects<T> on Response<T> {
  /// 依序走過的每一跳。
  List<Uri> get redirectedUris {
    var from = requestOptions.uri;
    return [
      for (final redirect in redirects)
        from = from.resolveUri(redirect.location),
    ];
  }

  /// 最後抓的網址。
  Uri get finalUri => redirectedUris.lastOrNull ?? requestOptions.uri;
}
