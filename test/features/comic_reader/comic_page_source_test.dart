import 'dart:io';

import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_download.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/features/comic_reader/comic_page_source.dart';
import 'package:night_reader/features/comic_reader/network_comic_page_source.dart';
import 'package:path/path.dart' as p;

import 'comic_test_pages.dart';

/// 書源：網站現在回 [served]。抓一張照真的做法（`ComicChapterDownload
/// .pageBytes`）：暫存資料夾有就讀那份，沒有才向網站要。
class _Site extends BookSourceService {
  _Site(this.served);

  Uint8List served;
  int fetches = 0;

  @override
  Future<List<String>> getComicPageUrls(
    BookSource source,
    Book book,
    BookChapter chapter, {
    bool remember = true,
    CancelToken? cancelToken,
  }) async => ['https://comic.test/1.png'];

  @override
  Future<Uint8List> getComicPage(
    BookSource source,
    Book book,
    BookChapter chapter,
    int index,
    String url, {
    bool keep = true,
    CancelToken? cancelToken,
  }) async {
    final dir = await ComicChapterDownload.partialDirFor(book, chapter);
    if (ComicChapterDownload.pageFileIn(dir, index) case final file?) {
      return file.readAsBytes();
    }
    fetches += 1;
    if (keep) {
      await dir.create(recursive: true);
      await File(
        p.join(dir.path, ComicChapterDownload.pageFileName(index, '.png')),
      ).writeAsBytes(served);
    }
    return served;
  }
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('comic-source-'));
  tearDown(() => temp.deleteSync(recursive: true));

  void writeCbz(String path, Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, bytes) {
      archive.add(
        ArchiveFile.bytes(name, bytes)..compression = CompressionType.none,
      );
    });
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('打開一次讀每一張；重新列清單時照現在的檔重新打開', () async {
    final path = p.join(temp.path, '1.cbz');
    final first = stripedPng(4, 6, 0x112233, 0x445566);
    final second = stripedPng(4, 8, 0x778899, 0x223344);
    writeCbz(path, {'0001.png': first, '0002.png': second});
    var opens = 0;
    final source = ComicChapterFilesSource((_) async {
      opens += 1;
      return path;
    });

    final pages = await source.pagesOf(0);
    expect(pages.map((page) => page.name), ['0001.png', '0002.png']);
    expect(await source.bytesOf(0, pages[0]), first);
    expect(await source.bytesOf(0, pages[1]), second);
    expect(opens, 1);

    // 換成另一個檔（重抓、重新匯入）後列清單：拿到新的圖。
    final replacement = stripedPng(4, 10, 0x000000, 0xFFFFFF);
    writeCbz(path, {'0001.png': replacement});
    final again = await source.pagesOf(0);
    expect(again.map((page) => page.height), [10]);
    expect(await source.bytesOf(0, again[0]), replacement);
    expect(opens, 2);
  });

  test('打不開的一話不留著，下次重新打開', () async {
    final path = p.join(temp.path, 'missing.cbz');
    final source = ComicChapterFilesSource((_) async => path);
    await expectLater(source.pagesOf(0), throwsA(isA<FileSystemException>()));
    writeCbz(path, {'0001.png': stripedPng(2, 2, 0, 0)});
    expect(await source.pagesOf(0), hasLength(1));
  });

  test('網路漫畫按「重試」：不讀之前暫存的那張（可能是壞的），照書源重抓', () async {
    AppStoragePaths.useRoots((
      documents: temp.path,
      support: temp.path,
      temporary: temp.path,
    ));
    final book = Book(
      bookUrl: 'https://comic.test/b',
      name: '長夜',
      origin: 'https://comic.test',
      isInBookshelf: true,
    );
    final chapter = BookChapter(
      url: 'https://comic.test/c1',
      title: '第1話',
      bookUrl: book.bookUrl,
      index: 0,
    );
    final good = stripedPng(4, 6, 0x112233, 0x445566);
    // 網站一開始回的圖只有檔頭（寬高讀得出來，圖解不開）。
    final site = _Site(Uint8List.sublistView(good, 0, 33));
    final pages = NetworkComicPageSource(
      book: book,
      source: BookSource(bookSourceUrl: book.origin, bookSourceName: '漫畫'),
      chapters: [chapter],
      service: site,
    );
    final page = (await pages.pagesOf(0)).single;
    expect(await pages.bytesOf(0, page), hasLength(33));

    site.served = good;
    expect(await pages.bytesOf(0, page), hasLength(33), reason: '一般讀照舊用暫存的');
    expect(await pages.bytesOf(0, page, refresh: true), good);
    expect(site.fetches, 2);
    expect(await pages.bytesOf(0, page), good, reason: '重抓的存回暫存資料夾');
  });
}
