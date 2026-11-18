import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/features/search/ai_find/app_ai_find_library.dart';
import 'package:night_reader/features/search/models/search_scope.dart';

void main() {
  test('chapter text for the AI keeps the words, marks pictures and drops '
      'tags and blank lines', () {
    expect(
      aiFindPlainText('　　第一段<b>粗體</b>\n\n<img src="a.jpg" alt="x">\n  第二段  \n'),
      '第一段粗體\n（插圖）\n第二段',
    );
  });

  // 笔趣阁 biquge345 的簡介原文寫著反斜線加 n；只有這個的簡介不算有簡介。
  test('a literal backslash-n from the site is a line break for the AI', () {
    expect(aiFindPlainText(r'第一行\n第二行'), '第一行\n第二行');
    expect(aiFindPlainText(r'\n'), isEmpty);
  });

  test('network failures say what the site did', () {
    final options = RequestOptions();
    expect(
      aiFindNetworkFailure(
        DioException.badResponse(
          statusCode: 503,
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 503),
        ),
      ),
      '網站回應 503',
    );
    expect(
      aiFindNetworkFailure(
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 5),
          requestOptions: options,
        ),
      ),
      '連線逾時',
    );
  });

  test('a work name looks up its Wikipedia entry, follows a search when the '
      'name is not a title, and reads the title in each region', () async {
    final asked = <String>[];
    final dio = Dio()..httpClientAdapter = _Wiki(asked);
    final library = AppAiFindLibrary(scope: SearchScope(), wikipedia: dio);

    final names = await library.workNames('咒回', CancelToken());
    expect(names!.title, '咒術迴戰');
    expect(names.names, {'台灣': '咒術迴戰', '中國大陸': '咒术回战', '香港': '咒術迴戰'});
    expect(names.intro, startsWith('《咒術迴戰》'));
    expect(names.aliases, ['咒术回战', '呪術廻戦']);
    expect(names.others, isEmpty, reason: '搜到的就是查到的那個條目');
    expect(
      asked,
      contains(contains('summary/%E5%92%92%E5%9B%9E')),
      reason: '照名稱拿過',
    );
    expect(asked, contains(contains('srsearch=')), reason: '沒有條目再搜尋');

    expect(await library.workNames('完全沒有', CancelToken()), isNull);
  });
}

/// 假的中文維基百科：只有「咒術迴戰」一個條目，搜「咒回」會搜到它。
class _Wiki implements HttpClientAdapter {
  _Wiki(this.asked);
  final List<String> asked;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri.toString();
    asked.add(uri);
    ResponseBody json(Object body, [int status = 200]) =>
        ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    if (uri.contains('prop=redirects')) {
      return json({
        'query': {
          'pages': {
            '1': {
              'title': '咒術迴戰',
              'redirects': [
                {'title': '咒术回战'},
                {'title': '呪術廻戦'},
              ],
            },
          },
        },
      });
    }
    if (uri.contains('srsearch=')) {
      return json({
        'query': {
          'search': uri.contains(Uri.encodeQueryComponent('咒回'))
              ? [
                  {'title': '咒術迴戰'},
                ]
              : [],
        },
      });
    }
    if (uri.contains(Uri.encodeComponent('咒術迴戰'))) {
      final variant = options.headers['Accept-Language'];
      return json({
        'title': '咒術迴戰',
        'displaytitle': variant == 'zh-cn'
            ? '<span class="mw-page-title-main">咒术回战</span>'
            : '<span class="mw-page-title-main">咒術迴戰</span>',
        'extract': '《咒術迴戰》是芥見下下創作的漫畫。',
      });
    }
    return json({'title': 'Not found.'}, 404);
  }

  @override
  void close({bool force = false}) {}
}
