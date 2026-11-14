/// 用真的網站與使用者自己的 AI 服務跑一次修復異常書源（ADR 0054），看整批
/// 每個書源走到哪一步、花了多少 token；調 AI 修書源的提示詞或流程時拿來比
/// 前後。會呼叫 AI 服務、花使用者的額度。
///
/// ```sh
/// NR_SOURCES=<書源 JSON> NR_AI_KEY_FILE=<只放金鑰的檔> NR_OUT=<結果 JSON> \
///   flutter test --run-skipped -t live test/live/source_repair_batch_live_test.dart
/// ```
///
/// - 給了 `NR_CASES`（案件集，`test/live/ai_repair_cases.json`）時，`NR_SOURCES`
///   是使用者的整份匯出檔，照案件集的名稱與網址挑出書源；跑完每件照預期答案
///   算對錯（修好了沒有、正文夠不夠長），印出表、寫進結果檔的 `score`。
///   `NR_ONLY=<名稱,名稱>` 只跑案件集裡這幾件（照 `name`）。
/// - `NR_AI_URL` 是服務網址，預設 DeepSeek（`https://api.deepseek.com`）；
///   OpenCode Go 是 `https://opencode.ai/inference/go/openai/v1`。`NR_AI_MODEL`
///   換模型，預設 `deepseek-flash`（服務的 `/models` 列得出有哪些）；
///   `NR_AI_EFFORT` 是思考程度（`low`、`medium`、`high`，不給是服務預設）；
/// - 書源先存進暫存資料庫，照 App 的流程重新校驗、檢查網站、換網址、問 AI、
///   套用到同網站；存的也是暫存資料庫，跑完刪掉。
/// - 結果檔是總時間、總 token 與每個書源的結果、網站檢查、AI 的每一步與
///   統計；每個書源的完整修復紀錄寫在最後印出的資料夾，用
///   `dart run tool/ai_repair_table.dart <資料夾>` 整理成評估表。
///
/// 書源的拿法同 `source_check_live_test.dart` 檔頭。金鑰固定放在主資料夾的
/// `.local/ai-repair.key`（git 忽略、不上傳；`docs/agents/ai-repair-runs.md`）。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
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
  final path = env['NR_SOURCES'];
  if (path == null) return;
  final key = File(env['NR_AI_KEY_FILE']!).readAsStringSync().trim();
  final out = env['NR_OUT']!;
  final all = [
    for (final json in (jsonDecode(File(path).readAsStringSync()) as List))
      BookSource.fromJson(json as Map<String, dynamic>),
  ];
  final casesPath = env['NR_CASES'];
  final only = env['NR_ONLY']?.split(',').map((name) => name.trim()).toSet();
  final cases = casesPath == null
      ? const <Map<String, dynamic>>[]
      : [
          for (final item
              in (jsonDecode(File(casesPath).readAsStringSync())
                      as Map<String, dynamic>)['cases']
                  as List)
            if (only == null || only.contains((item as Map)['name']))
              item as Map<String, dynamic>,
        ];
  final sources = cases.isEmpty
      ? all
      : [
          for (final item in cases)
            all.firstWhere(
              (s) =>
                  s.bookSourceName == item['name'] &&
                  s.bookSourceUrl == item['url'],
            ),
        ];

  test('整批修復 ${sources.length} 個書源', () async {
    await getIt<BookSourceDao>().upsertAll(sources);
    final batch = SourceRepairBatch(
      sources: sources,
      service: (
        baseUrl: env['NR_AI_URL'] ?? 'https://api.deepseek.com',
        apiKey: key,
        model: env['NR_AI_MODEL'] ?? 'deepseek-flash',
        effort: env['NR_AI_EFFORT'] ?? '',
      ),
    );
    var lastStage = '';
    batch.addListener(() {
      final now = '${batch.stage.name} ${batch.stageDone}/${batch.stageTotal}';
      if (now != lastStage) {
        lastStage = now;
        debugPrint('##### 進度 $now token ${batch.tokensUsed}');
      }
    });
    final watch = Stopwatch()..start();
    await batch.start();
    // 修復紀錄是排隊寫進檔案的：等最後幾段（結果、統計）寫完再結束，不然
    // 測試一結束程序就關了，紀錄停在最後一輪的中間。
    for (final item in batch.items) {
      await item.session?.log.file();
    }
    final rows = [
      for (final item in batch.items)
        {
          'name': item.source.bookSourceName,
          'url': item.source.bookSourceUrl,
          'outcome': item.outcome?.name,
          'detail': item.detail,
          'site': item.site?.toMap(),
          'tokens': item.tokens,
          'steps': [
            for (final step in item.session?.job.steps ?? const [])
              '${step.title}：${step.detail}',
          ],
          'stats': item.session?.stats?.toMap(),
        },
    ];
    // 書源照案件集的順序挑出來，修復項目也是同樣的順序：照位置配對（換了網址
    // 的書源沒有 AI 的修復紀錄，網址已經跟案件集的不一樣）。
    final score = [
      for (final (i, item) in cases.indexed) _score(item, batch.items[i]),
    ];
    File(out).writeAsStringSync(
      jsonEncode({
        'ms': watch.elapsedMilliseconds,
        'tokens': batch.tokensUsed,
        'items': rows,
        if (cases.isNotEmpty) 'score': score,
      }),
    );
    for (final row in score) {
      debugPrint(
        '##### 案件 ${row['name']}：預期 ${row['expected']}，實際 ${row['verdict']}'
        '${row['why'] == null ? '' : '（${row['why']}）'}'
        '${row['contentChars'] == null ? '' : '（正文 ${row['contentChars']} 字）'}'
        ' => ${switch (row['pass']) {
          true => '對',
          false => '錯',
          _ => '還沒定預期答案',
        }}',
      );
    }
    for (final row in rows) {
      debugPrint('##### ${row['name']} => ${row['outcome']} ${row['detail']}');
    }
    debugPrint(
      '##### 完整修復紀錄：${(await CrashHandler.logDirectory()).path}/ai-repair',
    );
  }, timeout: const Timeout(Duration(minutes: 40)));
}

/// 一件案件照預期答案算對錯：修好了沒有（[_verdict]），預期修得好、又寫了
/// `minContentChars` 的，最後一次試抓到的正文要夠長（只抓到半章的不算）；
/// 預期修不好、又寫了 `why` 的，放棄的原因要是其中一個（[_why]；`why` 是一個
/// 或一串：同一個判定底下的細分類都算對，例如網站限流是功能壞掉的一種）。
Map<String, Object?> _score(Map<String, dynamic> item, RepairItem repaired) {
  final verdict = _verdict(repaired);
  final chars = [
    for (final step in repaired.session?.job.steps ?? const <AiRepairStep>[])
      for (final m in RegExp(r'正文 (\d+) 字').allMatches(step.detail ?? ''))
        int.parse(m.group(1)!),
  ].lastOrNull;
  // 一個，或一串都算對的（網站狀態在變、兩種結論都有當下的事實撐著時）。
  final expected = switch (item['expected']) {
    final String one => [one],
    final List<dynamic> many => many.cast<String>(),
    _ => const ['unknown'],
  };
  final min = item['minContentChars'] as int?;
  final why = switch (item['why']) {
    final String one => [one],
    final List<dynamic> many => many.cast<String>(),
    _ => null,
  };
  return {
    'name': item['name'],
    'expected': expected.join('／'),
    'verdict': verdict,
    'why': _why(repaired),
    'contentChars': chars,
    'pass': expected.contains('unknown')
        ? null
        : expected.contains(verdict) &&
              (verdict != 'fixed' || min == null || (chars ?? 0) >= min) &&
              (verdict != 'unfixable' ||
                  why == null ||
                  why.contains(_why(repaired))),
  };
}

/// 修不好的原因：網站檢查判成不在了是 site_gone，其他是 AI 放棄時選的。
String? _why(RepairItem item) => item.outcome == RepairOutcome.siteGone
    ? 'site_gone'
    : item.session?.job.giveUpWhy;

/// 這件的結果：fixed（修好了，含換網址、套用同網站的、重新校驗就好）、
/// unfixable（網站不在了，或 AI 拿出證據說修不好），其他是 unfinished。
String _verdict(RepairItem item) => switch (item.outcome) {
  RepairOutcome.aiFixed ||
  RepairOutcome.moved ||
  RepairOutcome.shared ||
  RepairOutcome.healthy => 'fixed',
  RepairOutcome.siteGone => 'unfixable',
  RepairOutcome.notFixed when item.session?.job.confirmedUnfixable == true =>
    'unfixable',
  _ => 'unfinished',
};
