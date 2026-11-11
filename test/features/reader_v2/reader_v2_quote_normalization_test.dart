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

  test('half-width brackets in Chinese become full-width, nested ones too', () {
    expect(normalizeTypography('他說(真的)。'), '他說（真的）。');
    expect(normalizeTypography('他說(她想(真的嗎)還是假的)'), '他說（她想（真的嗎）還是假的）');
    expect(
      normalizeTypography('他說[她想[真的嗎]還是假的]'),
      normalizeTypography('他說【她想【真的嗎】還是假的】'),
    );
  });

  test('Latin and unpaired brackets stay as they are', () {
    expect(normalizeTypography('f(g(x)) + [1]'), 'f(g(x)) + [1]');
    expect(normalizeTypography('他說(f(x))'), '他說（f(x)）');
    expect(normalizeTypography('他說(真的'), '他說(真的');
    expect(normalizeTypography('真的)他說'), '真的)他說');
    expect(normalizeTypography('他說(第一行\n第二行)'), '他說(第一行\n第二行)');
  });

  test('deeply nested brackets are paired in one pass', () {
    // 每層都重掃括號內文的話，五萬層要掃十二億次，桌機要五秒多。
    const depth = 50000;
    final nested = '中${'(' * depth}x${')' * depth}';
    final stopwatch = Stopwatch()..start();
    final result = normalizeTypography(nested);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(result, '中（${'(' * (depth - 1)}x${')' * (depth - 1)}）');
  });

  test('pure Latin lines keep their quotes', () {
    expect(normalizeTypography('He said “hello”.'), 'He said “hello”.');
    expect(normalizeTypography("don't"), "don't");
  });
}
