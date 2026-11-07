import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/request_log.dart';

Response<dynamic> _response(String url, int status, Object? data) =>
    Response<dynamic>(
      requestOptions: RequestOptions(path: url),
      statusCode: status,
      data: data,
    );

void main() {
  test('each response names its URL, since replies can come back out of '
      'order', () async {
    final log = RequestLog(withResponses: true);
    await log.run(() async {
      recordResponse(_response('https://site.example/fast', 200, 'FAST'));
      recordResponse(_response('https://site.example/slow', 200, 'SLOW'));
    });

    expect(log.lines, [
      '  ← https://site.example/fast 200，4 字：FAST',
      '  ← https://site.example/slow 200，4 字：SLOW',
    ]);
  });

  test('busy, empty and unreachable count as the site faltering', () async {
    final log = RequestLog(withResponses: true);
    await log.run(() async {
      recordResponse(_response('https://a.example', 200, '<p>正常</p>'));
      recordResponse(_response('https://b.example', 503, 'busy'));
      recordResponse(_response('https://c.example', 200, '  '));
      recordResponse(
        null,
        error: DioException(
          requestOptions: RequestOptions(path: 'https://d.example'),
          type: DioExceptionType.unknown,
          error: const SocketException('reset'),
        ),
      );
      // 網站擋下夜讀（Cloudflare）也包成 unknown，但不是網路斷掉。
      recordResponse(
        null,
        error: DioException(
          requestOptions: RequestOptions(path: 'https://e.example'),
          type: DioExceptionType.unknown,
          error: StateError('blocked'),
        ),
      );
    });

    expect(log.transientResponses, 3);
    expect(log.lines[3], '  ← https://d.example 沒有回應（unknown）');
  });

  test('a rendered page says it has no status code', () async {
    final log = RequestLog(withResponses: true);
    await log.run(() async {
      recordRenderedPage('https://site.example/page', '');
    });

    expect(log.lines.single, contains('網頁渲染（沒有狀態碼）'));
    expect(log.transientResponses, 1);
  });

  test('source debugging records URLs only', () async {
    final log = RequestLog();
    await log.run(() async {
      recordRequestUrl('GET', Uri.parse('https://site.example/a#x'));
      recordResponse(_response('https://site.example/a', 503, 'busy'));
      recordRenderedPage('https://site.example/a', '');
    });

    expect(log.lines, ['https://site.example/a']);
    expect(log.transientResponses, 0);
  });
}
