import 'package:dio/dio.dart';

/// StrResponse - 對標 Android help/http/StrResponse.kt
class StrResponse {
  final String url;
  final String body;
  final Map<String, List<String>> headers;
  final Response raw;

  StrResponse({
    required this.url,
    required this.body,
    required this.headers,
    required this.raw,
  });

  List<String> get redirectChain =>
      ((raw.extra['_manualRedirectChain'] as List?) ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList();

  bool get isRedirect => raw.redirects.isNotEmpty || redirectChain.isNotEmpty;
}
