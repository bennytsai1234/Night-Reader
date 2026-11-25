import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:night_reader/core/network/str_response.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/exception/user_error.dart';
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

  BookSource source(Object? proxy) => BookSource(
    bookSourceUrl: 'http://site.test',
    bookSourceName: '代理',
    header: jsonEncode({'proxy': proxy, 'Referer': 'http://site.test/'}),
  );

  Future<StrResponse> fetch(String url, Object? proxy) =>
      AnalyzeUrl(url, source: source(proxy)).getStrResponse();

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

    test('an unknown form fails without echoing the setting', () {
      expect(
        () => SourceProxy.parse('ftp://a:21@user@secret'),
        throwsA(
          isA<SourceProxyException>().having(
            (e) => e.toString(),
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
    });
  });

  group('the proxy header', () {
    test('is taken out of the request headers', () {
      final url = AnalyzeUrl(
        'http://site.test/a',
        source: source('http://127.0.0.1:1@u@p'),
      );
      expect(url.proxy, 'http://127.0.0.1:1@u@p');
      expect(url.headerMap.containsKey('proxy'), isFalse);
      expect(url.headerMap['Referer'], 'http://site.test/');
    });

    test('null means no proxy, like Legado', () {
      final url = AnalyzeUrl('http://site.test/a', source: source(null));
      expect(url.proxy, isNull);
      expect(url.headerMap.containsKey('proxy'), isFalse);
    });

    test('is not among the headers the login browser sends', () {
      expect(
        source('http://127.0.0.1:1@u@p').getHeaderMapSync().keys,
        isNot(contains('proxy')),
      );
    });
  });

  group('http proxy', () {
    late HttpServer proxyServer;
    final requested = <String>[];
    final authorizations = <String?>[];

    setUp(() async {
      requested.clear();
      authorizations.clear();
      proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      proxyServer.listen((request) async {
        requested.add('${request.method} ${request.uri}');
        authorizations.add(request.headers.value('proxy-authorization'));
        if (request.method == 'CONNECT') {
          request.response.statusCode = HttpStatus.forbidden;
        } else if (request.uri.path == '/needs-auth') {
          request.response
            ..statusCode = HttpStatus.proxyAuthenticationRequired
            ..headers.set('proxy-authenticate', 'Basic realm="proxy"');
        } else {
          request.response.write('經過 HTTP 代理');
        }
        await request.response.close();
      });
    });
    tearDown(() => proxyServer.close(force: true));

    String basic(String user, String pass) =>
        'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

    test('gets the request and the credentials', () async {
      final port = proxyServer.port;
      final response = await fetch(
        'http://site.test/book/1',
        'http://127.0.0.1:$port@user@pa;ss',
      );
      expect(response.body, '經過 HTTP 代理');
      expect(requested, ['GET http://site.test/book/1']);
      expect(authorizations, [basic('user', 'pa;ss')]);
    });

    test('an empty password sends no credentials, like Legado', () async {
      final port = proxyServer.port;
      final response = await fetch(
        'http://site.test/book/1',
        'http://127.0.0.1:$port@user@',
      );
      expect(response.body, '經過 HTTP 代理');
      expect(authorizations, [null]);
    });

    // 帳密不對或代理要驗證：代理回 407，說是代理的問題，網址選項的 retry
    // 也不重送。
    test(
      'a 407 from the proxy says it is the proxy and is not resent',
      () async {
        final port = proxyServer.port;
        await expectLater(
          fetch(
            'http://site.test/needs-auth,{"retry":2}',
            'http://127.0.0.1:$port',
          ),
          throwsA(
            predicate(
              (Object e) => userErrorReason(e).contains('代理要求驗證'),
              '說是代理要驗證',
            ),
          ),
        );
        expect(requested, ['GET http://site.test/needs-auth']);
      },
    );

    test('https opens a tunnel with the credentials; a refusal is not '
        'retried and says it is the proxy', () async {
      final port = proxyServer.port;
      await expectLater(
        fetch('https://site.test/book/1', 'http://127.0.0.1:$port@user@pass'),
        throwsA(
          predicate(
            (Object e) => userErrorReason(e).contains('HTTP 代理拒絕'),
            '說是代理拒絕',
          ),
        ),
      );
      expect(requested, ['CONNECT site.test:443']);
      expect(authorizations, [basic('user', 'pass')]);
    });
  });

  group('socks proxy', () {
    test('socks5 tunnels to the site by name', () async {
      final socks = await _FakeSocks.start(version: 5);
      addTearDown(socks.close);
      final response = await fetch(
        'http://site.test/book/1',
        'socks5://127.0.0.1:${socks.port}',
      );
      expect(response.body, '經過 SOCKS 代理');
      expect(socks.targets, ['name site.test:80']);
      expect(socks.requestLines, ['GET /book/1 HTTP/1.1']);
    });

    test('socks5 sends IPv4 and IPv6 addresses as addresses', () async {
      final socks = await _FakeSocks.start(version: 5);
      addTearDown(socks.close);
      await fetch('http://10.1.2.3/a', 'socks5://127.0.0.1:${socks.port}');
      await fetch('http://[::1]:81/a', 'socks5://127.0.0.1:${socks.port}');
      expect(socks.targets, ['ipv4 10.1.2.3:80', 'ipv6 0:0:0:0:0:0:0:1:81']);
    });

    test('socks4 sends IPv4 as an address and names as socks4a', () async {
      final socks = await _FakeSocks.start(version: 4);
      addTearDown(socks.close);
      final port = socks.port;
      await fetch('http://10.1.2.3/a', 'socks4://127.0.0.1:$port');
      await fetch('http://site.test/a', 'socks4://127.0.0.1:$port');
      expect(socks.targets, ['ipv4 10.1.2.3:80', 'name site.test:80']);
    });

    test('socks4 cannot reach IPv6; a long domain cannot go through socks5; '
        'neither is retried', () async {
      final socks = await _FakeSocks.start(version: 4);
      addTearDown(socks.close);
      await expectLater(
        fetch('http://[::1]/a', 'socks4://127.0.0.1:${socks.port}'),
        throwsA(
          predicate((Object e) => userErrorReason(e).contains('IPv6'), 'IPv6'),
        ),
      );
      expect(socks.connections, 1);

      final socks5 = await _FakeSocks.start(version: 5);
      addTearDown(socks5.close);
      final longHost = '${'a.' * 130}test';
      await expectLater(
        fetch('http://$longHost/a', 'socks5://127.0.0.1:${socks5.port}'),
        throwsA(
          predicate((Object e) => userErrorReason(e).contains('網域太長'), '太長'),
        ),
      );
      expect(socks5.connections, 1);
    });

    test('a reply that is not socks is refused, not retried', () async {
      final socks = await _FakeSocks.start(version: 5, badVersion: true);
      addTearDown(socks.close);
      await expectLater(
        fetch('http://site.test/a', 'socks5://127.0.0.1:${socks.port}'),
        throwsA(
          predicate((Object e) => userErrorReason(e).contains('SOCKS5'), '代理'),
        ),
      );
      expect(socks.connections, 1);
    });
  });

  // https 網站經 HTTP 代理：通道開好後 TLS 完整握手走通；通道開好之後才
  // 逾時或放棄，代理那頭的連線也關乾淨。
  group('https through an http proxy tunnel', () {
    late _FakeTunnel tunnel;
    setUp(() async => tunnel = await _FakeTunnel.start());
    tearDown(() => tunnel.close());

    Future<HttpServer> site() async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/tls/self_signed_cert.pem')
        ..usePrivateKey('test/fixtures/tls/self_signed_key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      return server;
    }

    test('the TLS handshake completes and the page comes back', () async {
      final server = await site();
      server.listen((request) async {
        request.response.write('經過通道的 https');
        await request.response.close();
      });
      final response = await fetch(
        'https://127.0.0.1:${server.port}/book/1',
        'http://127.0.0.1:${tunnel.port}@user@pass',
      );
      expect(response.body, '經過通道的 https');
      expect(tunnel.connects, ['127.0.0.1:${server.port}']);
      expect(tunnel.authorizations, [
        'Basic ${base64Encode(utf8.encode('user:pass'))}',
      ]);
    });

    test(
      'a site that stops answering after the tunnel leaves nothing open',
      () async {
        final server = await site();
        server.listen((_) {}); // 收了請求不回。
        final client = SourceProxy.parse('http://127.0.0.1:${tunnel.port}')!
            .httpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('https://127.0.0.1:${server.port}/a'),
          );
          await request.close().timeout(const Duration(milliseconds: 500));
        } on TimeoutException {
          // 預期的。
        } finally {
          client.close(force: true);
        }
        for (var i = 0; i < 50 && tunnel.open > 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(tunnel.connects, hasLength(1));
        expect(tunnel.open, 0);
      },
    );
  });

  // 等太久或不要了的連線，代理那頭不留連線（每個逾時的請求都留一條的話，
  // 一次搜尋走慢代理就一直累積）。
  group('connections left at the proxy', () {
    Future<void> attempt(String proxy, String url) async {
      final client = SourceProxy.parse(proxy)!.httpClient()
        ..connectionTimeout = const Duration(milliseconds: 300);
      try {
        final request = await client.getUrl(Uri.parse(url));
        await (await request.close()).drain<void>();
      } catch (_) {
        // 逾時或失敗是預期的。
      } finally {
        client.close(force: true);
      }
    }

    Future<void> settle(_FakeSocks socks) async {
      for (var i = 0; i < 50 && socks.open > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    for (final (name, stall) in [
      ('a proxy that never answers the greeting', _Stall.greeting),
      ('a proxy that answers the greeting slowly', _Stall.slowGreeting),
      ('a site that never answers the TLS handshake', _Stall.tls),
    ]) {
      test(name, () async {
        final socks = await _FakeSocks.start(version: 5, stall: stall);
        addTearDown(socks.close);
        await attempt(
          'socks5://127.0.0.1:${socks.port}',
          '${stall == _Stall.tls ? 'https' : 'http'}://site.test/a',
        );
        await settle(socks);
        expect(socks.connections, greaterThan(0));
        expect(socks.open, 0);
      });
    }

    test('a request given up before the proxy answers', () async {
      final socks = await _FakeSocks.start(version: 5, stall: _Stall.greeting);
      addTearDown(socks.close);
      final client = SourceProxy.parse('socks5://127.0.0.1:${socks.port}')!
          .httpClient();
      final pending = client
          .getUrl(Uri.parse('http://site.test/a'))
          .then<Object?>((r) => r, onError: (Object e) => e);
      for (var i = 0; i < 50 && socks.connections == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      client.close(force: true);
      await pending;
      await settle(socks);
      expect(socks.connections, 1);
      expect(socks.open, 0);
    });
  });
}

enum _Stall { none, greeting, slowGreeting, tls }

/// 假的 HTTP 代理，只開通道（CONNECT）：記下連到哪裡、帶的帳密、代理那頭
/// 還開著幾條連線。
final class _FakeTunnel {
  _FakeTunnel._(this._server) {
    _server.listen(_serve);
  }

  static Future<_FakeTunnel> start() async =>
      _FakeTunnel._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final List<String> connects = [];
  final List<String?> authorizations = [];
  final List<Socket> _sockets = [];
  int open = 0;

  int get port => _server.port;

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }

  void _serve(Socket client) {
    open++;
    _sockets.add(client);
    final head = <int>[];
    Socket? target;
    var piping = false;
    var closed = false;
    void done() {
      if (closed) return;
      closed = true;
      open--;
      target?.destroy();
    }

    client.listen(
      (data) async {
        if (piping) {
          target?.add(data);
          return;
        }
        head.addAll(data);
        final text = latin1.decode(head);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        piping = true;
        final lines = text.substring(0, end).split('\r\n');
        final hostPort = lines.first.split(' ')[1];
        connects.add(hostPort);
        authorizations.add(
          lines
              .where((l) => l.toLowerCase().startsWith('proxy-authorization:'))
              .map((l) => l.substring(l.indexOf(':') + 1).trim())
              .firstOrNull,
        );
        final colon = hostPort.lastIndexOf(':');
        final upstream = target = await Socket.connect(
          hostPort.substring(0, colon),
          int.parse(hostPort.substring(colon + 1)),
        );
        _sockets.add(upstream);
        client.add(
          latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'),
        );
        final rest = head.sublist(end + 4);
        if (rest.isNotEmpty) upstream.add(rest);
        upstream.listen(
          client.add,
          onError: (Object _) => client.destroy(),
          onDone: () => client.destroy(),
        );
      },
      onError: (Object _) => done(),
      onDone: done,
    );
  }
}

/// 假的 SOCKS 代理：握手後自己當網站回一頁；記下連進來幾條、還開著幾條。
final class _FakeSocks {
  _FakeSocks._(this._server, this._version, this._stall, this._badVersion) {
    _server.listen(_serve);
  }

  static Future<_FakeSocks> start({
    required int version,
    _Stall stall = _Stall.none,
    bool badVersion = false,
  }) async => _FakeSocks._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    version,
    stall,
    badVersion,
  );

  final ServerSocket _server;
  final int _version;
  final _Stall _stall;
  final bool _badVersion;
  final List<String> targets = [];
  final List<String> requestLines = [];
  int connections = 0;
  int open = 0;
  final List<Socket> _sockets = [];

  int get port => _server.port;

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }

  Future<void> _serve(Socket socket) async {
    connections++;
    open++;
    _sockets.add(socket);
    final buffer = <int>[];
    final waiting = StreamController<void>.broadcast();
    var closed = false;
    socket.listen(
      (data) {
        buffer.addAll(data);
        waiting.add(null);
      },
      onError: (Object _) {},
      onDone: () {
        if (!closed) open--;
        closed = true;
        waiting.add(null);
      },
    );
    Future<List<int>> take(int count) async {
      while (buffer.length < count) {
        if (closed) throw StateError('closed');
        await waiting.stream.first;
      }
      final taken = buffer.sublist(0, count);
      buffer.removeRange(0, count);
      return taken;
    }

    Future<List<int>> takeUntil(int byte) async {
      while (!buffer.contains(byte)) {
        if (closed) throw StateError('closed');
        await waiting.stream.first;
      }
      return take(buffer.indexOf(byte) + 1);
    }

    String address(List<int> bytes) => bytes.length == 4
        ? bytes.join('.')
        : [
            for (var i = 0; i < 16; i += 2)
              (bytes[i] << 8 | bytes[i + 1]).toRadixString(16),
          ].join(':');

    try {
      if (_version == 5) {
        await take(3); // 5, 1, 0
        if (_stall == _Stall.greeting) return;
        if (_stall == _Stall.slowGreeting) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        if (closed) return;
        socket.add([_badVersion ? 4 : 5, 0]);
        if (_badVersion) return;
        final head = await take(4); // 5, 1, 0, 類型
        final String host;
        switch (head[3]) {
          case 1:
            host = 'ipv4 ${address(await take(4))}';
          case 4:
            host = 'ipv6 ${address(await take(16))}';
          default:
            final length = (await take(1))[0];
            host = 'name ${String.fromCharCodes(await take(length))}';
        }
        final p = await take(2);
        targets.add('$host:${p[0] << 8 | p[1]}');
        socket.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      } else {
        final head = await take(8); // 4, 1, 埠, 位址
        await takeUntil(0); // 使用者
        final port = head[2] << 8 | head[3];
        if (head[4] == 0 && head[5] == 0 && head[6] == 0 && head[7] != 0) {
          final name = await takeUntil(0);
          targets.add(
            'name ${String.fromCharCodes(name.sublist(0, name.length - 1))}'
            ':$port',
          );
        } else {
          targets.add('ipv4 ${address(head.sublist(4, 8))}:$port');
        }
        socket.add([0, 0x5a, 0, 0, 0, 0, 0, 0]);
      }
      // 網站：https 的不回 TLS 握手；http 的回一頁。
      if (_stall == _Stall.tls) return;
      final line = await takeUntil(10);
      requestLines.add(utf8.decode(line).trim());
      while ((await takeUntil(10)).length > 2) {}
      final body = utf8.encode('經過 SOCKS 代理');
      socket
        ..write(
          'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n'
          'Content-Length: ${body.length}\r\nConnection: close\r\n\r\n',
        )
        ..add(body);
      await socket.flush();
      await socket.close();
    } catch (_) {
      // 用戶端先關了。
    }
  }
}
