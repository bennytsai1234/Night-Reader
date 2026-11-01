import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/js/js_engine.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

/// 在測試裡開書源 isolate（ADR 0034）：規則 JS 要等網路的呼叫（`java.ajax`、
/// `Jsoup.connect().execute()` 這類）只能在那裡跑，請求由網路 isolate 發。
///
/// ```dart
/// final isolates = SourceIsolateHarness();
/// setUpAll(isolates.start);
/// tearDownAll(isolates.stop);
/// test('…', () async => expect(await evaluateInSourceIsolate('…'), '…'));
/// ```
class SourceIsolateHarness {
  late DriftIsolate _databaseIsolate;
  late AppDatabase _db;

  Future<void> start() async {
    quickJsUnavailableReason();
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    _databaseIsolate = await DriftIsolate.spawn(NativeDatabase.memory);
    _db = AppDatabase.connected(await _databaseIsolate.connect());
    registerDatabase(_db);
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);
    SourceIsolate.enabled = true;
    SourceIsolate.start(database: Future.value(_databaseIsolate));
  }

  Future<void> stop() async {
    await SourceIsolate.stop();
    SourceIsolate.enabled = false;
    await _db.close();
    await _databaseIsolate.shutdownAll();
    await GetIt.instance.reset();
  }
}

/// 在書源 isolate 跑一段規則 JS，傳回結果轉成的字串。
Future<String> evaluateInSourceIsolate(String code) =>
    SourceIsolate.run((_) async {
      final engine = JsEngine();
      try {
        return '${engine.evaluate(code)}';
      } finally {
        engine.dispose();
      }
    });
