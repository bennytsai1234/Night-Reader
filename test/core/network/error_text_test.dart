import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/error_text.dart';

void main() {
  final request = RequestOptions(path: 'https://site.test/search');

  test('a wrapped cause stays on the first line', () {
    // 憑證不受信任時 dio 只包住 HandshakeException，message 是 null。
    final error = DioException(
      requestOptions: request,
      error: const HandshakeException('unable to get local issuer certificate'),
    );

    expect(
      errorText(error).split('\n').first,
      allOf(contains('[unknown]'), contains('local issuer certificate')),
    );
  });

  test('errors with their own message are written as they are', () {
    final error = DioException.badResponse(
      statusCode: 404,
      requestOptions: request,
      response: Response(requestOptions: request, statusCode: 404),
    );

    expect(errorText(error), '$error');
    expect(errorText(StateError('夜讀')), '${StateError('夜讀')}');
  });
}
