/// 用真的網站與使用者自己的 AI 服務，從一個網址建立書源一次，看 AI 走了
/// 幾輪、卡在哪（`docs/agents/ai-repair-runs.md`）。會呼叫 AI 服務、花使用者
/// 的額度。
///
/// ```sh
/// NR_URL=<網址> NR_AI_KEY_FILE=<只放金鑰的檔> NR_OUT=<結果 JSON> \
///   FLUTTER_TEST_WALL=0 tool/flutter_test.sh --run-skipped -t live \
///   test/live/source_create_live_test.dart
/// ```
///
/// - `NR_TITLE`：選填的樣本書名。
/// - `NR_AI_URL`、`NR_AI_MODEL`、`NR_AI_EFFORT` 同
///   `source_repair_batch_live_test.dart`。
/// - 建立的書源存進暫存資料庫，跑完刪掉；結果檔是結果、每一步、統計與建立
///   的書源。完整紀錄寫在開頭與最後印出的資料夾，用
///   `dart run tool/ai_repair_table.dart <資料夾>` 整理成評估表。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/ai_create_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/diagnostics/crash_handler.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;
  static _MinimalServicesBinding ensureInitialized() =>
      _instance ??= _MinimalServicesBinding();
}

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getExternalStoragePath() async => root;
}

void main() {
  _MinimalServicesBinding.ensureInitialized();
  final root = Directory.systemTemp.createTempSync('night_reader_ai_');
  setUpAll(() async {
    quickJsUnavailableReason();
    PathProviderPlatform.instance = _TempPaths(root.path);
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    registerDatabase(AppDatabase());
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);
    SourceIsolate.enabled = true;
    SourceIsolate.start();
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );
  });
  tearDownAll(() async {
    await SourceIsolate.stop();
    await AppDatabase().close();
  });

  final env = Platform.environment;
  final url = env['NR_URL'];
  if (url == null) return;
  final key = File(env['NR_AI_KEY_FILE']!).readAsStringSync().trim();
  final out = env['NR_OUT']!;
  final blank = aiCreateBlankSource(url);
  if (blank == null) throw StateError('NR_URL 不是 http(s) 網址：$url');

  test('從 $url 建立書源', () async {
    final session = AiRepairSession(
      source: blank,
      create: (url: url, sampleTitle: env['NR_TITLE'] ?? ''),
      service: (
        baseUrl: env['NR_AI_URL'] ?? 'https://api.deepseek.com',
        apiKey: key,
        model: env['NR_AI_MODEL'] ?? 'deepseek-flash',
        effort: env['NR_AI_EFFORT'] ?? '',
      ),
    );
    final logs = '${(await CrashHandler.logDirectory()).path}/ai-repair';
    debugPrint('##### 完整紀錄：$logs');
    final watch = Stopwatch()..start();
    await session.start();
    await session.log.file();
    final job = session.job;
    final row = {
      'url': url,
      'ms': watch.elapsedMilliseconds,
      'outcome': job.outcome?.name,
      'explanation': job.explanation,
      'giveUp': job.giveUpWhy,
      'steps': [for (final step in job.steps) '${step.title}：${step.detail}'],
      'stats': session.stats?.toMap(),
      'source': job.repairedSource?.toJson(),
    };
    File(out)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(row));
    debugPrint('##### ${job.outcome?.name}：${job.explanation}');
    debugPrint('##### 完整紀錄：$logs');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
