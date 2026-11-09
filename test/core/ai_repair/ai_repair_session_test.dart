import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'sk-test',
  model: 'm',
);

BookSource _source(String url, {String content = 'id.old@text'}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: url.split('//').last,
  searchUrl: '/s?q={{key}}',
  ruleContent: ContentRule(content: content),
);

/// 校驗：正文規則是 `class.txt@text` 的才算沒問題；[broken] 裡的網址照它
/// 給的狀態失敗。
SourceCheckIsolateResult _checked(
  BookSource source, {
  SourceRuntimeHealth? broken,
}) {
  final healthy =
      broken == null && source.ruleContent?.content == 'class.txt@text';
  final copy = BookSource.fromJson(source.toJson())
    ..addHealthGroups(
      broken ?? (healthy ? SourceRuntimeHealth.healthy : _contentBroken),
    );
  return SourceCheckIsolateResult(
    stage: healthy ? 'done' : 'content',
    message: healthy ? '校驗成功' : '正文為空',
    isHealthy: healthy,
    updatedSourceJson: copy.toJson(),
    logs: const [],
    diagnostics: const ['[正文] 正文為空'],
  );
}

const _contentBroken = SourceRuntimeHealth(
  category: SourceHealthCategory.contentBroken,
  label: '正文失效',
  description: '',
  allowsSearch: true,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

const _loginRequired = SourceRuntimeHealth(
  category: SourceHealthCategory.loginRequired,
  label: '需要登入',
  description: '',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

SourceProbeReport _probe(BookSource source) =>
    source.ruleContent?.content == 'class.txt@text'
    ? const SourceProbeReport(
        logs: [
          (10, '︾開始解析搜尋頁'),
          (40, '︽正文頁解析完成 (內容長度: 3214)'),
          (1000, '︽解析完成'),
        ],
        requests: ['  ← https://site.example/c/1 200：<div class="txt">…'],
      )
    : const SourceProbeReport(
        logs: [(10, '︾開始解析搜尋頁'), (40, '︾開始解析正文頁'), (-1, '❌ 發生錯誤: 正文為空')],
        requests: ['  ← https://site.example/c/1 200：<div class="txt">…'],
      );

String _command(String action, {String content = 'class.txt@text'}) =>
    jsonEncode({
      'action': action,
      'source': {
        'bookSourceUrl': 'whatever',
        'searchUrl': '/s?q={{key}}',
        'ruleContent': {'content': content},
      },
      'note': '正文在 div.txt',
    });

void main() {
  late AiRepairBackups backups;
  late List<BookSource> applied;
  late List<List<AiMessage>> asked;

  // 改前版本存在全域的假 App 資料夾（test/flutter_test_config.dart），同一個
  // 測試檔共用，每項測試前清掉。
  setUp(() async {
    final file = await AiRepairBackups.file();
    if (file.existsSync()) file.deleteSync();
    backups = AiRepairBackups();
    applied = [];
    asked = [];
  });

  AiRepairSession session(
    List<BookSource> sources, {
    required List<String> replies,
    Map<String, SourceRuntimeHealth> broken = const {},
    bool clipboard = false,
    List<String>? copied,
    Set<String> secretValues = const {},
    Set<String> timesOut = const {},
  }) {
    var next = 0;
    return AiRepairSession(
      sources: sources,
      service: clipboard ? null : _service,
      check: (source, _) async => timesOut.contains(source.bookSourceUrl)
          ? null
          : _checked(source, broken: broken[source.bookSourceUrl]),
      probe: (source, _) async => _probe(source),
      ask: (messages, _) async {
        asked.add(List.of(messages));
        return replies[next++];
      },
      apply: (source, _) async => applied.add(source),
      secrets: (_) async => secretValues,
      copy: (text) async => copied?.add(text),
      backups: backups,
    );
  }

  test('the AI tests a fix, submits it, and the check lets it in', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test'), _command('submit')],
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.outcome, AiRepairOutcome.repaired);
    expect(job.explanation, 'AI：正文在 div.txt');
    expect(
      [for (final step in job.steps) (step.title, step.detail)],
      [
        ('校驗原本的書源', '正文失效：正文為空'),
        ('抓網頁', '搜尋、正文，共 1 頁'),
        ('第 1 輪', 'AI 改了正文，試抓：正文 3214 字'),
        ('第 2 輪', 'AI 改了正文，交出'),
        ('校驗修好的書源', '沒有問題'),
      ],
    );
    expect(applied.single.bookSourceUrl, 'https://site.example');
    expect(applied.single.ruleContent?.content, 'class.txt@text');
    expect(applied.single.bookSourceGroup, isNull, reason: '校驗通過，標記拿掉');
  });

  test(
    'earlier rounds shrink to a line so the conversation stays short',
    () async {
      final s = session(
        [_source('https://site.example')],
        replies: [
          _command('test', content: 'class.a@text'),
          _command('test'),
          _command('submit'),
        ],
      );

      await s.start();

      final third = asked[2];
      final firstReply = third[2];
      expect(firstReply.role, 'assistant');
      expect(firstReply.content, contains('（書源省略）'));
      expect(firstReply.content, isNot(contains('class.a@text')));
      expect(third[3].content, '# 試抓結果：發生錯誤: 正文為空（網頁內容省略）');
      expect(third.last.content, contains('<div class="txt">'));
    },
  );

  test('when the check still fails nothing is saved', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('submit', content: 'class.wrong@text')],
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.outcome, AiRepairOutcome.failed);
    expect(job.steps.last.state, AiRepairStepState.failed);
    expect(job.explanation, '校驗：正文失效：正文為空\nAI：正文在 div.txt');
    expect(applied, isEmpty);
  });

  test(
    'giving up and running out of rounds both leave the source alone',
    () async {
      final gaveUp = session(
        [_source('https://a.example')],
        replies: [
          jsonEncode({'action': 'give_up', 'reason': '網站要付費'}),
        ],
      );
      await gaveUp.start();
      expect(gaveUp.jobs.single.explanation, 'AI：網站要付費');

      final talky = session([
        _source('https://b.example'),
      ], replies: List.filled(aiRepairMaxRounds, '我再想想'));
      await talky.start();
      expect(talky.jobs.single.outcome, AiRepairOutcome.failed);
      expect(
        talky.jobs.single.steps.where((s) => s.title.startsWith('第')),
        hasLength(aiRepairMaxRounds),
      );
      expect(applied, isEmpty);
    },
  );

  test(
    'a batch skips healthy and unfixable sources without asking the AI',
    () async {
      final s = session(
        [
          _source('https://ok.example', content: 'class.txt@text'),
          _source('https://login.example'),
          _source('https://broken.example'),
        ],
        broken: {'https://login.example': _loginRequired},
        replies: [_command('submit')],
      );

      await s.start();

      expect(
        [for (final job in s.jobs) job.outcome],
        [
          AiRepairOutcome.skipped,
          AiRepairOutcome.skipped,
          AiRepairOutcome.repaired,
        ],
      );
      expect(s.jobs[1].steps.single.detail, '跳過：需要登入');
      expect(asked, hasLength(1));
      expect(s.count(AiRepairOutcome.repaired), 1);
    },
  );

  test(
    'the clipboard copies a prompt and validates what is pasted back',
    () async {
      final copied = <String>[];
      final s = session(
        [_source('https://site.example')],
        replies: const [],
        clipboard: true,
        copied: copied,
      );

      await s.start();
      final job = s.jobs.single;
      expect(job.awaitingPaste, isTrue);
      expect(s.isFinished, isFalse);
      expect(copied.single, contains('id.old@text'));
      expect(copied.single, contains('<div class="txt">'));

      expect(await s.submitPaste('不是 JSON'), '讀不出書源 JSON');
      expect(job.awaitingPaste, isTrue);

      await s.submitPaste(
        '```json\n${jsonEncode({
          'bookSourceUrl': 'https://site.example',
          'ruleContent': {'content': 'class.txt@text'},
        })}\n```',
      );
      expect(job.outcome, AiRepairOutcome.repaired);
      expect(applied.single.ruleContent?.content, 'class.txt@text');
      expect(asked, isEmpty);
    },
  );

  test('login data, cookies and variables that show up in the fetched pages '
      'are blanked out of what goes to the AI and the clipboard', () async {
    const secret = 'token-1234567';
    final leaky = _source('https://site.example');
    final probe = SourceProbeReport(
      logs: const [(10, '︾開始解析搜尋頁')],
      requests: ['  → https://site.example/s?q=x&token=$secret'],
    );
    final copied = <String>[];
    for (final clipboard in [false, true]) {
      final s = AiRepairSession(
        sources: [leaky],
        service: clipboard ? null : _service,
        check: (source, _) async => _checked(source),
        probe: (_, _) async => probe,
        ask: (messages, _) async {
          asked.add(List.of(messages));
          return jsonEncode({'action': 'give_up', 'reason': '不修'});
        },
        apply: (source, _) async => applied.add(source),
        copy: (text) async => copied.add(text),
        secrets: (_) async => {secret},
        backups: backups,
      );
      await s.start();
      expect(s.transcript, isNot(contains(secret)));
    }

    final sent = [for (final message in asked.single) message.content]
        .join('\n');
    expect(sent, isNot(contains(secret)));
    expect(sent, contains('token=«已遮蔽»'));
    expect(copied.single, isNot(contains(secret)));
  });

  test('a batch skips a source whose check runs out of time, without asking '
      'the AI', () async {
    final s = session(
      [_source('https://a.example'), _source('https://b.example')],
      replies: const [],
      timesOut: {'https://a.example', 'https://b.example'},
    );

    await s.start();

    expect(s.count(AiRepairOutcome.skipped), 2);
    expect(asked, isEmpty);
  });

  test('a source the AI writes with an impossible number is treated as an '
      'unreadable reply, not a crash', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        '{"action":"submit","source":{"bookSourceType":1e400},"note":""}',
        jsonEncode({'action': 'give_up', 'reason': '不修'}),
      ],
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.outcome, AiRepairOutcome.failed);
    expect(asked, hasLength(2));
    expect(asked.last.last.content, aiRepairBadReply);
    expect(s.isRunning, isFalse);
    expect(applied, isEmpty);
  });

  test('stopping while the fixed source is being saved reports what was '
      'saved', () async {
    late AiRepairSession s;
    s = AiRepairSession(
      sources: [_source('https://site.example')],
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _) async => _probe(source),
      ask: (_, _) async => _command('submit'),
      apply: (source, _) async {
        s.stop();
        applied.add(source);
      },
      secrets: (_) async => const {},
      backups: backups,
    );

    await s.start();

    expect(applied, hasLength(1));
    expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
  });

  test('a fix is not saved over a source that changed or was deleted while '
      'the AI worked on it', () async {
    for (final conflict in ['修的這段時間書源被改過了（例如同步），沒有存。', '修的這段時間書源被刪掉了，沒有存。']) {
      final s = AiRepairSession(
        sources: [_source('https://site.example')],
        service: _service,
        check: (source, _) async => _checked(source),
        probe: (source, _) async => _probe(source),
        ask: (_, _) async => _command('submit'),
        apply: (_, _) async => throw AiRepairConflict(conflict),
        secrets: (_) async => const {},
        backups: backups,
      );

      await s.start();

      expect(s.jobs.single.outcome, AiRepairOutcome.failed);
      expect(s.jobs.single.explanation, conflict);
    }
  });

  test('an over-long paste is refused and the paste card stays', () async {
    final s = session(
      [_source('https://site.example')],
      replies: const [],
      clipboard: true,
      copied: [],
    );
    await s.start();

    expect(await s.submitPaste('{' * (aiRepairMaxReplyLength + 1)), '貼回的內容太長');
    expect(s.jobs.single.awaitingPaste, isTrue);
    expect(
      await s.submitPaste('{"bookSourceUrl":"x","bookSourceType":1e400}'),
      '讀不出書源 JSON',
    );
    expect(s.jobs.single.awaitingPaste, isTrue);
  });

  test('stopping marks the running step and changes nothing', () async {
    late AiRepairSession s;
    s = AiRepairSession(
      sources: [_source('https://site.example')],
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _) async => _probe(source),
      ask: (_, cancelToken) async {
        s.stop();
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: cancelToken.cancelError,
        );
      },
      apply: (source, _) async => applied.add(source),
      secrets: (_) async => const {},
      backups: backups,
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.steps.last.detail, '已停止');
    expect(job.steps.last.state, AiRepairStepState.failed);
    expect(job.outcome, AiRepairOutcome.failed);
    expect(applied, isEmpty);
  });

  test(
    'previous versions survive a reload and follow deleted sources out',
    () async {
      await backups.put('https://a.example', {
        'bookSourceUrl': 'https://a.example',
      });
      await backups.put('https://b.example', {
        'bookSourceUrl': 'https://b.example',
      });

      final reloaded = AiRepairBackups();
      expect(await reloaded.urls(), {'https://a.example', 'https://b.example'});

      await reloaded.keepOnly({'https://b.example'});
      expect(await AiRepairBackups().urls(), {'https://b.example'});
      await reloaded.remove('https://b.example');
      expect((await AiRepairBackups.file()).existsSync(), isFalse);
    },
  );
}
