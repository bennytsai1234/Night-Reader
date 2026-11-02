import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// `java.md5Encode`、`digestHex`、`new java.lang.String(…)` 交回的文字，整段
/// 規則就是它時，規則拿到的是那段文字，同 Legado（交回 Java 的 String）；
/// 不是 `{_value: …}`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule() =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://m.test'))
          .setContent('<p>x</p>', baseUrl: 'https://m.test/');

  test('雜湊結果是文字', () {
    expect(
      rule().getString('@js:java.md5Encode("x")'),
      '9dd4e461268c8034f5c8564e155c67a6',
    );
    expect(rule().getString('@js:java.md5Encode16("x")'), '268c8034f5c8564e');
    expect(rule().getStringList('@js:java.md5Encode("x")'), [
      '9dd4e461268c8034f5c8564e155c67a6',
    ]);
  });

  test('Java 的 String 是文字，放在清單裡也是', () {
    expect(rule().getString('@js:new Packages.java.lang.String("夜讀")'), '夜讀');
    expect(
      rule().getStringList(
        '@js:[new Packages.java.lang.String("a"), java.md5Encode16("x")]',
      ),
      ['a', '268c8034f5c8564e'],
    );
  });

  test('網址規則整段是簽章時照常組成網址', () {
    expect(
      rule().getString('@js:"/s?sign=" + java.md5Encode("x")', isUrl: true),
      'https://m.test/s?sign=9dd4e461268c8034f5c8564e155c67a6',
    );
    expect(
      rule().getString('@js:java.md5Encode16("x")', isUrl: true),
      'https://m.test/268c8034f5c8564e',
    );
  });
}
