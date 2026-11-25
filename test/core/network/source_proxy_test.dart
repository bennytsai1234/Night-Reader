import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/network/source_proxy.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 書源標頭裡的 `proxy`，同 Legado `AnalyzeUrl`（拿出來、不當標頭送）與
/// `HttpHelper.getProxyClient`（照代理連）。代理都是本機假的。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  setUpAll(() => NetworkService().init(ephemeral: true));

  BookSource source(String proxy) => BookSource(
    bookSourceUrl: 'http://site.test',
    bookSourceName: '代理',
    header: jsonEncode({'proxy': proxy, 'Referer': 'http://site.test/'}),
  );

  group('parse like Legado', () {
    test('http with user and password', () {
      final proxy = SourceProxy.parse('http://10.0.0.1:8080@user@pass')!;
      expect(
        [proxy.type, proxy.host, proxy.port, proxy.username, proxy.password],
        ['http', '10.0.0.1', 8080, 'user', 'pass'],
      );
    });

    test('socks without credentials', () {
      final proxy = SourceProxy.parse('socks5://127.0.0.1:1080')!;
      expect(
        [proxy.type, proxy.host, proxy.port],
        ['socks5', '127.0.0.1', 1080],
      );
      expect(proxy.username, isNull);
    });

    test('an unknown form fails the request', () {
      expect(() => SourceProxy.parse('ftp://a:21'), throwsFormatException);
    });
  });

  test('the proxy header is taken out of the request headers', () {
    final url = AnalyzeUrl(
      'http://site.test/a',
      source: source('http://127.0.0.1:1@u@p'),
    );
    expect(url.proxy, 'http://127.0.0.1:1@u@p');
    expect(url.headerMap.containsKey('proxy'), isFalse);
    expect(url.headerMap['Referer'], 'http://site.test/');
  });

  test('an http proxy gets the request and the credentials', () async {
    final proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxyServer.close(force: true));
    String? requested;
    String? authorization;
    proxyServer.listen((request) async {
      requested = request.uri.toString();
      authorization = request.headers.value('proxy-authorization');
      request.response.write('經過 HTTP 代理');
      await request.response.close();
    });

    final response = await AnalyzeUrl(
      'http://site.test/book/1',
      source: source('http://127.0.0.1:${proxyServer.port}@user@pass'),
    ).getStrResponse();

    expect(response.body, '經過 HTTP 代理');
    expect(requested, 'http://site.test/book/1');
    expect(authorization, 'Basic ${base64Encode(utf8.encode('user:pass'))}');
  });

  for (final version in [5, 4]) {
    test('a socks$version proxy tunnels to the site by name', () async {
      final socks = await _FakeSocks.start(version);
      addTearDown(socks.close);

      final response = await AnalyzeUrl(
        'http://site.test/book/1',
        source: source('socks$version://127.0.0.1:${socks.port}'),
      ).getStrResponse();

      expect(response.body, '經過 SOCKS 代理');
      expect(socks.target, 'site.test:80');
      expect(socks.requestLine, 'GET /book/1 HTTP/1.1');
    });
  }
}

/// 只收一條連線的 SOCKS 代理：握手後自己當網站回一頁。
final class _FakeSocks {
  _FakeSocks._(this._server, this._version) {
    _server.listen(_serve);
  }

  static Future<_FakeSocks> start(int version) async => _FakeSocks._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    version,
  );

  final ServerSocket _server;
  final int _version;
  String? target;
  String? requestLine;

  int get port => _server.port;

  Future<void> close() => _server.close();

  Future<void> _serve(Socket socket) async {
    final buffer = <int>[];
    final waiting = StreamController<void>.broadcast();
    socket.listen((data) {
      buffer.addAll(data);
      waiting.add(null);
    });
    Future<List<int>> take(int count) async {
      while (buffer.length < count) {
        await waiting.stream.first;
      }
      final taken = buffer.sublist(0, count);
      buffer.removeRange(0, count);
      return taken;
    }

    Future<List<int>> takeUntil(int byte) async {
      while (!buffer.contains(byte)) {
        await waiting.stream.first;
      }
      return take(buffer.indexOf(byte) + 1);
    }

    if (_version == 5) {
      await take(3); // 5, 1, 0
      socket.add([5, 0]);
      final head = await take(5); // 5, 1, 0, 3, 長度
      final host = String.fromCharCodes(await take(head[4]));
      final port = await take(2);
      target = '$host:${port[0] << 8 | port[1]}';
      socket.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    } else {
      final head = await take(8); // 4, 1, 埠, 0.0.0.1
      await takeUntil(0); // 使用者
      final host = await takeUntil(0);
      target =
          '${String.fromCharCodes(host.sublist(0, host.length - 1))}'
          ':${head[2] << 8 | head[3]}';
      socket.add([0, 0x5a, 0, 0, 0, 0, 0, 0]);
    }
    final line = await takeUntil(10);
    requestLine = utf8.decode(line).trim();
    while (true) {
      final header = await takeUntil(10);
      if (header.length <= 2) break;
    }
    final body = Uint8List.fromList(utf8.encode('經過 SOCKS 代理'));
    socket
      ..write(
        'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n'
        'Content-Length: ${body.length}\r\nConnection: close\r\n\r\n',
      )
      ..add(body);
    await socket.flush();
    await socket.close();
    await waiting.close();
  }
}
