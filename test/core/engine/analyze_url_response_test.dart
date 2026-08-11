import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

List<int> _utf16Le(String text) {
  return <int>[
    for (final codeUnit in text.codeUnits) ...<int>[
      codeUnit & 0xFF,
      codeUnit >> 8,
    ],
  ];
}

void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      switch (request.uri.path) {
        case '/utf16':
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/plain; charset=UTF-16LE',
          );
          request.response.add(_utf16Le('夜讀 UTF16'));
        case '/quoted-utf16':
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/plain; charset = "UTF-16LE"',
          );
          request.response.add(_utf16Le('引號字元集'));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('HTTP charset decodes UTF-16LE response bytes', () async {
    final response = await AnalyzeUrl('$baseUrl/utf16').getStrResponse();

    expect(response.body, '夜讀 UTF16');
  });

  test('HTTP charset accepts optional whitespace and quotes', () async {
    final response = await AnalyzeUrl('$baseUrl/quoted-utf16').getStrResponse();

    expect(response.body, '引號字元集');
  });
}
