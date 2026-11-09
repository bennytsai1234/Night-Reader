import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

/// 一次試抓：照書源除錯從搜尋一路抓到正文（[SourceDebugService]），記下除錯
/// 紀錄與每個請求、網站回了什麼（每個回應留開頭 [responsePreview] 字），給
/// AI 看網頁現在長怎樣（ADR 0053）。
class SourceProbeReport {
  const SourceProbeReport({
    required this.logs,
    required this.requests,
    this.timedOut = false,
  });

  /// 除錯紀錄，`(狀態, 訊息)`；狀態同 [DebugLog.state]。
  final List<(int, String)> logs;

  /// 請求與網站的回應，照送出的順序（[RequestLog.lines]）。
  final List<String> requests;

  /// 整段試抓超過時間被停下。
  final bool timedOut;

  /// 每個回應記的字數。
  static const int responsePreview = 3000;

  /// 送給 AI 的請求與回應最多幾個字；超過的後半段截掉。
  static const int requestBudget = 20000;

  /// 一路抓到正文了。
  bool get succeeded =>
      !timedOut &&
      logs.any((log) => log.$1 == 1000) &&
      !logs.any((log) => log.$1 == -1);

  /// 抓到了哪幾段，例如「搜尋、詳情、目錄、正文」。
  String get stagesReached {
    const names = {10: '搜尋', 20: '詳情', 30: '目錄', 40: '正文'};
    final reached = {for (final (state, _) in logs) ?names[state]};
    return reached.join('、');
  }

  /// 回了幾頁網頁。
  int get pageCount => requests.where((line) => line.startsWith('  ← ')).length;

  /// 一句結果：抓到的正文多長，或停在哪裡。
  String get summary {
    if (timedOut) return '試抓超過時間';
    for (final (state, message) in logs.reversed) {
      if (state == -1) return _clean(message);
    }
    for (final (_, message) in logs.reversed) {
      final length = RegExp(r'內容長度: (\d+)').firstMatch(message)?.group(1);
      if (length != null) return '正文 $length 字';
    }
    return '沒有抓到正文';
  }

  /// 給 AI 看的全文：除錯紀錄，與截到 [requestBudget] 字的請求與回應。
  String get fullText {
    final buffer = StringBuffer()..writeln('## 除錯紀錄');
    for (final (_, message) in logs) {
      buffer.writeln(message);
    }
    if (timedOut) buffer.writeln('（試抓超過時間，停在這裡）');
    buffer
      ..writeln()
      ..writeln('## 請求與網站的回應（每個回應只留開頭 $responsePreview 字）');
    var used = 0;
    for (final line in requests) {
      if (used + line.length > requestBudget) {
        buffer.writeln(
          '（後面還有 ${requests.length - requests.indexOf(line)} 行，省略）',
        );
        break;
      }
      buffer.writeln(line);
      used += line.length;
    }
    return buffer.toString().trimRight();
  }

  static String _clean(String message) =>
      message.replaceFirst(RegExp(r'^[\s❌︽≡]+'), '').trim();

  Map<String, Object?> toMap() => {
    'logs': [
      for (final (state, message) in logs) [state, message],
    ],
    'requests': requests,
    'timedOut': timedOut,
  };

  factory SourceProbeReport.fromMap(Map<Object?, Object?> map) =>
      SourceProbeReport(
        logs: [
          for (final entry in map['logs']! as List)
            ((entry as List)[0] as int, entry[1] as String),
        ],
        requests: List<String>.from(map['requests']! as List),
        timedOut: map['timedOut'] as bool? ?? false,
      );
}

/// 開一個書源 worker 試抓 [source]（同書源校驗，ADR 0033）：用 [keyword]
/// 搜尋，從第一本書一路抓到第一章正文。到了 [timeout] 還沒抓完就結束
/// worker，傳回 [SourceProbeReport.timedOut]；[cancelToken] 取消時也是。
Future<SourceProbeReport> probeSource(
  BookSource source, {
  required String keyword,
  required Duration timeout,
  CancelToken? cancelToken,
  @visibleForTesting Future<DriftIsolate>? database,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SourceProbe',
      withDictionaries: false,
      database: database,
    );
  } catch (error, stack) {
    AppLog.e('試抓的 worker 開不起來: $error', error: error, stackTrace: stack);
    return SourceProbeReport(logs: [(-1, '試抓開不起來：$error')], requests: const []);
  }
  final completer = Completer<SourceProbeReport>();
  void finish(SourceProbeReport report) {
    if (completer.isCompleted) return;
    worker.kill(StateError('試抓已結束'));
    completer.complete(report);
  }

  const stopped = SourceProbeReport(logs: [], requests: [], timedOut: true);
  final timer = Timer(timeout, () => finish(stopped));
  unawaited(cancelToken?.whenCancel.then((_) => finish(stopped)));
  unawaited(
    worker
        .run(_probeTask(source.toJson(), keyword))
        .then(
          (map) => finish(SourceProbeReport.fromMap(map)),
          onError: (Object error, StackTrace stack) {
            if (completer.isCompleted) return;
            finish(
              SourceProbeReport(
                logs: [(-1, '試抓失敗：$error')],
                requests: const [],
              ),
            );
          },
        ),
  );
  final report = await completer.future;
  timer.cancel();
  return report;
}

/// 在 worker 裡跑的試抓；只捕捉書源與關鍵字的資料（`CODING_STANDARDS.md`）。
Future<Map<String, Object?>> Function(CancelToken) _probeTask(
  Map<String, dynamic> sourceJson,
  String keyword,
) => (_) async {
  final debug = SourceDebugService();
  final logs = <(int, String)>[];
  final subscription = debug.logStream.listen(
    (log) => logs.add((log.state, log.message)),
  );
  final requests = RequestLog(
    responsePreview: SourceProbeReport.responsePreview,
  );
  try {
    await requests.run(
      () => debug.startDebug(BookSource.fromJson(sourceJson), keyword),
    );
    // 紀錄經過 broadcast stream，讓最後幾筆送到。
    await Future<void>.delayed(Duration.zero);
  } finally {
    await subscription.cancel();
  }
  return SourceProbeReport(logs: logs, requests: requests.lines).toMap();
};
