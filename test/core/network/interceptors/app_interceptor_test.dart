import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/network/interceptors/app_interceptor.dart';

void main() {
  group('AppInterceptor', () {
    test('does not duplicate lower-case custom headers', () {
      final options = RequestOptions(
        path: 'https://example.com/search',
        headers: {
          'user-agent': 'Custom UA',
          'referer': 'https://example.com',
          'accept-language': 'ja-JP',
        },
      );

      AppInterceptor().onRequest(options, RequestInterceptorHandler());

      expect(
        options.headers.entries
            .where(
              (entry) => entry.key.toString().toLowerCase() == 'user-agent',
            )
            .map((entry) => entry.value)
            .toList(),
        ['Custom UA'],
      );
      expect(
        options.headers.entries
            .where((entry) => entry.key.toString().toLowerCase() == 'referer')
            .map((entry) => entry.value)
            .toList(),
        ['https://example.com'],
      );
      expect(
        options.headers.entries
            .where(
              (entry) =>
                  entry.key.toString().toLowerCase() == 'accept-language',
            )
            .map((entry) => entry.value)
            .toList(),
        ['ja-JP'],
      );
    });

    test('injects defaults when headers are missing', () {
      final options = RequestOptions(path: 'https://example.com/search');

      AppInterceptor().onRequest(options, RequestInterceptorHandler());

      expect(options.headers['Referer'], 'https://example.com');
      expect(options.headers['User-Agent'], isNotEmpty);
      expect(options.headers['Accept-Language'], 'zh-CN,zh;q=0.9,en;q=0.8');
    });
  });
}
