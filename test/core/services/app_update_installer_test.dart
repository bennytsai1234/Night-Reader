import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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

/// 回應先停住，[open] 之後才送出內容，模擬下載進行中。
class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this.bytes);

  final List<int> bytes;
  final _gate = Completer<void>();
  final _requestWaiters = <int, Completer<void>>{};
  int requests = 0;

  void open() => _gate.complete();

  /// 等到第 [count] 個請求送出。
  Future<void> untilRequests(int count) => count <= requests
      ? Future.value()
      : (_requestWaiters[count] ??= Completer<void>()).future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    _requestWaiters.remove(requests)?.complete();
    late final StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>(
      onListen: () => _gate.future.then((_) async {
        // 已被取消的請求不再送內容。
        if (!controller.hasListener) return;
        controller.add(Uint8List.fromList(bytes));
        await controller.close();
      }),
    );
    return ResponseBody(
      controller.stream,
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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('a download already in flight', () {
    late _GatedAdapter gated;

    setUp(() {
      gated = _GatedAdapter([1, 2, 3, 4]);
      installer = AppUpdateInstaller(
        dio: Dio()..httpClientAdapter = gated,
        directoryLoader: () async => updates,
      );
    });

    test('is joined instead of downloaded again', () async {
      final progress = <int>[];
      final first = installer.download(_info());
      // 另一個 installer（例如更新視窗自己建立的）接上同一份下載。
      final second = AppUpdateInstaller(
        dio: Dio()..httpClientAdapter = gated,
        directoryLoader: () async => updates,
      ).download(_info(), onProgress: (received, _) => progress.add(received));
      await gated.untilRequests(1);
      gated.open();

      final apks = await Future.wait([first, second]);
      expect(apks.map((apk) => apk.path).toSet(), hasLength(1));
      expect(await apks.first.readAsBytes(), [1, 2, 3, 4]);
      expect(gated.requests, 1);
      expect(progress.last, 4);
    });

    test('keeps running when one waiter cancels', () async {
      final cancelToken = CancelToken();
      final cancelled = installer.download(_info(), cancelToken: cancelToken);
      final kept = installer.download(_info());
      await gated.untilRequests(1);
      cancelToken.cancel();
      await expectLater(
        cancelled,
        throwsA(
          isA<DioException>().having(CancelToken.isCancel, 'isCancel', true),
        ),
      );
      gated.open();

      expect(await (await kept).readAsBytes(), [1, 2, 3, 4]);
      expect(gated.requests, 1);
    });

    test('stops when its only waiter cancels', () async {
      final cancelToken = CancelToken();
      final cancelled = installer.download(_info(), cancelToken: cancelToken);
      await gated.untilRequests(1);
      cancelToken.cancel();
      await expectLater(cancelled, throwsA(isA<DioException>()));

      // 取消後再按更新會重新下載，而不是接上已取消的那份。
      final retried = installer.download(_info());
      await gated.untilRequests(2);
      gated.open();

      expect(await (await retried).readAsBytes(), [1, 2, 3, 4]);
      expect(gated.requests, 2);
    });
  });

  group('isOnUnmeteredNetwork', () {
    const channel = MethodChannel('night_reader/app_installer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('follows the native metered flag', () async {
      var metered = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isActiveNetworkMetered');
        return metered;
      });

      expect(await installer.isOnUnmeteredNetwork(), isTrue);
      metered = true;
      expect(await installer.isOnUnmeteredNetwork(), isFalse);
    });

    test('a missing answer counts as metered', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      expect(await installer.isOnUnmeteredNetwork(), isFalse);
    });
  });
}
