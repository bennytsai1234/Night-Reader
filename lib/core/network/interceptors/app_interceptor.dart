import 'package:dio/dio.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/services/network_service.dart';

/// AppInterceptor - 全域網路攔截器 (對標 Android HttpHelper.kt 內建攔截器)
class AppInterceptor extends Interceptor {
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
  static const String _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/91.0.4472.124 Mobile Safari/537.36';
  static const String manualRedirectCountKey = '_manualRedirectCount';
  static const String manualRedirectChainKey = '_manualRedirectChain';
  static const String disableManualRedirectHandlingKey =
      '_disableManualRedirectHandling';
  static const int _maxManualRedirects = 10;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 1. 自動補全 Referer (對標 Android: 預設使用 Host 作為 Referer)
    if (!_hasHeader(options.headers, 'referer')) {
      options.headers['Referer'] = options.uri.origin;
    }

    // 2. 確保 User-Agent 存在
    if (!_hasHeader(options.headers, 'user-agent')) {
      options.headers['User-Agent'] = _defaultUserAgentFor(options.uri);
    }

    // 3. 語言修復 (對標 Android: 支援中文環境)
    if (!_hasHeader(options.headers, 'accept-language')) {
      options.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    }

    AppLog.i('Network Request: [${options.method}] ${options.uri}');
    super.onRequest(options, handler);
  }

  String _defaultUserAgentFor(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.startsWith('m.')) {
      return _mobileUserAgent;
    }
    return _desktopUserAgent;
  }

  bool _hasHeader(Map<String, dynamic> headers, String name) {
    final target = name.toLowerCase();
    return headers.keys.any((key) => key.toString().toLowerCase() == target);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 這裡可以處理特殊的內容編碼或自動修正
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    try {
      final redirected = await _tryFollowRedirect(err);
      if (redirected != null) {
        handler.resolve(redirected);
        return;
      }
    } on DioException catch (redirectError) {
      AppLog.e(
        'Network Redirect Error: ${redirectError.message}',
        error: redirectError.error,
        stackTrace: redirectError.stackTrace,
      );
      handler.next(redirectError);
      return;
    } catch (redirectError, stackTrace) {
      AppLog.e(
        'Network Redirect Error: $redirectError',
        error: redirectError,
        stackTrace: stackTrace,
      );
      handler.next(err);
      return;
    }

    AppLog.e(
      'Network Error: ${err.message}',
      error: err.error,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }

  Future<Response<dynamic>?> _tryFollowRedirect(DioException err) async {
    final response = err.response;
    if (err.type != DioExceptionType.badResponse || response == null) {
      return null;
    }
    if (err.requestOptions.extra[disableManualRedirectHandlingKey] == true) {
      return null;
    }
    final statusCode = response.statusCode;
    if (!_isRedirectStatus(statusCode)) {
      return null;
    }

    final request = err.requestOptions;
    final locationHeader = response.headers.value('location');
    if (locationHeader == null || locationHeader.trim().isEmpty) {
      return null;
    }

    final redirectCount = (request.extra[manualRedirectCountKey] as int?) ?? 0;
    if (redirectCount >= _maxManualRedirects) {
      return null;
    }

    final resolvedUri = response.realUri.resolve(locationHeader.trim());
    final redirectedMethod = _redirectMethod(request.method, statusCode);
    final maintainBody = _maintainsRedirectBody(request.method, statusCode);
    final redirectedHeaders = Map<String, dynamic>.from(request.headers);
    if (!maintainBody) {
      _removeHeader(redirectedHeaders, Headers.contentLengthHeader);
      _removeHeader(redirectedHeaders, Headers.contentTypeHeader);
      _removeHeader(redirectedHeaders, 'transfer-encoding');
    }
    if (!_isSameAuthority(request.uri, resolvedUri)) {
      _removeHeader(redirectedHeaders, 'authorization');
      _removeHeader(redirectedHeaders, 'cookie');
    }

    final redirectChain =
        ((request.extra[manualRedirectChainKey] as List?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    redirectChain.add(resolvedUri.toString());

    final redirectedExtra =
        Map<String, dynamic>.from(request.extra)
          ..[manualRedirectCountKey] = redirectCount + 1
          ..[manualRedirectChainKey] = redirectChain;

    final redirectedRequest = RequestOptions(
      method: redirectedMethod,
      sendTimeout: request.sendTimeout,
      receiveTimeout: request.receiveTimeout,
      connectTimeout: request.connectTimeout,
      data: maintainBody ? request.data : null,
      path: resolvedUri.toString(),
      baseUrl: '',
      queryParameters: const <String, dynamic>{},
      onReceiveProgress: request.onReceiveProgress,
      onSendProgress: request.onSendProgress,
      cancelToken: request.cancelToken,
      extra: redirectedExtra,
      headers: redirectedHeaders,
      preserveHeaderCase: request.preserveHeaderCase,
      responseType: request.responseType,
      validateStatus: request.validateStatus,
      receiveDataWhenStatusError: request.receiveDataWhenStatusError,
      followRedirects: false,
      maxRedirects: 0,
      persistentConnection: request.persistentConnection,
      requestEncoder: request.requestEncoder,
      responseDecoder: request.responseDecoder,
      listFormat: request.listFormat,
    );
    redirectedRequest.cancelToken?.requestOptions = redirectedRequest;

    AppLog.i(
      'Network Redirect: [${request.method}] ${request.uri} '
      '-> [$redirectedMethod] $resolvedUri ($statusCode)',
    );

    final redirectedResponse = await NetworkService().dio.fetch<dynamic>(
      redirectedRequest,
    );
    final finalChain =
        ((redirectedResponse.extra[manualRedirectChainKey] as List?) ??
                redirectChain)
            .map((item) => item.toString())
            .toList();
    redirectedResponse.extra[manualRedirectCountKey] = finalChain.length;
    redirectedResponse.extra[manualRedirectChainKey] = finalChain;
    return redirectedResponse;
  }

  bool _isRedirectStatus(int? statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  String _redirectMethod(String method, int? statusCode) {
    final upperMethod = method.toUpperCase();
    if (_redirectsToGet(upperMethod) &&
        statusCode != 307 &&
        statusCode != 308) {
      return 'GET';
    }
    return upperMethod;
  }

  bool _maintainsRedirectBody(String method, int? statusCode) {
    final upperMethod = method.toUpperCase();
    if (!_permitsRequestBody(upperMethod)) {
      return false;
    }
    return _redirectsWithBody(upperMethod) ||
        statusCode == 307 ||
        statusCode == 308;
  }

  bool _permitsRequestBody(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
      case 'HEAD':
        return false;
      default:
        return true;
    }
  }

  bool _redirectsToGet(String method) => method.toUpperCase() != 'PROPFIND';

  bool _redirectsWithBody(String method) => method.toUpperCase() == 'PROPFIND';

  bool _isSameAuthority(Uri left, Uri right) =>
      left.scheme == right.scheme &&
      left.host == right.host &&
      left.port == right.port;

  void _removeHeader(Map<String, dynamic> headers, String headerName) {
    final target = headerName.toLowerCase();
    final matches =
        headers.keys
            .where((key) => key.toString().toLowerCase() == target)
            .toList();
    for (final key in matches) {
      headers.remove(key);
    }
  }
}
