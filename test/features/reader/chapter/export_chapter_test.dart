import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';

/// 匯出書照 Legado（`ExportBookService.getExportData`）：套這本書的替換規則
/// 與標題規則，不做繁簡轉換、不重新分段，正文開頭重複的章名拿掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final book = Book(
    bookUrl: 'https://a.example/b',
    origin: 'https://a.example',
    name: '書',
    readConfig: ReadConfig(reSegment: true),
  );
  final chapter = BookChapter(
    url: 'c1',
    title: '第一章 开始',
    bookUrl: book.bookUrl,
  );

  test('套替換規則與標題規則，開頭重複的章名拿掉，不重新分段', () async {
    final exported = await ReaderContentTransformer.exportChapter(
      book: book,
      chapter: chapter,
      rawContent: '第一章 开始\n　　正文广告内容\n　　第二段。',
      enabledRules: [
        ReplaceRule(id: 1, name: '廣告', pattern: '广告', isRegex: false),
        ReplaceRule(
          id: 2,
          name: '章名',
          pattern: '开始',
          replacement: '起',
          isRegex: false,
          scopeTitle: true,
          scopeContent: false,
        ),
      ],
    );

    expect(exported.title, '第一章 起');
    expect(exported.text, '　　正文内容\n　　第二段。');
  });

  test('本書關掉替換規則時照原文', () async {
    final noRules = book.copyWith(
      readConfig: ReadConfig(useReplaceRule: false),
    );
    final exported = await ReaderContentTransformer.exportChapter(
      book: noRules,
      chapter: chapter,
      rawContent: '　　正文广告内容',
      enabledRules: [
        ReplaceRule(id: 1, name: '廣告', pattern: '广告', isRegex: false),
      ],
    );
    expect(exported.text, '　　正文广告内容');
  });
}
