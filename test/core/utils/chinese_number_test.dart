import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/string_utils.dart';

/// 中文數字只有一份換算：`java.toNumChapter` 與搜尋結果比較最新章節的章數
/// （`SearchBook`）都用它。
void main() {
  test('the spoken form drops the last unit: 一百一 is 110, like 一千五', () {
    expect(StringUtils.chineseNumToInt('一百一'), 110);
    expect(StringUtils.chineseNumToInt('二百二'), 220);
    expect(StringUtils.chineseNumToInt('一千五'), 1500);
    expect(StringUtils.chineseNumToInt('一萬二'), 12000);
  });

  test('a zero keeps the next digit in the ones place', () {
    expect(StringUtils.chineseNumToInt('一百零一'), 101);
    expect(StringUtils.chineseNumToInt('一千零五'), 1005);
    expect(StringUtils.chineseNumToInt('一百一十'), 110);
  });

  test('simplified, traditional and formal digits read the same', () {
    for (final number in ['两百', '兩百', '贰佰', '貳佰']) {
      expect(StringUtils.chineseNumToInt(number), 200, reason: number);
    }
    expect(StringUtils.chineseNumToInt('十二万三千'), 123000);
    expect(StringUtils.chineseNumToInt('一亿'), 100000000);
    expect(StringUtils.chineseNumToInt('一零二五'), 1025);
  });

  test('a run of Chinese digits is found whole', () {
    expect(StringUtils.chineseNumberRun.firstMatch('第两百章')?.group(0), '两百');
    expect(
      StringUtils.chineseNumberRun.firstMatch('第十二万三千章')?.group(0),
      '十二万三千',
    );
  });
}
