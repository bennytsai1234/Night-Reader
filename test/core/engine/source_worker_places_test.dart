import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_js/flutter_js.dart' show JsInterruptFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/js/js_engine.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

// 臨時 worker 的名額算到 isolate 真的結束（[SourceWorker.maxTemporaryWorkers]）。
// 自己一個檔：別的測試結束的 worker 可能還卡在規則 JS 裡、佔著名額。

/// 告訴主 isolate 開始了，接著同步佔住 worker [busy] 這麼久：被結束時
/// isolate 要等它跑完才真的結束（同規則 JS 卡在原生程式裡）。
Future<void> Function(CancelToken) _holdWorker(Duration busy) => (_) async {
  AppLog.i('worker 被佔住了');
  sleep(busy);
};

/// 寫成無窮迴圈的規則 JS；開始前告訴主 isolate。
Future<void> _ruleJsLoopingForever(CancelToken _) async {
  final engine = JsEngine();
  try {
    engine.evaluate('java.toast("worker 被佔住了"); while (true) {}');
  } finally {
    engine.dispose();
  }
}

/// 這個平台的規則 JS 不能中途停下時，跳過的原因。
String? _ruleJsInterruptUnavailableReason() =>
    quickJsUnavailableReason() ??
    (JsInterruptFlag.supported
        ? null
        : '這個平台的 QuickJS 函式庫沒有中斷處理（Windows 測試用的沒有匯出 '
              'JS_SetInterruptHandler），CI 的 Linux 會跑');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DriftIsolate databaseIsolate;
  late AppDatabase db;

  setUpAll(() async {
    quickJsUnavailableReason();
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    databaseIsolate = await DriftIsolate.spawn(NativeDatabase.memory);
    db = AppDatabase.connected(await databaseIsolate.connect());
    registerDatabase(db);
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);
  });

  tearDownAll(() async {
    await db.close();
    await databaseIsolate.shutdownAll();
    await GetIt.instance.reset();
  });

  group('temporary workers that have not exited yet', () {
    late int cap;
    late Completer<void> held;

    setUp(() {
      cap = SourceWorker.maxTemporaryWorkers;
      SourceWorker.maxTemporaryWorkers = 1;
      held = Completer<void>();
      AppLog.delegate = (message, error, stackTrace, toast, isError) {
        if (message.contains('worker 被佔住了') && !held.isCompleted) {
          held.complete();
        }
      };
    });

    tearDown(() {
      SourceWorker.maxTemporaryWorkers = cap;
      AppLog.delegate = null;
    });

    Future<SourceWorker> spawn({CancelToken? cancelToken}) =>
        SourceWorker.spawn(
          debugName: 'Temporary',
          withDictionaries: false,
          database: Future.value(databaseIsolate),
          cancelToken: cancelToken,
        );

    /// 開一個 worker、讓它被佔住 [busy]，再結束它。
    Future<void> stopWhileHeld(Duration busy) async {
      final worker = await spawn();
      unawaited(worker.run(_holdWorker(busy)).then((_) {}, onError: (_) {}));
      await held.future.timeout(const Duration(seconds: 10));
      worker.kill(StateError('已停止'));
    }

    // 校驗逾時就結束 worker、接著開下一個；被結束的那條還卡在規則 JS 裡時
    // 不算數的話，一批裡好幾個這種書源，還在跑的 isolate 就沒有上限。
    test('a stopped worker keeps its place until it really exits', () async {
      await stopWhileHeld(const Duration(seconds: 2));
      final waited = Stopwatch()..start();

      final next = await spawn();
      addTearDown(() => next.kill(StateError('測試結束')));

      expect(waited.elapsed, greaterThan(const Duration(milliseconds: 1500)));
    });

    // 2026-11-11 #358 改成等規則 JS 跑完才結束 worker（不然原生閃退），寫成
    // 無窮迴圈的規則從此停不下來；現在 QuickJS 在檢查點自己停下。
    test(
      'a worker stopped in a rule JS loop stops the loop and exits',
      () async {
        final worker = await spawn();
        unawaited(
          worker.run(_ruleJsLoopingForever).then((_) {}, onError: (_) {}),
        );
        await held.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        worker.kill(StateError('已停止'));

        // 名額只有一個：被結束的那條真的結束了才開得起來。
        final next = await spawn().timeout(const Duration(seconds: 10));
        next.kill(StateError('測試結束'));
      },
      skip: _ruleJsInterruptUnavailableReason(),
    );

    test('waiting for a place can be cancelled', () async {
      await stopWhileHeld(const Duration(seconds: 3));
      final cancel = CancelToken();
      final next = spawn(cancelToken: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final waited = Stopwatch()..start();

      cancel.cancel();

      await expectLater(next, throwsA(anything));
      expect(waited.elapsed, lessThan(const Duration(seconds: 1)));
      // 讓佔住的那條真的結束，不留給下一個測試。
      await spawn().then((worker) => worker.kill(StateError('測試結束')));
    });
  });
}
