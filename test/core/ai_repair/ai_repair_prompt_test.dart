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
      expect(test.source['ruleContent'], {'content': 'class.txt@text'});
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

  test('the AI fixes rules; identity and the user settings stay', () {
    final original = _source();
    final candidate = candidateFrom(original, {
      'bookSourceUrl': 'https://other.example',
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

  test('later rounds show the probe summary and how many rounds are left', () {
    const probe = SourceProbeReport(
      logs: [(10, '︾開始解析搜尋頁'), (40, '︽正文頁解析完成 (內容長度: 3214)'), (1000, '︽解析完成')],
      requests: ['https://site.example/s', '  ← https://site.example/s 200'],
    );

    expect(probe.succeeded, isTrue);
    expect(probe.summary, '正文 3214 字');
    expect(probe.stagesReached, '搜尋、正文');
    expect(probe.pageCount, 1);
    expect(
      aiRepairProbeReply(probe, roundsLeft: 0),
      allOf(startsWith('# 試抓結果：正文 3214 字'), endsWith('這是最後一輪，請交出或放棄。')),
    );
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
