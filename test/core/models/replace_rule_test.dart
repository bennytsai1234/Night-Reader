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

    test('Java 的原子群組與所有格量詞也能取代，分組編號不變', () {
      expect(regex(r'\d++').apply('abc123'), 'abc');
      expect(regex(r'(?>廣告)+').apply('廣告廣告正文'), '正文');
      expect(regex(r'(?>廣告)(\d+)', r'[$1]').apply('廣告123'), '[123]');
      expect(regex(r'\d++').isValid(), isTrue);
      expect(regex(r'(?>廣告)+').isValid(), isTrue);
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

  group('「替換為」照 Java 的取代字串（同 Legado）', () {
    String apply(String pattern, String replacement, String content) =>
        ReplaceRule(pattern: pattern, replacement: replacement).apply(content);

    test(r'${名稱} 取具名群組', () {
      expect(apply(r'(?<num>\d+)章', r'第${num}回', '12章'), '第12回');
    });

    test(r'\ 跳脫下一個字：\$ 是錢字號、\\ 是反斜線', () {
      expect(apply('元', r'\$\\', '十元'), r'十$\');
    });

    test(r'$12 只有一個群組時是第 1 組接著字「2」', () {
      expect(apply(r'(a)', r'$12', 'a'), 'a2');
    });

    test(r'$1 到 $n 與 $0 照舊', () {
      expect(apply(r'(甲)(乙)', r'$2$1$0', '甲乙'), '乙甲甲乙');
    });

    test('寫錯的取代字串（沒有的群組、結尾落單的 \\）整條規則不套，正文照舊', () {
      expect(apply(r'(a)', r'$2', 'abc'), 'abc');
      expect(apply(r'(a)', r'${none}', 'abc'), 'abc');
      expect(apply('a', r'x\', 'abc'), 'abc');
    });
  });
}
