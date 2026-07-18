import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_processed_chapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderV2ContentTransformer', () {
    test('normalizeTypography 清理空白、隱形字元與 CJK 標點', () {
      expect(
        normalizeTypography('你\u200B\t　好\u0001,世界... 3.14 https://a.com'),
        '你好，世界…… 3.14 https://a.com',
      );
      expect(normalizeTypography('英文句子, hello!'), '英文句子， hello!');
    });

    test('normalizeTypography 恆開：引號配對＋CJK 空格移除＋連續標點保留', () {
      // 直引號成對轉「」、漢字間空格移除；連續驚嘆號保留作者語氣。
      expect(normalizeTypography('"你 好 嗎"！！！'), '「你好嗎」！！！');
      expect(normalizeTypography('等等...'), '等等……');
      expect(normalizeTypography('你 好 嗎'), '你好嗎');
      // 全形標點鄰接的空格也是雜訊（不只漢字之間）。
      expect(normalizeTypography('他說 「你好」 了'), '他說「你好」了');
    });

    test('normalizeTypography 歧義寬度標點：彎引號成對轉 CJK 專屬碼位', () {
      // 中文脈絡的彎雙引號 → 「」；巢狀彎單引號 → 『』
      expect(normalizeTypography('\u201C你好\u201D'), '「你好」');
      expect(normalizeTypography('\u201C他說\u2018好\u2019了\u201D'), '「他說『好』了」');
      // 引號內只有標點也算中文脈絡（省略號/破折號開頭的對白）
      expect(normalizeTypography('\u201C……\u201D'), '「……」');
      // 引號內全西文但外側鄰字是中文 → 成對一起轉，不破對
      expect(
        normalizeTypography('他說\u201CHello, world\u201D。'),
        '他說「Hello, world」。',
      );
      // 純西文脈絡的引號對原樣保留
      expect(
        normalizeTypography('He said \u201Chello\u201D loudly'),
        'He said \u201Chello\u201D loudly',
      );
      // 落單（不成對）的引號原樣保留
      expect(normalizeTypography('他說\u201D了'), '他說\u201D了');
      expect(normalizeTypography('\u201C他說了'), '\u201C他說了');
      // 收尾前又開新引號：前一個落單保留，後一對正常轉
      expect(normalizeTypography('\u201C早안\u201C你好\u201D'), '\u201C早안「你好」');
      // 撇號不視為引號收尾
      expect(
        normalizeTypography('他說\u201Cdon\u2019t worry\u201D。'),
        '他說「don\u2019t worry」。',
      );
      expect(normalizeTypography("It\u2019s fine"), 'It\u2019s fine');
    });

    test('直引號逐行配對：雜訊引號只影響該行，純西文行不動', () {
      // 第二行奇數個引號：該行原樣保留，其他行正常配對
      //（舊實作為整章全域計數，全章奇數 → 三行全部放棄）。
      expect(
        normalizeTypography('"第一句"\n殘缺"引號行\n"第三句"'),
        '「第一句」\n殘缺"引號行\n「第三句」',
      );
      // 同行多對引號仍交替配對。
      expect(normalizeTypography('"甲"與"乙"'), '「甲」與「乙」');
      // 反斜線跳脫的引號不參與配對。
      expect(normalizeTypography('"甲\\"乙"'), '「甲\\"乙」');
      // 純西文行的直引號原樣保留（逐對 CJK 脈絡判定）。
      expect(normalizeTypography('"Hello," he said.'), '"Hello," he said.');
    });

    test('直單引號配對轉『』，撇號不受波及', () {
      expect(normalizeTypography("他說'好'了"), '他說『好』了');
      expect(normalizeTypography("他說don't好"), "他說don't好");
      expect(normalizeTypography("it's a 'test' here"), "it's a 'test' here");
    });

    test('破折號統一為全形 em dash，西文連字號不動', () {
      expect(normalizeTypography('他說--我不去'), '他說——我不去');
      expect(normalizeTypography('他說——我不去'), '他說——我不去');
      expect(normalizeTypography('他說\u2015我走'), '他說—我走');
      expect(normalizeTypography('\u2500\u2500他說'), '——他說');
      expect(normalizeTypography('他\u2013說'), '他—說');
      expect(normalizeTypography('1-5 和 2020--2021'), '1-5 和 2020--2021');
      expect(normalizeTypography('co-op 與 1\u20135'), 'co-op 與 1\u20135');
    });

    test('刪節號各種來源統一為 ……', () {
      expect(normalizeTypography('等等。。。'), '等等……');
      expect(normalizeTypography('等等…'), '等等……');
      expect(normalizeTypography('等等\u22EF\u22EF'), '等等……');
      expect(normalizeTypography('等等……好！！！'), '等等……好！！！');
    });

    test('半形括號在 CJK 脈絡成對轉全形，西文/數學不動', () {
      expect(normalizeTypography('他笑了(苦笑)一下'), '他笑了（苦笑）一下');
      // [] 先轉【】、再統一映射為「」。
      expect(normalizeTypography('[系統]任務完成'), '「系統」任務完成');
      expect(normalizeTypography('f(x)=1 and a[0]'), 'f(x)=1 and a[0]');
      expect(normalizeTypography('(他說'), '(他說');
    });

    test('CJK 專屬括號統一映射為上下引號', () {
      expect(normalizeTypography('【系統】升級完成'), '「系統」升級完成');
      expect(normalizeTypography('〖注〗這是註解'), '『注』這是註解');
      expect(normalizeTypography('\uFF62你好\uFF63'), '「你好」');
    });

    test('波浪號在 CJK 脈絡轉全形', () {
      expect(normalizeTypography('喂~你好'), '喂～你好');
      expect(normalizeTypography('a~b 和 3~5'), 'a~b 和 3~5');
    });

    test('CJK 空格移除不波及西文詞間空格', () {
      expect(normalizeTypography('你 好 hello world 嗎'), '你好 hello world 嗎');
    });

    test('normalizeTypography 歧義寬度標點：間隔號轉全形中點', () {
      expect(normalizeTypography('哈利·波特'), '哈利・波特');
      expect(normalizeTypography('哈利‧波特'), '哈利・波特');
      // 非漢字兩側不轉（數字/西文脈絡）
      expect(normalizeTypography('3·14'), '3·14');
      expect(normalizeTypography('a·b'), 'a·b');
    });

    test('normalizeTypography 不破壞詩歌換行與數字脈絡', () {
      expect(
        normalizeTypography('你\n 好\n3.14\nVersion 1.2'),
        '你\n 好\n3.14\nVersion 1.2',
      );
      expect(normalizeTypography('第3.章'), '第3.章');
    });

    test(
      'applies scoped content rules through the shared replace engine',
      () async {
        final transformer = ReaderV2ContentTransformer();
        final result = await transformer.process(
          book: Book(
            bookUrl: 'book://1',
            origin: 'https://source.example',
            name: '測試書',
            readConfig: ReadConfig(useReplaceRule: true),
          ),
          chapter: BookChapter(title: '第1章 廣告'),
          rawContent: '第1章 廣告\n正文 junk123\nad999',
          enabledRules: [
            ReplaceRule(
              name: '正文替換',
              pattern: r'junk(\d+)',
              replacement: r'ok$1',
              scope: '測試書',
              scopeContent: true,
              order: 0,
            ),
            ReplaceRule(
              name: '外書規則',
              pattern: '正文',
              replacement: '不應套用',
              scope: '其他書',
              scopeContent: true,
              order: 1,
            ),
            ReplaceRule(
              name: '標題替換',
              pattern: '廣告',
              replacement: '',
              scope: 'https://source.example',
              scopeTitle: true,
              scopeContent: false,
              order: 2,
            ),
          ],
          chineseConvertType: 0,
        );

        expect(result.displayTitle, '第1章 ');
        expect(result.content, contains('ok123'));
        expect(result.content, isNot(contains('junk123')));
        expect(result.content, isNot(contains('不應套用')));
        expect(result.sameTitleRemoved, isTrue);
        expect(result.effectiveReplaceRules.map((rule) => rule.name), ['正文替換']);
      },
    );

    test(
      'removes duplicate title after title replace rules are applied',
      () async {
        final transformer = ReaderV2ContentTransformer();
        final result = await transformer.process(
          book: Book(
            bookUrl: 'book://1',
            origin: 'https://source.example',
            name: '測試書',
            readConfig: ReadConfig(useReplaceRule: true),
          ),
          chapter: BookChapter(title: '第1章 正文'),
          rawContent: '正文\n真正內容',
          enabledRules: [
            ReplaceRule(
              name: '標題裁切',
              pattern: r'^第1章\s*',
              replacement: '',
              scopeTitle: true,
              scopeContent: false,
            ),
          ],
          chineseConvertType: 0,
        );

        expect(result.displayTitle, '正文');
        expect(result.content, isNot(contains('正文\n')));
        expect(result.content, contains('真正內容'));
        expect(result.sameTitleRemoved, isTrue);
      },
    );

    test(
      'does not remove a legal body prefix that only starts with title',
      () async {
        final result = await const ReaderV2ContentTransformer().process(
          book: Book(bookUrl: 'book://1', origin: 'local', name: '測試書'),
          chapter: BookChapter(title: '序'),
          rawContent: '序章內容從這裡開始。',
          enabledRules: const [],
          chineseConvertType: 0,
        );

        expect(result.content, contains('序章內容從這裡開始。'));
        expect(result.sameTitleRemoved, isFalse);
      },
    );

    test('keeps single newlines as paragraph boundaries', () {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '　　第一段內容。\n　　第二段內容。',
      );

      expect(content.paragraphs, ['第一段內容。', '第二段內容。']);
      expect(content.plainText, '第一段內容。\n\n第二段內容。');
    });

    test(
      're-segments a long single-line chapter by sentence punctuation',
      () async {
        final transformer = ReaderV2ContentTransformer();
        final rawContent =
            List<String>.filled(
              5,
              '這是一段沒有任何換行的長正文內容，來源把多個自然段全部黏在同一行裡，閱讀時會顯得過度擁擠。',
            ).join();
        final result = await transformer.process(
          book: Book(
            bookUrl: 'book://1',
            origin: 'https://source.example',
            name: '測試書',
            readConfig: ReadConfig(reSegment: true),
          ),
          chapter: BookChapter(title: '第一章'),
          rawContent: rawContent,
          enabledRules: const [],
          chineseConvertType: 0,
        );

        expect(result.content.split('\n'), hasLength(greaterThan(1)));
        expect(result.content, contains('\n　　'));
      },
    );

    test('worker 路徑：簡繁轉換在 worker isolate 內完成', () async {
      ReaderV2ContentTransformWorker.dictionaryDataLoader =
          () async => ['简体\t簡體', '简\t簡\n体\t體', '', ''];
      ReaderV2ContentTransformWorker.instance.debugReset();
      addTearDown(() {
        ReaderV2ContentTransformWorker.dictionaryDataLoader =
            ReaderV2ContentTransformWorker.loadDictionaryDataFromBundle;
        ReaderV2ContentTransformWorker.instance.debugReset();
      });

      final transformer = ReaderV2ContentTransformer();
      final result = await transformer.process(
        book: Book(bookUrl: 'book://1', origin: 'local', name: '測試書'),
        chapter: BookChapter(title: '第1章 简体'),
        rawContent: '這裡有简体字\n第二段也有简体',
        enabledRules: const [],
        chineseConvertType: 1,
      );

      expect(result.displayTitle, '第1章 簡體');
      expect(result.content, contains('簡體字'));
      expect(result.content, isNot(contains('简')));
    });

    test('worker 路徑：假名段落跳過簡繁轉換（保留日文漢字）', () async {
      ReaderV2ContentTransformWorker.dictionaryDataLoader =
          () async => ['中国\t中國', '国\t國', '', ''];
      ReaderV2ContentTransformWorker.instance.debugReset();
      addTearDown(() {
        ReaderV2ContentTransformWorker.dictionaryDataLoader =
            ReaderV2ContentTransformWorker.loadDictionaryDataFromBundle;
        ReaderV2ContentTransformWorker.instance.debugReset();
      });

      final transformer = ReaderV2ContentTransformer();
      final result = await transformer.process(
        book: Book(bookUrl: 'book://1', origin: 'local', name: '測試書'),
        chapter: BookChapter(title: '第1章'),
        rawContent: '中国很大\nこれは中国の本です',
        enabledRules: const [],
        chineseConvertType: 1,
      );

      // 中文行照常轉繁；日文行的漢字保持原樣（否則翻譯輸入被改壞）。
      expect(result.content, contains('中國很大'));
      expect(result.content, contains('これは中国の本です'));
    });

    test('worker 停用時退回 compute 路徑，替換規則仍生效', () async {
      ReaderV2ContentTransformWorker.debugDisableWorker = true;
      addTearDown(() {
        ReaderV2ContentTransformWorker.debugDisableWorker = false;
      });

      final transformer = ReaderV2ContentTransformer();
      final result = await transformer.process(
        book: Book(
          bookUrl: 'book://1',
          origin: 'https://source.example',
          name: '測試書',
          readConfig: ReadConfig(useReplaceRule: true),
        ),
        chapter: BookChapter(title: '第1章'),
        rawContent: '第1章\n正文 junk123',
        enabledRules: [
          ReplaceRule(
            name: '正文替換',
            pattern: r'junk(\d+)',
            replacement: r'ok$1',
            scopeContent: true,
          ),
        ],
        chineseConvertType: 0,
      );

      expect(result.content, contains('ok123'));
      expect(result.content, isNot(contains('junk123')));
      expect(result.sameTitleRemoved, isTrue);
    });

    test('worker 路徑與 compute 路徑輸出一致', () async {
      final transformer = ReaderV2ContentTransformer();
      Future<ReaderV2ProcessedChapter> run() {
        return transformer.process(
          book: Book(
            bookUrl: 'book://1',
            origin: 'https://source.example',
            name: '測試書',
            readConfig: ReadConfig(useReplaceRule: true, reSegment: true),
          ),
          chapter: BookChapter(title: '第2章 標題'),
          rawContent: '第2章 標題\n　　正文 junk7\n\n下一段',
          enabledRules: [
            ReplaceRule(
              name: '正文替換',
              pattern: r'junk(\d+)',
              replacement: r'ok$1',
              scopeContent: true,
            ),
          ],
          chineseConvertType: 0,
        );
      }

      ReaderV2ContentTransformWorker.instance.debugReset();
      final viaWorker = await run();

      ReaderV2ContentTransformWorker.debugDisableWorker = true;
      addTearDown(() {
        ReaderV2ContentTransformWorker.debugDisableWorker = false;
      });
      final viaCompute = await run();

      expect(viaWorker.displayTitle, viaCompute.displayTitle);
      expect(viaWorker.content, viaCompute.content);
      expect(viaWorker.sameTitleRemoved, viaCompute.sameTitleRemoved);
      expect(
        viaWorker.effectiveReplaceRules.map((rule) => rule.name),
        viaCompute.effectiveReplaceRules.map((rule) => rule.name),
      );
    });
  });
}
