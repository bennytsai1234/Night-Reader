import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_create_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_step.dart';
import 'package:night_reader/core/ai_repair/site_check.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';

import '../../support/fake_ai.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'sk-test',
  model: 'm',
  effort: '',
);

const _url = 'https://site.example/category.html';

/// 校驗：正文規則寫好了（`class.txt@text`）才沒問題。
SourceCheckIsolateResult _checked(BookSource source) {
  final healthy = source.ruleContent?.content == 'class.txt@text';
  return SourceCheckIsolateResult(
    stage: healthy ? 'done' : 'content',
    message: healthy ? '校驗成功' : '正文為空',
    isHealthy: healthy,
    updatedSourceJson: source.toJson(),
    logs: const [],
    diagnostics: const [],
  );
}

final _submit = jsonEncode({
  'action': 'submit',
  'patch': {
    'bookSourceName': '範例書站',
    'bookSourceType': 2,
    'searchUrl': '/s?q={{key}}',
    'ruleSearch': {'checkKeyWord': '夜行', 'bookList': 'li', 'name': 'a@text'},
    'ruleContent': {'content': 'class.txt@text'},
  },
  'note': '搜尋到正文都試過',
});

void main() {
  late List<BookSource> applied;
  late List<List<AiMessage>> asked;
  late List<String> fetched;

  setUp(() {
    applied = [];
    asked = [];
    fetched = [];
  });

  AiRepairSession session({
    required List<String> replies,
    SiteVerdict site = SiteVerdict.alive,
    String sampleTitle = '',
    SourceCheckIsolateResult Function(BookSource source)? check,
  }) {
    var next = 0;
    return AiRepairSession(
      source: aiCreateBlankSource(_url)!,
      create: (url: _url, sampleTitle: sampleTitle),
      service: _service,
      siteCheck: (_, _) async => SiteCheck(site, site.name),
      check: (source, _) async => (check ?? _checked)(source),
      probe: (source, _, {start}) async =>
          const SourceProbeReport(logs: [], requests: []),
      fetchPage: (source, url, _) async {
        fetched.add(url);
        return (
          lines: ['$url 標頭：User-Agent: t', '  ← $url 200：<form action="/s">'],
          pages: [(line: '  ← $url 200：<form action="/s">', body: '<form>')],
        );
      },
      ask: (messages, _) async {
        asked.add(List.of(messages));
        if (next >= replies.length) throw StateError('沒有更多回覆');
        return fakeAiReply(replies[next++]);
      },
      apply: (source, _) async => applied.add(source),
      secrets: (_) async => const {},
    );
  }

  test('a blank source starts from the origin of the pasted address', () {
    final blank = aiCreateBlankSource(_url)!;
    expect(blank.bookSourceUrl, 'https://site.example');
    expect(blank.bookSourceName, 'site.example');
    expect(aiCreateBlankSource('ftp://site.example'), isNull);
  });

  test('the AI opens on the pasted page and the site check, and the source it '
      'writes is saved under the name the AI gave it', () async {
    final s = session(replies: [_submit], sampleTitle: '夜行');

    await s.start();

    expect(fetched, [_url]);
    final opening = asked.first;
    expect(opening.first.content, aiCreateSystemPrompt);
    expect(opening[1].content, contains('# 使用者貼的網址\n$_url'));
    expect(opening[1].content, contains('# 樣本書名\n夜行'));
    expect(opening[1].content, contains('# 網站檢查\n網站在'));
    expect(s.job.outcome, AiRepairOutcome.repaired);
    expect(applied.single.bookSourceName, '範例書站');
    expect(applied.single.bookSourceUrl, 'https://site.example');
    expect(applied.single.bookSourceType, 2);
    expect(s.job.explanation, contains('搜尋到正文都試過'));
    expect(
      s.job.steps.map((step) => step.title),
      containsAllInOrder([
        aiCreateSiteStage,
        aiCreateFetchStage,
        aiCreateVerifyStage,
      ]),
    );
  });

  test('a site that is gone is not sent to the AI', () async {
    final s = session(replies: const [], site: SiteVerdict.gone);

    await s.start();

    expect(asked, isEmpty);
    expect(fetched, isEmpty);
    expect(s.job.outcome, AiRepairOutcome.failed);
    expect(s.job.explanation, startsWith('網站失效'));
    expect(applied, isEmpty);
  });

  test('giving up because the site is paid saves nothing', () async {
    final s = session(
      replies: [
        jsonEncode({
          'action': 'give_up',
          'why': 'paid',
          'reason': '第 17 章起要購買',
        }),
      ],
    );

    await s.start();

    expect(s.job.outcome, AiRepairOutcome.failed);
    expect(s.job.giveUpWhy, 'paid');
    expect(applied, isEmpty);
  });

  test('a check that finds paid chapters ends it at once without asking the '
      'AI again', () async {
    final s = session(
      replies: [_submit],
      check: (source) {
        final paid = BookSource.fromJson(source.toJson())
          ..addHealthGroups(
            const SourceRuntimeHealth(
              category: SourceHealthCategory.paid,
              label: paidSourceGroupTag,
              description: '',
              allowsSearch: false,
              allowsReading: false,
              cleanupCandidate: true,
              quarantined: true,
            ),
          );
        return SourceCheckIsolateResult(
          stage: 'content',
          message: '目錄有付費章節',
          isHealthy: false,
          updatedSourceJson: paid.toJson(),
          logs: const [],
        );
      },
    );

    await s.start();

    expect(asked, hasLength(1), reason: '交出一次就結束，不再退回給 AI');
    expect(s.job.outcome, AiRepairOutcome.failed);
    expect(s.job.giveUpWhy, 'paid');
    expect(s.job.explanation, startsWith('要付費'));
    expect(applied, isEmpty);
  });

  test('the system prompt says to give up as soon as a paid chapter shows', () {
    expect(aiCreateSystemPrompt, contains('一看到就放棄'));
    expect(aiCreateSystemPrompt, contains('不改挑免費的書當樣本'));
  });
}
