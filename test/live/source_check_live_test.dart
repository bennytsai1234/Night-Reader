/// 用真的網站校驗書源，分辨書源被標異常是網站的問題還是夜讀解析器的問題。
///
/// 拿手機上的書源：書源管理多選 →「分享選中」→「儲存到檔案管理員」，檔案在
/// 手機的 `/sdcard/Download/分享儲存/`，用 `adb pull` 拉到電腦。
///
/// ```sh
/// NR_SOURCES=<書源 JSON> flutter test --run-skipped -t live test/live
/// ```
///
/// - `NR_ONLY=<書源名稱的一部分>`：只跑名稱含這段字的書源。
/// - `NR_DISCOVERY=1`：也校驗發現（手機上的校驗預設有開）。
/// - `NR_KEYWORD`、`NR_TIMEOUT`：搜尋關鍵字與每步秒數，預設和手機一樣是
///   「我的」、15 秒。
/// - `NR_PARALLEL=<n>`：整批跑時同時校驗 n 個書源（每個在自己的 isolate），
///   全部算成一個測試；沒給時一個書源一個測試、依序跑。
/// - `NR_OUT=<檔案>`：每個書源的結果另外寫成一行 JSON 接在檔案後面（名稱、
///   網址、是否通過、階段、訊息、日誌），給整批統計用。
///
/// 和 App 一樣經 [spawnSourceCheck] 在書源 isolate 裡校驗：規則 JS 要等網路
/// 的呼叫（`java.ajax` 這類）只能在那裡跑（ADR 0034）。App 的資料夾指到一個
/// 暫存資料夾，資料庫照 App 的流程開在裡面，跑完刪掉；沒有登入資料。每個
/// 書源印出 `#####` 開頭的結論與校驗日誌。測試環境沒有 WebView，要
/// Cloudflare 驗證或網頁渲染的書源量不到。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

/// 不用 TestWidgetsFlutterBinding：它會把網路請求都擋成 400。
class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// App 的各個資料夾都指到 [root]。
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

  final root = Directory.systemTemp.createTempSync('night_reader_live_');
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
  });
  tearDownAll(() async {
    await SourceIsolate.stop();
    await AppDatabase().close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // 資料庫檔案在 Windows 上可能還被鎖著；暫存資料夾留給系統清。
    }
  });

  final env = Platform.environment;
  final path = env['NR_SOURCES'];
  if (path == null) {
    test('NR_SOURCES', () => fail('用 NR_SOURCES 指定書源 JSON 檔'));
    return;
  }
  final only = env['NR_ONLY'];
  final out = env['NR_OUT'];
  final config = IsolateCheckConfig(
    keyword: env['NR_KEYWORD'] ?? '我的',
    timeoutSeconds: int.tryParse(env['NR_TIMEOUT'] ?? '') ?? 15,
    checkSearch: true,
    checkDiscovery: env['NR_DISCOVERY'] == '1',
    checkInfo: true,
    checkCategory: true,
    checkContent: true,
  );
  final decoded = jsonDecode(File(path).readAsStringSync());
  final sources = [
    for (final json
        in (decoded is List ? decoded : [decoded]).cast<Map<String, dynamic>>())
      if (only == null || (json['bookSourceName'] as String).contains(only))
        json,
  ];
  final parallel = int.tryParse(env['NR_PARALLEL'] ?? '') ?? 1;

  Future<void> check(Map<String, dynamic> json) async {
    final name = json['bookSourceName'] as String;
    final handle = await spawnSourceCheck(
      BookSource.fromJson(json),
      config,
      const Duration(minutes: 3),
    );
    final result = await handle.result;
    final record = {
      'name': name,
      'url': json['bookSourceUrl'],
      'healthy': result?.isHealthy ?? false,
      'stage': result?.stage ?? 'timeout',
      'message': result?.message ?? '整體超過 3 分鐘',
      'logs': result?.logs ?? const <String>[],
    };
    debugPrint(
      '##### $name => '
      '${record['healthy'] == true ? '校驗成功' : '${record['stage']}：${record['message']}'}',
    );
    (record['logs'] as List).cast<String>().forEach(debugPrint);
    if (out != null) {
      File(out).writeAsStringSync(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  if (parallel <= 1) {
    for (final json in sources) {
      test(
        json['bookSourceName'] as String,
        () => check(json),
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
    return;
  }
  // 整批：同時校驗 [parallel] 個書源，每個在自己的 isolate 裡。
  test('${sources.length} 個書源', () async {
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        await check(sources[next++]);
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  }, timeout: Timeout(Duration(minutes: 4 * sources.length ~/ parallel + 4)));
}
