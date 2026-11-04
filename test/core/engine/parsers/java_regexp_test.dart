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

  test('wholeInput 整段都要符合（Java matches）', () {
    final url = javaRegExp(r'(?i)https://b\.test/BOOK/\d+', wholeInput: true);
    expect(url.hasMatch('https://b.test/book/1'), isTrue);
    expect(url.hasMatch('https://b.test/book/1/toc'), isFalse);
    expect(url.hasMatch('x https://b.test/book/1'), isFalse);
    expect(javaRegExp('a|ab', wholeInput: true).hasMatch('ab'), isTrue);
  });
}
