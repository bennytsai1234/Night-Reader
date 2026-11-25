import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/replace_rule/replace_rule_preview.dart';

import '../../test_helper.dart';

void main() {
  // 不匹配時要回溯 2^30 次：在測試的 isolate 直接跑會卡很久。
  ReplaceRule backtracking({int timeout = 200}) => ReplaceRule(
    name: '回溯',
    pattern: r'^(a+)+$',
    replacement: 'x',
    timeoutMillisecond: timeout,
  );
  final backtrackingInput = '${'a' * 30}!';

  test('依序套用每一條規則', () async {
    final result = await ReplaceRulePreview().run([
      ReplaceRule(pattern: r'junk(\d+)', replacement: r'[$1]'),
      ReplaceRule(pattern: '[123]', replacement: '一二三', isRegex: false),
    ], '包含 junk123 內容');
    expect(result, isA<ReplaceRulePreviewDone>());
    expect(result!.display, '包含 一二三 內容');
  });

  test('開了繁簡轉換：同一條規則的兩種寫法每一處只換一次', () async {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
    final result = await ReplaceRulePreview().run(
      [ReplaceRule(pattern: '小说|小說', replacement: '網路小說')],
      '我愛看小說。',
      chineseConvertType: 1,
    );
    expect(result!.display, '我愛看網路小說。');
  });

  test('「替換為」寫 @js: 的規則試跑時照樣跑 JS', skip: quickJsUnavailableReason(), () async {
    final result = await ReplaceRulePreview().run([
      ReplaceRule(
        pattern: r'\d+',
        replacement: '@js:String(Number(result) * 2)',
      ),
    ], '走了 21 步');
    expect(result, isA<ReplaceRulePreviewDone>());
    expect(result!.display, '走了 42 步');
  });

  test('跑超過執行期限就停下，說是哪一條', () async {
    final watch = Stopwatch()..start();
    final result = await ReplaceRulePreview().run([
      ReplaceRule(pattern: '!', replacement: '!'),
      backtracking(),
    ], backtrackingInput);
    expect(result, isA<ReplaceRulePreviewTimedOut>());
    expect(result!.display, '規則「回溯」執行超過 200 毫秒，已停止');
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('下一次試跑作廢還沒跑完的上一次', () async {
    final preview = ReplaceRulePreview();
    final stale = preview.run([
      backtracking(timeout: 60000),
    ], backtrackingInput);
    final fresh = preview.run([
      ReplaceRule(pattern: 'a+', replacement: 'b'),
    ], 'aaa!');
    expect(await stale, isNull);
    expect((await fresh)!.display, 'b!');
  });

  test('取消後傳回 null', () async {
    final preview = ReplaceRulePreview();
    final run = preview.run([backtracking(timeout: 60000)], backtrackingInput);
    preview.cancel();
    expect(await run, isNull);
  });
}
