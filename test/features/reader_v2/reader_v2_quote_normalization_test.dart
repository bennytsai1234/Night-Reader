import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';

/// 臺灣排版的引號契約：中文脈絡的各種引號一律成為「」，內層為『』。
void main() {
  test('curly, straight and full-width quotes become corner brackets', () {
    expect(normalizeTypography('他說“走吧”。'), '他說「走吧」。');
    expect(normalizeTypography('他說"走吧"。'), '他說「走吧」。');
    expect(normalizeTypography('他說＂走吧＂。'), '他說「走吧」。');
    expect(normalizeTypography('“他說‘不要’。”'), '「他說『不要』。」');
    expect(normalizeTypography('他說＇不要＇。'), '他說『不要』。');
  });

  test('pure Latin lines keep their quotes', () {
    expect(normalizeTypography('He said “hello”.'), 'He said “hello”.');
    expect(normalizeTypography("don't"), "don't");
  });
}
