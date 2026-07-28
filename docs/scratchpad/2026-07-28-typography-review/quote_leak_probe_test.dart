// 驗證假設：同一章內會不會殘留未轉換的 “ ” " ' ‘ ’，
// 導致粗彎引號與細直角引號混用（使用者回報「跟正常引號長不一樣」）。
// 執行：flutter test docs/scratchpad/2026-07-28-typography-review/quote_leak_probe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';

const _quoteRunes = <int, String>{
  0x201C: '“',
  0x201D: '”',
  0x2018: '‘',
  0x2019: '’',
  0x22: '"',
  0x27: "'",
};

String _leaks(String text) {
  final found = <String>[];
  for (final rune in text.runes) {
    final ch = _quoteRunes[rune];
    if (ch != null && !found.contains(ch)) found.add(ch);
  }
  return found.isEmpty ? '(無殘留)' : found.join(' ');
}

void main() {
  const cases = <String, String>{
    '多段落連續對白（中文小說標準用法）':
        '“我跟你說，這件事沒那麼簡單。\n'
        '“你以為他們是來談判的嗎？\n'
        '“他們是來收屍的。”',
    '落單開引號（下一段才收）': '他忽然開口：“這是我最後一次警告你',
    '落單收引號': '……我不會再說第二次。”他轉身離開。',
    '引號內又開引號': '“他說“不要”，然後就走了。”',
    '直引號奇數個（整行放棄）': '他喊道："住手!，聲音很大。',
    '直引號偶數個': '他喊道："住手!"，聲音很大。',
    '混合直引號與彎引號': '他說“好”，她回答"不好"。',
    '英文撇號在中文行': '他哼著 don\'t stop believin\' 走進房間。',
    '純英文行': '"Hello," he said, "how are you?"',
    '跨段的彎引號（段落間隔）': '“第一段。\n\n中間敘述。\n\n第二段。”',
  };

  test('殘留引號掃描', () {
    for (final entry in cases.entries) {
      final out = normalizeTypography(entry.value);
      // ignore: avoid_print
      print(
        '── ${entry.key}\n'
        'IN : ${entry.value.replaceAll('\n', ' ⏎ ')}\n'
        'OUT: ${out.replaceAll('\n', ' ⏎ ')}\n'
        '殘留: ${_leaks(out)}\n',
      );
    }
  });
}
