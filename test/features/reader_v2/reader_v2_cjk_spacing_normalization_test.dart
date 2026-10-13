import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';

/// 中文旁邊的半形空格在顯示時拿掉：中英文之間的間隙改由排版補白提供。
void main() {
  test('spaces between Chinese and Latin letters or digits are dropped', () {
    expect(normalizeTypography('他在 iPhone 上看書'), '他在iPhone上看書');
    expect(normalizeTypography('第 3 章'), '第3章');
    expect(normalizeTypography('共 100 萬字'), '共100萬字');
    expect(normalizeTypography('他說 「你好」'), '他說「你好」');
    expect(normalizeTypography('中  文'), '中文', reason: '連續空格視為一處');
  });

  test('spaces inside Latin text stay', () {
    expect(normalizeTypography('他買了 iPhone 15 Pro 了'), '他買了iPhone 15 Pro了');
    expect(normalizeTypography('He said hello'), 'He said hello');
  });

  test('titles keep their deliberate spaces', () {
    expect(normalizeTypography('第一章 起點', preserveCjkSpaces: true), '第一章 起點');
    expect(
      normalizeTypography('第 1 章 起點', preserveCjkSpaces: true),
      '第 1 章 起點',
    );
  });
}
