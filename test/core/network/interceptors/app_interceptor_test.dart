import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/services/network_service.dart';

class _RedirectLoopAdapter implements HttpClientAdapter {
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final nextPath = options.uri.path == '/loop-a' ? '/loop-b' : '/loop-a';
    return ResponseBody.fromString(
      '',
      302,
      headers: <String, List<String>>{
        HttpHeaders.locationHeader: <String>[nextPath],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('manual redirects stop before revisiting a URI', () async {
      await NetworkService().init(ephemeral: true);
      final dio = NetworkService().dio;
      final originalAdapter = dio.httpClientAdapter;
      final adapter = _RedirectLoopAdapter();
      dio.httpClientAdapter = adapter;
      addTearDown(() {
        dio.httpClientAdapter = originalAdapter;
      });

      await expectLater(
        dio.get<void>(
          'https://example.com/loop-a',
          options: Options(followRedirects: false),
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests.map((uri) => uri.path), <String>[
        '/loop-a',
        '/loop-b',
      ]);
    });
  });
}
