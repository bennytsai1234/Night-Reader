import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/services/chinese_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ChineseUtils.initialize();
  });

  group('ChineseUtils Tests', () {
    test('Simplified to Traditional conversion', () {
      expect(ChineseUtils.s2t('万与丑专业'), '萬與醜專業');
      expect(ChineseUtils.s2t('书买乱争'), '書買亂爭');
    });

    test('Traditional to Simplified conversion', () {
      expect(ChineseUtils.t2s('萬與醜專業'), '万与丑专业');
      expect(ChineseUtils.t2s('書買亂爭'), '书买乱争');
    });

    test('Handling characters not in table', () {
      expect(ChineseUtils.s2t('你好 abc 123'), '你好 abc 123');
    });

    test('Empty string returns empty', () {
      expect(ChineseUtils.s2t(''), '');
      expect(ChineseUtils.t2s(''), '');
    });

    test('Phrase-level conversion handles ambiguous characters', () {
      // 「发」在不同上下文有不同繁體：「發」vs「髮」
      // 詞彙級字典應正確處理
      final result = ChineseUtils.s2t('头发');
      expect(result, '頭髮');
    });
  });
}
