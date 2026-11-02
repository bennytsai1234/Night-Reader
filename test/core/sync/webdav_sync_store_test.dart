import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/core/sync/webdav_sync_store.dart';

/// 記在記憶體裡的 WebDAV 伺服器：檢查帳密、資料夾要先建、PUT 照 If-Match
/// 與 If-None-Match 比對 ETag。
class _FakeWebDav implements HttpClientAdapter {
  final Set<String> folders = {'/dav/'};
  final Map<String, (Uint8List, int)> files = {};
  final List<String> log = [];
  String auth = 'Basic ${base64.encode(utf8.encode('me:pw'))}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    log.add('${options.method} $path');
    if (options.headers['Authorization'] != auth) return _status(401);
    final parent = path.substring(
      0,
      path.lastIndexOf('/', path.length - 2) + 1,
    );
    switch (options.method) {
      case 'PROPFIND':
        return _status(folders.contains(path) ? 207 : 404);
      case 'MKCOL':
        if (folders.contains(path)) return _status(405);
        if (!folders.contains(parent)) return _status(409);
        folders.add(path);
        return _status(201);
      case 'GET' || 'HEAD':
        final file = files[path];
        if (file == null) return _status(404);
        return ResponseBody.fromBytes(
          options.method == 'HEAD' ? Uint8List(0) : file.$1,
          200,
          headers: {
            'etag': ['"${file.$2}"'],
          },
        );
      case 'PUT':
        final dir = path.substring(0, path.lastIndexOf('/') + 1);
        if (!folders.contains(dir)) return _status(409);
        final current = files[path];
        final ifMatch = options.headers['If-Match'];
        if (ifMatch != null && ifMatch != '"${current?.$2}"') {
          return _status(412);
        }
        if (options.headers['If-None-Match'] == '*' && current != null) {
          return _status(412);
        }
        final body = <int>[];
        await for (final chunk in requestStream!) {
          body.addAll(chunk);
        }
        files[path] = (Uint8List.fromList(body), (current?.$2 ?? 0) + 1);
        return _status(current == null ? 201 : 204);
    }
    return _status(405);
  }

  ResponseBody _status(int code) => ResponseBody.fromBytes(Uint8List(0), code);

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeWebDav server;

  WebDavSyncStore store({String password = 'pw'}) => WebDavSyncStore(
    url: 'https://dav.example.com/dav',
    user: 'me',
    password: password,
    dio: Dio()..httpClientAdapter = server,
  );

  setUp(() => server = _FakeWebDav());

  test(
    'check creates the folder; files round-trip with their version',
    () async {
      await store().check();
      expect(server.folders, contains('/dav/NightReader/'));

      expect(await store().read('progress.json'), isNull);
      await store().write('progress.json', '{"中文":1}', ifAbsent: true);
      final file = await store().read('progress.json');
      expect(file!.content, '{"中文":1}');
      expect(file.version, '"1"');
    },
  );

  test('the version can be asked without downloading the file', () async {
    expect(await store().version('p.json'), isNull);
    await store().write('p.json', 'one');
    server.log.clear();
    expect(
      await store().version('p.json'),
      (await store().read('p.json'))!.version,
    );
    expect(server.log.first, 'HEAD /dav/NightReader/p.json');
  });

  test('a write over a newer version is a conflict', () async {
    await store().write('p.json', 'one');
    final first = await store().read('p.json');
    await store().write('p.json', 'two', ifVersion: first!.version);
    await expectLater(
      store().write('p.json', 'three', ifVersion: first.version),
      throwsA(isA<SyncConflict>()),
    );
    await expectLater(
      store().write('p.json', 'four', ifAbsent: true),
      throwsA(isA<SyncConflict>()),
    );
    expect((await store().read('p.json'))!.content, 'two');
  });

  test('the folder is created on the first write', () async {
    await store().write('p.json', 'x');
    expect(server.log, [
      'PUT /dav/NightReader/p.json',
      'MKCOL /dav/NightReader/',
      'PUT /dav/NightReader/p.json',
    ]);
  });

  test('wrong password and missing address are reported plainly', () async {
    await expectLater(
      store(password: 'bad').check(),
      throwsA(
        isA<SyncStoreException>().having(
          (e) => e.message,
          'message',
          '帳號或密碼不對',
        ),
      ),
    );
    server.folders.clear();
    await expectLater(
      store().check(),
      throwsA(
        isA<SyncStoreException>().having(
          (e) => e.message,
          'message',
          '這個網址找不到 WebDAV',
        ),
      ),
    );
  });
}
