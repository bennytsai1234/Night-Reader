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
/// - 還沒下載好的照書源拿這一話的圖片網址，每張先看這一話後來打包好了沒有、
///   暫存資料夾抓到了沒有，沒有就照書源抓。書架上的書抓到的存進暫存資料夾，
///   書架自動下載接著用。
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

  /// 下載好的那幾話打開的 CBZ；讀圖用打開時記下的位置。
  final Map<int, ComicChapterContents> _cbz = {};

  /// 還沒下載好的那幾話的圖片網址。
  final Map<int, List<String>> _urls = {};

  /// 列清單時還沒下載好、之後打包好的那幾話打開的 CBZ；同時來的幾張共用
  /// 同一次打開。還沒打包好、打不開的不留著，下一張再看一次。
  final Map<int, Future<ComicChapterContents?>> _packed = {};

  @override
  Future<List<ComicPage>> pagesOf(int chapterIndex) async {
    final chapter = chapters[chapterIndex];
    final cbz = await ComicChapterDownload.cbzFor(book, chapter);
    _cbz.remove(chapterIndex);
    _packed.remove(chapterIndex)?.ignore();
    if (cbz != null) {
      ComicChapterContents? opened;
      try {
        opened = await ComicChapterFiles.open(cbz.path);
      } catch (_) {
        opened = null;
      }
      if (opened != null && opened.pages.isNotEmpty) {
        _cbz[chapterIndex] = opened;
        return opened.pages;
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
      final bytes = await cbz.read(page.name);
      if (bytes == null) throw StateError('這張圖不見了：${page.name}');
      return bytes;
    }
    final urls = _urls[chapterIndex] ?? const <String>[];
    final index = urls.indexOf(page.name);
    if (index < 0) throw StateError('這一話沒有這張圖');
    if (await _packedPage(chapterIndex, index) case final bytes?) return bytes;
    return _service.getComicPage(
      source,
      book,
      chapters[chapterIndex],
      index,
      page.name,
      keep: book.isInBookshelf,
    );
  }

  /// 列清單之後才下載完、打包好的那一話：第 [index] 張從 CBZ 讀，打開一次
  /// 留著；還沒打包好是 null。
  Future<Uint8List?> _packedPage(int chapterIndex, int index) async {
    final opening = _packed[chapterIndex] ??= _openPacked(chapterIndex);
    final opened = await opening;
    if (opened == null) {
      if (identical(_packed[chapterIndex], opening)) {
        _packed.remove(chapterIndex)?.ignore();
      }
      return null;
    }
    final prefix = ComicChapterDownload.pageFileName(index, '.');
    for (final page in opened.pages) {
      if (page.name.startsWith(prefix)) return opened.read(page.name);
    }
    return null;
  }

  Future<ComicChapterContents?> _openPacked(int chapterIndex) async {
    final cbz = await ComicChapterDownload.cbzFor(book, chapters[chapterIndex]);
    if (cbz == null) return null;
    try {
      return await ComicChapterFiles.open(cbz.path);
    } catch (_) {
      return null;
    }
  }

  @override
  String? webUrlOf(int chapterIndex, ComicPage page) =>
      _cbz.containsKey(chapterIndex) ? null : page.name;
}
