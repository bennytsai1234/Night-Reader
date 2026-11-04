import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';

void main() {
  ReplaceRule regex(String pattern, [String replacement = '']) =>
      ReplaceRule(pattern: pattern, replacement: replacement);

  group('正則照 Java 預設（同 Legado）', () {
    test('. 預設不跨段', () {
      expect(regex('廣告.*結束').apply('廣告一\n二結束\n正文'), '廣告一\n二結束\n正文');
      expect(regex('廣告.*').apply('廣告一\n正文'), '\n正文');
    });

    test('開頭寫 (?s) 才跨段', () {
      expect(regex('(?s)廣告.*結束').apply('廣告一\n二結束\n正文'), '\n正文');
    });

    test('^ 預設只對整段開頭，寫 (?m) 才逐行', () {
      expect(regex('^廣告').apply('廣告甲\n廣告乙'), '甲\n廣告乙');
      expect(regex('(?m)^廣告').apply('廣告甲\n廣告乙'), '甲\n乙');
    });

    test(r'$ 預設只對結尾（與最後一個換行之前），寫 (?m) 才逐行', () {
      expect(regex(r'完$').apply('甲完\n乙完'), '甲完\n乙');
      expect(regex(r'(?m)完$').apply('甲完\n乙完'), '甲\n乙');
    });

    test(r'(?i) 不分大小寫，分組照樣用 $1', () {
      expect(regex(r'(?i)ad(\d)', r'[$1]').apply('AD1 ad2'), '[1] [2]');
    });

    test('寫了 (?s) 的規則是合法的規則', () {
      expect(regex('(?s)廣告.*結束').isValid(), isTrue);
      expect(regex('(?s)(').isValid(), isFalse);
    });
  });

  test('純文字規則照字面替換，. ^ \$ 不是特殊字元', () {
    final plain = ReplaceRule(
      pattern: r'^廣.告$',
      replacement: '',
      isRegex: false,
    );
    expect(
      plain.apply(
        r'甲^廣.告$乙'
        '\n廣告',
      ),
      '甲乙\n廣告',
    );
    expect(plain.isValid(), isTrue);
  });
}
