import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/download/download_failure.dart';
import 'package:night_reader/core/engine/source_isolate/isolate_channel.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/cloudflare.dart';

DioException response(int code) {
  final options = RequestOptions(path: 'https://book.example/c/1');
  return DioException.badResponse(
    statusCode: code,
    requestOptions: options,
    response: Response<void>(requestOptions: options, statusCode: code),
  );
}

DownloadFailure content(Object error) =>
    DownloadFailure.of(error, part: DownloadPart.content);

void main() {
  final options = RequestOptions(path: 'https://book.example/c/1');

  // 每一種都要說清楚發生什麼、讀者能怎麼處理，不落到含糊的說法。
  final cases = <String, (Object, String, String)>{
    '403': (response(403), '網站拒絕', '換源'),
    '404': (response(404), '網站找不到', '校驗書源'),
    '429': (response(429), '網站限制頻率', '隔一段時間再重試'),
    '503': (response(503), '網站出錯', '稍後重試'),
    'timeout': (
      DioException.connectionTimeout(
        timeout: const Duration(seconds: 15),
        requestOptions: options,
      ),
      '網站回應太慢',
      '稍後重試',
    ),
    'offline': (
      DioException.connectionError(
        requestOptions: options,
        reason: 'Failed host lookup',
        error: const SocketException('Failed host lookup'),
      ),
      '連不上網站',
      '檢查網路',
    ),
    'cloudflare checkbox': (
      DioException(
        requestOptions: options,
        error: HumanVerificationRequiredException(),
      ),
      '網站要真人驗證',
      '換源',
    ),
    'login wall': (LoginCheckException('目錄需要登入後閱讀'), '要登入', '登入書源'),
    'rule js error': (
      RuleJsException('TypeError: Cannot read property "text" of null'),
      '書源抓不到正文',
      'AI 修復',
    ),
    'empty content': (ContentEmptyException('章節內容為空'), '書源抓不到正文', '校驗'),
    'disk full': (
      const FileSystemException(
        'Cannot write',
        '/data/book.txt',
        OSError('No space left on device', 28),
      ),
      '空間不足',
      '清出空間',
    ),
    'text from another isolate': (
      IsolateTaskError(HumanVerificationRequiredException().message),
      '網站要真人驗證',
      '換源',
    ),
  };
  for (final MapEntry(key: name, value: (error, reason, remedy))
      in cases.entries) {
    test('$name: $reason, $remedy', () {
      final failure = content(error);
      expect(failure.reason, reason);
      expect(failure.message, contains(remedy));
      expect(failure.message, isNot(contains('未預期')));
    });
  }

  test('a bug in 夜讀 itself says so and how to report it', () {
    Object? error;
    try {
      (null as dynamic).text;
    } catch (e) {
      error = e;
    }
    final failure = content(error!);
    expect(failure, same(DownloadFailure.appError));
    expect(failure.message, contains('重試'));
    expect(failure.message, contains('App 日誌'));
  });

  test('a source that returns no TOC names the TOC', () {
    expect(
      DownloadFailure.of(
        TocEmptyException('目錄為空'),
        part: DownloadPart.toc,
      ).message,
      startsWith('書源抓不到目錄'),
    );
  });

  test('an already classified failure passes through unchanged', () {
    expect(
      content(DownloadFailure.sourceDeleted),
      DownloadFailure.sourceDeleted,
    );
  });
}
