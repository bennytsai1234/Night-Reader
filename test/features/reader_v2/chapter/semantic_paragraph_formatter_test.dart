import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/chapter/semantic_paragraph_formatter.dart';

void main() {
  group('正文段落整理', () {
    test('把孤立的下引號接回同一句，保留後面的敘述', () {
      const source = '「請進。\n」一個悅耳的女性聲音在門後傳來。';
      expect(
        SemanticParagraphFormatter.repair(source),
        '「請進。」一個悅耳的女性聲音在門後傳來。',
      );
      expect(ReaderV2Content.paragraphsOf(source), [
        '「請進。」一個悅耳的女性聲音在門後傳來。',
      ]);
    });

    test('行首帶有來源縮排時，不把縮排塞進段落中間', () {
      const source = '　　「請進。\n　　」一個悅耳的聲音。';
      expect(
        SemanticParagraphFormatter.repair(source),
        '　　「請進。」一個悅耳的聲音。',
      );
    });

    test('落單的彎引號也會接回，供之後的中文標點正規化使用', () {
      expect(
        SemanticParagraphFormatter.repair('「請進。\n”她回答。'),
        '「請進。”她回答。',
      );
    });

    test('開頭標點留在行尾時接上下一行', () {
      expect(
        SemanticParagraphFormatter.repair('他說：「\n你好。」'),
        '他說：「你好。」',
      );
      expect(
        SemanticParagraphFormatter.repair('故事的開端（\n第一章）'),
        '故事的開端（第一章）',
      );
    });

    test('跨行的成對刪節號與破折號保持相鄰', () {
      expect(
        SemanticParagraphFormatter.repair('他想…\n…然後答應。'),
        '他想……然後答應。',
      );
      expect(
        SemanticParagraphFormatter.repair('他說—\n—不要走。'),
        '他說——不要走。',
      );
    });

    test('插圖記號不會遮住行尾開引號或行首收引號', () {
      const illustration = '\uE000';
      expect(
        SemanticParagraphFormatter.repair('他說：「' + illustration + '\n你好。」'),
        '他說：「' + illustration + '你好。」',
      );
      expect(
        SemanticParagraphFormatter.repair('「請進。\n' + illustration + '」她回答。'),
        '「請進。' + illustration + '」她回答。',
      );
    });

    test('普通段落及連續對話仍各是一段', () {
      const source = '第一段寫完了。\n第二段開始。\n「你好。」\n「再見。」';
      expect(SemanticParagraphFormatter.repair(source), source);
      expect(ReaderV2Content.paragraphsOf(source), [
        '第一段寫完了。',
        '第二段開始。',
        '「你好。」',
        '「再見。」',
      ]);
    });

    test('空白行是確定的段落邊界，不跨越修補', () {
      const source = '「請進。\n\n」下一段。';
      expect(SemanticParagraphFormatter.repair(source), source);
    });

    test('只有短行或不規則行長時不猜測是否硬折行', () {
      const source = '第一行並不是完整的句子\n第二行仍然是獨立段落\n第三行。';
      expect(SemanticParagraphFormatter.repair(source), source);
    });

    test('高可信度的固定欄寬折行接回原段落', () {
      final lines = <String>[
        for (var i = 0; i < 5; i++) '甲' * 24,
        '這是末行。',
      ];
      expect(
        SemanticParagraphFormatter.repair(lines.join('\n')),
        lines.join(),
      );
    });

    test('固定欄寬也不合併已結束的句子及新對話', () {
      final lines = <String>[
        '甲' * 23 + '。',
        for (var i = 0; i < 4; i++) '乙' * 24,
        '「新的對話。」',
      ];
      final output = SemanticParagraphFormatter.repair(lines.join('\n'));
      expect(output.startsWith(lines.first + '\n'), isTrue);
      expect(output.endsWith('\n「新的對話。」'), isTrue);
    });

    test('整理可重複執行，已處理內容不再變動', () {
      const source = '　　「請進。\r\n　　」她說。\r\n下一段。';
      final repaired = SemanticParagraphFormatter.repair(source);
      expect(SemanticParagraphFormatter.repair(repaired), repaired);
    });

    test('章節的段落、文字與雜湊由修復後內容建立', () {
      final document = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '　　「請進。\n　　」她說。\n　　下一段。',
      );
      expect(document.paragraphs, ['「請進。」她說。', '下一段。']);
      expect(
        document.displayText,
        '第一章\n\n「請進。」她說。\n\n下一段。',
      );
    });
  });
}
