import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/local_book_service.dart';

void main() {
  test('Local TXT Parsing and Reading Test', () async {
    // 1. 建立測試檔案（寫入系統暫存目錄，避免污染專案根目錄）
    final tempDir = await Directory.systemTemp.createTemp(
      'night_reader_txt_test',
    );
    final testFile = File('${tempDir.path}/test_book.txt');
    const content = '''
前言內容在此。
第1章 起始
這是第一章的內容。包含中文和符號！
第2章 發展
這是第二章的內容。
更加詳細的描述。
''';
    await testFile.writeAsString(content);

    try {
      // 2. 測試解析位移
      final parser = TxtParser(testFile);
      final result = await parser.splitChapters();
      final chaptersData = result.chapters;

      expect(chaptersData.length, greaterThanOrEqualTo(3));
      expect(chaptersData[0]['title'], equals('前言'));
      expect(chaptersData[1]['title'], equals('第1章 起始'));
      expect(chaptersData[2]['title'], equals('第2章 發展'));

      // 3. 測試讀取內容
      final service = LocalBookService();
      final book = Book(
        bookUrl: 'local://${testFile.path}',
        name: '測試書',
        charset: 'utf-8',
      );

      // 驗證第一章
      final ch1 = BookChapter(
        title: chaptersData[1]['title'],
        start: chaptersData[1]['start'],
        end: chaptersData[1]['end'],
      );
      final readContent1 = await service.getContent(book, ch1);
      expect(readContent1.trim(), equals('第1章 起始\n這是第一章的內容。包含中文和符號！'));

      // 驗證第二章
      final ch2 = BookChapter(
        title: chaptersData[2]['title'],
        start: chaptersData[2]['start'],
        end: chaptersData[2]['end'],
      );
      final readContent2 = await service.getContent(book, ch2);
      expect(readContent2.trim(), equals('第2章 發展\n這是第二章的內容。\n更加詳細的描述。'));
    } finally {
      // 4. 清理：盡力移除暫存目錄。
      //    Windows 上解析後檔案 handle 可能尚未釋放，刪除會擲出 errno 32；
      //    因寫入的是 OS 暫存目錄，殘留無害（系統會自行回收），故清理採盡力而為。
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
