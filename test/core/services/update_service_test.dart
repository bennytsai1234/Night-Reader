import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/services/update_service.dart';

void main() {
  group('AppUpdateService.isNewer', () {
    test('detects newer patch correctly across non-lexical numbers', () {
      expect(AppUpdateService.isNewer('v0.2.72', '0.2.9'), isTrue);
      expect(AppUpdateService.isNewer('v0.2.9', '0.2.72'), isFalse);
    });

    test('handles tag with and without v prefix', () {
      expect(AppUpdateService.isNewer('v0.3.0', '0.2.99'), isTrue);
      expect(AppUpdateService.isNewer('0.3.0', '0.2.99'), isTrue);
      expect(AppUpdateService.isNewer('V0.3.0', 'v0.2.99'), isTrue);
    });

    test('same version is not newer', () {
      expect(AppUpdateService.isNewer('v0.2.72', '0.2.72'), isFalse);
    });

    test('major and minor bumps win', () {
      expect(AppUpdateService.isNewer('v1.0.0', '0.99.99'), isTrue);
      expect(AppUpdateService.isNewer('v0.3.0', '0.2.99'), isTrue);
    });

    test('unparseable version is treated as not newer', () {
      expect(AppUpdateService.isNewer('v0.2', '0.2.0'), isFalse);
      expect(AppUpdateService.isNewer('vbeta', '0.2.0'), isFalse);
    });
  });

  group('AppUpdateService.checkLatest', () {
    test(
      'returns UpdateInfo when remote is newer and APK asset exists',
      () async {
        final service = AppUpdateService(
          dio: _dioReturning({
            'tag_name': 'v0.3.0',
            'body': 'New stuff',
            'html_url': 'https://github.com/x/y/releases/tag/v0.3.0',
            'assets': [
              {
                'name': 'inkpage-v0.3.0.apk',
                'browser_download_url': 'https://example.com/app.apk',
                'size': 12345,
              },
            ],
          }),
          currentVersionLoader: () async => '0.2.72',
        );

        final info = await service.checkLatest();

        expect(info, isNotNull);
        expect(info!.versionName, '0.3.0');
        expect(info.tagName, 'v0.3.0');
        expect(info.downloadUrl, 'https://example.com/app.apk');
        expect(info.assetSize, 12345);
        expect(info.releasePageUrl, contains('v0.3.0'));
      },
    );

    test('returns null when current version is up to date', () async {
      final service = AppUpdateService(
        dio: _dioReturning({
          'tag_name': 'v0.2.72',
          'body': '',
          'html_url': '',
          'assets': [
            {
              'name': 'app.apk',
              'browser_download_url': 'https://example.com/app.apk',
              'size': 1,
            },
          ],
        }),
        currentVersionLoader: () async => '0.2.72',
      );

      expect(await service.checkLatest(), isNull);
    });

    test('returns null when no APK asset is published', () async {
      final service = AppUpdateService(
        dio: _dioReturning({
          'tag_name': 'v0.3.0',
          'body': '',
          'html_url': '',
          'assets': [
            {'name': 'sources.json', 'browser_download_url': '', 'size': 0},
          ],
        }),
        currentVersionLoader: () async => '0.2.72',
      );

      expect(await service.checkLatest(), isNull);
    });

    test('returns null on HTTP error', () async {
      final service = AppUpdateService(
        dio: _dioThrowing(),
        currentVersionLoader: () async => '0.2.72',
      );

      expect(await service.checkLatest(), isNull);
    });
  });
}

Dio _dioReturning(Map<String, dynamic> payload) {
  final dio = Dio();
  dio.httpClientAdapter = _StaticAdapter(payload);
  return dio;
}

Dio _dioThrowing() {
  final dio = Dio();
  dio.httpClientAdapter = _ThrowingAdapter();
  return dio;
}

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.payload);
  final Map<String, dynamic> payload;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final bytes = utf8.encode(jsonEncode(payload));
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'simulated network failure',
    );
  }
}
