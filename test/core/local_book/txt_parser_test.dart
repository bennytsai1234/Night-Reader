import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';

void main() {
  group('TxtParser Tests', () {
    late File utf8File;
    late File gbkFile;
    late File noChapterFile;

    setUpAll(() async {
      final tempDir = Directory.systemTemp.createTempSync();
      utf8File = File('${tempDir.path}/utf8.txt');
      await utf8File.writeAsString('第一章 測試\n內容1\n第二章 測試\n內容2');

      gbkFile = File('${tempDir.path}/gbk.txt');
      // 簡單測試，目前 parser 內部預設 utf8
      await gbkFile.writeAsString('第1章 測試\n內容1');

      noChapterFile = File('${tempDir.path}/no_chapter.txt');
      await noChapterFile.writeAsString('這是一段沒有章節標題的文字內容。');
    });

    test('UTF-8 Chapter Splitting', () async {
      final parser = TxtParser(utf8File);
      await parser.load();

      final result = await parser.splitChapters();
      final chapters = result.chapters;

      expect(chapters.length, 2);
      expect(chapters[0]['title'], contains('第一章'));
      expect(chapters[1]['title'], contains('第二章'));
    });

    test('No Chapter Title Handling', () async {
      final parser = TxtParser(noChapterFile);
      await parser.load();

      final result = await parser.splitChapters();
      final chapters = result.chapters;

      // 深度還原：若無章節則返回全文作為第一章
      expect(chapters.isNotEmpty, true);
      expect(chapters[0]['title'], contains('正文'));
    });

    test(
      'No Chapter Title Large Content Splits Into Multiple Chunks',
      () async {
        final largeNoChapter = File(
          '${Directory.systemTemp.path}/no_chapter_large.txt',
        );
        final largeContent = '沒有章節標題\\n' * 20000;
        await largeNoChapter.writeAsString(largeContent);

        try {
          final parser = TxtParser(largeNoChapter);
          final result = await parser.splitChapters();
          final chapters = result.chapters;

          expect(chapters.length, greaterThan(1));
          expect(chapters.first['title'], contains('正文'));

          for (var i = 0; i < chapters.length - 1; i++) {
            expect(chapters[i]['end'], equals(chapters[i + 1]['start']));
          }

          final bytes = await largeNoChapter.readAsBytes();
          expect(chapters.first['start'], equals(0));
          expect(chapters.last['end'], equals(bytes.length));
        } finally {
          if (await largeNoChapter.exists()) {
            await largeNoChapter.delete();
          }
        }
      },
    );

    test('Large File Splitting Logic', () async {
      final largeContent = '內容' * 30000; // 超過 50,000 字符閾值 (假設一箇中文字 2 bytes)
      final tempFile = File('${Directory.systemTemp.path}/large.txt');
      await tempFile.writeAsString('第一章\n$largeContent');

      final parser = TxtParser(tempFile);
      await parser.load();

      final result = await parser.splitChapters();
      final chapters = result.chapters;

      // 驗證是否觸發了物理切塊 (預期會有 2 個或更多切片)
      expect(chapters.length, greaterThan(1));
      expect(chapters[0]['title'], contains('(1)'));

      await tempFile.delete();
    });
  });
}
