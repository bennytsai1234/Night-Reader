import 'package:dio/dio.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/chapter.dart';
import 'package:night_reader/core/source/book_source_service.dart';

/// 換源清單的假網站共用的詳情與目錄：換源清單要抓到目錄才列出一本書。
/// 每個書源的目錄有 [chapterCountFor] 章，0 章（目錄抓不到）的不列。
mixin ChapterListSites on BookSourceService {
  int chapterCountFor(String origin) => 10;

  /// 每次抓目錄是不是要整份（`requireComplete`）。
  final List<bool> completeRequests = [];

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async => book;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async {
    completeRequests.add(requireComplete);
    return [
      for (var i = 0; i < chapterCountFor(source.bookSourceUrl); i++)
        BookChapter(
          url: '${book.bookUrl}/c$i',
          title: '第${i + 1}章',
          bookUrl: book.bookUrl,
          index: i,
        ),
    ];
  }
}
