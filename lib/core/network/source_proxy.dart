import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:night_reader/core/network/source_tls.dart';

/// 書源標頭裡的 `proxy`（代理），同 Legado `HttpHelper.getProxyClient`：
/// `http://主機:埠`、`socks4://主機:埠`、`socks5://主機:埠`，HTTP 代理可以在
/// 後面接 `@帳號@密碼`。
final class SourceProxy {
  const SourceProxy._(
    this.type,
    this.host,
    this.port, {
    this.username,
    this.password,
  });

  /// `http`、`socks4` 或 `socks5`。
  final String type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  static final RegExp _pattern = RegExp(
    r'(http|socks4|socks5)://(.*):(\d{2,5})(@.*@.*)?',
  );

  /// 照 Legado 的寫法讀代理；主機是空的時不走代理（null）。寫法認不出來時
  /// 丟出 [FormatException]，這個請求照 Legado 失敗。
  static SourceProxy? parse(String raw) {
    final match = _pattern.firstMatch(raw);
    if (match == null) throw FormatException('書源的代理寫法認不出來', raw);
    final host = match.group(2)!;
    if (host.isEmpty) return null;
    String? username;
    String? password;
    final auth = match.group(4);
    if (auth != null && auth.isNotEmpty) {
      final parts = auth.split('@');
      username = parts[1];
      password = parts[2];
    }
    return SourceProxy._(
      match.group(1)!,
      host,
      int.parse(match.group(3)!),
      username: username,
      password: password,
    );
  }

  /// 走這個代理的連線，其餘同 [sourceHttpClient]。同 Legado 只有 HTTP 代理
  /// 帶帳號密碼（OkHttp 的 `proxyAuthenticator` 只管 HTTP 代理）。
  HttpClient httpClient() {
    final client = sourceHttpClient();
    if (type == 'http') {
      final auth = username != null && username!.isNotEmpty
          ? '$username:$password@'
          : '';
      client.findProxy = (_) => 'PROXY $auth$host:$port';
    } else {
      client.connectionFactory = (uri, _, _) async =>
          ConnectionTask.fromSocket(_connectThroughSocks(uri), () {});
    }
    return client;
  }

  Future<Socket> _connectThroughSocks(Uri uri) async {
    final upstream = await Socket.connect(host, port);
    final reader = _SocketReader(upstream);
    try {
      final targetPort = uri.hasPort
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      if (type == 'socks4') {
        await _socks4Connect(upstream, reader, uri.host, targetPort);
      } else {
        await _socks5Connect(upstream, reader, uri.host, targetPort);
      }
    } catch (_) {
      upstream.destroy();
      rethrow;
    }
    final local = await reader.relay(upstream);
    if (uri.scheme != 'https') return local;
    return SecureSocket.secure(
      local,
      host: uri.host,
      onBadCertificate: (_) => true,
    );
  }

  /// SOCKS5（RFC 1928），不帶帳號密碼，網域交給代理查（同 OkHttp 把沒解析的
  /// 主機交給 SOCKS 代理）。
  static Future<void> _socks5Connect(
    Socket socket,
    _SocketReader reader,
    String host,
    int port,
  ) async {
    socket.add([5, 1, 0]);
    final greeting = await reader.read(2);
    if (greeting[0] != 5 || greeting[1] != 0) {
      throw const SocketException('SOCKS5 代理不接受不帶帳號密碼的連線');
    }
    final hostBytes = Uint8List.fromList(host.codeUnits);
    socket.add([
      5, 1, 0, 3, hostBytes.length, ...hostBytes, port >> 8, port & 0xff, //
    ]);
    final head = await reader.read(4);
    if (head[1] != 0) {
      throw SocketException('SOCKS5 代理連不上目標（代碼 ${head[1]}）');
    }
    final addressLength = switch (head[3]) {
      1 => 4,
      4 => 16,
      3 => (await reader.read(1))[0],
      _ => throw const SocketException('SOCKS5 代理回的位址看不懂'),
    };
    await reader.read(addressLength + 2);
  }

  /// SOCKS4a：網域交給代理查。
  static Future<void> _socks4Connect(
    Socket socket,
    _SocketReader reader,
    String host,
    int port,
  ) async {
    socket.add([
      4, 1, port >> 8, port & 0xff, 0, 0, 0, 1, 0, //
      ...host.codeUnits, 0,
    ]);
    final reply = await reader.read(8);
    if (reply[1] != 0x5a) {
      throw SocketException('SOCKS4 代理連不上目標（代碼 ${reply[1]}）');
    }
  }
}

/// 從 SOCKS 代理的連線讀握手的回覆。連線的資料只能聽一次，握手完 [relay]
/// 把之後的資料接到一條本機連線上交給 HttpClient（它要自己聽、自己加 TLS）。
final class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  late final StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Completer<void>? _waiting;
  Object? _error;
  bool _done = false;

  void _wake() {
    _waiting?.complete();
    _waiting = null;
  }

  Future<Uint8List> read(int count) async {
    while (_buffer.length < count) {
      if (_error case final error?) throw error;
      if (_done) throw const SocketException('代理在握手時關掉連線');
      await (_waiting ??= Completer<void>()).future;
    }
    final bytes = _buffer.takeBytes();
    if (bytes.length > count) _buffer.add(bytes.sublist(count));
    return Uint8List.sublistView(bytes, 0, count);
  }

  /// 開一條本機連線，兩頭互相轉送，交回 HttpClient 那一頭。
  Future<Socket> relay(Socket upstream) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final Socket local;
    final Socket inner;
    try {
      final accepted = server.first;
      local = await Socket.connect(server.address, server.port);
      inner = await accepted;
    } finally {
      await server.close();
    }
    if (_buffer.isNotEmpty) inner.add(_buffer.takeBytes());
    _subscription
      ..onData(inner.add)
      ..onError((Object _) => inner.destroy())
      ..onDone(() => unawaited(inner.close()));
    if (_done) unawaited(inner.close());
    inner.listen(
      upstream.add,
      onError: (Object _) => upstream.destroy(),
      onDone: () => unawaited(upstream.close()),
      cancelOnError: true,
    );
    return local;
  }
}

/// 書源的連線：請求帶著代理（[extraKey]）時走那個代理，同一個代理共用一份
/// 連線（同 Legado 的 `proxyClientCache`），沒有時同 [sourceHttpClientAdapter]。
final class SourceProxyAdapter implements HttpClientAdapter {
  SourceProxyAdapter() : _direct = sourceHttpClientAdapter();

  /// 請求選項 `extra` 裡放代理字串的鍵；轉址與 Cloudflare 重試照樣帶著。
  static const String extraKey = 'sourceProxy';

  final HttpClientAdapter _direct;
  final Map<String, HttpClientAdapter> _byProxy = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final raw = options.extra[extraKey];
    final adapter = raw is String && raw.trim().isNotEmpty
        ? _adapterFor(raw)
        : _direct;
    return adapter.fetch(options, requestStream, cancelFuture);
  }

  HttpClientAdapter _adapterFor(String raw) {
    final cached = _byProxy[raw];
    if (cached != null) return cached;
    final proxy = SourceProxy.parse(raw);
    final adapter = proxy == null
        ? _direct
        : IOHttpClientAdapter(createHttpClient: proxy.httpClient);
    return _byProxy[raw] = adapter;
  }

  @override
  void close({bool force = false}) {
    _direct.close(force: force);
    for (final adapter in _byProxy.values) {
      if (!identical(adapter, _direct)) adapter.close(force: force);
    }
    _byProxy.clear();
  }
}
