import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/backup/export_book_service.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/epub_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
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

/// 第一卷底下兩章，卷名和第一章指向同一個檔案。[nav] 時用 EPUB 3 的目錄頁，
/// 卷名是沒有連結的 `<span>`；否則用 NCX。[description] 是 OPF 的簡介。
Map<String, Object> _volumes({bool nav = false, String? description}) => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf':
      '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>分卷之書</dc:title>
    ${description == null ? '' : '<dc:description>$description</dc:description>'}
  </metadata>
  <manifest>
    ${nav ? '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' : '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'}
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine${nav ? '' : ' toc="ncx"'}><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''',
  if (nav)
    'OEBPS/nav.xhtml': _xhtml(
      '''
<nav epub:type="toc"><ol>
  <li><span>第一卷</span>
    <ol><li><a href="c1.xhtml">第一章</a></li><li><a href="c2.xhtml">第二章</a></li></ol>
  </li>
</ol></nav>''',
    )
  else
    'OEBPS/toc.ncx': '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
  <navPoint><navLabel><text>第一卷</text></navLabel><content src="c1.xhtml"/>
    <navPoint><navLabel><text>第一章</text></navLabel><content src="c1.xhtml"/></navPoint>
    <navPoint><navLabel><text>第二章</text></navLabel><content src="c2.xhtml"/></navPoint>
  </navPoint>
</navMap></ncx>''',
  'OEBPS/c1.xhtml': _xhtml('<h1>第一章</h1><p>甲</p>'),
  'OEBPS/c2.xhtml': _xhtml('<h1>第二章</h1><p>乙</p>'),
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

/// 閱讀順序就是 [docs] 的順序，目錄（NCX）是 [toc] 的（章名, href）。
Map<String, Object> _simple(
  Map<String, Object> docs,
  List<(String, String)> toc,
) {
  final ids = [for (var i = 0; i < docs.length; i++) 'd$i'];
  final hrefs = docs.keys.toList();
  return {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _container,
    'OEBPS/content.opf':
        '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata/>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    ${[for (var i = 0; i < ids.length; i++) '<item id="${ids[i]}" href="${hrefs[i]}" media-type="application/xhtml+xml"/>'].join('\n')}
  </manifest>
  <spine toc="ncx">${ids.map((id) => '<itemref idref="$id"/>').join()}</spine>
</package>''',
    'OEBPS/toc.ncx':
        '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
${[for (final (title, href) in toc) '<navPoint><navLabel><text>$title</text></navLabel><content src="$href"/></navPoint>'].join('\n')}
</navMap></ncx>''',
    for (final MapEntry(:key, :value) in docs.entries) 'OEBPS/$key': value,
  };
}

List<int> _utf16le(String text) => [
  0xFF,
  0xFE,
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
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
    // 底下還有條目的是分卷，卷首的字照樣讀得到。
    expect(info.chapters.map((c) => c.isVolume), [false, false, true, false]);
  });

  test('目錄的上層標成分卷；只有卷名、和第一章指向同一處的也留成一列', () async {
    for (final nav in [false, true]) {
      final (info, texts) = await convert(
        await write('volumes-$nav.epub', _volumes(nav: nav)),
      );

      expect(info.chapters.map((c) => c.title), ['第一卷', '第一章', '第二章']);
      expect(info.chapters.map((c) => c.isVolume), [true, false, false]);
      expect(texts, ['第一卷', '第一章\n甲', '第二章\n乙']);
    }
  });

  test('讀 OPF 的簡介，是 HTML 時只取文字', () async {
    final (plain, _) = await convert(
      await write('intro.epub', _volumes(description: '一段簡介。')),
    );
    expect(plain.intro, '一段簡介。');

    final (html, _) = await convert(
      await write(
        'intro-html.epub',
        _volumes(description: '&lt;p&gt;第一段&lt;/p&gt;&lt;p&gt;第二段&lt;/p&gt;'),
      ),
    );
    expect(html.intro, '第一段第二段');

    final (none, _) = await convert(await write('no-intro.epub', _volumes()));
    expect(none.intro, isNull);

    final imported = await LocalBookService().importBook(
      await write('intro-import.epub', _volumes(description: '一段簡介。')),
    );
    expect(imported!.book.intro, '一段簡介。');
  });

  test('插圖在原位置留標記、圖抽到插圖資料夾；只有圖的章併到下一章開頭', () async {
    final path = await write(
      'pictures.epub',
      _simple(
        {
          'Text/color.xhtml': _xhtml(
            '<svg><image xlink:href="../Images/color.png"/></svg>',
          ),
          'Text/one.xhtml': _xhtml(
            '<h1>第一章</h1><p>前文</p><p><img src="../Images/in%20line.png"/></p>'
            '<p>後文<img src="../Images/gone.png"/></p>',
          ),
          'Text/end.xhtml': _xhtml('<img src="../Images/color.png"/>'),
        },
        [
          ('彩頁', 'Text/color.xhtml'),
          ('第一章', 'Text/one.xhtml'),
          ('後記插圖', 'Text/end.xhtml'),
        ],
      )..addAll({
        'OEBPS/Images/color.png': _png,
        'OEBPS/Images/in line.png': _png,
      }),
    );
    final (info, texts) = await convert(path);

    expect(info.chapters.map((c) => c.title), ['第一章']);
    expect(texts, [
      '<img src="OEBPS/Images/color.png">\n第一章\n前文\n'
          '<img src="OEBPS/Images/in line.png">\n後文\n'
          '<img src="OEBPS/Images/color.png">',
    ]);
    final images = Directory(
      p.join(dir.path, 'out', BookIllustrationStorage.folderName),
    );
    expect(images.listSync().map((f) => p.basename(f.path)).toSet(), {
      BookIllustrationStorage.fileNameFor('OEBPS/Images/color.png'),
      BookIllustrationStorage.fileNameFor('OEBPS/Images/in line.png'),
    });
  });

  test('封面那張圖不放進正文', () async {
    final (_, texts) = await convert(
      await write(
        'cover-in-text.epub',
        _epub3()
          ..['OEBPS/Text/a.xhtml'] = _xhtml(
            '<h1>第一章 起點</h1><img src="../images/c%201.png"/><p>正文</p>',
          ),
      ),
    );
    expect(texts[1], '第一章 起點\n正文');
  });

  test('轉法改過的舊文字，開書時重轉、換上新的章節範圍', () async {
    final path = await write('old.epub', _epub3());
    final result = (await LocalBookService().importBook(path))!;
    final textPath = await LocalBookService.epubTextPath(result.book);
    final ranges = EpubParser.readChapters(textPath);
    expect(ranges, [
      for (final c in result.chapters)
        (title: c.title, start: c.start!, end: c.end!, isVolume: c.isVolume),
    ]);
    expect(await LocalBookService().currentEpubChapters(result.book), ranges);

    // 舊版轉出來的：沒有章節範圍檔。
    await File(EpubParser.chaptersPathFor(textPath)).delete();
    expect(EpubParser.readChapters(textPath), isNull);
    expect(await LocalBookService().currentEpubChapters(result.book), ranges);
    expect(EpubParser.readChapters(textPath), ranges);
    expect(LocalBookService.chaptersMatch(result.chapters, ranges!), isTrue);
    expect(
      LocalBookService.chaptersMatch(
        [...result.chapters]..last = (result.chapters.last..end = 1),
        ranges,
      ),
      isFalse,
    );
  });

  test('帶著舊目錄開書（書籍詳情傳進來的）也先對轉法版本，讀章前換上新範圍', () async {
    final path = await write('stale.epub', _epub3());
    final result = (await LocalBookService().importBook(path))!;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // 舊版轉出來的範圍：最後一章的結尾對不上現在的文字檔。
    final stale = [for (final c in result.chapters) c.copyWith()]
      ..last.end = result.chapters.last.end! - 1;
    await db.chapterDao.insertChapters(stale);
    final repository = ReaderChapterRepository(
      book: result.book,
      initialChapters: stale,
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      contentDao: db.readerChapterContentDao,
    );

    final chapters = await repository.ensureChapters();

    expect(chapters.last.end, result.chapters.last.end);
    expect(
      (await db.chapterDao.getByBook(result.book.bookUrl)).last.end,
      result.chapters.last.end,
    );
  });

  test('EPUB 2 讀 NCX 巢狀目錄，卷名頁是分卷', () async {
    final (info, texts) = await convert(await write('book2.epub', _epub2()));

    expect(info.title, '二版書');
    expect(info.author, isNull);
    expect(info.coverExtension, '.jpg');
    expect(info.chapters.map((c) => c.title), ['第一卷', '第一章']);
    expect(info.chapters.map((c) => c.isVolume), [true, false]);
    expect(texts, ['第一卷', '第一章\n正文。']);
  });

  test('舊轉法的書開書時重轉多出分卷，閱讀位置照章名留在同一章', () async {
    final path = await write('old-volumes.epub', _volumes());
    final result = (await LocalBookService().importBook(path))!;
    final textPath = await LocalBookService.epubTextPath(result.book);
    // 舊轉法（textVersion 2）沒有只有卷名的分卷：目錄只有兩章，讀到第二章。
    final old = [
      for (final (i, c) in result.chapters.skip(1).indexed)
        c.copyWith(index: i, url: '${result.book.bookUrl}#$i'),
    ];
    final chaptersFile = File(EpubParser.chaptersPathFor(textPath));
    final json = jsonDecode(await chaptersFile.readAsString()) as Map;
    await chaptersFile.writeAsString(jsonEncode({...json, 'version': 2}));
    final book = result.book
      ..chapterIndex = 1
      ..durChapterTitle = '第二章'
      ..totalChapterNum = 2;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.bookDao.upsert(book);
    await db.chapterDao.insertChapters(old);
    final repository = ReaderChapterRepository(
      book: book,
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      contentDao: db.readerChapterContentDao,
    );

    final chapters = await repository.ensureChapters();

    expect(chapters.map((c) => c.title), ['第一卷', '第一章', '第二章']);
    expect(repository.takeRefreshedChapterIndex(1), 2);
    // 只對一次：之後拿到的已經是新目錄的位置。
    expect(repository.takeRefreshedChapterIndex(2), 2);
    final stored = (await db.bookDao.getByUrl(book.bookUrl))!;
    expect(stored.chapterIndex, 2);
    expect(stored.durChapterTitle, '第二章');
    expect(stored.totalChapterNum, 3);
    expect(
      (await db.chapterDao.getByBook(book.bookUrl)).map((c) => c.isVolume),
      [true, false, false],
    );
  });

  test('轉好的文字不見時重轉，舊目錄的章照章名讀新範圍', () async {
    final path = await write('lost-volumes.epub', _volumes());
    final result = (await LocalBookService().importBook(path))!;
    await File(await LocalBookService.epubTextPath(result.book)).delete();
    // 舊轉法的目錄：沒有分卷，第一章是第 0 個、範圍是新轉法裡卷名的位置。
    final first = result.chapters[1].copyWith(
      index: 0,
      start: result.chapters[0].start,
      end: result.chapters[0].end,
    );

    expect(await LocalBookService().getContent(result.book, first), '第一章\n甲');
  });

  test('轉好的文字不見時不開書直接匯出全書，每一章都是自己的字', () async {
    final path = await write('lost-export.epub', _volumes());
    final result = (await LocalBookService().importBook(path))!;
    await File(await LocalBookService.epubTextPath(result.book)).delete();
    // 舊轉法的目錄：沒有分卷，範圍照舊轉法、各差一章。
    final old = [
      for (final (i, c) in result.chapters.skip(1).indexed)
        c.copyWith(
          index: i,
          url: '${result.book.bookUrl}#$i',
          start: result.chapters[i].start,
          end: result.chapters[i].end,
        ),
    ];
    final book = result.book
      ..isInBookshelf = true
      ..chapterIndex = 1
      ..durChapterTitle = '第二章'
      ..totalChapterNum = 2;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.bookDao.upsert(book);
    await db.chapterDao.insertChapters(old);
    await GetIt.instance.reset();
    GetIt.instance
      ..registerSingleton<BookDao>(db.bookDao)
      ..registerSingleton<ChapterDao>(db.chapterDao)
      ..registerSingleton<BookSourceDao>(db.bookSourceDao)
      ..registerSingleton<ReaderChapterContentDao>(db.readerChapterContentDao);
    addTearDown(GetIt.instance.reset);
    const share = MethodChannel('dev.fluttercommunity.plus/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          share,
          (_) async => 'dev.fluttercommunity.plus/share/unavailable',
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(share, null),
    );

    await ExportBookService().exportToTxt(
      book,
      present: (chapter, raw) async => (title: chapter.title, text: raw),
    );

    final exported = await (await AppStoragePaths.shareExportFile('分卷之書.txt'))
        .readAsString();
    expect(exported, contains('第二章\n乙'));
    expect('甲'.allMatches(exported), hasLength(1));
    expect((await db.chapterDao.getByBook(book.bookUrl)).map((c) => c.title), [
      '第一卷',
      '第一章',
      '第二章',
    ]);
    final stored = (await db.bookDao.getByUrl(book.bookUrl))!;
    expect(stored.chapterIndex, 2);
    expect(stored.totalChapterNum, 3);
  });

  test('卷名和第一章指向同一個檔案時，正文只出現一次', () async {
    final (info, texts) = await convert(
      await write(
        'volume.epub',
        _simple(
          {'c1.xhtml': _xhtml('<p>甲</p>')},
          [('第一卷', 'c1.xhtml'), ('第一章', 'c1.xhtml')],
        ),
      ),
    );

    expect(info.chapters.map((c) => c.title), ['第一章']);
    expect(texts, ['甲']);
  });

  test('只差大小寫的兩個檔案各是各的', () async {
    final (_, texts) = await convert(
      await write(
        'case.epub',
        _simple(
          {'x.xhtml': _xhtml('<p>甲</p>'), 'X.xhtml': _xhtml('<p>乙</p>')},
          [('一', 'x.xhtml'), ('二', 'X.xhtml')],
        ),
      ),
    );

    expect(texts, ['甲', '乙']);
  });

  test('UTF-16 的檔案、屬性值裡有 > 的自閉標籤照樣讀出正文', () async {
    final (_, texts) = await convert(
      await write(
        'utf16.epub',
        _simple(
          {
            'c1.xhtml': _utf16le(
              _xhtml('<script src="a.js" data-note="1 > 0"/><p>甲</p>')
                  .replaceFirst('encoding="utf-8"', 'encoding="UTF-16"'),
            ),
          },
          [('一', 'c1.xhtml')],
        ),
      ),
    );

    expect(texts, ['甲']);
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

  test('超過五萬字的章照拿掉插圖後的字切：標記不被切開，切點和沒有圖時一樣', () async {
    final path = await write(
      'long-picture.epub',
      _simple(
        {
          'Text/one.xhtml': _xhtml(
            '<p>${'字' * 29998}<img src="../Images/a.png"/>${'字' * 30002}</p>',
          ),
        },
        [('第一章', 'Text/one.xhtml')],
      )..['OEBPS/Images/a.png'] = _png,
    );
    final (info, texts) = await convert(path);

    final marker = RegExp(r'<img src="[^"]*">');
    expect(info.chapters.map((c) => c.title), ['第一章 (1)', '第一章 (2)']);
    expect(texts.join().split('<img').length - 1, 1);
    expect(texts.map((t) => marker.allMatches(t).length).toList(), [1, 0]);
    // 第一塊拿掉標記後正好三萬字，和沒有插圖時切在同一個地方。
    expect(texts[0].replaceAll(marker, '').length, 30000);
  });

  test('超過五萬字、有分段的章照字數切，不找換行、不照 TXT 的新規則（textVersion 2 的切法）', () async {
    // 轉好的文字檔不見時會重轉：切法一變，資料庫裡的章節與閱讀位置就對不上。
    final paragraphs = [
      for (var i = 0; i < 70; i += 1)
        if (i == 20)
          '<p>序章</p>'
        else if (i == 40)
          '<p>Chapter 1 Start</p>'
        else
          '<p>${'字' * 999}</p>',
    ].join();
    final path = await write(
      'long-paragraphs.epub',
      _simple(
        {'Text/one.xhtml': _xhtml(paragraphs)},
        [('第一章', 'Text/one.xhtml')],
      ),
    );
    final (info, texts) = await convert(path);

    expect(info.chapters.map((c) => c.title), [
      '第一章 (1)',
      '第一章 (2)',
      '第一章 (3)',
    ]);
    expect(texts[0].length, 30000);
    expect(texts[1].length, 30000);
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

    await expectLater(
      LocalBookService().getContent(book, chapter),
      throwsA(
        isA<LocalBookContentException>().having(
          (e) => e.message,
          'message',
          '本地書索引缺失，請重新匯入',
        ),
      ),
    );
  });
}
