import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/network/source_tls.dart';

/// 沒帶瀏覽器標識的書源請求送夜讀的預設（同 Legado `HttpHelper` 沒有 UA 時
/// 補上 `AppConfig.userAgent`）：網路封面與封面存檔直接用書源連線、不經攔截器，
/// 原本送的是 Dart 自己的「Dart/版本 (dart:io)」。
void main() {
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.write(request.headers.value('user-agent') ?? '');
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  test(
    'a cover request with no User-Agent sends the reader\'s default',
    () async {
      final client = IOClient(sourceHttpClient());
      final sent = (await client.get(Uri.parse('$baseUrl/cover.jpg'))).body;
      client.close();
      expect(sent, AppInterceptor.desktopUserAgent);
    },
  );

  test('a request that names its own User-Agent keeps it', () async {
    final client = IOClient(sourceHttpClient());
    final sent = (await client.get(
      Uri.parse('$baseUrl/cover.jpg'),
      headers: {'User-Agent': 'MyReader/1.0'},
    )).body;
    client.close();
    expect(sent, 'MyReader/1.0');
  });
}
