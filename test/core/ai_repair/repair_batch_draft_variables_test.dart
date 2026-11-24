import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/site_check.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/core/utils/cache_manager.dart';

import '../../support/fake_ai.dart';

/// 修復異常書源換網址、套用同網站修好的規則時，校驗候選書源時規則存的
/// 變數寫在候選自己那一份；候選通過、存好了才寫回，沒採用就丟掉。和 AI
/// 修書源的草稿同一套（#557）。
void main() {
  const service = (
    baseUrl: 'https://ai.example/v1',
    apiKey: 'k',
    model: 'm',
    effort: '',
  );
  const broken = SourceRuntimeHealth(
    category: SourceHealthCategory.contentBroken,
    label: '正文失效',
    description: '',
    allowsSearch: false,
    allowsReading: false,
    cleanupCandidate: false,
    quarantined: true,
  );
  const fixed = 'class.txt@text';

  BookSource sourceAt(String url) => BookSource(
    bookSourceUrl: url,
    bookSourceName: url,
    searchUrl: '/s?q={{key}}',
    ruleContent: ContentRule(content: 'id.old@text'),
  );

  /// 測試用到的每個鍵，結束時清掉。
  final touched = <String>[];
  String tokenOf(String url) {
    final key = sourceAt(url).ruleVariableCacheKey('token');
    touched.add(key);
    return key;
  }

  late List<BookSource> saved;

  setUp(() async {
    final file = await AiRepairBackups.file();
    if (file.existsSync()) file.deleteSync();
    saved = [];
  });

  tearDown(() async {
    for (final key in touched) {
      await CacheManager().delete(key);
    }
    touched.clear();
  });

  /// 校驗：網址換到 new.example、或正文規則是 [fixed] 而且網址不是 `#bad`
  /// 結尾的才算修好。每次都照規則的方式存一個變數（候選書源的鍵）。
  Future<SourceCheckIsolateResult> check(BookSource candidate) async {
    await CacheManager().put(candidate.ruleVariableCacheKey('token'), 'draft');
    final url = candidate.bookSourceUrl;
    final healthy =
        url.contains('new.example') ||
        (candidate.ruleContent?.content == fixed && !url.endsWith('#bad'));
    return SourceCheckIsolateResult(
      stage: healthy ? 'done' : 'content',
      message: healthy ? '校驗成功' : '正文為空',
      isHealthy: healthy,
      updatedSourceJson: candidate.toJson(),
      logs: const [],
    );
  }

  /// [movedTo] 給了是網站搬家；AI 照 [fix] 交出改好的正文規則，否則放棄。
  SourceRepairBatch batch(
    List<String> urls, {
    String? movedTo,
    bool fix = false,
  }) => SourceRepairBatch(
    sources: [for (final url in urls) sourceAt(url)],
    service: service,
    recheck: (urls, _, _) async => [
      for (final url in urls)
        SourceCheckEntry(
          sourceUrl: url,
          sourceName: url,
          stage: 'content',
          message: '正文為空',
          health: broken,
        ),
    ],
    checkSite: (_) async => movedTo == null
        ? const SiteCheck(SiteVerdict.alive, '網站正常回應')
        : SiteCheck(SiteVerdict.moved, '首頁轉到別的網域', movedTo: movedTo),
    check: (candidate, _) => check(candidate),
    save: (repaired, _) async => saved.add(repaired),
    markGone: (_, _) async {},
    markUnfixable: (_, _) async {},
    delete: (_) async {},
    session: (s, item) => AiRepairSession(
      source: s,
      service: service,
      priorCheck: item.priorCheck,
      check: (candidate, _) async => SourceCheckIsolateResult(
        stage: 'done',
        message: '校驗成功',
        isHealthy: candidate.ruleContent?.content == fixed,
        updatedSourceJson: candidate.toJson(),
        logs: const [],
      ),
      probe: (_, _, {start}) async =>
          const SourceProbeReport(logs: [(-1, '❌ 正文為空')], requests: []),
      ask: (_, _) async => fakeAiReply(
        fix
            ? jsonEncode({
                'action': 'submit',
                'patch': {
                  'ruleContent': {'content': fixed},
                },
              })
            : jsonEncode({
                'action': 'give_up',
                'why': 'site_gone',
                'reason': '關了',
              }),
      ),
      apply: (repaired, _) async => saved.add(repaired),
      secrets: (_) async => const {},
      copy: (_) async {},
      backups: AiRepairBackups(),
    ),
  );

  test('a move that fails the check leaves nothing behind', () async {
    const old = 'https://www.old.example';
    await CacheManager().put(tokenOf(old), 'real');

    await batch([old], movedTo: 'https://www.bad.example').start();

    expect(saved, isEmpty);
    expect(await CacheManager().get(tokenOf(old)), 'real');
    expect(
      await CacheManager().get(tokenOf('https://www.bad.example')),
      isNull,
    );
  });

  test('a move that passes writes what its check stored to the new '
      'address', () async {
    const old = 'https://www.old.example';
    await CacheManager().put(tokenOf(old), 'real');

    await batch([old], movedTo: 'https://www.new.example').start();

    expect(saved.single.bookSourceUrl, 'https://www.new.example');
    expect(
      await CacheManager().get(tokenOf('https://www.new.example')),
      'draft',
    );
  });

  test('borrowing the fixed rules that fail the check leaves the sibling '
      'variables alone', () async {
    const lead = 'https://www.s.example#a';
    const sibling = 'https://www.s.example#bad';
    await CacheManager().put(tokenOf(sibling), 'real');

    await batch([lead, sibling], fix: true).start();

    expect([for (final s in saved) s.bookSourceUrl], [lead]);
    expect(await CacheManager().get(tokenOf(sibling)), 'real');
  });
}
