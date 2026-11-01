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
///
/// 每個書源印出 `#####` 開頭的結論與校驗日誌。測試環境沒有 WebView，要
/// Cloudflare 驗證或網頁渲染的書源量不到；「回填 wordCount 失敗」是測試沒有
/// 資料庫，不影響結果。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';

import '../test_helper.dart';

/// 不用 TestWidgetsFlutterBinding：它會把網路請求都擋成 400。
class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();
  setUpAll(() async => NetworkService().init());

  final env = Platform.environment;
  final path = env['NR_SOURCES'];
  if (path == null) {
    test('NR_SOURCES', () => fail('用 NR_SOURCES 指定書源 JSON 檔'));
    return;
  }
  final only = env['NR_ONLY'];
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
  final sources = (decoded is List ? decoded : [decoded])
      .cast<Map<String, dynamic>>();

  for (final json in sources) {
    final name = json['bookSourceName'] as String;
    if (only != null && !name.contains(only)) continue;
    test(name, () async {
      final result = await SourceChecker(
        source: BookSource.fromJson(json),
        config: config,
      ).run();
      debugPrint(
        '##### $name => '
        '${result.isHealthy ? '校驗成功' : '${result.stage}：${result.message}'}',
      );
      result.logs.forEach(debugPrint);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
