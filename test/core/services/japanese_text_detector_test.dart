import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/japanese_text_detector.dart';

void main() {
  group('looksJapanese', () {
    test('日文句子（漢字假名混排）判定為日文', () {
      expect(looksJapanese('彼は学校に行った'), isTrue);
      expect(looksJapanese('これはペンです'), isTrue);
      expect(looksJapanese('カタカナダケノブン'), isTrue);
      expect(looksJapanese('はい'), isTrue);
      expect(looksJapanese('ｱｲｳｴｵ'), isTrue);
    });

    test('中文句子不誤判', () {
      expect(looksJapanese('完全是中文的句子。'), isFalse);
      expect(looksJapanese('他說「你好」了。'), isFalse);
      expect(looksJapanese(''), isFalse);
      expect(looksJapanese('English only line.'), isFalse);
    });

    test('中文慣用的單一假名與擬聲拖長不觸發', () {
      // 網文常見「XXの店」：單一 の 不算日文。
      expect(looksJapanese('歡迎光臨貓の店'), isFalse);
      // 長音符借作中文擬聲拖長：不是核心假名證據。
      expect(looksJapanese('啊ーーー'), isFalse);
      // 大量中文夾兩個假名：比例門檻擋下。
      expect(looksJapanese('這是一段相當長的中文敘述文字總共非常多漢字がな'), isFalse);
    });
  });
}
