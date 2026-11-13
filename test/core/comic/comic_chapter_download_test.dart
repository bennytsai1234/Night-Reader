import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_download.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_chapter_files.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import '../../features/comic_reader/comic_test_pages.dart';

void main() {
  late Directory root;
  final book = Book(
    bookUrl: 'https://comic.test/book/1',
    origin: 'https://comic.test',
    name: '夜行',
    type: 2,
  );
  final chapter = BookChapter(
    url: 'https://comic.test/ch/1',
    title: '第1話 <開始>',
    bookUrl: book.bookUrl,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('comic_download_');
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('正文裡依序的圖片網址：img 標記與整行網址', () {
    const content =
        '<img src="https://a.test/1.jpg">\n'
        'https://a.test/2.webp\n'
        '說明文字\n'
        '<img src="https://a.test/3.png"><img src="https://a.test/4.png">';
    expect(ComicChapterDownload.imageUrlsOf(content), [
      'https://a.test/1.jpg',
      'https://a.test/2.webp',
      'https://a.test/3.png',
      'https://a.test/4.png',
    ]);
  });

  test('暫存資料夾的圖打包成 CBZ，打開時每張寬高一開始就知道', () async {
    final dir = await ComicChapterDownload.partialDirFor(book, chapter);
    dir.createSync(recursive: true);
    File(p.join(dir.path, '0002.png'))
        .writeAsBytesSync(stripedPng(10, 30, 0, 0));
    File(p.join(dir.path, '0001.png'))
        .writeAsBytesSync(stripedPng(10, 20, 0, 0));
    // 沒寫完的不算。
    File(p.join(dir.path, '0003.png.part')).writeAsBytesSync([1]);
    expect(ComicChapterDownload.pageFileIn(dir, 2), isNull);
    expect(await ComicChapterDownload.cbzFor(book, chapter), isNull);
    // 下載中的資料夾不算下載好的章節檔。
    expect(await BookChapterFiles.downloaded(book), isEmpty);

    final cbz = await ComicChapterDownload.pack(book, chapter, dir, 2);
    expect(cbz.path, endsWith('.cbz'));
    expect((await ComicChapterDownload.cbzFor(book, chapter))?.path, cbz.path);

    final archive = ZipDecoder().decodeBytes(cbz.readAsBytesSync());
    final info = utf8.decode(
      archive.find(ComicChapterFiles.comicInfoName)!.readBytes()!,
    );
    expect(info, contains('第1話 &lt;開始&gt;'));
    expect(info, contains('ImageHeight="30"'));
    expect(
      archive.files.firstWhere((f) => f.name == '0001.png').compression,
      CompressionType.none,
    );
    final opened = await ComicChapterFiles.open(cbz.path);
    expect(await opened.read('0002.png'), stripedPng(10, 30, 0, 0));
    expect(opened.pages, const [
      ComicPage(name: '0001.png', width: 10, height: 20),
      ComicPage(name: '0002.png', width: 10, height: 30),
    ]);
  });

  test('已下載的話只算打包好的 CBZ，下載到一半的不算', () async {
    final other = BookChapter(
      url: 'https://comic.test/ch/2',
      title: '第2話',
      bookUrl: book.bookUrl,
    );
    final dir = await ComicChapterDownload.partialDirFor(book, chapter);
    dir.createSync(recursive: true);
    File(p.join(dir.path, '0001.png')).writeAsBytesSync(stripedPng(2, 2, 0, 0));
    expect(await downloadedComicChapterUrls(book, [chapter, other]), isEmpty);

    await ComicChapterDownload.pack(book, chapter, dir, 1);
    expect(await downloadedComicChapterUrls(book, [chapter, other]), {
      chapter.url,
    });
  });

  test('少了一張時不打包', () async {
    final dir = await ComicChapterDownload.partialDirFor(book, chapter);
    dir.createSync(recursive: true);
    File(p.join(dir.path, '0001.png')).writeAsBytesSync(stripedPng(4, 4, 0, 0));
    await expectLater(
      ComicChapterDownload.pack(book, chapter, dir, 2),
      throwsStateError,
    );
    expect(await ComicChapterDownload.cbzFor(book, chapter), isNull);
  });

  test('副檔名照檔頭認', () {
    expect(ComicChapterDownload.extensionOf(stripedPng(1, 1, 0, 0)), '.png');
    expect(
      ComicChapterDownload.extensionOf(
        Uint8List.fromList('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits),
      ),
      '.webp',
    );
    expect(ComicChapterDownload.extensionOf(Uint8List(4)), '.jpg');
  });
}
