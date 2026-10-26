import 'dart:async';
import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/http_client.dart' as app_http;
import 'package:night_reader/core/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 送進書源 isolate 的工作都在頂層函式裡建立，只捕捉參數。

/// 在書源 isolate 開一段交易，交易中途等 [url] 回應。
Future<void> _transactionWaitingOn(String url) => SourceIsolate.run((_) async {
  await getIt<AppDatabase>().transaction(() async {
    await getIt<CacheDao>().upsert(Cache(key: 'during', value: 'x'));
    await app_http.HttpClient().client.get<String>(url);
  });
}, affinity: 'same');

/// 同一條書源 isolate 上，停住讀快取（資料庫）。
Future<Object?> _blockedCacheRead(String key) => SourceIsolate.run(
  (_) async => BlockingCall.run(() => CacheManager().get(key)),
  affinity: 'same',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late DriftIsolate databaseIsolate;
  late AppDatabase db;
  late HttpServer server;
  late String baseUrl;
  final released = Completer<void>();
  final arrived = Completer<void>();

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('night_reader_source_io_');
    final path = '${dir.path}/night_reader.db';
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    databaseIsolate = await spawnDatabaseIsolate(path);
    db = AppDatabase.connected(await databaseIsolate.connect());
    registerDatabase(db);
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);
    await getIt<CacheDao>().upsert(Cache(key: 'saved', value: '存好的'));

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      arrived.complete();
      await released.future;
      request.response.write('ok');
      await request.response.close();
    });

    SourceIsolate.enabled = true;
    SourceIsolate.start(
      database: Future.value(databaseIsolate),
      databaseFile: Future.value(path),
    );
  });

  tearDownAll(() async {
    await SourceIsolate.stop();
    SourceIsolate.enabled = false;
    await server.close(force: true);
    await db.close();
    await databaseIsolate.shutdownAll();
    await GetIt.instance.reset();
    await dir.delete(recursive: true);
  });

  test('a blocked read does not wait for a transaction its own source isolate '
      'holds', () async {
    // 書源 isolate 的一段交易做到一半在等網路；同一條上另一個工作停住讀
    // 資料庫。drift isolate 在交易結束前不做別的查詢，交易又要等停住的這條
    // 醒來才做得完：讀取排在交易後面的話，兩邊互相等死。
    final transaction = _transactionWaitingOn('$baseUrl/held');
    await arrived.future;

    expect(await _blockedCacheRead('saved'), '存好的');

    released.complete();
    await transaction;
  });
}
