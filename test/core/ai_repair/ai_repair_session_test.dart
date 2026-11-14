import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';

import '../../support/fake_ai.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'sk-test',
  model: 'm',
  effort: '',
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
  List<String> diagnostics = const ['[正文] 正文為空'],
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
    diagnostics: diagnostics,
  );
}

/// 發現頁那一段的診斷：網站回了 [response] 那一行。
List<String> _discoveryDiagnostics(String response) => [
  '[發現] 發現頁沒有結果\n這一段的請求與回應:\nhttps://site.example/all\n$response',
];

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

SourceProbeReport _probe(BookSource source) =>
    source.ruleContent?.content == 'class.txt@text'
    ? const SourceProbeReport(
        logs: [
          (10, '︾開始解析搜尋頁'),
          (40, '︽正文頁解析完成 (內容長度: 3214)'),
          (1000, '︽解析完成'),
        ],
        requests: ['  ← https://site.example/c/1 200：<div class="txt">…'],
        contentUsable: true,
      )
    : const SourceProbeReport(
        logs: [(10, '︾開始解析搜尋頁'), (40, '︾開始解析正文頁'), (-1, '❌ 發生錯誤: 正文為空')],
        requests: ['  ← https://site.example/c/1 200：<div class="txt">…'],
      );

String _command(String action, {String content = 'class.txt@text'}) =>
    jsonEncode({
      'action': action,
      'patch': {
        'searchUrl': '/s?q={{key}}',
        'ruleContent': {'content': content},
      },
      'note': '正文在 div.txt',
    });

/// 試抓過之後照原樣交出（試抓不會交出，AI 看過結果自己 submit）。
final _submitTested = jsonEncode({
  'action': 'submit',
  'patch': <String, dynamic>{},
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
    Future<Set<String>> Function(BookSource source)? secrets,
    Set<String> timesOut = const {},
    List<String>? fetched,
    SourceCheckIsolateResult? Function(BookSource source)? check,
    bool Function(BookSource source)? followsKeyword,
    List<String>? keywordChecked,
    List<String>? checked,
    AiRepairPriorCheck? priorCheck,
    Directory? logs,
    SourceProbeReport Function(BookSource source)? probe,
    String Function(String url)? fetchStatus,
  }) {
    var next = 0;
    return AiRepairSession(
      logDirectory: logs == null ? null : () async => logs,
      priorCheck: priorCheck,
      source: sources.single,
      service: clipboard ? null : _service,
      check: (source, _) async {
        checked?.add(source.ruleContent?.content ?? '');
        return timesOut.contains(source.bookSourceUrl)
            ? null
            : check?.call(source) ??
                  _checked(source, broken: broken[source.bookSourceUrl]);
      },
      probe: (source, _, {start}) async => (probe ?? _probe)(source),
      keywordCheck: (source, _) async {
        keywordChecked?.add(source.ruleContent?.content ?? '');
        return followsKeyword?.call(source) ?? true;
      },
      fetchPage: (source, url, _) async {
        fetched?.add(url);
        final status = fetchStatus?.call(url) ?? '200';
        // 請求那一行照請求紀錄的寫法：POST 寫方法與送出的內容，回應那一行
        // 只有網址。
        final [address, ...rest] = url.split(',{');
        final options = rest.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode('{${rest.join(',{')}') as Map<String, dynamic>;
        final request = options['method'] == 'POST'
            ? 'POST $address 送出：${options['body']} 標頭：User-Agent: t'
            : '$address 標頭：User-Agent: t';
        return (
          lines: [request, '  ← $address $status：<form action="/s2">'],
          pages: [
            (
              line: '  ← $address $status：<form action="/s2">',
              body: '<html><form action="/s2"></html>',
            ),
          ],
        );
      },
      recheckDelay: Duration.zero,
      ask: (messages, _) async {
        asked.add(List.of(messages));
        // 回覆用完：測試寫錯了，不讓它一直問下去。
        if (next >= replies.length) throw StateError('沒有更多回覆');
        return fakeAiReply(replies[next++]);
      },
      apply: (source, _) async => applied.add(source),
      secrets: secrets ?? (_) async => secretValues,
      copy: (text) async => copied?.add(text),
      backups: backups,
    );
  }

  test('the same request answering now and then is said so after the '
      'result', () async {
    // 2026-11-14 白光小说：同一個搜尋一下 200、一下 502，AI 每次成功就接著
    // 修別段，36 輪用完；思怡、读客书库同樣。程式把這件修復裡同一個請求
    // 回過的狀態碼列在結果後面，AI 不用自己記。
    final statuses = ['200', '502', '502'];
    var call = 0;
    final s = session(
      [_source('https://site.example')],
      fetchStatus: (_) => statuses[call++],
      replies: [
        for (var i = 0; i < 3; i++)
          jsonEncode({
            'action': 'fetch',
            'url': 'https://site.example/s',
            'note': '第 $i 次',
          }),
        jsonEncode({
          'action': 'give_up',
          'why': 'rate_limited',
          'reason': '時好時壞',
        }),
      ],
    );

    await s.start();

    String result(int i) => asked[i + 1].last.content;
    expect(result(0), isNot(contains('同一個請求這次回過不同的結果')));
    expect(
      result(1),
      contains('# 同一個請求這次回過不同的結果\nhttps://site.example/s：200、502'),
    );
    expect(result(2), contains('https://site.example/s：200、502、502'));
  });

  test('two different requests to one address are not called flaky', () async {
    // 2026-11-14 白光小说：POST /search/ 只帶 keyword 回 502，多帶 submit 就
    // 301 到結果頁。原本只看網址，把兩個不同的請求標成時好時壞，誤導 AI 放棄
    // 一個修得好的書源。
    final statuses = ['502', '301', '502'];
    var call = 0;
    final s = session(
      [_source('https://site.example')],
      fetchStatus: (_) => statuses[call++],
      replies: [
        for (final body in ['q=1', 'q=1&submit=1', 'q=1'])
          jsonEncode({
            'action': 'fetch',
            'url': 'https://site.example/s,{"method":"POST","body":"$body"}',
            'note': body,
          }),
        jsonEncode({'action': 'give_up', 'why': 'site_broken', 'reason': '測試'}),
      ],
    );

    await s.start();

    for (var i = 0; i < 3; i++) {
      expect(asked[i + 1].last.content, isNot(contains('這次回過不同的結果')));
    }
  });

  test('a hand-in that changes no rule is not called fixed', () async {
    // 2026-11-13 品书楼：AI 查過每一段都沒問題，原本照樣寫「修好了」。
    final s = session(
      [_source('https://site.example', content: 'class.txt@text')],
      replies: [
        jsonEncode({
          'action': 'submit',
          'patch': <String, dynamic>{},
          'note': '每一段都正常',
        }),
      ],
    );

    await s.start();

    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(s.job.explanation, 'AI 查過，沒有要改的規則\nAI：每一段都正常');
    expect(s.log.summary, contains('AI 查過，沒有要改的規則；重新校驗沒有問題'));
  });

  test(
    'a test whose search name differs from the detail page says so',
    () async {
      // 2026-11-13 肉肉屋#3：20 本都叫「目录」，試抓與校驗都過，AI 沒有下一輪。
      final s = session(
        [_source('https://site.example')],
        replies: [_command('test'), _submitTested],
        probe: (_) => const SourceProbeReport(
          logs: [
            (10, '︽搜尋頁解析完成，獲取到 20 本書籍'),
            (10, '  [0] 目录 - 连山会'),
            (20, '︽詳情頁解析完成: 《救命！》'),
            (20, '  作者: 连山会, 目錄: https://site.example/index/1'),
            (40, '︽正文頁解析完成 (內容長度: 3214)'),
            (1000, '︽解析完成'),
          ],
          requests: [],
          contentUsable: true,
        ),
      );

      await s.start();

      expect(asked, hasLength(2));
      expect(
        asked.last.last.content,
        contains('# 書名或作者對不上：搜尋結果第一本進了詳情頁，書名搜尋是「目录」、詳情頁是「《救命！》」'),
      );
      expect(s.job.outcome, AiRepairOutcome.repaired);
      expect(applied, hasLength(1));
    },
  );

  test('a test that reaches the text goes back to the AI; its hand-in goes '
      'to the check, which lets it in', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test'), _submitTested],
    );

    await s.start();

    final job = s.job;
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

  test('the conversation keeps every earlier round word for word and only '
      'grows at the end', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        _command('test', content: 'class.a@text'),
        _command('test', content: 'class.b@text'),
        _command('test'),
        _submitTested,
      ],
    );

    await s.start();

    final second = asked[1];
    final third = asked[2];
    expect(third.take(second.length), second, reason: '前面的訊息原樣留著');
    expect(third[2].toolCalls.single.arguments, contains('class.a@text'));
    expect(third[3].content, contains('<div class="txt">'));
    expect(s.job.outcome, AiRepairOutcome.repaired);
  });

  test(
    'the full log holds every message sent to the AI word for word, each '
    'once, and the raw pages; the summary holds each round in short',
    () async {
      final logs = Directory.systemTemp.createTempSync('ai-repair-log');
      addTearDown(() => logs.deleteSync(recursive: true));
      const raw =
          '<html><head><script>location="https://ads.example"</script>'
          '</head><body><div class="txt">正文</div></body></html>';
      final replies = [
        jsonEncode({'action': 'fetch', 'url': '/', 'note': '看首頁'}),
        _command('test'),
        _submitTested,
      ];
      var next = 0;
      final s = AiRepairSession(
        source: _source('https://site.example'),
        service: _service,
        check: (source, _) async => _checked(source),
        probe: (source, _, {start}) async => SourceProbeReport(
          logs: _probe(source).logs,
          requests: _probe(source).requests,
          pages: [(line: _probe(source).requests.single, body: raw)],
          contentUsable: _probe(source).contentUsable,
        ),
        keywordCheck: (_, _) async => true,
        fetchPage: (_, url, _) async => (
          lines: ['  ← $url 200：<form action="/s2">'],
          pages: [
            (
              line: '  ← $url 200：<form action="/s2">',
              body: '<html>首頁原文</html>',
            ),
          ],
        ),
        recheckDelay: Duration.zero,
        ask: (messages, _) async {
          asked.add(List.of(messages));
          return fakeAiReply(replies[next++]);
        },
        apply: (source, _) async => applied.add(source),
        secrets: (_) async => const {},
        backups: backups,
        logDirectory: () async => logs,
      );

      await s.start();

      expect(s.job.outcome, AiRepairOutcome.repaired);
      final full = (await s.log.file())!.readAsStringSync();
      // 每一句話與每個工具呼叫的參數都照原樣、只寫一次。
      final conversation = [
        for (final message in [
          ...asked.last,
          AiMessage.assistant(
            '',
            toolCalls: fakeAiReply(replies.last).toolCalls,
          ),
        ]) ...[
          if (message.content.isNotEmpty) (message.role, message.content),
          for (final call in message.toolCalls) (message.role, call.arguments),
        ],
      ];
      for (final (role, text) in conversation) {
        expect(text.allMatches(full).length, 1, reason: '$role 的話照原樣、只寫一次');
      }
      expect(full, contains(raw), reason: '網頁原文不精簡、不截');
      expect(full, contains('<html>首頁原文</html>'));
      final summary = s.log.summary;
      expect(summary, contains('## 第 1 輪'));
      expect(summary, contains('看網頁 /'));
      expect(summary, contains('## 第 2 輪'));
      expect(summary, contains('AI 改了正文，試抓'));
      expect(summary, contains('## 結果'));
      expect(summary, isNot(contains(raw)));
      expect(
        summary,
        isNot(contains(asked.first.first.content)),
        reason: '提示詞不進摘要',
      );
    },
  );

  test('pages carry numbers; read, find, parse and js work on them without '
      'fetching, and a test can start from the table of contents', () async {
    const tocPage = '<div class="list"><a href="/c/1">第一章</a></div>';
    final parsed = <(String, String, String?)>[];
    final ran = <(String, Map<int, String>)>[];
    final starts = <String?>[];
    final replies = [
      jsonEncode({'action': 'read', 'page': 1, 'raw': true}),
      jsonEncode({'action': 'find', 'page': 1, 'text': '第一章'}),
      jsonEncode({
        'action': 'parse',
        'page': 1,
        'as': 'toc',
        'patch': {
          'ruleToc': {'chapterList': '.list a'},
        },
      }),
      jsonEncode({'action': 'read', 'page': 9}),
      jsonEncode({'action': 'js', 'code': 'page(1).length'}),
      jsonEncode({
        'action': 'test',
        'from': 'toc',
        'url': 'https://site.example/book/1/',
        'patch': {
          'ruleContent': {'content': 'class.txt@text'},
        },
      }),
      _submitTested,
    ];
    var next = 0;
    final s = AiRepairSession(
      source: _source('https://site.example'),
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _, {start}) async {
        starts.add(start);
        final report = _probe(source);
        return SourceProbeReport(
          logs: report.logs,
          requests: report.requests,
          pages: [(line: report.requests.single, body: tocPage)],
          contentUsable: report.contentUsable,
        );
      },
      keywordCheck: (_, _) async => true,
      parsePage: (source, stage, page, _) async {
        parsed.add((stage, page.body, source.ruleToc?.chapterList));
        return '解析成目錄頁：1 章';
      },
      runJs: (_, code, pages, _) async {
        ran.add((code, pages));
        return '傳回：${pages[1]!.length}';
      },
      recheckDelay: Duration.zero,
      ask: (messages, _) async {
        asked.add(List.of(messages));
        return fakeAiReply(replies[next++]);
      },
      apply: (source, _) async => applied.add(source),
      secrets: (_) async => const {},
      backups: backups,
    );

    await s.start();

    expect(asked.first[1].content, contains('← 頁 1｜https://site.example/c/1'));
    String answer(int round) => asked[round].last.content;
    expect(answer(1), contains(tocPage), reason: '讀頁給原文');
    expect(answer(2), contains('div.list > a'));
    expect(parsed.single, ('toc', tocPage, '.list a'));
    expect(answer(3), contains('解析成目錄頁：1 章'));
    expect(answer(4), startsWith('# 沒有頁 9'));
    expect(ran.single.$1, 'page(1).length');
    expect(ran.single.$2, {1: tocPage}, reason: '只送程式用到的那頁');
    expect(answer(5), contains('傳回：${tocPage.length}'));
    expect(starts, [null, '++https://site.example/book/1/']);
    expect(s.job.outcome, AiRepairOutcome.repaired);
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
    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(applied.single.ruleContent?.content, 'class.txt@text');
  });

  test('a failing check goes back to the AI; giving up after trying marks it '
      'not fixable', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        for (var i = 0; i < 4; i++)
          _command('submit', content: 'class.wrong$i@text'),
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '正文要付費'}),
      ],
    );

    await s.start();

    final job = s.job;
    expect(asked, hasLength(5));
    expect(asked[1].last.content, startsWith('# 書源校驗沒過'));
    expect(job.outcome, AiRepairOutcome.failed);
    expect(job.explanation, 'AI：要付費。正文要付費');
    expect(job.confirmedUnfixable, isTrue);
    expect(applied, isEmpty);
  });

  test('a hand-in whose check times out goes back to the AI', () async {
    final s = session(
      [_source('https://site.example')],
      timesOut: {'https://site.example'},
      replies: [
        _command('submit', content: 'class.again@text'),
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '網站太慢'}),
      ],
    );

    await s.start();

    expect(asked[1].last.content, contains('校驗超過時間'));
    expect(s.job.outcome, AiRepairOutcome.failed);
  });

  test(
    'an unexpected error ends as not fixed instead of a spinning step',
    () async {
      final s = AiRepairSession(
        source: _source('https://site.example'),
        service: _service,
        check: (_, _) async => throw StateError('isolate 掛了'),
        probe: (source, _, {start}) async => _probe(source),
        keywordCheck: (_, _) async => true,
        ask: (_, _) async => fakeAiReply(_submitTested),
        apply: (source, _) async => applied.add(source),
        secrets: (_) async => const {},
        backups: backups,
      );

      await s.start();

      expect(s.job.outcome, AiRepairOutcome.failed);
      expect(s.job.explanation, contains('isolate 掛了'));
      expect(s.job.steps.single.state, AiRepairStepState.failed);
      expect(s.isRunning, isFalse);
    },
  );

  test('an empty reply is asked again instead of ending the repair', () async {
    var calls = 0;
    final s = AiRepairSession(
      source: _source('https://site.example'),
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _, {start}) async => _probe(source),
      keywordCheck: (_, _) async => true,
      ask: (messages, _) async {
        asked.add(List.of(messages));
        final call = calls++;
        if (call == 0) throw const AiEmptyReply();
        return fakeAiReply(call == 1 ? _command('test') : _submitTested);
      },
      apply: (source, _) async => applied.add(source),
      secrets: (_) async => const {},
      backups: backups,
    );

    await s.start();

    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(asked[1], asked[0], reason: '同樣的話再問一次');
  });

  test(
    'a secret that shows up only after a tool ran is hidden from then on',
    () async {
      // 審查：開始時讀到的秘密是快照，修到一半規則才寫進的 Cookie 或變數照樣
      // 要遮。這裡讓第二次讀秘密才多出一個值，網站回的頁面正好帶著它。
      const secret = 'late-session-987654';
      var reads = 0;
      final s = session(
        [_source('https://site.example')],
        replies: [
          jsonEncode({'action': 'fetch', 'url': '/s?t=$secret'}),
          _command('test'),
          _submitTested,
        ],
        secrets: (_) async => reads++ == 0 ? const {} : {secret},
      );

      await s.start();

      expect(asked[1].last.content, isNot(contains(secret)));
      expect(asked[1].last.content, contains('«已遮蔽»'));
    },
  );

  test('an AI going in circles stops as not finished, not as unfixable, with '
      'the stats line for the evaluation table', () async {
    final logs = Directory.systemTemp.createTempSync('ai-repair-log');
    addTearDown(() => logs.deleteSync(recursive: true));
    final look = jsonEncode({'action': 'fetch', 'url': '/s', 'note': '再看看'});
    final s = session(
      [_source('https://site.example')],
      replies: List.filled(AiAgentKnobs.sameCallLimit, look),
      logs: logs,
    );

    await s.start();

    final job = s.job;
    expect(asked, hasLength(AiAgentKnobs.sameCallLimit));
    expect(asked[2].last.content, contains('這是同樣參數的第 2 次，結果與前幾次相同'));
    expect(job.outcome, AiRepairOutcome.failed);
    expect(job.confirmedUnfixable, isFalse);
    expect(job.explanation, contains('同樣的工具與參數第 4 次'));
    expect(
      job.steps.where((step) => step.state == AiRepairStepState.running),
      isEmpty,
      reason: '審查：到了門檻直接結束，最後一輪不停在轉圈',
    );
    expect(s.log.summary, contains('無法確認'));
    final full = (await s.log.file())!.readAsStringSync();
    final stats = full
        .split('\n')
        .singleWhere((line) => line.startsWith(aiRepairStatsMarker));
    final map = jsonDecode(
      stats.substring(aiRepairStatsMarker.length),
    ) as Map<String, dynamic>;
    expect(map['end'], 'unconfirmed');
    expect(map['attempts'], AiAgentKnobs.attempts);
    expect(map['promptVersion'], aiRepairPromptVersion);
  });

  test('giving up because the site is gone is taken at once, without a '
      'try', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        jsonEncode({'action': 'give_up', 'why': 'site_gone', 'reason': '停放頁'}),
      ],
    );

    await s.start();

    expect(asked, hasLength(1));
    expect(s.job.explanation, 'AI：網站不在了。停放頁');
    expect(s.job.confirmedUnfixable, isTrue);
    // 評估表的「交件」欄照統計那一行的放棄原因寫。
    final stats = (await s.log.file())!.readAsLinesSync().singleWhere(
      (line) => line.startsWith(aiRepairStatsMarker),
    );
    final map = jsonDecode(
      stats.substring(aiRepairStatsMarker.length),
    ) as Map<String, dynamic>;
    expect(map['why'], 'site_gone');
    expect(map['reason'], '放棄被收下');
  });

  test('giving up is taken at once, even right after the opening', () async {
    final gaveUp = session(
      [_source('https://a.example')],
      replies: [
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '網站要付費'}),
      ],
    );
    await gaveUp.start();
    expect(asked, hasLength(1));
    expect(gaveUp.job.explanation, 'AI：要付費。網站要付費');
  });

  test('giving up after looking at the site is taken at once', () async {
    // 2026-11-13 蜘蛛小说网：搜尋每 30 秒只准一次，連續觸發會拉長；限流到不能用
    // 是網站壞掉的一種（使用者定）。
    final s = session(
      [_source('https://a.example')],
      replies: [
        jsonEncode({'action': 'fetch', 'url': '/s', 'note': '看搜尋'}),
        jsonEncode({
          'action': 'give_up',
          'why': 'rate_limited',
          'reason': '搜尋回「搜索间隔: 30 秒」',
        }),
      ],
    );

    await s.start();

    expect(asked, hasLength(2));
    expect(s.job.giveUpWhy, 'rate_limited');
    expect(s.job.explanation, 'AI：網站限流。搜尋回「搜索间隔: 30 秒」');
  });

  test('a site whose own search is broken can be given up on', () async {
    // 2026-11-12 蜘蛛小说网：網站的搜尋 GET、POST 都回空的搜尋頁，原因只能選
    // 「擋下所有請求」。
    final giveUp = jsonEncode({
      'action': 'give_up',
      'why': 'site_broken',
      'reason': '搜什麼都回空的搜尋頁',
    });
    final s = session([_source('https://a.example')], replies: [giveUp]);

    await s.start();

    expect(asked, hasLength(1));
    expect(s.job.explanation, 'AI：網站的功能壞了。搜什麼都回空的搜尋頁');
    expect(s.job.giveUpWhy, 'site_broken');
    expect(s.job.confirmedUnfixable, isTrue);
  });

  test('an unreadable reply is answered with what is wrong and the repair '
      'goes on', () async {
    final s = session(
      [_source('https://site.example')],
      replies: ['我再想想', '我再想想', _command('test'), _submitTested],
    );

    await s.start();

    expect(asked[1].last.content, startsWith('# 這一輪沒有呼叫工具'));
    expect(s.job.outcome, AiRepairOutcome.repaired);
  });

  test('more tries than the old limit stay in one conversation that only '
      'grows at the end', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        for (var i = 0; i < 7; i++) _command('test', content: 'class.w$i@text'),
        _command('test'),
        _submitTested,
      ],
    );

    await s.start();

    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(s.job.steps.map((step) => step.title), isNot(contains('重新來一次')));
    expect(asked.last, hasLength(2 + 8 * 2), reason: '同一段對話一路接下去');
    expect(asked.last.take(2), asked.first, reason: '開頭沒變');
  });

  test('looking at pages has no limit, and patches add up', () async {
    final fetched = <String>[];
    final s = session(
      [_source('https://site.example')],
      fetched: fetched,
      replies: [
        for (var i = 0; i < 7; i++)
          jsonEncode({'action': 'fetch', 'url': '/p$i'}),
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
        _submitTested,
      ],
    );

    await s.start();

    expect(fetched, [for (var i = 0; i < 7; i++) '/p$i']);
    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(applied.single.searchUrl, '/s2?q={{key}}', reason: '前一次的改動留著');
    expect(applied.single.ruleContent?.content, 'class.txt@text');
  });

  test('a fix whose test reached the text is checked once more after a '
      'pause when the first check fails', () async {
    var checks = 0;
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test'), _submitTested],
      check: (source) =>
          source.ruleContent?.content == 'class.txt@text' && ++checks == 1
          ? _checked(source, broken: _contentBroken)
          : null,
    );

    await s.start();

    expect(checks, 2);
    expect(s.job.outcome, AiRepairOutcome.repaired);
  });

  test('a source whose only problem was discovery is not called fixed while '
      'discovery still fails', () async {
    final s = session(
      [_source('https://site.example', content: 'class.txt@text')],
      replies: [
        _command('test'),
        _submitTested,
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '發現頁修不好'}),
      ],
      check: (source) => _checked(source, broken: _discoveryBroken),
    );

    await s.start();

    expect(asked[2].last.content, startsWith('# 書源校驗沒過：發現失效'));
    expect(s.job.outcome, AiRepairOutcome.failed);
    expect(applied, isEmpty);
  });

  test('a search that returns the same books for any word is not a fix, and '
      'the AI is told why', () async {
    var checks = 0;
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test'), _submitTested, _submitTested],
      // 原本的書源（開場）照常；AI 第一次交的搜尋抓到固定的書，第二次對了。
      followsKeyword: (source) =>
          source.ruleContent?.content == 'id.old@text' || ++checks > 1,
    );

    await s.start();

    expect(asked[2].last.content, contains('搜尋結果跟關鍵字無關'));
    expect(s.job.outcome, AiRepairOutcome.repaired);
  });

  test('the opening says when discovery borrows the search rules; whether the '
      'search follows the keyword is only tested on what the AI hands in '
      '(the source being repaired is broken anyway)', () async {
    final keywordChecked = <String>[];
    final s = session(
      [
        _source('https://site.example')
          ..exploreUrl = '全部::/all'
          ..ruleSearch = SearchRule(bookList: 'class.book', name: 'a@text'),
      ],
      replies: [
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '不修'}),
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '不修'}),
      ],
      followsKeyword: (_) => false,
      keywordChecked: keywordChecked,
    );

    await s.start();

    final opening = asked.first.last.content;
    expect(opening, isNot(contains(aiRepairUnrelatedSearch)));
    expect(opening, contains(aiRepairExploreBorrowsSearch));
    expect(keywordChecked, isEmpty);
  });

  test('a check the batch just made is used as it is: the original source is '
      'not checked again', () async {
    final source = _source('https://site.example');
    final checked = <String>[];
    final s = session(
      [source],
      replies: [_command('test'), _submitTested],
      checked: checked,
      priorCheck: (result: _checked(source, broken: null)),
    );

    await s.start();

    expect(checked, ['class.txt@text'], reason: '只校驗 AI 修好的那份');
    expect(s.job.steps.first.detail, '沿用剛才的校驗：正文失效：正文為空');
    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(asked.first.last.content, contains('正文為空'));
  });

  test(
    'changing the search rules that discovery uses counts as touching '
    'discovery: not kept when discovery then fails, and the AI is told why',
    () async {
      final original = BookSource(
        bookSourceUrl: 'https://site.example',
        bookSourceName: 'site.example',
        searchUrl: '/s?q={{key}}',
        exploreUrl: '全部::/all',
        ruleSearch: SearchRule(bookList: 'class.old', name: 'a@text'),
        ruleContent: ContentRule(content: 'id.old@text'),
      );
      final s = session(
        [original],
        replies: [
          jsonEncode({
            'action': 'test',
            'patch': {
              'searchUrl': '/api?q={{key}}',
              'ruleSearch': {'bookList': r'$[*]', 'name': r'$.title'},
              'ruleContent': {'content': 'class.txt@text'},
            },
          }),
          _submitTested,
          jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '發現頁修不好'}),
        ],
        check: (source) => source.ruleContent?.content == 'class.txt@text'
            ? _checked(
                source,
                broken: _discoveryBroken,
                diagnostics: _discoveryDiagnostics(
                  '  ← https://site.example/all 200 text/html，9000 位元組：'
                  '<div class="book">…',
                ),
              )
            : null,
      );

      await s.start();

      expect(asked[2].last.content, startsWith('# 書源校驗沒過：發現失效'));
      expect(asked[2].last.content, contains('發現頁用搜尋規則解析'));
      expect(applied, isEmpty);
    },
  );

  test('a fix is kept when only discovery still fails and the AI did not '
      'touch discovery', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('test'), _submitTested],
      check: (source) => source.ruleContent?.content == 'class.txt@text'
          ? _checked(source, broken: _discoveryBroken)
          : null,
    );

    await s.start();

    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(applied.single.ruleContent?.content, 'class.txt@text');
  });

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
      final job = s.job;
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
    final logs = Directory.systemTemp.createTempSync('ai-repair-log');
    addTearDown(() => logs.deleteSync(recursive: true));
    for (final clipboard in [false, true]) {
      final s = AiRepairSession(
        logDirectory: () async => logs,
        source: leaky,
        service: clipboard ? null : _service,
        check: (source, _) async => _checked(source),
        probe: (_, _, {start}) async => probe,
        keywordCheck: (_, _) async => true,
        ask: (messages, _) async {
          asked.add(List.of(messages));
          return fakeAiReply(
            jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '不修'}),
          );
        },
        apply: (source, _) async => applied.add(source),
        copy: (text) async => copied.add(text),
        secrets: (_) async => {secret},
        backups: backups,
      );
      await s.start();
      expect(s.log.summary, contains('token=«已遮蔽»'));
      expect(s.log.summary, isNot(contains(secret)));
      final full = (await s.log.file())!.readAsStringSync();
      expect(full, contains('token=«已遮蔽»'));
      expect(full, isNot(contains(secret)));
    }

    final sent = [for (final message in asked.first) message.content]
        .join('\n');
    expect(sent, isNot(contains(secret)));
    expect(sent, contains('token=«已遮蔽»'));
    expect(copied.single, isNot(contains(secret)));
  });

  test('a source the AI writes with an impossible number is treated as an '
      'unreadable reply, not a crash', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [
        '{"action":"submit","patch":{"bookSourceType":1e400},"note":""}',
        jsonEncode({'action': 'give_up', 'why': 'paid', 'reason': '不修'}),
      ],
    );

    await s.start();

    final job = s.job;
    expect(job.outcome, AiRepairOutcome.failed);
    expect(asked, hasLength(2), reason: '讀不懂一次、再放棄');
    expect(asked[1].last.content, startsWith(aiRepairBadCall));
    expect(s.isRunning, isFalse);
    expect(applied, isEmpty);
  });

  test('stopping while the fixed source is being saved reports what was '
      'saved', () async {
    late AiRepairSession s;
    s = AiRepairSession(
      source: _source('https://site.example'),
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _, {start}) async => _probe(source),
      keywordCheck: (_, _) async => true,
      ask: (_, _) async => fakeAiReply(_command('submit')),
      apply: (source, _) async {
        s.stop();
        applied.add(source);
      },
      secrets: (_) async => const {},
      backups: backups,
    );

    await s.start();

    expect(applied, hasLength(1));
    expect(s.job.outcome, AiRepairOutcome.repaired);
  });

  test('a fix is not saved over a source that changed or was deleted while '
      'the AI worked on it', () async {
    for (final conflict in ['修的這段時間書源被改過了（例如同步），沒有存。', '修的這段時間書源被刪掉了，沒有存。']) {
      final s = AiRepairSession(
        source: _source('https://site.example'),
        service: _service,
        check: (source, _) async => _checked(source),
        probe: (source, _, {start}) async => _probe(source),
        keywordCheck: (_, _) async => true,
        ask: (_, _) async => fakeAiReply(_command('submit')),
        apply: (_, _) async => throw AiRepairConflict(conflict),
        secrets: (_) async => const {},
        backups: backups,
      );

      await s.start();

      expect(s.job.outcome, AiRepairOutcome.failed);
      expect(s.job.explanation, conflict);
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
    expect(s.job.awaitingPaste, isTrue);
    expect(
      await s.submitPaste('{"bookSourceUrl":"x","bookSourceType":1e400}'),
      '讀不出書源 JSON',
    );
    expect(s.job.awaitingPaste, isTrue);
  });

  test('stopped session cannot restart before or after disposal', () async {
    final s = session(
      [_source('https://site.example')],
      replies: [_command('submit')],
    );
    s.stop();
    await s.start();
    expect(asked, isEmpty);
    expect(applied, isEmpty);
    expect(s.isFinished, isTrue);
    s.dispose();
    await s.start();
    expect(asked, isEmpty);
  });

  test('clipboard validation waits for cancellation', () async {
    final source = _source('https://site.example');
    final gate = Completer<SourceCheckIsolateResult?>();
    var checks = 0;
    final s = AiRepairSession(
      source: source,
      service: null,
      check: (source, _) {
        checks++;
        return checks == 1 ? Future.value(_checked(source)) : gate.future;
      },
      probe: (source, _, {start}) async => _probe(source),
      keywordCheck: (_, _) async => true,
      copy: (_) async {},
      secrets: (_) async => const {},
      apply: (source, _) async => applied.add(source),
      backups: backups,
    );
    await s.start();
    expect(s.job.awaitingPaste, isTrue);
    final edited = _source('https://site.example', content: 'class.txt@text');
    final validating = s.submitPaste(jsonEncode(sourceForAi(edited)));
    await Future<void>.delayed(Duration.zero);
    expect(s.isRunning, isTrue);
    s.stop();
    expect(s.isFinished, isFalse);
    var completed = false;
    final completion = s.completion.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    gate.complete(_checked(edited));
    await validating;
    await completion;
    expect(s.isFinished, isTrue);
    expect(applied, isEmpty);
  });

  test('stopping marks the running step and changes nothing', () async {
    late AiRepairSession s;
    s = AiRepairSession(
      source: _source('https://site.example'),
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (source, _, {start}) async => _probe(source),
      keywordCheck: (_, _) async => true,
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

    final job = s.job;
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
