import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/interceptors/lenient_cookie_manager.dart';
import 'package:night_reader/core/network/request_log.dart';

Response<dynamic> _response(String url, int status, Object? data) =>
    Response<dynamic>(
      requestOptions: RequestOptions(path: url),
      statusCode: status,
      data: data,
    );

void main() {
  test('網站寫了 Cookie、書源沒開 Cookie 罐時，回應那一行寫出沒存的 Cookie 名稱', () async {
    Response<dynamic> withCookie({required bool jar}) => Response<dynamic>(
      requestOptions: RequestOptions(
        path: 'http://m.site.example/shuku/1.html',
        extra: LenientCookieManager.sourceExtra(jar),
      ),
      statusCode: 200,
      data: 'ok',
      headers: Headers.fromMap({
        HttpHeaders.setCookieHeader: ['PHPSESSID=abc; path=/', 'v=1'],
      }),
    );
    final log = RequestLog(responsePreview: RequestLog.diagnosisPreview);
    await log.run(() async {
      recordResponse(withCookie(jar: false));
      recordResponse(withCookie(jar: true));
    });

    expect(log.lines, [
      '  ← http://m.site.example/shuku/1.html 200 '
          '（網站寫了 Cookie PHPSESSID、v，書源沒開 Cookie 罐，沒存），2 字：ok',
      '  ← http://m.site.example/shuku/1.html 200，2 字：ok',
    ]);
  });

  test('each response names its URL, since replies can come back out of '
      'order', () async {
    final log = RequestLog(responsePreview: RequestLog.diagnosisPreview);
    await log.run(() async {
      recordResponse(_response('https://site.example/fast', 200, 'FAST'));
      recordResponse(_response('https://site.example/slow', 200, 'SLOW'));
    });

    expect(log.lines, [
      '  ← https://site.example/fast 200，4 字：FAST',
      '  ← https://site.example/slow 200，4 字：SLOW',
    ]);
  });

  test(
    'the AI repair log writes the headers sent, cookies by name only',
    () async {
      final log = RequestLog(responsePreview: 6000, sentHeaders: true);
      await log.run(() async {
        recordRequestUrl(
          'GET',
          Uri.parse('https://m.site.example/s?q=1'),
          headers: {
            'User-Agent': 'Mobile',
            'cookie': 'search_pass=1; PHPSESSID=abc123',
            'Authorization': 'Bearer sk-secret',
          },
        );
      });
      final plain = RequestLog(responsePreview: 6000);
      await plain.run(() async {
        recordRequestUrl(
          'GET',
          Uri.parse('https://m.site.example/s'),
          headers: {'cookie': 'a=1'},
        );
      });

      expect(
        log.lines.single,
        'https://m.site.example/s?q=1 標頭：User-Agent: Mobile；'
        'Cookie（search_pass、PHPSESSID）；Authorization（有送，值不列）',
      );
      expect(
        plain.lines.single,
        'https://m.site.example/s',
        reason: '只有 AI 修復記',
      );
    },
  );

  test('a page that only redirects by script says where it goes, even after '
      'the script is digested away', () async {
    final log = RequestLog(responsePreview: 6000, digestPages: true);
    await log.run(() async {
      recordResponse(
        _response(
          'https://site.example/',
          200,
          '<html><head><script>location.href="https://new.example/"</script>'
              '</head><body></body></html>',
        ),
      );
    });

    expect(
      log.lines.single,
      startsWith(
        '  ← https://site.example/ 200，92 字，太短不精簡'
        '（這頁用程式轉到 https://new.example/）：<html><head><script>',
      ),
    );
  });

  test('a tiny page that is only a script shows its text instead of an empty '
      'digest', () async {
    final log = RequestLog(responsePreview: 6000, digestPages: true);
    await log.run(() async {
      recordResponse(
        _response(
          'https://site.example/search/',
          200,
          '<script>alert("搜索间隔: 30 秒");window.history.go(-1);</script>',
        ),
      );
    });

    expect(
      log.lines.single,
      '  ← https://site.example/search/ 200，59 字，太短不精簡'
      '（網站限流：「搜索间隔: 30 秒」）：'
      '<script>alert("搜索间隔: 30 秒");window.history.go(-1);</script>',
    );
  });

  test('a reply from a cache in front of the site says so', () async {
    final log = RequestLog(responsePreview: 6000, digestPages: true);
    await log.run(() async {
      recordResponse(
        Response<dynamic>(
          requestOptions: RequestOptions(path: 'https://site.example/search/'),
          statusCode: 200,
          data: '<p>搜索间隔</p>',
          headers: Headers.fromMap({
            'x-cache': ['HIT'],
            'age': ['120'],
          }),
        ),
      );
    });

    expect(
      log.lines.single,
      startsWith('  ← https://site.example/search/ 200 （快取 HIT，存了 120 秒）'),
    );
  });

  test('busy, empty and unreachable count as the site faltering', () async {
    final log = RequestLog(responsePreview: RequestLog.diagnosisPreview);
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
    final log = RequestLog(responsePreview: RequestLog.diagnosisPreview);
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

  test('a POST shows what it sent when responses are recorded too', () async {
    final checked = RequestLog(responsePreview: RequestLog.diagnosisPreview);
    final debugged = RequestLog();
    for (final log in [checked, debugged]) {
      await log.run(() async {
        recordRequestUrl(
          'POST',
          Uri.parse('https://site.example/search/'),
          body: 'searchkey=%E6%88%91&searchtype=all&submit=',
        );
        recordRequestUrl('GET', Uri.parse('https://site.example/'), body: '');
      });
    }

    expect(checked.lines, [
      'POST https://site.example/search/ 送出：'
          'searchkey=%E6%88%91&searchtype=all&submit=',
      'https://site.example/',
    ]);
    expect(debugged.lines.first, 'POST https://site.example/search/');
  });

  test('the full copy keeps the whole page as sent, the preview stays short '
      'and digested', () async {
    final page =
        '<html><head><script>go()</script></head>'
        '<body><p>${'正文' * 4000}</p></body></html>';
    final log = RequestLog(
      responsePreview: 100,
      digestPages: true,
      keepPages: true,
    );
    await log.run(() async {
      recordRequestUrl('GET', Uri.parse('https://site.example/c/1'));
      recordResponse(_response('https://site.example/c/1', 200, page));
    });

    expect(log.pages, hasLength(log.lines.length), reason: '一筆對一筆');
    expect(log.pages.first, (line: 'https://site.example/c/1', body: null));
    expect(log.pages.last.line, log.lines.last);
    expect(log.pages.last.body, page);
    expect(
      log.lines.last,
      matches(
        RegExp(
          '^  ← https://site.example/c/1 200，${page.length} 字，精簡後 \\d+ 字：',
        ),
      ),
      reason: 'AI 看得到精簡後整頁有多長',
    );
    expect(log.lines.last, isNot(contains('go()')));
    expect(log.lines.last.length, lessThan(200));
  });

  test('a GBK page reads as Chinese, not mojibake', () async {
    final log = RequestLog(responsePreview: RequestLog.diagnosisPreview);
    await log.run(() async {
      recordResponse(
        _response(
          'https://gbk.example',
          200,
          gbk.encode('<meta charset="gbk"><p>第一章 夜雨</p>'),
        ),
      );
    });

    expect(log.lines.single, contains('第一章 夜雨'));
  });

  test('the preview keeps as many characters as asked', () async {
    final page = 'x' * 5000;
    final short = RequestLog(responsePreview: RequestLog.diagnosisPreview);
    final long = RequestLog(responsePreview: 4000);
    for (final log in [short, long]) {
      await log.run(() async {
        recordResponse(_response('https://site.example', 200, page));
      });
    }

    expect(short.lines.single, endsWith('${'x' * 160}…'));
    expect(long.lines.single, endsWith('${'x' * 4000}…'));
    expect(long.lines.single, isNot(contains('x' * 4001)));
  });
}
