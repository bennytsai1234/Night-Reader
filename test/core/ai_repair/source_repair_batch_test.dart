import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/site_check.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'k',
  model: 'm',
  effort: '',
);

BookSource _source(String url, {String content = 'id.old@text'}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: url.split('//').last,
  searchUrl: '${url.split('#').first}/s?q={{key}}',
  ruleContent: ContentRule(content: content),
);

const _broken = SourceRuntimeHealth(
  category: SourceHealthCategory.contentBroken,
  label: '正文失效',
  description: '',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

const _login = SourceRuntimeHealth(
  category: SourceHealthCategory.loginRequired,
  label: '需要登入',
  description: '',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

SourceCheckEntry _entry(String url, SourceRuntimeHealth health) =>
    SourceCheckEntry(
      sourceUrl: url,
      sourceName: url,
      stage: 'content',
      message: '正文為空',
      health: health,
    );

/// 正文規則是 class.txt@text、或網址換到 new.example 的才算修好。
bool _good(BookSource source) =>
    source.ruleContent?.content == 'class.txt@text' ||
    source.bookSourceUrl.contains('new.example');

SourceCheckIsolateResult _checked(BookSource source) {
  final healthy = _good(source);
  final copy = BookSource.fromJson(source.toJson())
    ..addHealthGroups(healthy ? SourceRuntimeHealth.healthy : _broken);
  return SourceCheckIsolateResult(
    stage: healthy ? 'done' : 'content',
    message: healthy ? '校驗成功' : '正文為空',
    isHealthy: healthy,
    updatedSourceJson: copy.toJson(),
    logs: const [],
    diagnostics: const [],
  );
}

SourceProbeReport _probe(BookSource source) => _good(source)
    ? const SourceProbeReport(
        logs: [(40, '︽正文頁解析完成 (內容長度: 3214)'), (1000, '︽解析完成')],
        requests: [],
      )
    : const SourceProbeReport(logs: [(-1, '❌ 正文為空')], requests: []);

final _fix = jsonEncode({
  'action': 'test',
  'patch': {
    'ruleContent': {'content': 'class.txt@text'},
  },
});
final _giveUp = jsonEncode({'action': 'give_up', 'reason': '網站關了'});

void main() {
  late List<BookSource> saved;
  late List<String> gone;
  late List<String> unfixable;
  late List<String> asked;
  late AiRepairBackups backups;

  setUp(() async {
    final file = await AiRepairBackups.file();
    if (file.existsSync()) file.deleteSync();
    backups = AiRepairBackups();
    saved = [];
    gone = [];
    unfixable = [];
    asked = [];
  });

  SourceRepairBatch batch(
    List<BookSource> sources, {
    Map<String, SourceRuntimeHealth> recheck = const {},
    Map<String, SiteCheck> sites = const {},
    List<String> Function(String url)? replies,
    int? tokenBudget,
    int tokensPerAnswer = 0,
  }) {
    late SourceRepairBatch b;
    b = SourceRepairBatch(
      sources: sources,
      service: _service,
      tokenBudget: tokenBudget,
      recheck: (urls) async => [
        for (final url in urls) _entry(url, recheck[url] ?? _broken),
      ],
      checkSite: (source) async =>
          sites[siteKey(source)] ??
          const SiteCheck(SiteVerdict.alive, '網站正常回應'),
      check: (source, _) async => _checked(source),
      save: (repaired, original) async => saved.add(repaired),
      markGone: (source, site) async => gone.add(source.bookSourceUrl),
      markUnfixable: (source) async => unfixable.add(source.bookSourceUrl),
      session: (source, item) {
        final answers = replies?.call(source.bookSourceUrl) ?? [_fix];
        var next = 0;
        return AiRepairSession(
          source: source,
          service: _service,
          check: (s, _) async => _checked(s),
          probe: (s, _) async => _probe(s),
          keywordCheck: (_, _) async => true,
          ask: (_, _) async {
            asked.add(source.bookSourceUrl);
            b.tokensUsed += tokensPerAnswer;
            return answers[next++ % answers.length];
          },
          apply: (repaired, original) async => saved.add(repaired),
          secrets: (_) async => const {},
          backups: backups,
          recheckDelay: Duration.zero,
          hasBudget: () => tokenBudget == null || b.tokensUsed < tokenBudget,
        );
      },
    );
    return b;
  }

  test(
    'sources that pass the recheck, or need login, are not repaired',
    () async {
      final b = batch(
        [_source('https://ok.example'), _source('https://login.example')],
        recheck: {
          'https://ok.example': SourceRuntimeHealth.healthy,
          'https://login.example': _login,
        },
      );

      await b.start();

      expect(
        [for (final item in b.items) item.outcome],
        [RepairOutcome.healthy, RepairOutcome.skipped],
      );
      expect(asked, isEmpty);
      expect(b.isFinished, isTrue);
    },
  );

  test('a site that is gone is marked, without asking the AI', () async {
    final b = batch(
      [_source('https://gone.example'), _source('https://m.gone.example')],
      sites: {'gone.example': const SiteCheck(SiteVerdict.gone, '網域查不到')},
    );

    await b.start();

    expect(b.count(RepairOutcome.siteGone), 2);
    expect(gone, ['https://gone.example', 'https://m.gone.example']);
    expect(asked, isEmpty);
  });

  test('a site that moved is tried at its new address first', () async {
    final b = batch(
      [_source('https://www.old.example#mark')],
      sites: {
        'old.example': const SiteCheck(
          SiteVerdict.moved,
          '首頁轉到 www.new.example',
          movedTo: 'https://www.new.example',
        ),
      },
    );

    await b.start();

    final item = b.items.single;
    expect(item.outcome, RepairOutcome.moved);
    expect(item.source.bookSourceUrl, 'https://www.new.example#mark');
    expect(item.source.searchUrl, 'https://www.new.example/s?q={{key}}');
    expect(asked, isEmpty);
  });

  test('the AI fixes one source per site and the rest of the site borrows '
      'the fix', () async {
    final b = batch([
      _source('https://www.site.example#a'),
      _source('https://m.site.example#b'),
      _source('https://other.example'),
    ]);

    await b.start();

    expect(
      [for (final item in b.items) item.outcome],
      [RepairOutcome.aiFixed, RepairOutcome.shared, RepairOutcome.aiFixed],
    );
    expect(asked.toSet(), {
      'https://www.site.example#a',
      'https://other.example',
    });
    final borrowed = b.items[1].source;
    expect(borrowed.bookSourceName, 'm.site.example#b');
    expect(borrowed.ruleContent?.content, 'class.txt@text');
  });

  test('when the AI cannot fix a site, the rest of the site says so', () async {
    final b = batch([
      _source('https://a.site.example'),
      _source('https://b.site.example'),
    ], replies: (_) => [_giveUp]);

    await b.start();

    expect(b.items.first.outcome, RepairOutcome.notFixed);
    expect(b.items.last.outcome, RepairOutcome.notFixed);
    expect(b.items.last.detail, contains('沒修好'));
    expect(unfixable, ['https://a.site.example', 'https://b.site.example']);
  });

  test('a source the AI already could not fix, and one that never had a '
      'search, are skipped without asking the AI', () async {
    final tried = _source('https://tried.example')
      ..addGroup(aiUnfixableSourceGroupTag);
    final exploreOnly = BookSource(
      bookSourceUrl: 'https://explore.example',
      bookSourceName: '只有發現',
      exploreUrl: '分類::/list/1',
    );
    const searchBroken = SourceRuntimeHealth(
      category: SourceHealthCategory.searchBroken,
      label: '搜尋失效',
      description: '',
      allowsSearch: false,
      allowsReading: true,
      cleanupCandidate: false,
      quarantined: false,
    );
    final b = batch(
      [tried, exploreOnly],
      recheck: {'https://explore.example': searchBroken},
    );

    await b.start();

    expect(b.count(RepairOutcome.skipped), 2);
    expect(b.items.first.detail, contains('AI 之前試過修不好'));
    expect(b.items.last.detail, contains('沒有搜尋規則'));
    expect(asked, isEmpty);
  });

  test('sites that answer normally go to the AI before unreachable ones, and '
      'the spending limit stops the rest', () async {
    final b = batch(
      [
        _source('https://down.example'),
        _source('https://a.example'),
        _source('https://b.example'),
        _source('https://c.example'),
      ],
      sites: {'down.example': const SiteCheck(SiteVerdict.unreachable, '連不上')},
      replies: (_) => [_giveUp],
      tokenBudget: 1,
      tokensPerAnswer: 1,
    );

    await b.start();

    expect(asked.first, isNot('https://down.example'));
    expect(b.count(RepairOutcome.notTried), greaterThan(0));
    expect(
      b.items
          .firstWhere((i) => i.source.bookSourceUrl == 'https://down.example')
          .outcome,
      RepairOutcome.notTried,
    );
  });

  test('a moved source has the old domain replaced inside its rules too', () {
    final moved = movedSource(
      BookSource(
        bookSourceUrl: 'http://www.old.cc/#x',
        bookSourceName: '舊站 old.cc',
        searchUrl: 'https://m.old.cc/s?q={{key}}',
      ),
      'https://www.new.net',
    );

    expect(moved.bookSourceUrl, 'https://www.new.net/#x');
    expect(moved.searchUrl, 'https://m.new.net/s?q={{key}}');
    expect(moved.bookSourceName, '舊站 old.cc', reason: '名稱照舊');
  });
}
