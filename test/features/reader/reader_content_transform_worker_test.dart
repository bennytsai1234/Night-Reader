import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';

Map<String, Object?> _args({
  Object? rules = const <Object?>[],
  String rawContent = '第一段。\n第二段。',
}) => <String, Object?>{
  'bookName': '測試書',
  'bookOrigin': 'local',
  'chapterTitle': '第一章',
  'rawContent': rawContent,
  'rulesJson': rules,
  'useReplaceRules': true,
  'reSegmentEnabled': true,
  'chineseConvertType': 0,
};

// 不匹配時要回溯 2^30 次：沒有逾時就一直跑下去。
final ReplaceRule _backtracking = ReplaceRule(
  id: 1,
  name: '回溯',
  pattern: r'(?m)^(a+)+$',
  replacement: 'x',
  timeoutMillisecond: 200,
  order: 1,
);
final String _backtrackingContent = '第一段。\n${'a' * 30}!';
final ReplaceRule _after = ReplaceRule(
  id: 2,
  name: '之後',
  pattern: '第一段',
  replacement: '開頭',
  isRegex: false,
  order: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final worker = ReaderContentTransformWorker.instance;

  test('the worker processes chapter content off the main isolate', () async {
    final result = await worker.process(_args());

    expect(result['content'], '　　第一段。\n　　第二段。');
  });

  test('the worker also splits paragraphs and hashes the chapter', () async {
    final result = await worker.process({..._args(), 'chapterIndex': 7});

    final document = result['document']! as ReaderContent;
    final onMain = ReaderContent.fromRaw(
      chapterIndex: 7,
      title: '第一章',
      rawText: '　　第一段。\n　　第二段。',
    );
    expect(document.chapterIndex, 7);
    expect(document.paragraphs, ['第一段。', '第二段。']);
    expect(document.displayText, '第一章\n\n第一段。\n\n第二段。');
    expect(document.contentHash, onMain.contentHash);
  });

  test(
    'content worker repairs an orphan closing quote before making blocks',
    () async {
      final result = await worker.process(
        _args(rawContent: '　　「請進。\n　　」一個悅耳的女性聲音在門後傳來。'),
      );
      expect(result['content'], '　　「請進。」一個悅耳的女性聲音在門後傳來。');
      final document = result['document']! as ReaderContent;
      expect(document.paragraphs, ['「請進。」一個悅耳的女性聲音在門後傳來。']);
    },
  );

  test('curly closing quotes recover CJK shape after joining', () async {
    final result = await worker.process(_args(rawContent: '　　“請進。\n　　”她回答。'));
    expect(result['content'], '　　「請進。」她回答。');
  });

  test(
    'a blank source line still separates paragraphs after conversion',
    () async {
      final result = await worker.process({
        ..._args(rawContent: '「請進。\n\n」下一段刻意從引號開始。'),
        'reSegmentEnabled': false,
      });
      final document = result['document']! as ReaderContent;
      expect(document.paragraphs, ['「請進。', '」下一段刻意從引號開始。']);
    },
  );

  test(
    'with re-segmenting on, a sentence broken across a blank line joins',
    () async {
      final result = await worker.process(
        _args(rawContent: '他推開門走了\n\n進去，屋裡一片漆黑。'),
      );
      final document = result['document']! as ReaderContent;
      expect(document.paragraphs, ['他推開門走了進去，屋裡一片漆黑。']);
    },
  );

  test(
    'selection source paragraphs line up with shown ones around illustrations',
    () async {
      final book = Book(bookUrl: 'b', name: '測試書', origin: 'local')
        ..readConfig = ReadConfig(useReplaceRule: true, reSegment: true);
      final long = '前文。${'甲' * 180}。後文。\n<img src="a.png">';
      for (final raw in [long, '「請進。\n<img src="a.png">\n」她說。']) {
        final result = await worker.process(_args(rawContent: raw));
        final document = result['document']! as ReaderContent;
        final sources = await ReaderContentTransformer.ruleStageParagraphs(
          book: book,
          chapter: BookChapter(url: 'c', title: '第一章'),
          rawContent: raw,
          enabledRules: const [],
          chineseConvertType: 0,
        );
        expect(
          sources.paragraphs,
          hasLength(document.paragraphs.length),
          reason: raw,
        );
      }
    },
  );

  test(
    'a failed chapter surfaces as an error and the worker keeps serving',
    () async {
      await expectLater(
        worker.process(_args(rules: const <Object?>['不是規則'])),
        throwsA(isA<ReaderContentTransformException>()),
      );

      final result = await worker.process(_args());
      expect(result['content'], '　　第一段。\n　　第二段。');
    },
  );

  group('替換規則跑超過逾時', () {
    test('停下那一條、說是哪一條，其他規則照常套完', () async {
      final timedOut = <ReplaceRule>[];
      final watch = Stopwatch()..start();
      final result = await worker.process(
        _args(
          rules: [_backtracking.toJson(), _after.toJson()],
          rawContent: _backtrackingContent,
        ),
        onRuleTimedOut: timedOut.add,
      );

      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(timedOut.map((rule) => rule.name), ['回溯']);
      expect(result['content'], '　　開頭。\n　　${'a' * 30}!');
    });

    test('排在後面、也有那一條的章不再跑它', () async {
      final first = <ReplaceRule>[];
      final second = <ReplaceRule>[];
      final args = _args(
        rules: [_backtracking.toJson(), _after.toJson()],
        rawContent: _backtrackingContent,
      );
      final results = await Future.wait([
        worker.process(args, onRuleTimedOut: first.add),
        worker.process({...args}, onRuleTimedOut: second.add),
      ]);

      // 兩章可能屬於不同的閱讀器，都要知道它停用了。
      expect(first.map((rule) => rule.name), ['回溯']);
      expect(second.map((rule) => rule.name), ['回溯']);
      for (final result in results) {
        expect(result['content'], '　　開頭。\n　　${'a' * 30}!');
      }
    });

    test('同一個閱讀器排著好幾章時只通知一次', () async {
      final timedOut = <ReplaceRule>[];
      final args = _args(
        rules: [_backtracking.toJson(), _after.toJson()],
        rawContent: _backtrackingContent,
      );
      await Future.wait([
        worker.process(args, onRuleTimedOut: timedOut.add),
        worker.process({...args}, onRuleTimedOut: timedOut.add),
      ]);

      expect(timedOut.map((rule) => rule.name), ['回溯']);
    });

    test('標題規則跑超過逾時也停下那一條', () async {
      final titleRule = ReplaceRule(
        id: 3,
        name: '標題回溯',
        pattern: r'^(a+)+$',
        replacement: 'x',
        scopeTitle: true,
        scopeContent: false,
        timeoutMillisecond: 200,
      );
      final timedOut = <ReplaceRule>[];
      final result = await worker.process({
        ..._args(rules: [titleRule.toJson()]),
        'chapterTitle': '${'a' * 30}!',
      }, onRuleTimedOut: timedOut.add);

      expect(timedOut.map((rule) => rule.name), ['標題回溯']);
      expect(result['displayTitle'], '${'a' * 30}!');
    });

    test('停下之後照常處理下一章', () async {
      await worker.process(
        _args(
          rules: [_backtracking.toJson()],
          rawContent: _backtrackingContent,
        ),
        onRuleTimedOut: (_) {},
      );

      final result = await worker.process(_args(rules: [_after.toJson()]));
      expect(result['content'], '　　開頭。\n　　第二段。');
    });
  });

  // 先轉繁簡再套規則（同 Legado），規則的字也轉成顯示的寫法（ADR 0084）。
  group('繁簡轉換與替換規則的先後', () {
    const s2t = 1;
    Map<String, Object?> converting(List<ReplaceRule> rules) => {
      ..._args(
        rules: [for (final rule in rules) rule.toJson()],
        rawContent: '她的头发很长。\n广告词结束。',
      ),
      'chapterTitle': '第一章 求月票',
      'chineseConvertType': s2t,
    };

    test('照畫面上的繁體寫的規則對得到簡體原文', () async {
      final result = await worker.process(
        converting([
          ReplaceRule(pattern: '廣告詞結束。', replacement: '', isRegex: false),
          ReplaceRule(
            pattern: r' ?求月票$',
            replacement: '',
            scopeTitle: true,
            scopeContent: false,
          ),
        ]),
      );
      expect(result['content'], '　　她的頭髮很長。');
      expect(result['displayTitle'], '第一章');
    });

    test('照原文的簡體寫的規則照樣對得到，換上的字照字面放（同 Legado）', () async {
      final result = await worker.process(
        converting([
          ReplaceRule(pattern: '头发', replacement: '这是', isRegex: false),
          ReplaceRule(pattern: r'(广告)词', replacement: r'$1语'),
        ]),
      );
      expect(result['content'], '　　她的这是很長。\n　　廣告语結束。');
    });

    Map<String, Object?> chapter(
      String raw,
      List<ReplaceRule> rules, {
      int convertType = s2t,
      String title = '第一章',
    }) => {
      ..._args(
        rules: [for (final rule in rules) rule.toJson()],
        rawContent: raw,
      ),
      'chapterTitle': title,
      'chineseConvertType': convertType,
    };

    test('照畫面建的規則（選字隱藏「干擾。」）照字面對得到，不再轉一次變字', () async {
      final result = await worker.process(
        chapter('前文。\n干扰。', [
          ReplaceRule(pattern: '干擾。', replacement: '', isRegex: false),
        ]),
      );
      expect(result['content'], '　　前文。');
    });

    test('換成「襯托」，正文就是「襯托」', () async {
      final result = await worker.process(
        chapter('前文。\n后文。', [
          ReplaceRule(pattern: '前文', replacement: '襯托', isRegex: false),
        ]),
      );
      expect(result['content'], '　　襯托。\n　　後文。');
    });

    test('標題規則寫繁體時，正文開頭重複的章名照樣去得掉', () async {
      final result = await worker.process(
        chapter('第一章 风起\n正文开始。', [
          ReplaceRule(
            pattern: '【廣告】',
            replacement: '',
            isRegex: false,
            scopeTitle: true,
            scopeContent: false,
          ),
        ], title: '第一章 风起【广告】'),
      );
      expect(result['content'], '　　正文開始。');
      expect(result['displayTitle'], '第一章 風起');
    });

    test('關掉繁簡轉換時照字面比：簡轉繁下建的繁體規則對不到簡體原文', () async {
      final result = await worker.process(
        chapter('她的头发很长。', [
          ReplaceRule(pattern: '頭髮', replacement: '', isRegex: false),
        ], convertType: 0),
      );
      expect(result['content'], '　　她的头发很长。');
    });

    test('同一條規則的兩種寫法每一處只換一次，不把剛換上的字再換一次', () async {
      final result = await worker.process(
        chapter('我爱看小说。', [
          ReplaceRule(pattern: '小说|小說', replacement: '網路小說', scopeTitle: true),
        ], title: '第一章 小说'),
      );
      expect(result['content'], '　　我愛看網路小說。');
      expect(result['displayTitle'], '第一章 網路小說');
    });

    test('選字找原文用的段落也是轉過的寫法', () async {
      final sources = await ReaderContentTransformer.ruleStageParagraphs(
        book: Book(bookUrl: 'b', name: '測試書', origin: 'local')
          ..readConfig = ReadConfig(useReplaceRule: true),
        chapter: BookChapter(url: 'c', title: '第一章'),
        rawContent: '她的头发很长。\n广告词结束。',
        enabledRules: [
          ReplaceRule(pattern: '廣告詞結束。', replacement: '', isRegex: false),
        ],
        chineseConvertType: s2t,
      );
      expect(sources.paragraphs, ['她的頭髮很長。']);
      expect(
        await ReaderContentTransformer.sourceParagraphs(
          rawContent: '她的头发很长。\n广告词结束。',
          chineseConvertType: s2t,
        ),
        ['她的頭髮很長。', '廣告詞結束。'],
      );
    });
  });
}
