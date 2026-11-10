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

const _discoveryBroken = SourceRuntimeHealth(
  category: SourceHealthCategory.discoveryBroken,
  label: '發現失效',
  description: '',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
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
    List<String>? fetched,
    SourceCheckIsolateResult? Function(BookSource source)? check,
  }) {
    var next = 0;
    return AiRepairSession(
      sources: sources,
      service: clipboard ? null : _service,
      check: (source, _) async => timesOut.contains(source.bookSourceUrl)
          ? null
          : check?.call(source) ??
                _checked(source, broken: broken[source.bookSourceUrl]),
      probe: (source, _) async => _probe(source),
      fetchPage: (source, url, _) async {
        fetched?.add(url);
        return '  ← $url 200：<form action="/s2">';
      },
      recheckDelay: Duration.zero,
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

  test('a test that reaches the text goes straight to the check, which lets '
      'it in', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test')],
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
        ('第 1 輪', 'AI 改了正文，試抓：正文 3214 字，交出'),
        ('校驗修好的書源', '沒有問題'),
      ],
    );
    expect(applied.single.bookSourceUrl, 'https://site.example');
    expect(applied.single.ruleContent?.content, 'class.txt@text');
    expect(applied.single.bookSourceGroup, isNull, reason: '校驗通過，標記拿掉');
  });

  test('the conversation keeps every earlier round word for word and only '
      'grows at the end', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        _command('test', content: 'class.a@text'),
        _command('test', content: 'class.b@text'),
        _command('test'),
      ],
    );

    await s.start();

    final second = asked[1];
    final third = asked[2];
    expect(third.take(second.length), second, reason: '前面的訊息原樣留著');
    expect(third[2].content, contains('class.a@text'));
    expect(third[3].content, contains('<div class="txt">'));
    expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
  });

  test('when the check fails the AI is told why and keeps going; nothing is '
      'saved until a check passes', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        _command('submit', content: 'class.wrong@text'),
        _command('submit'),
      ],
    );

    await s.start();

    expect(asked[1].last.content, startsWith('# 書源校驗沒過：正文失效：正文為空'));
    expect(asked[1].last.content, contains('[正文] 正文為空'));
    expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
    expect(applied.single.ruleContent?.content, 'class.txt@text');
  });

  test('a check that fails on the last try leaves the source alone', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        for (var i = 0; i < aiRepairMaxTests; i++)
          _command('submit', content: 'class.wrong$i@text'),
      ],
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.outcome, AiRepairOutcome.failed);
    expect(job.steps.last.state, AiRepairStepState.failed);
    expect(job.explanation, '校驗：正文失效：正文為空\nAI：正文在 div.txt');
    expect(applied, isEmpty);
  });

  test('an empty reply is asked again instead of ending the repair', () async {
    var calls = 0;
    final s = AiRepairSession(
      sources: [_source('https://site.example')],
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _) async => _probe(source),
      ask: (messages, _) async {
        asked.add(List.of(messages));
        if (calls++ == 0) throw const AiEmptyReply();
        return _command('test');
      },
      apply: (source, _) async => applied.add(source),
      secrets: (_) async => const {},
      backups: backups,
    );

    await s.start();

    expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
    expect(asked[1], asked[0], reason: '同樣的話再問一次');
  });

  test(
    'giving up before trying anything is sent back once; giving up again and '
    'running out of replies both leave the source alone',
    () async {
      final giveUp = jsonEncode({'action': 'give_up', 'reason': '網站要付費'});
      final gaveUp = session(
        [_source('https://a.example')],
        replies: [giveUp, giveUp],
      );
      await gaveUp.start();
      expect(asked, hasLength(2));
      expect(asked.last.last.content, startsWith(aiRepairTryFirst));
      expect(gaveUp.jobs.single.explanation, 'AI：網站要付費');

      final talky = session([
        _source('https://b.example'),
      ], replies: List.filled(aiRepairMaxReplies, '我再想想'));
      await talky.start();
      expect(talky.jobs.single.outcome, AiRepairOutcome.failed);
      expect(
        talky.jobs.single.steps.where((s) => s.title.startsWith('第')),
        hasLength(aiRepairMaxReplies),
      );
      expect(applied, isEmpty);
    },
  );

  test('when the tests run out the AI gets a fresh second try that is told '
      'what was tried', () async {
    String wrong(int i) => jsonEncode({
      'action': 'test',
      'patch': {
        'ruleContent': {'content': 'class.w$i@text'},
      },
      'note': '試法 $i',
    });
    final s = session(
      [_source('https://site.example')],
      replies: [
        for (var i = 0; i < aiRepairMaxTests; i++) wrong(i),
        _command('test'),
      ],
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.outcome, AiRepairOutcome.repaired);
    expect(job.steps.map((step) => step.title), contains('重新來一次'));
    final secondOpening = asked.last[1].content;
    expect(secondOpening, contains('# 上一回沒修好，試過這些'));
    expect(secondOpening, contains('試法 0（AI 改了正文） → 試抓：發生錯誤: 正文為空'));
    expect(asked.last, hasLength(2), reason: '第二回從頭開始');
  });

  test(
    'looking at pages does not use up the tests, and patches add up',
    () async {
      final fetched = <String>[];
      final s = session(
        [_source('https://site.example')],
        fetched: fetched,
        replies: [
          for (var i = 0; i < aiRepairMaxFetches; i++)
            jsonEncode({'action': 'fetch', 'url': '/p$i'}),
          jsonEncode({'action': 'fetch', 'url': '/one-too-many'}),
          jsonEncode({
            'action': 'test',
            'patch': {'searchUrl': '/s2?q={{key}}'},
          }),
          jsonEncode({
            'action': 'test',
            'patch': {
              'ruleContent': {'content': 'class.txt@text'},
            },
          }),
        ],
      );

      await s.start();

      expect(fetched, [for (var i = 0; i < aiRepairMaxFetches; i++) '/p$i']);
      expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
      expect(applied.single.searchUrl, '/s2?q={{key}}', reason: '前一次的改動留著');
      expect(applied.single.ruleContent?.content, 'class.txt@text');
    },
  );

  test('a fix whose test reached the text is checked once more after a '
      'pause when the first check fails', () async {
    var checks = 0;
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test')],
      check: (source) =>
          source.ruleContent?.content == 'class.txt@text' && ++checks == 1
          ? _checked(source, broken: _contentBroken)
          : null,
    );

    await s.start();

    expect(checks, 2);
    expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
  });

  test('a fix is kept when only discovery still fails and the AI did not '
      'touch discovery', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test')],
      check: (source) => source.ruleContent?.content == 'class.txt@text'
          ? _checked(source, broken: _discoveryBroken)
          : null,
    );

    await s.start();

    expect(s.jobs.single.outcome, AiRepairOutcome.repaired);
    expect(applied.single.ruleContent?.content, 'class.txt@text');
  });

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

    final sent = [for (final message in asked.first) message.content]
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
        jsonEncode({'action': 'give_up', 'reason': '不修'}),
      ],
    );

    await s.start();

    final job = s.jobs.single;
    expect(job.outcome, AiRepairOutcome.failed);
    expect(asked, hasLength(3), reason: '讀不懂一次、放棄被退回一次、再放棄');
    expect(asked[1].last.content, startsWith(aiRepairBadReply));
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
