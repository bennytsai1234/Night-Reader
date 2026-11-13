import 'dart:async';
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

import '../../support/fake_ai.dart';

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
        contentUsable: true,
        requests: [],
      )
    : const SourceProbeReport(logs: [(-1, '❌ 正文為空')], requests: []);

final _fix = jsonEncode({
  'action': 'test',
  'patch': {
    'ruleContent': {'content': 'class.txt@text'},
  },
});
final _giveUp = jsonEncode({
  'action': 'give_up',
  'why': 'site_gone',
  'reason': '網站關了',
});

void main() {
  late List<BookSource> saved;
  late List<String> gone;
  late List<String> unfixable;
  late List<String> asked;
  late List<String> rechecked;
  late AiRepairBackups backups;

  setUp(() async {
    final file = await AiRepairBackups.file();
    if (file.existsSync()) file.deleteSync();
    backups = AiRepairBackups();
    saved = [];
    gone = [];
    unfixable = [];
    asked = [];
    rechecked = [];
  });

  SourceRepairBatch batch(
    List<BookSource> sources, {
    Map<String, SourceRuntimeHealth> recheck = const {},
    Map<String, SiteCheck> sites = const {},
    List<String> Function(String url)? replies,
    int? tokenBudget,
    int tokensPerAnswer = 0,
    DateTime Function()? now,
  }) {
    late SourceRepairBatch b;
    b = SourceRepairBatch(
      sources: sources,
      service: _service,
      tokenBudget: tokenBudget,
      now: now,
      recheck: (urls, _) async {
        rechecked.addAll(urls);
        return [for (final url in urls) _entry(url, recheck[url] ?? _broken)];
      },
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
          probe: (s, _, {start}) async => _probe(s),
          keywordCheck: (_, _) async => true,
          knownTitleSearch: (_, _) async => null,
          ask: (_, _) async {
            asked.add(source.bookSourceUrl);
            b.tokensUsed += tokensPerAnswer;
            return fakeAiReply(answers[next++ % answers.length]);
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
      [_source('https://gone.example#a'), _source('https://gone.example#b')],
      sites: {'gone.example': const SiteCheck(SiteVerdict.gone, '網域查不到')},
    );

    await b.start();

    expect(b.count(RepairOutcome.siteGone), 2);
    expect(gone, ['https://gone.example#a', 'https://gone.example#b']);
    expect(asked, isEmpty);
  });

  test('a site that moved is tried at its new address first', () async {
    final b = batch(
      [_source('https://www.old.example#mark')],
      sites: {
        'www.old.example': const SiteCheck(
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
      _source('https://www.site.example#b'),
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
    expect(borrowed.bookSourceName, 'www.site.example#b');
    expect(borrowed.ruleContent?.content, 'class.txt@text');
  });

  test('when the AI cannot fix a site, the rest of the site says so', () async {
    final b = batch([
      _source('https://site.example#a'),
      _source('https://site.example#b'),
    ], replies: (_) => [_giveUp]);

    await b.start();

    expect(b.items.first.outcome, RepairOutcome.notFixed);
    expect(b.items.last.outcome, RepairOutcome.notFixed);
    expect(b.items.last.detail, contains('沒修好'));
    expect(unfixable, ['https://site.example#a', 'https://site.example#b']);
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

  test('sources already marked as not worth repairing are not checked '
      'again', () async {
    final tried = _source('https://tried.example')
      ..addHealthGroups(_broken)
      ..addGroup(aiUnfixableSourceGroupTag);
    final siteGone = _source('https://gone.example')
      ..addHealthGroups(upstreamHealth(siteBrokenSourceGroupTag))
      ..addErrorComment('網站: 網域查不到');
    final login = _source('https://login.example')..addHealthGroups(_login);
    final b = batch([tried, siteGone, login, _source('https://stale.example')]);

    await b.start();

    expect(rechecked, ['https://stale.example']);
    expect(
      [for (final item in b.items) item.outcome],
      [
        RepairOutcome.skipped,
        RepairOutcome.siteGone,
        RepairOutcome.skipped,
        RepairOutcome.aiFixed,
      ],
    );
    expect(b.items[1].detail, '網站: 網域查不到');
    expect(gone, isEmpty, reason: '已經標過了，不再標一次');
  });

  test('a source checked within a day goes on with that result; an older '
      'one is checked again', () async {
    final now = DateTime(2026, 11, 11, 12);
    BookSource checkedAgo(String url, Duration ago) => _source(url)
      ..addHealthGroups(_broken)
      ..addErrorComment('正文為空')
      ..lastCheckTime = now.subtract(ago).millisecondsSinceEpoch;
    final b = batch([
      checkedAgo('https://fresh.example', const Duration(hours: 1)),
      checkedAgo('https://old.example', const Duration(hours: 25)),
    ], now: () => now);

    await b.start();

    expect(rechecked, ['https://old.example']);
    expect(b.reusedChecks, 1);
    expect(
      asked,
      containsAll(['https://fresh.example', 'https://old.example']),
    );
    expect(b.count(RepairOutcome.aiFixed), 2);
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

  test('the mobile and desktop sites are repaired separately', () async {
    final b = batch([
      _source('https://www.two.example'),
      _source('https://m.two.example'),
    ]);

    await b.start();

    expect(b.count(RepairOutcome.aiFixed), 2);
    expect(asked.toSet(), {'https://www.two.example', 'https://m.two.example'});
  });

  test('one site going wrong does not end the batch early', () async {
    final b = SourceRepairBatch(
      sources: [
        _source('https://bad.example'),
        _source('https://gone.example'),
      ],
      service: _service,
      recheck: (urls, _) async => [
        for (final url in urls) _entry(url, _broken),
      ],
      checkSite: (source) async => source.bookSourceUrl.contains('bad')
          ? throw StateError('壞掉')
          : const SiteCheck(SiteVerdict.gone, '網域查不到'),
      check: (source, _) async => _checked(source),
      save: (_, _) async {},
      markGone: (source, _) async => gone.add(source.bookSourceUrl),
      markUnfixable: (_) async {},
      session: (source, _) => AiRepairSession(
        source: source,
        service: _service,
        check: (s, _) async => _checked(s),
        probe: (s, _, {start}) async => _probe(s),
        keywordCheck: (_, _) async => true,
        knownTitleSearch: (_, _) async => null,
        ask: (_, _) async => fakeAiReply(_giveUp),
        secrets: (_) async => const {},
        backups: backups,
      ),
    );

    await b.start();

    expect(gone, ['https://gone.example']);
    expect(b.isFinished, isTrue);
  });

  test('recheck updates progress before all sources finish', () async {
    final source1 = _source('https://first.example');
    final source2 = _source('https://second.example');
    final gate = Completer<List<SourceCheckEntry>>();
    late void Function(int) onProgress;
    final b = SourceRepairBatch(
      sources: [source1, source2],
      service: _service,
      recheck: (urls, progress) {
        expect(urls, [source1.bookSourceUrl, source2.bookSourceUrl]);
        onProgress = progress;
        return gate.future;
      },
      checkSite: (_) async => const SiteCheck(SiteVerdict.alive, '網站正常'),
      markGone: (_, _) async => fail('stopped batch must not mark sources'),
      markUnfixable: (_) async => fail('stopped batch must not write'),
    );

    final running = b.start();
    expect(b.stage, RepairStage.checking);
    expect(b.stageDone, 0);
    expect(b.stageTotal, 2);
    onProgress(1);
    expect(b.stageDone, 1);
    b.stop();
    gate.complete([
      _entry(source1.bookSourceUrl, _broken),
      _entry(source2.bookSourceUrl, _broken),
    ]);
    await running;

    expect(b.isFinished, isTrue);
    expect(b.count(RepairOutcome.notTried), 2);
    expect(b.stageDone, 1);
    expect(asked, isEmpty);
  });

  test('stop during site check never marks the site gone', () async {
    final source = _source('https://stopping.example');
    final gate = Completer<SiteCheck>();
    final b = SourceRepairBatch(
      sources: [source],
      service: _service,
      recheck: (urls, progress) async {
        progress(urls.length);
        return [_entry(source.bookSourceUrl, _broken)];
      },
      checkSite: (_) => gate.future,
      markGone: (source, site) async => gone.add(source.bookSourceUrl),
      markUnfixable: (_) async {},
    );

    final running = b.start();
    await Future<void>.delayed(Duration.zero);
    expect(b.stage, RepairStage.checkingSites);
    b.stop();
    gate.complete(const SiteCheck(SiteVerdict.gone, '網域查不到'));
    await running;
    expect(gone, isEmpty);
    expect(b.count(RepairOutcome.notTried), 1);
    // 畫面照這個把被打斷的那一步畫成停下，不是綠勾。
    expect(b.stoppedStage, RepairStage.checkingSites);
  });

  test('failed recheck is shown and does not continue to the AI', () async {
    final b = SourceRepairBatch(
      sources: [_source('https://broken-check.example')],
      service: _service,
      recheck: (_, _) async => throw StateError('校驗服務無法啟動'),
      checkSite: (_) async => fail('must not proceed after recheck failure'),
      markUnfixable: (_) async => fail('must not change sources'),
    );
    await b.start();

    expect(b.errorMessage, contains('校驗服務無法啟動'));
    expect(b.failedStage, RepairStage.checking);
    expect(b.count(RepairOutcome.notTried), 1);
    expect(b.isFinished, isTrue);
  });

  test('start after stop does not restart a cancelled batch', () async {
    final b = batch([_source('https://not-started.example')]);
    b.stop();
    await b.start();
    expect(asked, isEmpty);
    expect(b.isStopped, isTrue);
    expect(b.isRunning, isFalse);
    expect(b.isFinished, isTrue);
    expect(b.count(RepairOutcome.notTried), 1);
  });

  test('missing recheck results are not passed to AI', () async {
    final b = SourceRepairBatch(
      sources: [_source('https://missing.example')],
      service: _service,
      recheck: (urls, progress) async {
        progress(urls.length);
        return [];
      },
      checkSite: (_) async => fail('must not inspect an unverified source'),
      markUnfixable: (_) async => fail('must not persist an unverified source'),
    );

    await b.start();
    expect(b.count(RepairOutcome.notTried), 1);
    expect(b.items.single.detail, contains('校驗沒有取得結果'));
    expect(asked, isEmpty);
  });

  test('transient AI errors do not quarantine the site', () async {
    final b = SourceRepairBatch(
      sources: [
        _source('https://unstable.example#a'),
        _source('https://unstable.example#b'),
      ],
      service: _service,
      recheck: (urls, progress) async {
        progress(urls.length);
        return [for (final url in urls) _entry(url, _broken)];
      },
      checkSite: (_) async => const SiteCheck(SiteVerdict.alive, '網站正常'),
      markUnfixable: (source) async => unfixable.add(source.bookSourceUrl),
      session: (source, item) => AiRepairSession(
        source: source,
        service: _service,
        check: (source, _) async => _checked(source),
        probe: (source, _, {start}) async => _probe(source),
        keywordCheck: (_, _) async => true,
        knownTitleSearch: (_, _) async => null,
        ask: (_, _) async => throw StateError('AI 服務無法回應'),
        secrets: (_) async => const {},
        backups: backups,
      ),
    );

    await b.start();
    expect(unfixable, isEmpty);
    expect(b.items.first.outcome, RepairOutcome.notFixed);
    expect(b.items.first.detail, contains('AI 服務無法回應'));
    expect(b.items.last.outcome, RepairOutcome.notTried);
    expect(b.items.last.detail, contains('同網站的 AI 修復中斷'));
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

    final careful = movedSource(
      BookSource(
        bookSourceUrl: 'https://old.cc',
        bookSourceName: 'x',
        searchUrl: 'https://cdn.bold.cc/s?from=old.cc.cn&q={{key}}',
      ),
      'https://new.net',
    );
    expect(
      careful.searchUrl,
      'https://cdn.bold.cc/s?from=old.cc.cn&q={{key}}',
      reason: '只換完整的網域',
    );
  });
}
