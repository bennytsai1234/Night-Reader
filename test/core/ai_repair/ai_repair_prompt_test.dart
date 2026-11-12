import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';

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
  group('reading the AI reply', () {
    test('finds the command inside prose and code fences', () {
      final command = AiRepairCommand.parse('''
好的，我改了正文規則：
```json
{"action":"test","source":{"bookSourceUrl":"x","ruleContent":{"content":"class.txt@text"}},"note":"正文換成 class.txt"}
```
''');

      expect(command, isA<AiTest>());
      final test = command! as AiTest;
      expect(test.note, '正文換成 class.txt');
      expect(test.change.source!['ruleContent'], {'content': 'class.txt@text'});
    });

    test('a patch, a page to look at, and a reply missing its last braces', () {
      final patch = AiRepairCommand.parse(
        '{"action":"test","patch":{"ruleSearch":{"bookList":".item"}},"note":"列表換了"}',
      );
      expect((patch! as AiTest).change.patch, {
        'ruleSearch': {'bookList': '.item'},
      });

      final fetch = AiRepairCommand.parse('{"action":"fetch","url":"/"}');
      expect((fetch! as AiFetch).url, '/');

      final unclosed = AiRepairCommand.parse(
        '{"action":"test","source":{"ruleContent":{"content":"a{b}c"}},"note":"x"',
      );
      expect((unclosed! as AiTest).change.source!['ruleContent'], {
        'content': 'a{b}c',
      });

      final withList = AiRepairCommand.parse(
        '{"action":"test","patch":{"ruleSearch":{"bookList":"[x]"},"x":[1,{"a":2',
      );
      expect((withList! as AiTest).change.patch!['x'], [
        1,
        {'a': 2},
      ]);
    });

    test('an unreadable reply is told what was wrong', () {
      expect(aiRepairBadReplyFor('沒有 JSON'), contains('裡面沒有 JSON 物件'));
      expect(aiRepairBadReplyFor('{"a":1,}'), contains('JSON 格式錯'));
      expect(
        aiRepairBadReplyFor('{"action":"test"}'),
        contains('action 或欄位不對'),
      );
    });

    test('braces inside strings do not end the object early', () {
      final command = AiRepairCommand.parse(
        r'{"action":"give_up","reason":"規則 {{key}} 的 \"}\" 不對"}',
      );

      expect((command! as AiGiveUp).reason, r'規則 {{key}} 的 "}" 不對');
    });

    test('unknown actions and broken JSON are not commands', () {
      expect(AiRepairCommand.parse('我覺得是正文規則的問題'), isNull);
      expect(AiRepairCommand.parse('{"action":"dance"}'), isNull);
      expect(AiRepairCommand.parse('{"action":"submit"}'), isNull);
    });

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
    );

    expect(probe.succeeded, isFalse);
    expect(probe.summary, '正文 11 字');
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
