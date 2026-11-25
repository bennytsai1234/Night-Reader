// 書籍詳情匯出全書時，本地 EPUB 的目錄可能被重寫（轉好的文字不見、重轉後
// 多了分卷）：匯出完詳情手上的目錄與進度要是新的，再開閱讀器才帶對的目錄。
// 整個 App（記憶體資料庫、真的匯出）跑一次。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/widgets/book_info_header.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';

String _xhtml(String body) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title/></head>'
    '<body>$body</body></html>';

/// 第一卷底下兩章，卷名和第一章指向同一個檔案。
const _entries = <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
  'OEBPS/content.opf': '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>分卷之書</dc:title>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''',
  'OEBPS/toc.ncx': '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
  <navPoint><navLabel><text>第一卷</text></navLabel><content src="c1.xhtml"/>
    <navPoint><navLabel><text>第一章</text></navLabel><content src="c1.xhtml"/></navPoint>
    <navPoint><navLabel><text>第二章</text></navLabel><content src="c2.xhtml"/></navPoint>
  </navPoint>
</navMap></ncx>''',
};

void main() {
  /// 一段一段推進（每段讓出真實時間給檔案與背景 isolate），直到 [done] 成立。
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue);
  }

  bool showing(Finder finder) => finder.evaluate().isNotEmpty;

  testWidgets('匯出時重寫了本地書的目錄，詳情接著用新目錄與對好的進度開書', (tester) async {
    setUpPhone(tester);
    late Directory dir;
    late Book book;
    await tester.runAsync(() async {
      await setUpApp();
      dir = await Directory.systemTemp.createTemp('book_detail_export');
      AppStoragePaths.useRoots((
        documents: dir.path,
        support: dir.path,
        temporary: dir.path,
      ));
      final archive = Archive();
      _entries.forEach(
        (name, text) =>
            archive.addFile(ArchiveFile.bytes(name, utf8.encode(text))),
      );
      archive
        ..addFile(
          ArchiveFile.bytes(
            'OEBPS/c1.xhtml',
            utf8.encode(_xhtml('<h1>第一章</h1><p>甲</p>')),
          ),
        )
        ..addFile(
          ArchiveFile.bytes(
            'OEBPS/c2.xhtml',
            utf8.encode(_xhtml('<h1>第二章</h1><p>乙</p>')),
          ),
        );
      final path = p.join(dir.path, 'volumes.epub');
      await File(path).writeAsBytes(ZipEncoder().encodeBytes(archive));
      final result = (await LocalBookService().importBook(path))!;
      await File(await LocalBookService.epubTextPath(result.book)).delete();
      // 舊轉法的目錄：沒有分卷，讀到第二章。
      final old = [
        for (final (i, c) in result.chapters.skip(1).indexed)
          c.copyWith(
            index: i,
            url: '${result.book.bookUrl}#$i',
            start: result.chapters[i].start,
            end: result.chapters[i].end,
          ),
      ];
      book = result.book
        ..isInBookshelf = true
        ..chapterIndex = 1
        ..durChapterTitle = '第二章'
        ..totalChapterNum = 2;
      await getIt<BookDao>().upsert(book);
      await getIt<ChapterDao>().insertChapters(old);
    });
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
    await pumpApp(tester);
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: book)),
        );
    await settleUntil(tester, () => showing(find.text('已在書架')));
    await settle(tester);

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is GlassMenuButton),
    );
    await settle(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('匯出全書'));
    await settleUntil(tester, () => showing(find.text('已建立匯出檔案')));
    await settle(tester, const Duration(milliseconds: 500));

    final provider = Provider.of<BookDetailProvider>(
      tester.element(find.byType(BookInfoHeader)),
      listen: false,
    );
    // 「繼續閱讀」帶進閱讀器的目錄與位置。
    expect(provider.allChapters.map((c) => c.title), ['第一卷', '第一章', '第二章']);
    expect(provider.book.chapterIndex, 2);

    // 拆掉 App，讓它留下的計時器跑完，測試才能正常結束。
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 5));
    await tester.pump(const Duration(minutes: 1));
    await tester.runAsync(() async {
      await LocalBookService().closeOpenFile();
      await dir.delete(recursive: true);
    });
  });
}
