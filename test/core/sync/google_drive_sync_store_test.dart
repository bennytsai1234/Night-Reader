import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/google_drive_auth.dart';
import 'package:night_reader/core/sync/google_drive_sync_store.dart';
import 'package:night_reader/core/sync/sync_store.dart';

/// 換 token 時遞增；[stale] 的 token 雲端硬碟會拒絕。
class _FakeAuth implements GoogleDriveAuth {
  int issued = 0;
  final Set<String> forgotten = {};

  /// 每次取 token 指定的帳號。
  final Set<String> accounts = {};

  @override
  Future<String> token(String account) async {
    accounts.add(account);
    return 'token-$issued';
  }

  @override
  Future<void> forget(String token) async {
    forgotten.add(token);
    issued++;
  }

  @override
  Future<String> signIn() async => 'me@example.com';

  @override
  Future<void> signOut() async {}
}

/// 記在記憶體裡的雲端硬碟 App 資料夾：列出、下載、更新內容、多段上傳新建。
class _FakeDrive implements HttpClientAdapter {
  final Map<String, ({String name, String content, int version})> files = {};
  final List<String> log = [];
  Set<String> rejected = {};

  /// 下載這些檔名的檔案時回 403（只有這幾份被拒絕）。
  final Set<String> forbidden = {};

  /// 下載時回這個狀態碼與內容（模擬限流、伺服器故障）；null 時照常。
  (int, Map<String, Object?>)? failure;

  /// 列檔時先回一頁空的、附上下一頁（雲端硬碟會這樣回）。
  bool emptyFirstPage = false;
  var _nextId = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final auth = options.headers['Authorization'] as String;
    log.add('${options.method} ${options.uri.path}');
    if (rejected.contains(auth.substring(7))) return _json(401, {});
    final uri = options.uri;
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    if (uri.path == '/drive/v3/files' && options.method == 'GET') {
      expect(uri.queryParameters['spaces'], 'appDataFolder');
      if (emptyFirstPage && uri.queryParameters['pageToken'] == null) {
        return _json(200, {'files': <Object>[], 'nextPageToken': 'page-2'});
      }
      final q = uri.queryParameters['q'];
      final name = q == null
          ? null
          : RegExp(r"name = '([^']+)'").firstMatch(q)![1];
      return _json(200, {
        'files': [
          for (final entry in files.entries)
            if (name == null || entry.value.name == name)
              {'id': entry.key, 'version': '${entry.value.version}'},
        ],
      });
    }
    if (uri.path.startsWith('/drive/v3/files/') && options.method == 'GET') {
      final file = files[uri.pathSegments.last];
      if (file == null) return _json(404, {});
      if (forbidden.contains(file.name)) return _json(403, {});
      if (failure case (final status, final body)) return _json(status, body);
      return ResponseBody.fromBytes(utf8.encode(file.content), 200);
    }
    if (uri.path.startsWith('/upload/drive/v3/files/') &&
        options.method == 'PATCH') {
      final id = uri.pathSegments.last;
      final file = files[id]!;
      files[id] = (
        name: file.name,
        content: utf8.decode(body),
        version: file.version + 1,
      );
      return _json(200, {'id': id});
    }
    if (uri.path == '/upload/drive/v3/files' && options.method == 'POST') {
      final text = utf8.decode(body);
      final parts = text.split('--night_reader_sync_boundary');
      final metadata = jsonDecode(parts[1].split('\r\n\r\n')[1].trim()) as Map;
      expect(metadata['parents'], ['appDataFolder']);
      final content = parts[2].split('\r\n\r\n')[1];
      final id = 'f${_nextId++}';
      files[id] = (
        name: metadata['name'] as String,
        content: content.substring(0, content.length - 2),
        version: 1,
      );
      return _json(200, {'id': id});
    }
    return _json(405, {});
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeDrive drive;
  late _FakeAuth auth;

  GoogleDriveSyncStore store() => GoogleDriveSyncStore(
    auth: auth,
    account: 'me@example.com',
    dio: Dio()..httpClientAdapter = drive,
  );

  setUp(() {
    drive = _FakeDrive();
    auth = _FakeAuth();
  });

  test(
    'files round-trip in the hidden app folder with their version',
    () async {
      await store().check();
      expect(await store().read('progress.json'), isNull);
      expect(await store().version('progress.json'), isNull);

      await store().write('progress.json', '{"中文":1}', ifAbsent: true);
      final first = await store().read('progress.json');
      expect(first!.content, '{"中文":1}');
      expect(await store().version('progress.json'), first.version);

      await store().write(
        'progress.json',
        '{"中文":2}',
        ifVersion: first.version,
      );
      expect((await store().read('progress.json'))!.content, '{"中文":2}');
      expect(auth.accounts, {'me@example.com'});
    },
  );

  test('a file behind an empty first page is still found', () async {
    await store().write('p.json', 'one');
    drive.emptyFirstPage = true;
    expect((await store().read('p.json'))!.content, 'one');
    await store().write('p.json', 'two');
    expect(drive.files, hasLength(1));
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

  test('a token Google rejects is dropped and a fresh one is used', () async {
    drive.rejected = {'token-0'};
    await store().write('p.json', 'x');
    expect(auth.forgotten, {'token-0'});
    expect((await store().read('p.json'))!.content, 'x');
  });

  test('access refused after a fresh token says to sign in again', () async {
    drive.rejected = {'token-0', 'token-1'};
    await expectLater(
      store().check(),
      throwsA(
        isA<SyncStoreException>().having(
          (e) => e.message,
          'message',
          contains('重新登入'),
        ),
      ),
    );
  });

  test('one refused file fails alone; a rejected token fails the whole '
      'space', () async {
    await store().write('p.json', 'x');
    drive.forbidden.add('p.json');
    await expectLater(
      store().read('p.json'),
      throwsA(
        isA<SyncStoreException>().having(
          (e) => e.wholeSpace,
          'wholeSpace',
          false,
        ),
      ),
    );

    drive.rejected = {'token-0', 'token-1'};
    await expectLater(
      store().read('q.json'),
      throwsA(
        isA<SyncStoreException>().having(
          (e) => e.wholeSpace,
          'wholeSpace',
          true,
        ),
      ),
    );
  });

  test('rate limiting and a server failure stop the whole round', () async {
    await store().write('p.json', 'x');
    Matcher whole(bool value) => throwsA(
      isA<SyncStoreException>().having(
        (e) => e.wholeSpace,
        'wholeSpace',
        value,
      ),
    );

    drive.failure = (
      403,
      {
        'error': {
          'code': 403,
          'errors': [
            {'reason': 'userRateLimitExceeded'},
          ],
        },
      },
    );
    await expectLater(store().read('p.json'), whole(true));

    drive.failure = (503, {});
    await expectLater(store().read('p.json'), whole(true));

    drive.failure = (400, {});
    await expectLater(store().read('p.json'), whole(false));
  });
}
