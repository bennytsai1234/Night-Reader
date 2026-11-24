import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/parsers/java_regexp.dart';

/// 期待值都在 Java 21 的 `Pattern` 上對照過。
void main() {
  bool find(String pattern, String input) =>
      javaRegExp(pattern).hasMatch(input);

  test('預設 . 不跨行，(?s) 才跨', () {
    expect(find('第一.*第二', '第一章\n第二章'), isFalse);
    expect(find('(?s)第一.*第二', '第一章\n第二章'), isTrue);
  });

  test(r'沒開 (?m) 時 ^ 只對開頭，$ 只對結尾或最後一個換行之前', () {
    expect(find('^b', 'a\nb'), isFalse);
    expect(find(r'a$', 'a\nb'), isFalse);
    expect(find(r'a$', 'a\n'), isTrue);
    expect(find(r'a$', 'a\r\n'), isTrue);
    expect(find(r'a$', 'a\n\n'), isFalse);
    expect(find(r'(?m)^b', 'a\nb'), isTrue);
    expect(find(r'(?m)a$', 'a\nb'), isTrue);
  });

  test(r'跳脫的 $ 與字元集合裡的 $ 照字面', () {
    expect(find(r'a\$', r'a$'), isTrue);
    expect(find(r'a[$]', r'a$'), isTrue);
  });

  test(r'\A、\z、\Z', () {
    expect(find(r'\Ab', 'a\nb'), isFalse);
    expect(find(r'(?m)\Aa', 'a\nb'), isTrue);
    expect(find(r'a\z', 'a\n'), isFalse);
    expect(find(r'a\Z', 'a\n'), isTrue);
  });

  test('開頭連續的旗標都認得', () {
    expect(find('(?i)(?s)a.b', 'A\nB'), isTrue);
    expect(find('(?is)a.b', 'A\nB'), isTrue);
  });

  test('(?x) 拿掉空白與註解，字元集合裡也是', () {
    expect(find('(?x)a b', 'ab'), isTrue);
    expect(find(r'(?x)a\ b', 'a b'), isTrue);
    expect(find('(?x)a # 註解\nb', 'ab'), isTrue);
    expect(find('(?x)[a b]', ' '), isFalse);
  });

  test('Java 的原子群組與所有格量詞換成 Dart 的等價寫法', () {
    // 原子群組不佔編號：$1 仍指到後面那個捕獲組。
    final atomic = javaRegExp(r'(?>廣告)(\d+)').firstMatch('廣告123')!;
    expect(atomic.group(0), '廣告123');
    expect(atomic.group(1), '123');

    // 所有格量詞拿掉後面多出來的那個 +，比對結果照規則的意思。
    expect(find(r'\d++', 'abc123'), isTrue);
    expect(find(r'a*+b', 'aaab'), isTrue);
    expect(find(r'a?+b', 'ab'), isTrue);
    expect(find(r'a{2,3}+b', 'aaab'), isTrue);
    // 跳脫的加號後面接一般量詞、字元集合裡的加號都不動。
    expect(find(r'\++', '++'), isTrue);
    expect(find(r'[+*]+', '+*'), isTrue);
    // 懶惰量詞照原樣留著。
    expect(javaRegExp(r'a+?').firstMatch('aaa')!.group(0), 'a');
  });

  test('Unicode 跳脫與註解模式的量詞不被當成所有格', () {
    expect(javaRegExp(r'(?u)\u{61}+').firstMatch('aaa')!.group(0), 'aaa');
    expect(find(r'(?x)a{2, 3}+b', 'aaab'), isTrue);
    expect(find(r'(?x)a{2, 3}b', 'aaab'), isTrue);
    // 註解模式裡量詞中的註解也算空白。
    expect(find('(?x)a{2, # 兩個到\n 3}+b', 'aaab'), isTrue);
  });

  test('wholeInput 整段都要符合（Java matches）', () {
    final url = javaRegExp(r'(?i)https://b\.test/BOOK/\d+', wholeInput: true);
    expect(url.hasMatch('https://b.test/book/1'), isTrue);
    expect(url.hasMatch('https://b.test/book/1/toc'), isFalse);
    expect(url.hasMatch('x https://b.test/book/1'), isFalse);
    expect(javaRegExp('a|ab', wholeInput: true).hasMatch('ab'), isTrue);
  });

  test('wholeInput 寫錯的規則照樣丟錯，不和包在外面的字接成別的規則', () {
    for (final broken in ['[https', r'https://s\.example/book/[0-9', 'a)|(b']) {
      expect(
        () => javaRegExp(broken, wholeInput: true),
        throwsFormatException,
        reason: broken,
      );
    }
  });
  // Java 的 Pattern 不用開選項就認得 \p{…}；Dart 要開 unicode，沒開時 \p 是
  // 字母 p。Java 專有的名稱換成 Dart 認得的寫法。
  group(r'\p{…} 字元類別', () {
    List<String> all(String pattern, String input) => [
      for (final m in javaRegExp(pattern).allMatches(input)) m.group(0)!,
    ];

    test('一般分類：標點、文字、數字', () {
      // { } 在 Unicode 是標點（Ps、Pe），Java 一樣對得到；p、P 是字母。
      expect(all(r'[\p{P}]+', 'a,b。cpP{}'), [',', '。', '{}']);
      expect(all(r'\p{L}+', '中文 abc'), ['中文', 'abc']);
      expect(all(r'\pL+', '中文1'), ['中文']);
      expect(all(r'\P{L}+', '中文12文'), ['12']);
      expect(all(r'\p{IsP}', 'a！'), ['！']);
      expect(all(r'\p{Nd}+', '第12章'), ['12']);
    });

    test('文字系統與 Unicode 區塊', () {
      expect(all(r'\p{IsHan}+', 'abc漢字def'), ['漢字']);
      expect(all(r'\p{script=Han}+', 'abc漢字'), ['漢字']);
      expect(all(r'\p{InCJKUnifiedIdeographs}+', 'a漢字。'), ['漢字']);
      expect(all(r'[^\p{InCJKUnifiedIdeographs}]+', '漢字，abc'), ['，abc']);
    });

    // Legado 跑在 Android 上，Java 的正則由 ICU 執行：POSIX 名稱照 Unicode
    // 認（桌機的 JDK 只看 ASCII）。
    test('POSIX 名稱照 Android（ICU）認 Unicode', () {
      expect(all(r'\p{Punct}+', 'a,.b。'), [',.', '。']);
      expect(all(r'\p{Alpha}+', 'abc中α1'), ['abc中α']);
      expect(all(r'\p{Digit}+', 'a12３'), ['12３']);
      expect(all(r'\p{Space}', 'a b　'), [' ', '　']);
      expect(all(r'\p{Blank}+', 'a \t　b\n'), [' \t　']);
      expect(all(r'\p{Alnum}+', '中3,'), ['中3']);
      expect(all(r'\p{XDigit}+', 'xaF9g'), ['aF9']);
      expect(all(r'\p{ASCII}+', 'ab中'), ['ab']);
      expect(all(r'[^\P{Punct}]+', 'a。b'), ['。']);
      expect(all(r'\p{Graph}+', 'a b'), ['a', 'b']);
      expect(all(r'\p{Print}+', 'a b\n'), ['a b']);
    });

    test('Java 的 java… 名稱與不加 Is 的文字系統', () {
      expect(all(r'\p{javaLowerCase}+', 'aBc'), ['a', 'c']);
      expect(all(r'\p{javaWhitespace}+', 'a \tb'), [' \t']);
      expect(all(r'\p{Han}+', 'ab漢字'), ['漢字']);
    });

    test(r'規則有 \p 時，其他 Java 寫法照樣能用', () {
      expect(all(r'\p{L}\x{41}', '中A'), ['中A']);
      expect(all(r'\p{L}\0101', '中A'), ['中A']);
      expect(all(r'\p{L}\Q.*\E', '中.*'), ['中.*']);
      expect(all(r'\p{L}\h\p{L}', '甲　乙'), ['甲　乙']);
      expect(all(r'\p{L}\R', '甲\r\n'), ['甲\r\n']);
      expect(all(r'\p{L}\e', '甲\u001B'), ['甲\u001B']);
    });

    test(r'規則裡其他 Java 的跳脫照樣能用', () {
      expect(all(r'[\p{P}\-_]+', 'a-_,b'), ['-_,']);
      expect(all(r'\p{P}\<\"', '，<"'), ['，<"']);
      expect(all(r'[\w-]+\p{P}', 'ab-c。'), ['ab-c。']);
      expect(all(r'\p{L}}', '中}'), ['中}']);
    });

    test('認不得的名稱丟出 FormatException', () {
      expect(() => javaRegExp(r'\p{NoSuchThing}'), throwsFormatException);
    });
  });
}
