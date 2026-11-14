import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';

BookSource _source() => BookSource(
  bookSourceUrl: 'https://site.example',
  bookSourceName: '筆趣閣',
  bookSourceGroup: '常用',
  customOrder: 7,
  enabled: false,
  searchUrl: '/search?q={{key}}',
  ruleContent: ContentRule(content: 'id.content@text'),
);

void main() {
  test(
    'the opening says why the source was sent: what the last check found',
    () {
      // 2026-11-13 品书楼：開場重新校驗沒問題，AI 不知道為什麼送來，每段都查。
      const probe = SourceProbeReport(logs: [], requests: []);
      String opening(BookSource source) => aiRepairOpening(
        source: source,
        checkResult: '沒有問題',
        probe: probe,
      ).last.content;

      final sent = _source()
        ..bookSourceGroup = '異常,搜尋失效'
        ..bookSourceComment = '// Error: 搜尋: 搜尋結果為空 (我的)';
      expect(
        opening(sent),
        contains('# 送來修的原因\n上一次校驗的結論：搜尋失效：搜尋: 搜尋結果為空 (我的)。'),
      );
      expect(opening(_source()), isNot(contains('送來修的原因')));
    },
  );

  test('the opening lists the fetched pages without their text; the '
      'clipboard prompt keeps the text', () {
    const probe = SourceProbeReport(
      logs: [(10, '︾開始解析搜尋頁')],
      requests: [
        'https://site.example/s?q=1',
        '  ← 頁 1｜https://site.example/s?q=1 200 text/html，900 位元組，精簡後 '
            '300 字：<div class="list">第一本書</div>',
      ],
    );
    final opening = aiRepairOpening(
      source: _source(),
      checkResult: '搜尋失效',
      probe: probe,
    ).last.content;
    expect(opening, contains('頁 1｜https://site.example/s?q=1 200 text/html'));
    expect(opening, contains('（內容沒放進開場）'));
    expect(opening, isNot(contains('第一本書')));
    expect(
      aiRepairClipboardPrompt(
        source: _source(),
        checkResult: '搜尋失效',
        probe: probe,
      ),
      contains('第一本書'),
      reason: '網頁版 AI 沒有讀頁的工具',
    );
  });

  group('reading the AI reply', () {
    AiToolCall call(String name, String arguments) =>
        (id: 'call_1', name: name, arguments: arguments);

    test(
      'a tool call is read into a command, with a key for its arguments',
      () {
        final test = readAiRepairCall(
          call(
            'test',
            '{"patch":{"ruleSearch":{"bookList":".item"}},"note":"列表換了"}',
          ),
        );
        final command = test.command! as AiTest;
        expect(command.note, '列表換了');
        expect(command.change.patch, {
          'ruleSearch': {'bookList': '.item'},
        });
        expect(
          test.key,
          readAiRepairCall(
            call(
              'test',
              '{"note":"說明不同","patch":{"ruleSearch":{"bookList":".item"}}}',
            ),
          ).key,
          reason: '同樣的參數、說明不同，key 一樣',
        );

        final read = readAiRepairCall(call('read', '{"page":"3"}'));
        expect((read.command! as AiRead).page, 3, reason: '頁碼寫成字串也認');
        final fetch = readAiRepairCall(call('fetch', '{"url":"/"}'));
        expect((fetch.command! as AiFetch).url, '/');
      },
    );

    test('an unreadable call is told what was wrong', () {
      expect(
        readAiRepairCall(call('dance', '{}')).fact,
        allOf(startsWith(aiRepairBadCall), contains('沒有叫 dance 的工具')),
      );
      expect(
        readAiRepairCall(call('fetch', '{"url":')).fact,
        contains('參數不是合法的 JSON'),
      );
      // 2026-11-14 读客书库：模型把內建的工具標記寫進參數，只回「Unexpected
      // character」時它看不出壞在哪，照樣再送兩次，三次讀不懂就停下。
      final broken = readAiRepairCall(
        call('test', '{"note">試抓</parameter>, "patch": {}}'),
      ).fact;
      expect(broken, contains('第 8 個字'));
      expect(broken, contains('{"note">試抓</parameter>'));
      expect(
        readAiRepairCall(call('fetch', '["/"]')).fact,
        contains('參數要是一個 JSON 物件'),
      );
      // 審查：選填參數的型別不對時是讀不懂，不是丟出例外中止整件。
      final wrongType = readAiRepairCall(call('test', '{"patch":{},"from":7}'));
      expect(wrongType.command, isNull);
      expect(wrongType.fact, contains('值不對'));
      expect(
        readAiRepairCall(call('submit', '{}')).fact,
        allOf(contains('少了必要的參數'), contains('patch')),
      );
      expect(readAiRepairCall(call('submit', '{}')).command, isNull);
    });

    test('every tool says which arguments it needs', () {
      for (final tool in aiRepairTools) {
        final properties = tool.parameters['properties']! as Map;
        for (final name in tool.parameters['required']! as List) {
          expect(properties, contains(name), reason: tool.name);
        }
      }
    });

    test('every give-up reason is explained where the AI picks it', () {
      final giveUp = aiRepairTools.singleWhere((t) => t.name == 'give_up');
      final why = (giveUp.parameters['properties']! as Map)['why'] as Map;
      expect(why['enum'], aiGiveUpLabels.keys.toList());
      for (final key in aiGiveUpLabels.keys) {
        expect(why['description'], contains('$key：'), reason: key);
      }
    });

    test(
      'the AI is told how fetched content counts, with the check numbers',
      () {
        // 2026-11-13 涨姿势：AI 不知道正文怎樣算抓到，花四輪猜門檻。
        expect(
          aiRepairSystemPrompt,
          allOf(
            contains('小說去掉圖片後至少 $chapterTextMinRunes 字'),
            contains('至少 ${ChapterContentKind.novelMinRunes} 字是小說'),
            contains('至少 ${ChapterContentKind.comicMinImages} 張圖'),
            contains('give_up 的 not_a_book'),
          ),
        );
      },
    );

    test('the AI is told a failed connect is not the site answering 500', () {
      // 2026-11-14 實跑：望书阁、大白、色情小说、趣书网、饿狼小说兩件，AI 把
      // java.connect 連不上時夜讀填的 500 當成網站回的，多花一兩輪。
      expect(
        aiRepairSystemPrompt,
        allOf(contains('夜讀填的 500'), contains('這段程式送出的請求')),
      );
    });

    test(
      'before saying a site is gone, the AI tries each opening of it once',
      () {
        // 2026-11-14 實跑：躺着看只看裸網域就判網站不在了（www 還是小說站）；
        // 色情小说、趣书网同樣的逾時試了 9、7 輪。
        expect(
          aiRepairSystemPrompt,
          allOf(
            contains('https、http、有沒有 www、m. 的首頁各看一次'),
            contains('同樣的失敗不再換路徑重試'),
          ),
        );
      },
    );

    test(
      'a site that answers only now and then is given up as rate limited',
      () {
        // 2026-11-14 白光、读客书库、思怡小说的網站一下 200、一下 429 或 502，
        // 86读书時快時慢，AI 一直重試、換主機、先修別段，各花二三十輪。還原
        // 读客书库的對話問 AI：「再送一次」沒寫上限、跟「不再等第二次」打架，
        // 換網域與查其他段它當成診斷。工具結果後面列出「同一個請求這次回過
        // 不同的結果」時當下放棄，蓋過其他每一條；還沒列出時只重送一次。
        expect(
          aiRepairSystemPrompt,
          allOf(
            contains('「同一個請求這次回過不同的結果」'),
            contains('這一次回覆就用 give_up 的 rate_limited 放棄'),
            contains('這條蓋過下面每一條'),
            contains('也不查其他段'),
            contains('只送這一次'),
          ),
        );
        final giveUp = aiRepairTools.firstWhere((t) => t.name == 'give_up');
        final why = (giveUp.parameters['properties'] as Map)['why'] as Map;
        expect(why['description'], contains('時好時壞'));
        expect(why['description'], contains('慢到超過校驗的時限'));
      },
    );

    test('a pasted source may be bare, a command, or a Legado array', () {
      expect(pastedSourceJson('```\n{"bookSourceUrl":"a"}\n```'), {
        'bookSourceUrl': 'a',
      });
      expect(
        pastedSourceJson('{"action":"submit","source":{"bookSourceUrl":"b"}}'),
        {'bookSourceUrl': 'b'},
      );
      expect(pastedSourceJson('[{"bookSourceUrl":"c"}]'), {
        'bookSourceUrl': 'c',
      });
      expect(pastedSourceJson('{"name":"不是書源"}'), isNull);
    });

    test('a pasted source missing its last braces, or with braces inside '
        'strings, is still read', () {
      expect(
        pastedSourceJson(
          '好的：\n{"bookSourceUrl":"a","ruleContent":{"content":"a{b}c"}',
        ),
        {
          'bookSourceUrl': 'a',
          'ruleContent': {'content': 'a{b}c'},
        },
      );
      expect(
        pastedSourceJson(r'{"bookSourceUrl":"b","searchUrl":"{{key}} \"}\""}'),
        {'bookSourceUrl': 'b', 'searchUrl': r'{{key}} "}"'},
      );
    });
  });

  test('what goes to the AI leaves out check marks and empty fields', () {
    final source = _source()
      ..addHealthGroups(
        const SourceRuntimeHealth(
          category: SourceHealthCategory.searchBroken,
          label: searchBrokenSourceGroupTag,
          description: '',
          allowsSearch: false,
          allowsReading: true,
          cleanupCandidate: false,
          quarantined: false,
        ),
      )
      ..addErrorComment('搜尋結果為空');

    final json = sourceForAi(source);

    expect(json['bookSourceGroup'], '常用');
    expect(json.containsKey('bookSourceComment'), isFalse);
    expect(json.containsKey('loginUrl'), isFalse);
    expect(json['ruleContent'], {'content': 'id.content@text'});
  });

  test('a patch replaces fields and single rules, and empty values remove '
      'them', () {
    final current = sourceForAi(_source());
    final next = applyAiChange(current, (
      source: null,
      patch: {
        'searchUrl': '',
        'ruleContent': {'content': 'class.txt@text', 'replaceRegex': '##廣告'},
        'header': '{"Referer":"x"}',
      },
    ));

    expect(next.containsKey('searchUrl'), isFalse);
    expect(next['ruleContent'], {
      'content': 'class.txt@text',
      'replaceRegex': '##廣告',
    });
    expect(next['header'], '{"Referer":"x"}');
    expect(current['searchUrl'], '/search?q={{key}}', reason: '原本的不動');
  });

  test('a change naming a field the source does not have is turned back, '
      'with the fields it can use', () {
    // 2026-11-12 涨姿势：AI 把詳情規則寫成 ruleInfo，照收的話什麼都沒改。
    final wrongRule = aiChangeProblem((
      source: null,
      patch: {
        'ruleInfo': {'name': 'h1@text'},
      },
    ));
    expect(wrongRule, contains('ruleInfo'));
    expect(wrongRule, contains('ruleBookInfo'));
    expect(
      aiChangeProblem((
        source: null,
        patch: {
          'ruleToc': {'chapterTitle': 'text'},
        },
      )),
      allOf(contains('chapterTitle'), contains('chapterName')),
    );
    expect(
      aiChangeProblem((
        source: null,
        patch: {
          'ruleBookInfo': {'tocUrl': ''},
          'searchUrl': '/s?q={{key}}',
          'ruleSearch': '',
        },
      )),
      isNull,
    );
  });

  test('the site address may only change at its start', () {
    expect(
      siteMovedUrl('http://www.a.cc/#🎃', 'https://a.cc/whatever'),
      'https://a.cc/#🎃',
    );
    expect(siteMovedUrl('https://a.cc#x', 'https://A.cc'), 'https://a.cc#x');
    expect(siteMovedUrl('https://a.cc', '不是網址'), 'https://a.cc');
    expect(siteMovedUrl('https://a.cc', null), 'https://a.cc');
  });

  test('the AI fixes rules; identity and the user settings stay', () {
    final original = _source();
    final candidate = candidateFrom(original, {
      'bookSourceUrl': 'https://site.example/other',
      'bookSourceName': 'AI 改的名字',
      'bookSourceGroup': '',
      'bookSourceType': 2,
      'enabled': true,
      'searchUrl': '/s?q={{key}}',
      'ruleContent': {'content': 'class.txt@text'},
    });

    expect(candidate.bookSourceUrl, original.bookSourceUrl);
    expect(candidate.bookSourceName, '筆趣閣');
    expect(candidate.bookSourceGroup, '常用');
    expect(candidate.customOrder, 7);
    expect(candidate.enabled, isFalse);
    expect(candidate.bookSourceType, 2);
    expect(candidate.ruleContent?.content, 'class.txt@text');
    expect(changedParts(original, candidate), '類型、搜尋、正文');
  });

  test('later rounds show the probe summary', () {
    const probe = SourceProbeReport(
      logs: [(10, '︾開始解析搜尋頁'), (40, '︽正文頁解析完成 (內容長度: 3214)'), (1000, '︽解析完成')],
      requests: ['https://site.example/s', '  ← https://site.example/s 200'],
      contentUsable: true,
    );

    expect(probe.succeeded, isTrue);
    expect(probe.summary, '正文 3214 字');
    expect(probe.stagesReached, '搜尋、正文');
    expect(probe.pageCount, 1);
    expect(aiRepairProbeReply(probe), startsWith('# 試抓結果：正文 3214 字'));
  });

  test('a probe that reaches only a line of text has not succeeded', () {
    const probe = SourceProbeReport(
      logs: [(40, '︽正文頁解析完成 (內容長度: 11)'), (1000, '︽解析完成')],
      requests: [],
      contentUsable: false,
    );

    expect(probe.succeeded, isFalse);
    expect(probe.summary, startsWith('正文 11 字，書源校驗不算抓到'));
  });

  test('a failed probe says where it stopped', () {
    const probe = SourceProbeReport(
      logs: [(10, '︾開始解析搜尋頁'), (-1, '︽未獲取到書籍')],
      requests: [],
    );

    expect(probe.succeeded, isFalse);
    expect(probe.summary, '未獲取到書籍');
  });
}
