import 'dart:isolate';
import 'dart:typed_data';

import 'package:night_reader/core/comic/comic_chapter_download.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';

import 'comic_page_source.dart';

/// 網路漫畫的圖從哪裡來（ADR 0052）：
/// - 下載好的話讀 CBZ；
/// - 還沒下載好的照書源拿這一話的圖片網址，每張先看暫存資料夾抓到了沒有，
///   沒有就照書源抓。書架上的書抓到的存進暫存資料夾，書架自動下載接著用。
class NetworkComicPageSource implements ComicPageSource {
  NetworkComicPageSource({
    required this.book,
    required this.source,
    required this.chapters,
    BookSourceService? service,
  }) : _service = service ?? BookSourceService();

  final Book book;
  final BookSource source;
  final List<BookChapter> chapters;
  final BookSourceService _service;

  /// 下載好的那幾話的 CBZ。
  final Map<int, String> _cbz = {};

  /// 還沒下載好的那幾話的圖片網址。
  final Map<int, List<String>> _urls = {};

  @override
  Future<List<ComicPage>> pagesOf(int chapterIndex) async {
    final chapter = chapters[chapterIndex];
    final cbz = await ComicChapterDownload.cbzFor(book, chapter);
    if (cbz != null) {
      List<ComicPage> pages;
      try {
        pages = await ComicChapterFiles.pagesOf(cbz.path);
      } catch (_) {
        pages = const [];
      }
      if (pages.isNotEmpty) {
        _cbz[chapterIndex] = cbz.path;
        return pages;
      }
      // 下載好的檔壞了：刪掉照書源重抓，書架自動下載也會再排這一話。
      await cbz.delete();
    }
    final urls = await _service.getComicPageUrls(
      source,
      book,
      chapter,
      remember: book.isInBookshelf,
    );
    _urls[chapterIndex] = urls;
    // 已經抓到的圖記得寬高，一開始就是正確高度。
    final dir = (await ComicChapterDownload.partialDirFor(book, chapter)).path;
    final sizes = await Isolate.run(
      () => ComicChapterDownload.sizesIn(dir, urls.length),
    );
    return [
      for (var i = 0; i < urls.length; i++)
        ComicPage(
          name: urls[i],
          width: sizes[i]?.width,
          height: sizes[i]?.height,
        ),
    ];
  }

  @override
  Future<Uint8List> bytesOf(int chapterIndex, ComicPage page) async {
    if (_cbz[chapterIndex] case final cbz?) {
      final bytes = await ComicChapterFiles.readPage(cbz, page.name);
      if (bytes == null) throw StateError('這張圖不見了：${page.name}');
      return bytes;
    }
    final urls = _urls[chapterIndex] ?? const <String>[];
    final index = urls.indexOf(page.name);
    if (index < 0) throw StateError('這一話沒有這張圖');
    return _service.getComicPage(
      source,
      book,
      chapters[chapterIndex],
      index,
      page.name,
      keep: book.isInBookshelf,
    );
  }

  @override
  String? webUrlOf(int chapterIndex, ComicPage page) =>
      _cbz.containsKey(chapterIndex) ? null : page.name;
}
