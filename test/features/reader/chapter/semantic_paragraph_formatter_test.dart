import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/chapter/semantic_paragraph_formatter.dart';

void main() {
  group('正文段落整理', () {
    test('把孤立的下引號接回同一句，保留後面的敘述', () {
      const source = '「請進。\n」一個悅耳的女性聲音在門後傳來。';
      expect(SemanticParagraphFormatter.repair(source), '「請進。」一個悅耳的女性聲音在門後傳來。');
      expect(ReaderV2Content.paragraphsOf(source), ['「請進。」一個悅耳的女性聲音在門後傳來。']);
    });

    test('行首帶有來源縮排時，不把縮排塞進段落中間', () {
      const source = '　　「請進。\n　　」一個悅耳的聲音。';
      expect(SemanticParagraphFormatter.repair(source), '　　「請進。」一個悅耳的聲音。');
    });

    test('落單的彎引號也會接回，供之後的中文標點正規化使用', () {
      expect(SemanticParagraphFormatter.repair('「請進。\n”她回答。'), '「請進。”她回答。');
    });

    test('開頭標點留在行尾時接上下一行', () {
      expect(SemanticParagraphFormatter.repair('他說：「\n你好。」'), '他說：「你好。」');
      expect(SemanticParagraphFormatter.repair('故事的開端（\n第一章）'), '故事的開端（第一章）');
    });

    test('跨行的成對刪節號與破折號保持相鄰', () {
      expect(SemanticParagraphFormatter.repair('他想…\n…然後答應。'), '他想……然後答應。');
      expect(SemanticParagraphFormatter.repair('他說—\n—不要走。'), '他說——不要走。');
    });

    test('各自完整的刪節號、破折號不算被折開', () {
      for (final source in ['他看著遠方……\n……良久，他才開口。', '她說——\n——這是另一段。']) {
        expect(SemanticParagraphFormatter.repair(source), source);
      }
    });

    // 真網站抓到的正文（2026-11-18，28 個書源 74 章）裡，誤合併都是引號方向
    // 打反：書源把收引號打成 “、開引號打成 ”。
    test('引號方向打反時，前一段沒有沒收的引號就不接', () {
      for (final source in [
        '“我走了。“\n她拉開門，又回頭看了一眼。',
        '他看著窗外，小聲說道。\n”別怕，等回去了我慢慢教你。”',
        '“看！是驚喜。“\n“這算什麼驚喜。”她笑了。',
        '他站在門口，身影擋住了光。\n”你來了……“她抬起頭。',
      ]) {
        expect(SemanticParagraphFormatter.repair(source), source);
      }
    });

    test('一句話跨好幾行、收引號打反時，不接下一段', () {
      const source = '“從來只有我走，\n沒有人可以叫我走，今天我就要走！“\n她拉開門，又回頭看了一眼。';
      expect(SemanticParagraphFormatter.repair(source), source);
    });

    test('前一段有沒收的引號時，下一行的收引號接回來', () {
      expect(SemanticParagraphFormatter.repair('他大聲喊：“老師！\n”'), '他大聲喊：“老師！”');
      expect(SemanticParagraphFormatter.repair('他說：“\n你好。”'), '他說：“你好。”');
      expect(SemanticParagraphFormatter.repair('“師傅！\n！”'), '“師傅！！”');
    });

    test('英文撇號與另一層的引號不算沒收的引號', () {
      for (final source in ['I don’t know.\n”這一段的開引號打反了。“', '「甲說完了。\n』乙的引文']) {
        expect(SemanticParagraphFormatter.repair(source), source);
      }
    });

    test('接起來的段落記得原文的換行', () {
      final repaired = SemanticParagraphFormatter.repairWithSources(
        '「請進。\n」她說。\n\n下一段。',
      );
      expect(repaired.lines, ['「請進。」她說。', '', '下一段。']);
      expect(repaired.sources, ['「請進。\n」她說。', '', '下一段。']);
      expect(ReaderV2Content.sourceParagraphsOf('「請進。\n」她說。\n\n下一段。'), [
        '「請進。\n」她說。',
        '下一段。',
      ]);
    });

    test('連續對白每段只有開引號，各段照樣分開', () {
      const source = '“第一段話還沒說完。\n“第二段接著說。\n“最後一段說完了。”';
      expect(SemanticParagraphFormatter.repair(source), source);
    });

    test('整行只有標點的一段不接到上一行', () {
      for (final source in ['「你說什麼？」\n？？？', '他愣住了。\n！！', '她沒有回答。\n。。。']) {
        expect(SemanticParagraphFormatter.repair(source), source);
      }
    });

    test('只有插圖的行是段落邊界，記號留在原位', () {
      const illustration = '\uE000';
      for (final source in [
        '「請進。\n$illustration\n」她回答。',
        '他說：「\n$illustration\n你好。」',
      ]) {
        expect(SemanticParagraphFormatter.repair(source), source);
      }
    });

    test('插圖記號不會遮住行尾開引號或行首收引號', () {
      const illustration = '\uE000';
      expect(
        SemanticParagraphFormatter.repair('他說：「$illustration\n你好。」'),
        '他說：「$illustration你好。」',
      );
      expect(
        SemanticParagraphFormatter.repair('「請進。\n$illustration」她回答。'),
        '「請進。$illustration」她回答。',
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
      final lines = <String>[for (var i = 0; i < 8; i++) '甲' * 24, '這是末行。'];
      expect(SemanticParagraphFormatter.repair(lines.join('\n')), lines.join());
    });

    test('行長不算插圖記號，有插圖的行照樣接回', () {
      final lines = <String>[
        for (var i = 0; i < 7; i++) '甲' * 24,
        '${'乙' * 24}\uE000',
        '這是末行。',
      ];
      expect(SemanticParagraphFormatter.repair(lines.join('\n')), lines.join());
    });

    test('幾項等長的列表不當成固定欄寬', () {
      final source = [for (var i = 1; i <= 5; i++) '　${'甲' * 13}$i'].join('\n');
      expect(SemanticParagraphFormatter.repair(source), source);
    });

    test('固定欄寬不把英文字詞黏在一起', () {
      final source = [for (var i = 0; i < 8; i++) 'This is line $i of text']
          .join('\n');
      expect(SemanticParagraphFormatter.repair(source), source);
    });

    test('欄寬落在兩種行長中間時也認得', () {
      final lines = <String>[
        for (var i = 0; i < 8; i++) '甲' * (i.isEven ? 19 : 21),
        '這是末行。',
      ];
      expect(SemanticParagraphFormatter.repair(lines.join('\n')), lines.join());
    });

    test('固定欄寬也不合併已結束的句子及新對話', () {
      final lines = <String>[
        '甲' * 23 + '。',
        for (var i = 0; i < 7; i++) '乙' * 24,
        '「新的對話。」',
      ];
      final output = SemanticParagraphFormatter.repair(lines.join('\n'));
      expect(output.startsWith('${lines.first}\n'), isTrue);
      expect(output.endsWith('\n「新的對話。」'), isTrue);
    });

    test('整理可重複執行，已處理內容不再變動', () {
      const source = '　　「請進。\r\n　　」她說。\r\n下一段。';
      final repaired = SemanticParagraphFormatter.repair(source);
      expect(SemanticParagraphFormatter.repair(repaired), repaired);
    });

    test('只有插圖的行夾在中間時，圖照樣排在下一段開頭', () {
      final document = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '',
        rawText: '他說：「\n\uE000\n你好。」',
        illustrationSlots: [
          (src: 'a.png', path: 'a.png', pixelWidth: 10, pixelHeight: 10),
        ],
      );
      expect(document.paragraphs, ['他說：「', '你好。」']);
      expect(
        document.illustrations.single.offset,
        document.displayText.indexOf('你好'),
      );
    });

    test('章節的段落、文字與雜湊由修復後內容建立', () {
      final document = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '　　「請進。\n　　」她說。\n　　下一段。',
      );
      expect(document.paragraphs, ['「請進。」她說。', '下一段。']);
      expect(document.displayText, '第一章\n\n「請進。」她說。\n\n下一段。');
    });
  });
}
