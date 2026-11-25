import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/source_tls.dart';

/// 書源的代理寫法不對、連不上或拒絕連線：讀者看得出是代理的問題，請求不
/// 重試（重試也一樣）。訊息不帶代理字串，裡面可能有帳號密碼。
class SourceProxyException extends AppException {
  SourceProxyException(super.message);
}

/// 書源標頭裡的 `proxy`（代理），同 Legado `HttpHelper.getProxyClient`：
/// `http://主機:埠`、`socks4://主機:埠`、`socks5://主機:埠`，後面可以接
/// `@帳號@密碼`（同 Legado 只給 HTTP 代理用，帳號、密碼都有才用）。
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

  bool get _hasCredentials =>
      (username?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  static final RegExp _pattern = RegExp(
    r'(http|socks4|socks5)://(.*):(\d{2,5})(@.*@.*)?',
  );

  /// 照 Legado 的寫法讀代理；主機是空的時不走代理（null）。寫法認不出來時
  /// 丟出 [SourceProxyException]，這個請求照 Legado 失敗。
  static SourceProxy? parse(String raw) {
    final match = _pattern.firstMatch(raw);
    if (match == null) throw SourceProxyException('書源的代理寫法認不出來');
    final host = match.group(2)!;
    if (host.isEmpty) return null;
    final auth = match.group(4)?.split('@') ?? const <String>[];
    return SourceProxy._(
      match.group(1)!,
      host,
      int.parse(match.group(3)!),
      username: auth.length > 1 ? auth[1] : null,
      password: auth.length > 2 ? auth[2] : null,
    );
  }

  /// 代理字串裡的秘密：整段、`@帳號@密碼` 那段與帳號、密碼（AI 修復送出
  /// 前遮掉）。認不出的寫法整段都算。
  static Iterable<String> secretsOf(String raw) sync* {
    yield raw;
    final at = raw.indexOf('@');
    if (at >= 0) yield raw.substring(at);
    final match = _pattern.firstMatch(raw);
    final auth = match?.group(4)?.split('@') ?? const <String>[];
    yield* auth.where((part) => part.isNotEmpty);
  }

  /// 走這個代理的連線，其餘同 [sourceHttpClient]：
  ///
  /// - HTTP 代理：http 網站由 HttpClient 經代理送（請求行寫完整網址），
  ///   https 網站自己向代理開通道（CONNECT）。帳密放在連線的代理帳密與
  ///   通道請求裡，不寫進代理設定字串（密碼有 `;` 會被切壞）。
  /// - SOCKS 代理：自己握手、連目標，不照系統的環境代理。
  HttpClient httpClient() {
    final client = sourceHttpClient();
    if (type == 'http') {
      client.findProxy = (uri) =>
          uri.scheme == 'https' ? 'DIRECT' : 'PROXY $host:$port';
      if (_hasCredentials) {
        client.addProxyCredentials(
          host,
          port,
          '',
          HttpClientBasicCredentials(username!, password!),
        );
      }
    } else {
      client.findProxy = (_) => 'DIRECT';
    }
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final connection = _ProxyConnection(
        this,
        uri,
        throughHttpProxy: proxyHost != null,
      );
      return ConnectionTask.fromSocket(connection.open(), connection.cancel);
    };
    return client;
  }
}

/// 經代理的一條連線。HttpClient 等太久或不要了會取消（[cancel]）：手上
/// 已經開的連線全部關掉，之後才連上的也立刻關；任何一步失敗也全部關掉，
/// 不留連線在代理那頭。
final class _ProxyConnection {
  _ProxyConnection(this.proxy, this.uri, {required this.throughHttpProxy});

  final SourceProxy proxy;
  final Uri uri;

  /// http 網站經 HTTP 代理：只連到代理，請求由 HttpClient 照代理的寫法送。
  final bool throughHttpProxy;

  final List<Socket> _sockets = [];
  ServerSocket? _server;
  _SocketReader? _reader;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _closeAll();
  }

  void _closeAll() {
    for (final socket in _sockets) {
      socket.destroy();
    }
    _sockets.clear();
    final server = _server;
    if (server != null) unawaited(server.close().catchError((_) => server));
    _reader?.fail(const SocketException('代理連線已關閉'));
  }

  T _keep<T extends Socket>(T socket) {
    if (_cancelled) {
      socket.destroy();
      throw const SocketException('代理連線已取消');
    }
    _sockets.add(socket);
    return socket;
  }

  void _checkCancelled() {
    if (_cancelled) throw const SocketException('代理連線已取消');
  }

  int get _targetPort =>
      uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

  Future<Socket> open() async {
    try {
      final Socket upstream;
      try {
        upstream = _keep(await Socket.connect(proxy.host, proxy.port));
      } on SocketException {
        if (_cancelled) rethrow;
        throw SourceProxyException('連不上書源設定的代理');
      }
      if (throughHttpProxy) return upstream;
      final reader = _reader = _SocketReader(upstream);
      switch (proxy.type) {
        case 'http':
          await _httpConnect(upstream, reader);
        case 'socks4':
          await _socks4Connect(upstream, reader);
        default:
          await _socks5Connect(upstream, reader);
      }
      _checkCancelled();
      final local = await _relay(upstream, reader);
      _checkCancelled();
      if (uri.scheme != 'https') return local;
      final secure = _keep(
        await SecureSocket.secure(
          local,
          host: uri.host,
          onBadCertificate: (_) => true,
        ),
      );
      _checkCancelled();
      return secure;
    } catch (_) {
      _closeAll();
      rethrow;
    }
  }

  /// HTTP 代理開通道（https 網站），帳號、密碼都有時帶上。
  Future<void> _httpConnect(Socket socket, _SocketReader reader) async {
    final target = '${_hostForRequest(uri.host)}:$_targetPort';
    final auth = proxy._hasCredentials
        ? 'Proxy-Authorization: Basic '
              '${base64Encode(utf8.encode('${proxy.username}:${proxy.password}'))}'
              '\r\n'
        : '';
    socket.add(
      utf8.encode('CONNECT $target HTTP/1.1\r\nHost: $target\r\n$auth\r\n'),
    );
    final head = await reader.readUntil(utf8.encode('\r\n\r\n'), limit: 16384);
    final status = latin1.decode(head).split('\r\n').first.split(' ');
    if (status.length < 2 || status[1] != '200') {
      throw SourceProxyException(
        'HTTP 代理拒絕連到網站（${status.length > 1 ? status[1] : '回應看不懂'}）',
      );
    }
  }

  /// SOCKS5（RFC 1928），不帶帳號密碼；IPv4、IPv6 照位址送，網域交給代理
  /// 查（同 OkHttp 把沒解析的主機交給 SOCKS 代理）。
  Future<void> _socks5Connect(Socket socket, _SocketReader reader) async {
    socket.add([5, 1, 0]);
    final greeting = await reader.read(2);
    if (greeting[0] != 5) throw SourceProxyException('SOCKS5 代理回應看不懂');
    if (greeting[1] != 0) {
      throw SourceProxyException('SOCKS5 代理要帳號密碼，書源沒給');
    }
    final address = InternetAddress.tryParse(_bareHost(uri.host));
    final List<int> target;
    if (address != null) {
      target = [
        address.type == InternetAddressType.IPv6 ? 4 : 1,
        ...address.rawAddress,
      ];
    } else {
      final hostBytes = utf8.encode(uri.host);
      if (hostBytes.length > 255) {
        throw SourceProxyException('網站的網域太長，SOCKS5 代理送不出去');
      }
      target = [3, hostBytes.length, ...hostBytes];
    }
    socket.add([5, 1, 0, ...target, _targetPort >> 8, _targetPort & 0xff]);
    final head = await reader.read(4);
    if (head[0] != 5) throw SourceProxyException('SOCKS5 代理回應看不懂');
    if (head[1] != 0) {
      throw SourceProxyException('SOCKS5 代理連不上網站（代碼 ${head[1]}）');
    }
    final addressLength = switch (head[3]) {
      1 => 4,
      4 => 16,
      3 => (await reader.read(1))[0],
      _ => throw SourceProxyException('SOCKS5 代理回應看不懂'),
    };
    await reader.read(addressLength + 2);
  }

  /// SOCKS4：IPv4 照位址送，網域用 SOCKS4a 交給代理查；IPv6 送不了。
  Future<void> _socks4Connect(Socket socket, _SocketReader reader) async {
    final address = InternetAddress.tryParse(_bareHost(uri.host));
    if (address?.type == InternetAddressType.IPv6) {
      throw SourceProxyException('SOCKS4 代理連不了 IPv6 網址');
    }
    final port = [_targetPort >> 8, _targetPort & 0xff];
    socket.add(
      address != null
          ? [4, 1, ...port, ...address.rawAddress, 0]
          : [4, 1, ...port, 0, 0, 0, 1, 0, ...utf8.encode(uri.host), 0],
    );
    final reply = await reader.read(8);
    if (reply[0] != 0) throw SourceProxyException('SOCKS4 代理回應看不懂');
    if (reply[1] != 0x5a) {
      throw SourceProxyException('SOCKS4 代理連不上網站（代碼 ${reply[1]}）');
    }
  }

  /// 開一條本機連線，兩頭互相轉送，交回 HttpClient 那一頭：代理那條連線的
  /// 資料只能聽一次，握手時聽過了，HttpClient 要自己聽、自己加 TLS。
  Future<Socket> _relay(Socket upstream, _SocketReader reader) async {
    final server = _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final accepted = server.first;
    final local = _keep(await Socket.connect(server.address, server.port));
    final inner = _keep(await accepted);
    await server.close();
    _server = null;
    reader.pipeTo(inner);
    var upstreamClosed = false;
    inner.listen(
      (data) {
        if (!upstreamClosed) upstream.add(data);
      },
      onError: (Object _) {
        upstreamClosed = true;
        upstream.destroy();
      },
      onDone: () {
        if (upstreamClosed) return;
        upstreamClosed = true;
        unawaited(upstream.close().catchError((_) => upstream));
      },
      cancelOnError: true,
    );
    return local;
  }

  static String _bareHost(String host) =>
      host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;

  static String _hostForRequest(String host) =>
      host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
}

/// 從代理的連線讀握手的回覆；握手完 [pipeTo] 把之後的資料轉給本機連線。
final class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onError: (Object error) => fail(error),
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
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  /// 連線被關掉或出錯：等著讀的立刻結束。
  void fail(Object error) {
    _error ??= error;
    _wake();
  }

  Future<void> _waitForMore() async {
    if (_error case final error?) throw error;
    if (_done) throw SourceProxyException('代理在握手時關掉連線');
    await (_waiting ??= Completer<void>()).future;
  }

  Future<Uint8List> read(int count) async {
    while (_buffer.length < count) {
      await _waitForMore();
    }
    return _take(count);
  }

  /// 讀到 [marker]（含）為止；超過 [limit] 還沒讀到算回應看不懂。
  Future<Uint8List> readUntil(List<int> marker, {required int limit}) async {
    while (true) {
      final bytes = _buffer.toBytes();
      final end = _indexOf(bytes, marker);
      if (end >= 0) return _take(end + marker.length);
      if (bytes.length > limit) {
        throw SourceProxyException('代理回應看不懂');
      }
      await _waitForMore();
    }
  }

  Uint8List _take(int count) {
    final bytes = _buffer.takeBytes();
    if (bytes.length > count) _buffer.add(bytes.sublist(count));
    return Uint8List.sublistView(bytes, 0, count);
  }

  static int _indexOf(Uint8List bytes, List<int> marker) {
    outer:
    for (var i = 0; i + marker.length <= bytes.length; i++) {
      for (var j = 0; j < marker.length; j++) {
        if (bytes[i + j] != marker[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// 之後代理送來的資料轉給 [inner]；一頭關了另一頭跟著關，關閉的錯誤吸收
  /// 掉，關了之後不再寫。
  void pipeTo(Socket inner) {
    var innerClosed = false;
    void closeInner() {
      if (innerClosed) return;
      innerClosed = true;
      unawaited(inner.close().catchError((_) => inner));
    }

    if (_buffer.isNotEmpty) inner.add(_buffer.takeBytes());
    _subscription
      ..onData((data) {
        if (!innerClosed) inner.add(data);
      })
      ..onError((Object _) {
        innerClosed = true;
        inner.destroy();
      })
      ..onDone(closeInner);
    if (_done) closeInner();
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
