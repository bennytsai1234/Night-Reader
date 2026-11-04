import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';

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
  final worker = ReaderV2ContentTransformWorker.instance;

  test('the worker processes chapter content off the main isolate', () async {
    final result = await worker.process(_args());

    expect(result['content'], '　　第一段。\n　　第二段。');
  });

  test('the worker also splits paragraphs and hashes the chapter', () async {
    final result = await worker.process({..._args(), 'chapterIndex': 7});

    final document = result['document']! as ReaderV2Content;
    final onMain = ReaderV2Content.fromRaw(
      chapterIndex: 7,
      title: '第一章',
      rawText: '　　第一段。\n　　第二段。',
    );
    expect(document.chapterIndex, 7);
    expect(document.paragraphs, onMain.paragraphs);
    expect(document.displayText, onMain.displayText);
    expect(document.contentHash, onMain.contentHash);
  });

  test(
    'a failed chapter surfaces as an error and the worker keeps serving',
    () async {
      await expectLater(
        worker.process(_args(rules: const <Object?>['不是規則'])),
        throwsA(isA<ReaderV2ContentTransformException>()),
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

      expect(first.map((rule) => rule.name), ['回溯']);
      expect(second, isEmpty);
      for (final result in results) {
        expect(result['content'], '　　開頭。\n　　${'a' * 30}!');
      }
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
}
