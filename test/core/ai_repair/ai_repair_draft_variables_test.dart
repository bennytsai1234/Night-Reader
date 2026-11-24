import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/core/utils/cache_manager.dart';

import '../../support/fake_ai.dart';

/// AI 修書源用草稿試抓、校驗時，規則 JS 的 `source.put`／`java.put` 存的
/// 變數寫在草稿自己那一份；正式的書源到修好套用時才換成草稿的。
void main() {
  const url = 'https://site.example';
  const fixed = 'class.txt@text';
  const service = (
    baseUrl: 'https://ai.example/v1',
    apiKey: 'sk-test',
    model: 'm',
    effort: '',
  );
  final source = BookSource(
    bookSourceUrl: url,
    bookSourceName: '站',
    searchUrl: '/s?q={{key}}',
    ruleContent: ContentRule(content: 'id.old@text'),
  );
  final realKey = source.ruleVariableCacheKey('token');

  setUp(() async {
    final file = await AiRepairBackups.file();
    if (file.existsSync()) file.deleteSync();
    await CacheManager().put(realKey, 'real');
  });

  tearDown(() => CacheManager().delete(realKey));

  /// 試抓：改好的草稿（正文規則是 [fixed]）照書源規則的方式存一個變數，
  /// 並記下存之前讀到的值。
  final seen = <String?>[];
  Future<SourceProbeReport> probe(BookSource candidate) async {
    final good = candidate.ruleContent?.content == fixed;
    if (good) {
      final key = candidate.ruleVariableCacheKey('token');
      seen.add(await CacheManager().get(key));
      await CacheManager().put(key, 'draft');
    }
    return SourceProbeReport(
      logs: [
        (10, '︾開始解析搜尋頁'),
        if (good) (40, '︽正文頁解析完成 (內容長度: 3214)') else (-1, '❌ 正文為空'),
        if (good) (1000, '︽解析完成'),
      ],
      requests: const [],
      contentUsable: good ? true : null,
    );
  }

  SourceCheckIsolateResult check(BookSource candidate) {
    final healthy = candidate.ruleContent?.content == fixed;
    return SourceCheckIsolateResult(
      stage: healthy ? 'done' : 'content',
      message: healthy ? '校驗成功' : '正文為空',
      isHealthy: healthy,
      updatedSourceJson: candidate.toJson(),
      logs: const [],
    );
  }

  AiRepairSession session(List<String> replies) {
    var next = 0;
    return AiRepairSession(
      source: BookSource.fromJson(source.toJson()),
      service: service,
      check: (candidate, _) async => check(candidate),
      probe: (candidate, _, {start}) => probe(candidate),
      fetchPage: (_, _, _) async =>
          (lines: const <String>[], pages: const <LoggedPage>[]),
      recheckDelay: Duration.zero,
      ask: (messages, _) async => fakeAiReply(replies[next++]),
      apply: (_, _) async {},
      secrets: (_) async => const {},
      copy: (_) async {},
      backups: AiRepairBackups(),
    );
  }

  final test_ = jsonEncode({
    'action': 'test',
    'patch': {
      'ruleContent': {'content': fixed},
    },
    'note': '正文在 div.txt',
  });

  setUp(seen.clear);

  test('a draft that is tested but not applied leaves the source variables '
      'alone', () async {
    final s = session([
      test_,
      jsonEncode({'action': 'give_up', 'why': 'site_broken', 'reason': '壞了'}),
    ]);
    await s.start();

    expect(seen, ['real'], reason: '草稿從正式書源的變數開始');
    expect(await CacheManager().get(realKey), 'real');
  });

  test(
    'a repair that is applied takes the variables the draft stored',
    () async {
      final s = session([
        test_,
        jsonEncode({
          'action': 'submit',
          'patch': <String, dynamic>{},
          'note': '好了',
        }),
      ]);
      await s.start();

      expect(s.job.outcome, AiRepairOutcome.repaired);
      expect(await CacheManager().get(realKey), 'draft');
    },
  );
}
