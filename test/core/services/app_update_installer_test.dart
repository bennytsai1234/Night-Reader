import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_update_installer.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:path/path.dart' as p;

/// 回傳固定內容的 HTTP 轉接器，記下請求次數。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bytes);

  final List<int> bytes;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      200,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UpdateInfo _info({String tag = 'v0.4.0', int size = 4}) => UpdateInfo(
  versionName: tag.substring(1),
  tagName: tag,
  updateLog: '',
  downloadUrl: 'https://example.com/night-reader.apk',
  assetSize: size,
  releasePageUrl: '',
);

void main() {
  late Directory root;
  late Directory updates;
  late _FakeAdapter adapter;
  late AppUpdateInstaller installer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_update_installer_');
    updates = Directory(p.join(root.path, 'updates'));
    adapter = _FakeAdapter([1, 2, 3, 4]);
    installer = AppUpdateInstaller(
      dio: Dio()..httpClientAdapter = adapter,
      directoryLoader: () async => updates,
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('downloads the APK and reports progress', () async {
    final progress = <int>[];
    final apk = await installer.download(
      _info(),
      onProgress: (received, _) => progress.add(received),
    );

    expect(p.basename(apk.path), 'night-reader-v0.4.0.apk');
    expect(await apk.readAsBytes(), [1, 2, 3, 4]);
    expect(progress.last, 4);
    expect(updates.listSync().map((e) => p.basename(e.path)), [
      'night-reader-v0.4.0.apk',
    ]);
  });

  test('reuses a completed download of the same version', () async {
    await installer.download(_info());
    await installer.download(_info());

    expect(adapter.requests, 1);
  });

  test('a size mismatch fails and leaves no APK behind', () async {
    await expectLater(
      installer.download(_info(size: 99)),
      throwsA(isA<StateError>()),
    );

    expect(updates.listSync(), isEmpty);
  });

  test('a new version replaces the old APK', () async {
    await installer.download(_info(tag: 'v0.4.0'));
    await installer.download(_info(tag: 'v0.4.1'));

    expect(updates.listSync().map((e) => p.basename(e.path)), [
      'night-reader-v0.4.1.apk',
    ]);
  });

  test('clearDownloads removes downloaded APKs', () async {
    await installer.download(_info());
    await installer.clearDownloads();

    expect(await updates.exists(), isFalse);
  });
}
