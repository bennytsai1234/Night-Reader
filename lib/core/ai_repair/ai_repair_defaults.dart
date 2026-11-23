import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_loop.dart';
import 'ai_chat_client.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_settings.dart';
import 'repair_pages.dart';
import 'repair_rule_tools.dart';
import 'source_probe.dart';

/// AI 修復接的真東西（[AiRepairSession] 沒給時用）：照校驗設定校驗、試抓、
/// 看網頁、解析、跑程式，問使用者的 AI 服務，複製到剪貼簿。
abstract final class AiRepairDefaults {
  static Future<SourceCheckConfig> _config() async =>
      SourceCheckConfig.fromPreferences(await SharedPreferences.getInstance());

  /// 照校驗設定校驗一次（在自己的 isolate 裡，ADR 0051）；逾時是 null。
  static Future<SourceCheckIsolateResult?> check(
    BookSource source,
    CancelToken cancelToken,
  ) async => _check(source, cancelToken, await _config());

  /// 建立書源的校驗（ADR 0082）：每一段都驗，不照使用者在校驗設定關掉的
  /// 段：從空白寫的書源，關掉的那一段可能根本沒有規則。關鍵字與時限照設定。
  static Future<SourceCheckIsolateResult?> checkAll(
    BookSource source,
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    return _check(
      source,
      cancelToken,
      SourceCheckConfig(
        keyword: config.keyword,
        timeoutSeconds: config.timeoutSeconds,
        checkSearch: true,
        checkDiscovery: true,
        checkInfo: true,
        checkCategory: true,
        checkContent: true,
      ),
    );
  }

  static Future<SourceCheckIsolateResult?> _check(
    BookSource source,
    CancelToken cancelToken,
    SourceCheckConfig config,
  ) async {
    final handle = await spawnSourceCheck(
      source,
      config.forIsolate,
      config.sourceTimeoutDuration,
    );
    unawaited(cancelToken.whenCancel.then((_) => handle.abort()));
    return handle.result;
  }

  static Future<SourceProbeReport> probe(
    BookSource source,
    CancelToken cancelToken, {
    String? start,
  }) async {
    final config = await _config();
    return probeSource(
      source,
      keyword: start ?? source.getCheckKeyword(config.keyword),
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static Future<AiPage> fetchPage(
    BookSource source,
    String url,
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    return fetchPageForAi(
      source,
      url,
      keyword: source.getCheckKeyword(config.keyword),
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static Future<String> parsePage(
    BookSource source,
    String stage,
    RepairPage page,
    CancelToken cancelToken,
  ) async => parseRepairPage(
    source,
    stage: stage,
    body: page.body,
    url: page.url,
    timeout: (await _config()).sourceTimeoutDuration,
    cancelToken: cancelToken,
  );

  static Future<String> runJs(
    BookSource source,
    String code,
    Map<int, String> pages,
    CancelToken cancelToken,
  ) async => runRepairJs(
    source,
    code: code,
    pages: pages,
    timeout: (await _config()).sourceTimeoutDuration,
    cancelToken: cancelToken,
  );

  static AgentAsk ask(AiService service) {
    final client = AiChatClient(service);
    return (messages, cancelToken) => client.complete(
      messages,
      tools: aiRepairTools,
      cancelToken: cancelToken,
    );
  }

  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
