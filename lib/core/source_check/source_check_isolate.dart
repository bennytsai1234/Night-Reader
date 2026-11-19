import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';

import 'source_checker.dart';

// ═══════════════════════════════════════════════════════════════════
//  Public types
// ═══════════════════════════════════════════════════════════════════

class IsolateCheckConfig {
  final String keyword;
  final int timeoutSeconds;
  final bool checkSearch;
  final bool checkDiscovery;
  final bool checkInfo;
  final bool checkCategory;
  final bool checkContent;

  const IsolateCheckConfig({
    required this.keyword,
    required this.timeoutSeconds,
    required this.checkSearch,
    required this.checkDiscovery,
    required this.checkInfo,
    required this.checkCategory,
    required this.checkContent,
  });

  Duration get timeoutDuration => Duration(seconds: timeoutSeconds);

  Map<String, dynamic> toMap() => {
    'keyword': keyword,
    'timeoutSeconds': timeoutSeconds,
    'checkSearch': checkSearch,
    'checkDiscovery': checkDiscovery,
    'checkInfo': checkInfo,
    'checkCategory': checkCategory,
    'checkContent': checkContent,
  };

  factory IsolateCheckConfig.fromMap(Map<String, dynamic> map) =>
      IsolateCheckConfig(
        keyword: map['keyword'] as String,
        timeoutSeconds: map['timeoutSeconds'] as int,
        checkSearch: map['checkSearch'] as bool,
        checkDiscovery: map['checkDiscovery'] as bool,
        checkInfo: map['checkInfo'] as bool,
        checkCategory: map['checkCategory'] as bool,
        checkContent: map['checkContent'] as bool,
      );
}

class SourceCheckIsolateResult {
  final String stage;
  final String message;
  final bool isHealthy;
  final Map<String, dynamic> updatedSourceJson;
  final List<String> logs;

  /// 每個問題一段診斷（`SourceChecker._diagnosis`），主 isolate 寫進
  /// `SourceCheckDiagnostics`。
  final List<String> diagnostics;

  const SourceCheckIsolateResult({
    required this.stage,
    required this.message,
    required this.isHealthy,
    required this.updatedSourceJson,
    required this.logs,
    this.diagnostics = const [],
  });

  Map<String, dynamic> toMap() => {
    'stage': stage,
    'message': message,
    'isHealthy': isHealthy,
    'updatedSourceJson': updatedSourceJson,
    'logs': logs,
    'diagnostics': diagnostics,
  };

  factory SourceCheckIsolateResult.fromMap(Map<String, dynamic> map) =>
      SourceCheckIsolateResult(
        stage: map['stage'] as String,
        message: map['message'] as String,
        isHealthy: map['isHealthy'] as bool,
        updatedSourceJson: Map<String, dynamic>.from(
          map['updatedSourceJson'] as Map,
        ),
        logs: List<String>.from(map['logs'] as List),
        diagnostics: List<String>.from(map['diagnostics'] as List),
      );
}

class SourceCheckIsolateHandle {
  final Future<SourceCheckIsolateResult?> result;
  final void Function() abort;

  const SourceCheckIsolateHandle({required this.result, required this.abort});
}

// ═══════════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════════

/// 開一個書源 worker（[SourceWorker]）校驗 [source]：和閱讀時一樣的環境，
/// 網頁渲染、Cloudflare 檢查、Cookie 與資料庫都交給主 isolate。到了
/// [timeout] 還沒做完就結束 worker，結果不再等它（[SourceWorker.kill]）。
/// 逾時、取消或開不起來時結果是 null，呼叫端當成逾時或異常。
///
/// 立刻交回 handle：還沒真的結束的臨時 worker 太多時，worker 要等名額才開
/// （[SourceWorker.maxTemporaryWorkers]），等的時候也能 abort；[timeout] 從
/// worker 開好才算。
Future<SourceCheckIsolateHandle> spawnSourceCheck(
  BookSource source,
  IsolateCheckConfig config,
  Duration timeout,
) async {
  final completer = Completer<SourceCheckIsolateResult?>();
  final stop = CancelToken();
  SourceWorker? worker;
  Timer? timer;

  void finish(SourceCheckIsolateResult? result) {
    if (completer.isCompleted) return;
    timer?.cancel();
    worker?.kill(StateError('書源校驗已結束'));
    stop.cancel();
    completer.complete(result);
  }

  Future<void> run() async {
    try {
      worker = await SourceWorker.spawn(
        debugName: 'SourceCheck',
        withDictionaries: false,
        cancelToken: stop,
      );
    } catch (e, stack) {
      if (!stop.isCancelled) {
        AppLog.e('書源校驗 worker 開不起來: $e', error: e, stackTrace: stack);
      }
      finish(null);
      return;
    }
    if (completer.isCompleted) {
      worker!.kill(StateError('書源校驗已結束'));
      return;
    }
    timer = Timer(timeout, () => finish(null));
    try {
      final map = await worker!.run(
        _checkTask(source.toJson(), config.toMap()),
      );
      finish(SourceCheckIsolateResult.fromMap(map));
    } catch (error, stack) {
      // 先把真實錯誤記成錯誤（App 日誌；App 沒有閃退，不寫崩潰日誌），
      // 再以 null 收尾，避免被誤判為「整體校驗超時」；結束 worker 的那一次
      // 不算。
      if (!completer.isCompleted) {
        AppLog.e(
          '書源校驗失敗 [${source.bookSourceName}] '
          '(${source.bookSourceUrl})',
          error: error,
          stackTrace: stack,
        );
      }
      finish(null);
    }
  }

  unawaited(run());
  return SourceCheckIsolateHandle(
    result: completer.future,
    abort: () => finish(null),
  );
}

/// 在 worker 裡跑的校驗；只捕捉書源與設定的資料（`CODING_STANDARDS.md`）。
Future<Map<String, dynamic>> Function(CancelToken) _checkTask(
  Map<String, dynamic> sourceJson,
  Map<String, dynamic> configMap,
) => (_) async {
  final checker = SourceChecker(
    source: BookSource.fromJson(sourceJson),
    config: IsolateCheckConfig.fromMap(configMap),
  );
  return (await checker.run()).toMap();
};
