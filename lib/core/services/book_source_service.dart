import 'package:dio/dio.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';

/// BookSourceService - 書源核心業務調度 (對標 Android model/webBook/WebBook.kt)
class BookSourceService {
  /// 獲取書籍詳情 (對標 getBookInfoAwait)
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    return await WebBook.getBookInfoAwait(
      source,
      book,
      cancelToken: cancelToken,
    );
  }

  /// 獲取目錄列表 (對標 getChapterListAwait)
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return await WebBook.getChapterListAwait(
      source,
      book,
      chapterLimit: chapterLimit,
      pageConcurrency: pageConcurrency,
      cancelToken: cancelToken,
    );
  }

  /// 獲取正文內容 (對標 getContentAwait)
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return await WebBook.getContentAwait(
      source,
      book,
      chapter,
      nextChapterUrl: nextChapterUrl,
      pageConcurrency: pageConcurrency,
      cancelToken: cancelToken,
    );
  }

  /// 搜尋書籍 (對標 searchBookAwait)
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    return await WebBook.searchBookAwait(
      source,
      key,
      page: page,
      filter: filter,
      shouldBreak: shouldBreak,
      cancelToken: cancelToken,
    );
  }

  /// 發現/探索書籍 (對標 exploreBookAwait)
  Future<List<SearchBook>> exploreBooks(
    BookSource source,
    String url, {
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    return await WebBook.exploreBookAwait(
      source,
      url,
      page: page,
      cancelToken: cancelToken,
    );
  }

  /// 精確搜尋
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author,
  ) async {
    return await WebBook.searchBookAwait(
      source,
      name,
      filter: (n, a) => n == name && a == author,
      shouldBreak: (size) => size >= 1,
    );
  }

  Future<List<Book>> importBookshelf(String url) async {
    final result = await BookshelfExchangeService().importFromUrl(url);
    if (result.books <= 0) return [];
    return getIt<BookDao>().getInBookshelf();
  }

  /// 儲存（新增或更新）書源
  Future<void> saveSource(BookSource source) =>
      getIt<BookSourceDao>().upsert(source);

  /// 依 URL 取得書源
  Future<BookSource?> getSourceByUrl(String url) =>
      getIt<BookSourceDao>().getByUrl(url);

  /// 取得書籍所有章節（用於不帶完整 provider 的頁面）
  Future<List<BookChapter>> getBookChapters(String bookUrl) =>
      getIt<ChapterDao>().getByBook(bookUrl);
}
