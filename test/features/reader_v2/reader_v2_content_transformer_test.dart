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
