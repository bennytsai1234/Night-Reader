import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;
  late Future<void> Function(HttpRequest request) requestHandler;

  setUpAll(() async {
    await NetworkService().init();
    requestHandler = (_) async {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      await requestHandler(request);
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('AnalyzeUrl follows POST 302 redirect as GET', () async {
    final requests = <String>[];
    String? postBody;
    String? resultMethod;
    requestHandler = (request) async {
      requests.add('${request.method} ${request.uri}');
      if (request.uri.path == '/search') {
        postBody = await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/result?q=${Uri.encodeQueryComponent('我的')}',
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/result') {
        resultMethod = request.method;
        request.response.write('found=${request.uri.queryParameters['q']}');
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };

    final analyzeUrl = AnalyzeUrl(
      '$baseUrl/search, {"method":"POST", "body":"q={{key}}"}',
      key: '我的',
    );
    final response = await analyzeUrl.getStrResponse();

    expect(response.body, 'found=我的');
    expect(response.url, '$baseUrl/result?q=%E6%88%91%E7%9A%84');
    expect(response.isRedirect, isTrue);
    expect(postBody, 'q=%E6%88%91%E7%9A%84');
    expect(resultMethod, 'GET');
    expect(requests, <String>[
      'POST /search',
      'GET /result?q=%E6%88%91%E7%9A%84',
    ]);
  });

  test(
    'HttpClient follows POST 302 redirect and exposes redirect chain',
    () async {
      final requests = <String>[];
      String? postBody;
      String? resultMethod;
      requestHandler = (request) async {
        requests.add('${request.method} ${request.uri}');
        if (request.uri.path == '/submit') {
          postBody = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/done?name=redirect',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/done') {
          resultMethod = request.method;
          request.response.write('done=${request.uri.queryParameters['name']}');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final response = await HttpClient().client.post<String>(
        '$baseUrl/submit',
        data: 'name=redirect',
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            Headers.contentTypeHeader:
                'application/x-www-form-urlencoded; charset=utf-8',
          },
        ),
      );

      expect(response.data, 'done=redirect');
      expect(response.realUri.toString(), '$baseUrl/done?name=redirect');
      expect(postBody, 'name=redirect');
      expect(resultMethod, 'GET');
      expect(response.extra['_manualRedirectChain'], <String>[
        '$baseUrl/done?name=redirect',
      ]);
      expect(requests, <String>['POST /submit', 'GET /done?name=redirect']);
    },
  );
}
