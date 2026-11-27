import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/core/utils/cache_manager.dart';

import '../../support/fake_ai.dart';

/// AI 修書源用草稿試抓、校驗時，規則 JS 的 `source.put`／`java.put` 存的
/// 變數寫在草稿自己那一份；正式的書源到修好套用時才換成草稿改過的。
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
  final tokenKey = source.ruleVariableCacheKey('token');
  final otherKey = source.ruleVariableCacheKey('other');

  late List<List<AiMessage>> asked;

  setUp(() async {
    final file = await AiRepairBackups.file();
    if (file.existsSync()) file.deleteSync();
    await CacheManager().put(tokenKey, 'real');
    asked = [];
  });

  tearDown(() async {
    await CacheManager().delete(tokenKey);
    await CacheManager().delete(otherKey);
    await source.setVariable(null);
  });

  /// 試抓：開場拿原本的書源時跑 [opening]，拿改好的草稿（正文規則是
  /// [fixed]）時跑 [draft]，傳回的字放進請求紀錄（送給 AI 的那一段）。
  AiRepairSession session(
    List<String> replies, {
    Future<String> Function(BookSource candidate)? opening,
    Future<String> Function(BookSource candidate)? draft,
  }) {
    var next = 0;
    return AiRepairSession(
      source: BookSource.fromJson(source.toJson()),
      service: service,
      check: (candidate, _) async {
        final healthy = candidate.ruleContent?.content == fixed;
        return SourceCheckIsolateResult(
          stage: healthy ? 'done' : 'content',
          message: healthy ? '校驗成功' : '正文為空',
          isHealthy: healthy,
          updatedSourceJson: candidate.toJson(),
          logs: const [],
        );
      },
      probe: (candidate, _, {start}) async {
        final good = candidate.ruleContent?.content == fixed;
        final sent = await (good ? draft : opening)?.call(candidate) ?? '';
        return SourceProbeReport(
          logs: [
            (10, '︾開始解析搜尋頁'),
            if (good) (40, '︽正文頁解析完成 (內容長度: 3214)') else (-1, '❌ 正文為空'),
            if (good) (1000, '︽解析完成'),
          ],
          requests: ['$url/s?t=$sent'],
          contentUsable: good ? true : null,
        );
      },
      fetchPage: (_, _, _) async =>
          (lines: const <String>[], pages: const <LoggedPage>[]),
      recheckDelay: Duration.zero,
      ask: (messages, _) async {
        asked.add(List.of(messages));
        return fakeAiReply(replies[next++]);
      },
      apply: (_, _) async {},
      secrets: aiRepairSecretsOf,
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
  final submit = jsonEncode({
    'action': 'submit',
    'patch': <String, dynamic>{},
    'note': '好了',
  });
  final giveUp = jsonEncode({
    'action': 'give_up',
    'why': 'site_broken',
    'reason': '壞了',
  });

  test('a draft that is tested but not applied leaves the source variables '
      'alone', () async {
    String? seen;
    final s = session(
      [test_, giveUp],
      draft: (candidate) async {
        final key = candidate.ruleVariableCacheKey('token');
        seen = await CacheManager().get(key);
        await CacheManager().put(key, 'draft');
        return '';
      },
    );
    await s.start();

    expect(seen, 'real', reason: '草稿從正式書源的變數開始');
    expect(await CacheManager().get(tokenKey), 'real');
  });

  test('a repair that is applied takes the variables the draft changed, and '
      'keeps what the source stored meanwhile', () async {
    final s = session(
      [test_, submit],
      // 開場拿正式書源試抓時寫的，套用時不被草稿開始時抄的舊值蓋回去。
      opening: (original) async {
        await CacheManager().put(original.ruleVariableCacheKey('token'), 'new');
        return '';
      },
      draft: (candidate) async {
        await CacheManager().put(
          candidate.ruleVariableCacheKey('other'),
          'draft',
        );
        return '';
      },
    );
    await s.start();

    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(await CacheManager().get(otherKey), 'draft');
    expect(await CacheManager().get(tokenKey), 'new');
  });

  // 規則 JS 在校驗草稿時寫的登入資料與登入標頭（含 Cookie）也留在草稿：沒
  // 採用時原書源的值不動、網站 Cookie 不被清。
  test('login data a discarded draft wrote stays out of the source', () async {
    addTearDown(() async {
      await CacheManager().delete(source.loginInfoCacheKey);
      await CacheManager().delete(source.loginHeaderCacheKey);
      await CookieStore().removeCookie(url);
    });
    await CacheManager().put(source.loginInfoCacheKey, '{"user":"real"}');
    await CacheManager().put(source.loginHeaderCacheKey, '{"X-Token":"real"}');
    await CookieStore().setCookie(url, 'sid=real');

    final s = session(
      [test_, giveUp],
      draft: (candidate) async {
        await candidate.putLoginInfo('{"user":"draft"}');
        await candidate.putLoginHeader(
          '{"Cookie":"sid=draft","X-Token":"draft"}',
        );
        return '';
      },
    );
    await s.start();

    expect(await source.getLoginInfo(), '{"user":"real"}');
    expect(await source.getLoginHeader(), '{"X-Token":"real"}');
    expect(await CookieStore().getCookie(url), 'sid=real');
  });

  test(
    'a repair that is applied takes the login data the draft wrote',
    () async {
      addTearDown(() async {
        await CacheManager().delete(source.loginInfoCacheKey);
        await CacheManager().delete(source.loginHeaderCacheKey);
        await CookieStore().removeCookie(url);
      });
      await CacheManager().put(
        source.loginHeaderCacheKey,
        '{"X-Token":"real"}',
      );
      await CookieStore().setCookie(url, 'sid=real');

      final s = session(
        [test_, submit],
        draft: (candidate) async {
          await candidate.putLoginInfo('{"user":"draft"}');
          await candidate.putLoginHeader(
            '{"Cookie":"sid=draft","X-Token":"draft"}',
          );
          return '';
        },
      );
      await s.start();

      expect(s.job.outcome, AiRepairOutcome.repaired);
      expect(await source.getLoginInfo(), '{"user":"draft"}');
      expect(
        await source.getLoginHeader(),
        '{"Cookie":"sid=draft","X-Token":"draft"}',
      );
      expect(await CookieStore().getCookie(url), contains('sid=draft'));
    },
  );

  test('a secret the draft stored is hidden from the AI', () async {
    const secret = 'draft-only-token-123456';
    final s = session(
      [test_, giveUp],
      draft: (candidate) async {
        await candidate.setVariable(secret);
        return secret;
      },
    );
    await s.start();

    final sent = [
      for (final round in asked)
        for (final message in round) message.content,
    ].join('\n');
    expect(sent, isNot(contains(secret)));
    expect(sent, contains(aiRepairRedacted));
  });
}
