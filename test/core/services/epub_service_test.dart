import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/epub_service.dart';

Future<File> _createMinimalEpub({
  required String filePath,
  required String chapterBody,
}) async {
  final archive = Archive();

  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.add(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0"
           xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
              media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  add('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0"
         unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>測試書名</dc:title>
    <dc:creator>測試作者</dc:creator>
    <dc:identifier id="bookid">test-epub-service-001</dc:identifier>
    <dc:language>zh-TW</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="chapter1.xhtml"
          media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx"
          media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
  </spine>
</package>''');

  add('OEBPS/toc.ncx', '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="test-epub-service-001"/>
    <meta name="dtb:depth" content="1"/>
  </head>
  <docTitle><text>測試書名</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>第一章</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>''');

  add('OEBPS/chapter1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>第一章</title></head>
  <body><h1>第一章</h1><p>$chapterBody</p></body>
</html>''');

  final zipBytes = ZipEncoder().encode(archive);
  final file = File(filePath);
  await file.writeAsBytes(zipBytes, flush: true);
  return file;
}

void main() {
  group('EpubService', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('epub_service_test_');
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test('parseMetadata and getChapterContent work for local epub', () async {
      final file = await _createMinimalEpub(
        filePath: '${tempDir.path}/book.epub',
        chapterBody: '內容 A',
      );

      final service = EpubService();
      final meta = await service.parseMetadata(file);
      expect(meta.title, equals('測試書名'));
      expect(meta.author, equals('測試作者'));
      expect(meta.chapters, isNotEmpty);

      final content = await service.getChapterContent(
        file,
        'chapter1.xhtml#section',
      );
      expect(content, contains('內容 A'));
    });

    test('cache invalidates when epub file is updated', () async {
      final file = await _createMinimalEpub(
        filePath: '${tempDir.path}/book_update.epub',
        chapterBody: '舊內容',
      );

      final service = EpubService();
      final first = await service.getChapterContent(file, 'chapter1.xhtml');
      expect(first, contains('舊內容'));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _createMinimalEpub(filePath: file.path, chapterBody: '新內容-已更新');

      final second = await service.getChapterContent(file, 'chapter1.xhtml');
      expect(second, contains('新內容-已更新'));
    });
  });
}
