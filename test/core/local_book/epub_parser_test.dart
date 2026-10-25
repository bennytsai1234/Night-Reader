import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/epub_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _container = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

String _xhtml(String body, {String title = ''}) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head>${title.isEmpty ? '<title/>' : '<title>$title</title>'}<link rel="stylesheet" href="s.css"/></head>
<body>$body</body>
</html>''';

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

/// EPUB 3：封面頁只有圖、版權頁在目錄之前、兩章共用一個檔案靠錨點分開、
/// 一章跨兩個檔案。
Map<String, Object> _epub3() => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>測試之書</dc:title>
    <dc:creator>某作者</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="img" href="images/c%201.png" media-type="image/png" properties="cover-image"/>
    <item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="copy" href="Text/copyright.xhtml" media-type="application/xhtml+xml"/>
    <item id="a" href="Text/a.xhtml" media-type="application/xhtml+xml"/>
    <item id="b1" href="Text/b1.xhtml" media-type="application/xhtml+xml"/>
    <item id="b2" href="Text/b2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="cover"/>
    <itemref idref="copy"/>
    <itemref idref="a"/>
    <itemref idref="b1"/>
    <itemref idref="b2"/>
  </spine>
</package>''',
  'OEBPS/nav.xhtml': _xhtml('''
<nav epub:type="landmarks"><ol><li><a href="Text/cover.xhtml">封面</a></li></ol></nav>
<nav epub:type="toc"><ol>
  <li><a href="Text/a.xhtml">第一章 起點</a></li>
  <li><a href="Text/a.xhtml#ch2">第二章 岔路</a>
    <ol><li><a href="Text/b1.xhtml">第三章 遠方</a></li></ol>
  </li>
</ol></nav>'''),
  'OEBPS/images/c 1.png': _png,
  'OEBPS/Text/cover.xhtml': _xhtml(
    '<div><img src="../images/c%201.png"/></div>',
  ),
  'OEBPS/Text/copyright.xhtml': _xhtml('<p>版權所有</p>', title: '版權頁'),
  'OEBPS/Text/a.xhtml': _xhtml('''
<h1>第一章 起點</h1>
<p>他走進
  <ruby>森<rt>sēn</rt></ruby>林。</p>
<p>第二行<br/>換行</p>
<h2 id="ch2">第二章 岔路</h2>
<p>岔路口。</p>'''),
  'OEBPS/Text/b1.xhtml': _xhtml('<h1>第三章 遠方</h1><p>上半</p>'),
  'OEBPS/Text/b2.xhtml': _xhtml('<p>下半</p><script>bad()</script>'),
};

/// EPUB 2：NCX 巢狀目錄，卷名頁只有卷名。
Map<String, Object> _epub2() => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" xmlns:opf="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>二版書</dc:title>
    <meta name="cover" content="cov"/>
  </metadata>
  <manifest>
    <opf:item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <opf:item id="cov" href="cover.jpg" media-type="image/jpeg"/>
    <opf:item id="v1" href="v1.html" media-type="application/xhtml+xml"/>
    <opf:item id="c1" href="c1.html" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="v1"/>
    <itemref idref="c1"/>
  </spine>
</package>''',
  'OEBPS/toc.ncx': '''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="p1"><navLabel><text>第一卷</text></navLabel><content src="v1.html"/>
      <navPoint id="p2"><navLabel><text>第一章</text></navLabel><content src="c1.html"/></navPoint>
    </navPoint>
  </navMap>
</ncx>''',
  'OEBPS/cover.jpg': _png,
  'OEBPS/v1.html': _xhtml('<h1>第一卷</h1>'),
  'OEBPS/c1.html': _xhtml('<h1>第一章</h1><p>正文。</p>'),
};

/// 沒有目錄：一個檔案一章，章名取第一個標題。
Map<String, Object> _noToc() => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata/>
  <manifest>
    <item id="x" href="x.xhtml" media-type="application/xhtml+xml"/>
    <item id="y" href="y.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="x"/><itemref idref="y"/></spine>
</package>''',
  'OEBPS/x.xhtml': _xhtml('<h2>序章</h2><p>甲</p>'),
  'OEBPS/y.xhtml': _xhtml('<p>乙</p>'),
};

/// 由 TXT 轉成的 EPUB：目錄只有「封面」一條，整本書在同一章。
Map<String, Object> _coarseToc() {
  final body = StringBuffer('<p>本書由某站整理</p>');
  for (final title in ['第一回 甲', '第二回 乙']) {
    body.write('<p>$title</p>');
    for (var i = 0; i < 300; i++) {
      body.write('<p>${'字' * 99}</p>');
    }
  }
  return {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _container,
    'OEBPS/content.opf': '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata/>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="x" href="x.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="x"/></spine>
</package>''',
    'OEBPS/toc.ncx': '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
  <navPoint id="p"><navLabel><text>封面</text></navLabel><content src="x.xhtml"/></navPoint>
</navMap></ncx>''',
    'OEBPS/x.xhtml': _xhtml(body.toString()),
  };
}

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('epub_parser_test');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DirPathProvider(dir.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
  });

  tearDown(() async {
    await LocalBookService().closeOpenFile();
    await dir.delete(recursive: true);
  });

  Future<String> write(String name, Map<String, Object> entries) async {
    final archive = Archive();
    entries.forEach((path, content) {
      final bytes = content is String
          ? utf8.encode(content)
          : content as List<int>;
      archive.addFile(ArchiveFile.bytes(path, bytes));
    });
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return file.path;
  }

  /// 轉好的純文字檔裡每一章的字。
  Future<(EpubBookInfo, List<String>)> convert(String epubPath) async {
    final textPath = p.join(dir.path, 'out', 'text.txt');
    final info = await EpubParser.convert(epubPath, textPath);
    final bytes = await File(textPath).readAsBytes();
    return (
      info,
      [
        for (final chapter in info.chapters)
          utf8.decode(bytes.sublist(chapter.start, chapter.end)),
      ],
    );
  }

  test('EPUB 3 照目錄分章，錨點切開同一檔、跨檔併成一章、純圖頁不列', () async {
    final (info, texts) = await convert(await write('book3.epub', _epub3()));

    expect(info.title, '測試之書');
    expect(info.author, '某作者');
    expect(info.cover, _png);
    expect(info.coverExtension, '.png');
    expect(info.chapters.map((c) => c.title), [
      '版權頁',
      '第一章 起點',
      '第二章 岔路',
      '第三章 遠方',
    ]);
    expect(texts, [
      '版權所有',
      '第一章 起點\n他走進 森林。\n第二行\n換行',
      '第二章 岔路\n岔路口。',
      '第三章 遠方\n上半\n下半',
    ]);
  });

  test('EPUB 2 讀 NCX 巢狀目錄，卷名頁照樣是一章', () async {
    final (info, texts) = await convert(await write('book2.epub', _epub2()));

    expect(info.title, '二版書');
    expect(info.author, isNull);
    expect(info.coverExtension, '.jpg');
    expect(info.chapters.map((c) => c.title), ['第一卷', '第一章']);
    expect(texts, ['第一卷', '第一章\n正文。']);
  });

  test('沒有目錄時一個檔案一章，章名取第一個標題', () async {
    final (info, texts) = await convert(await write('notoc.epub', _noToc()));

    expect(info.chapters.map((c) => c.title), ['序章', '第 2 章']);
    expect(texts, ['序章\n甲', '乙']);
  });

  test('目錄太粗、一章超過五萬字時照 TXT 的章名規則再切', () async {
    final (info, texts) = await convert(
      await write('coarse.epub', _coarseToc()),
    );

    expect(info.chapters.map((c) => c.title), ['封面', '第一回 甲', '第二回 乙']);
    expect(texts[0].trim(), '本書由某站整理');
    expect(texts[1], startsWith('第一回 甲\n字'));
    expect(texts[2], startsWith('第二回 乙\n字'));
  });

  test('不是 EPUB 的檔案給使用者看得懂的錯誤', () async {
    final file = File(p.join(dir.path, 'broken.epub'));
    await file.writeAsString('not a zip');
    await expectLater(
      EpubParser.convert(file.path, p.join(dir.path, 'broken.txt')),
      throwsA(
        isA<EpubFormatException>().having(
          (e) => e.message,
          'message',
          'EPUB 檔案損壞或格式不對',
        ),
      ),
    );
  });

  test('LocalBookService 匯入 EPUB 後依章節索引讀出正文', () async {
    final path = await write('service.epub', _epub3());
    final result = await LocalBookService().importBook(path);

    expect(result, isNotNull);
    final book = result!.book;
    expect(book.bookUrl, 'local://$path');
    expect(book.name, '測試之書');
    expect(book.author, '某作者');
    expect(book.origin, 'local');
    expect(book.charset, 'utf-8');
    expect(result.cover, _png);
    expect(result.chapters, hasLength(4));
    final third = result.chapters[2];
    expect(third.url, '${book.bookUrl}#2');
    expect(await LocalBookService().getContent(book, third), '第二章 岔路\n岔路口。');
  });

  test('轉好的文字不見時從 EPUB 重新轉一次', () async {
    final path = await write('regen.epub', _epub3());
    final result = (await LocalBookService().importBook(path))!;
    await File(await LocalBookService.epubTextPath(result.book)).delete();

    expect(
      await LocalBookService().getContent(result.book, result.chapters.last),
      '第三章 遠方\n上半\n下半',
    );
  });

  test('章節索引缺失時回報要重新匯入', () async {
    final path = await write('missing.epub', _epub3());
    final book = Book(bookUrl: 'local://$path', origin: 'local');
    final result = await LocalBookService().importBook(path);
    final chapter = result!.chapters.first..start = null;

    expect(await LocalBookService().getContent(book, chapter), '本地書索引缺失，請重新匯入');
  });
}
