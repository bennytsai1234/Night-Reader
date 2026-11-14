import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/features/search/ai_find/app_ai_find_library.dart';

void main() {
  test('chapter text for the AI keeps the words, marks pictures and drops '
      'tags and blank lines', () {
    expect(
      aiFindPlainText('　　第一段<b>粗體</b>\n\n<img src="a.jpg" alt="x">\n  第二段  \n'),
      '第一段粗體\n（插圖）\n第二段',
    );
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
}
