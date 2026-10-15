import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/exception/user_error.dart';

void main() {
  DioException dio(DioExceptionType type, {int? status, Object? error}) {
    final options = RequestOptions(path: 'https://s.example/shelf.json');
    return DioException(
      requestOptions: options,
      type: type,
      error: error,
      response: status == null
          ? null
          : Response(requestOptions: options, statusCode: status),
    );
  }

  test('network failures read as plain Chinese', () {
    expect(userErrorReason(dio(DioExceptionType.connectionError)), '網路連線失敗');
    expect(userErrorReason(dio(DioExceptionType.receiveTimeout)), '連線逾時');
    expect(
      userErrorReason(dio(DioExceptionType.badResponse, status: 403)),
      '伺服器回應錯誤（403）',
    );
    expect(
      userErrorReason(
        dio(
          DioExceptionType.unknown,
          error: const SocketException('Failed host lookup'),
        ),
      ),
      '網路連線失敗',
    );
  });

  test('a file that is not a backup reads as a format problem', () {
    expect(
      userErrorReason(const FormatException('Unexpected character', '<', 0)),
      '資料格式不對',
    );
    expect(
      userErrorReason(const PathNotFoundException('/x', OSError('gone'))),
      '讀寫檔案失敗',
    );
  });

  test('messages the app already writes in Chinese are kept', () {
    expect(userErrorReason(NetworkException('書源回應異常')), '書源回應異常');
    expect(userErrorReason(Exception('找不到可匯入的資料')), '找不到可匯入的資料');
    expect(userErrorReason(StateError('找不到可閱讀書源')), '找不到可閱讀書源');
  });

  test('anything else does not leak an English stack of words', () {
    expect(userErrorReason(StateError('Bad state of controller')), '發生未預期的錯誤');
    expect(failureMessage('匯入', ArgumentError('x')), '匯入失敗：發生未預期的錯誤');
  });
}
