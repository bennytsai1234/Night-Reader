import 'package:dio/dio.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/engine/rule_data_fields.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';

/// BookSourceService - 書源核心業務調度 (對標 Android model/webBook/WebBook.kt)
///
/// 書源的抓取與解析都在書源 isolate 執行（ADR 0028），畫面執行緒只收結果；
/// 已經在書源 isolate 裡（例如規則 JS 呼叫回來）或沒開書源 isolate 時原地
/// 執行。送過去的書與章節是複本，規則在複本上改的欄位（例如
/// `book.putVariable`）跑完後抄回傳入的物件，和原地執行時一樣。
class BookSourceService {
  /// 獲取書籍詳情 (對標 getBookInfoAwait)
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) => _runOnSource(
    _bookInfoTask(source, book),
    book: book,
    cancelToken: cancelToken,
  );

  /// 獲取目錄列表 (對標 getChapterListAwait)
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) => _runOnSource(
    _chapterListTask(
      source,
      book,
      chapterLimit: chapterLimit,
      pageConcurrency: pageConcurrency,
      requireComplete: requireComplete,
    ),
    book: book,
    cancelToken: cancelToken,
  );

  /// 獲取正文內容。
  ///
  /// 正文分頁必須完整走完才算成功；達安全上限仍有下一頁時直接失敗，
  /// 避免只抓到前半章卻被上層當 ready 寫入正文快取。
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) => _runOnSource(
    _contentTask(
      source,
      book,
      chapter,
      nextChapterUrl: nextChapterUrl,
      pageConcurrency: pageConcurrency,
    ),
    book: book,
    chapter: chapter,
    cancelToken: cancelToken,
  );

  /// 搜尋書籍 (對標 searchBookAwait)
  ///
  /// [filter]、[shouldBreak] 會跟著送進書源 isolate，要在只捕捉書名、作者
  /// 這類資料的頂層函式裡建立（`CODING_STANDARDS.md`）。
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) => _runOnSource(
    _searchTask(
      source,
      key,
      page: page,
      filter: filter,
      shouldBreak: shouldBreak,
    ),
    cancelToken: cancelToken,
  );

  /// 發現/探索書籍 (對標 exploreBookAwait)
  Future<List<SearchBook>> exploreBooks(
    BookSource source,
    String url, {
    int? page = 1,
    CancelToken? cancelToken,
  }) => _runOnSource(
    _exploreTask(source, url, page: page),
    cancelToken: cancelToken,
  );

  /// 發現頁的分類（對標 BookSource.getExploreKinds）；`<js>`、`@js:` 規則
  /// 也在書源 isolate 執行。
  Future<List<ExploreKind>> exploreKinds(
    String? exploreUrl, {
    BookSource? source,
  }) => _runOnSource(_exploreKindsTask(exploreUrl, source));

  /// 精確搜尋：書名與作者都相同的第一本。
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author,
  ) => searchBooks(
    source,
    name,
    filter: _exactBook(name, author),
    shouldBreak: stopAtFirstSearchResult,
  );

  Future<List<Book>> importBookshelf(String url) async {
    final result = await BookshelfExchangeService().importFromUrl(url);
    if (result.books <= 0) return [];
    return getIt<BookDao>().getInBookshelf();
  }

  /// 儲存編輯後的書源；網址改過時一併移除原網址那筆。
  Future<void> saveEditedSource(BookSource source, {String? previousUrl}) =>
      getIt<BookSourceDao>().saveEdited(source, previousUrl: previousUrl);

  /// 依 URL 取得書源
  Future<BookSource?> getSourceByUrl(String url) =>
      getIt<BookSourceDao>().getByUrl(url);

  /// 取得書籍所有章節（用於不帶完整 provider 的頁面）
  Future<List<BookChapter>> getBookChapters(String bookUrl) =>
      getIt<ChapterDao>().getByBook(bookUrl);
}

/// 搜尋找到第一本就停，給 [BookSourceService.searchBooks] 的 `shouldBreak`。
/// 頂層函式送得進書源 isolate。
bool stopAtFirstSearchResult(int size) => size >= 1;

bool Function(String name, String author) _exactBook(
  String name,
  String author,
) =>
    (n, a) => n == name && a == author;

// ── 送進書源 isolate 的工作 ─────────────────────────────────────────
//
// 每個工作在只捕捉書源、書、章節與參數的頂層函式裡建立，連同捕捉的變數複製
// 到書源 isolate。工作把它手上的書與章節（書源 isolate 裡是複本）一起傳回，
// 讓 [_runOnSource] 把規則改過的欄位抄回來。

typedef _SourceTask<R> = Future<_Ran<R>> Function(CancelToken cancelToken);

final class _Ran<R> {
  const _Ran(this.result, {this.book, this.chapter});

  final R result;
  final Book? book;
  final BookChapter? chapter;
}

_SourceTask<Book> _bookInfoTask(BookSource source, Book book) =>
    (cancelToken) async => _Ran(
      await WebBook.getBookInfoAwait(source, book, cancelToken: cancelToken),
      book: book,
    );

_SourceTask<List<BookChapter>> _chapterListTask(
  BookSource source,
  Book book, {
  required int? chapterLimit,
  required int? pageConcurrency,
  required bool requireComplete,
}) =>
    (cancelToken) async => _Ran(
      await WebBook.getChapterListAwait(
        source,
        book,
        chapterLimit: chapterLimit,
        pageConcurrency: pageConcurrency,
        cancelToken: cancelToken,
        requireComplete: requireComplete,
      ),
      book: book,
    );

_SourceTask<String> _contentTask(
  BookSource source,
  Book book,
  BookChapter chapter, {
  required String? nextChapterUrl,
  required int? pageConcurrency,
}) =>
    (cancelToken) async => _Ran(
      await CompleteContentFetcher.fetch(
        source,
        book,
        chapter,
        nextChapterUrl: nextChapterUrl,
        pageConcurrency: pageConcurrency,
        cancelToken: cancelToken,
      ),
      book: book,
      chapter: chapter,
    );

_SourceTask<List<SearchBook>> _searchTask(
  BookSource source,
  String key, {
  required int page,
  required bool Function(String name, String author)? filter,
  required bool Function(int size)? shouldBreak,
}) =>
    (cancelToken) async => _Ran(
      await WebBook.searchBookAwait(
        source,
        key,
        page: page,
        filter: filter,
        shouldBreak: shouldBreak,
        cancelToken: cancelToken,
      ),
    );

_SourceTask<List<SearchBook>> _exploreTask(
  BookSource source,
  String url, {
  required int? page,
}) =>
    (cancelToken) async => _Ran(
      await WebBook.exploreBookAwait(
        source,
        url,
        page: page,
        cancelToken: cancelToken,
      ),
    );

_SourceTask<List<ExploreKind>> _exploreKindsTask(
  String? exploreUrl,
  BookSource? source,
) =>
    (cancelToken) async =>
        _Ran(await ExploreUrlParser.parseAsync(exploreUrl, source: source));

/// 在書源 isolate 執行 [task]，把規則在 [book]、[chapter] 複本上改的欄位
/// （[bookRuleFields]、[chapterRuleFields]）抄回來。只抄這次跑的期間有變的欄位：同一段時間裡畫面執行緒改了這本書
/// （例如閱讀進度），規則沒動的欄位不會被舊值蓋掉。
Future<R> _runOnSource<R>(
  _SourceTask<R> task, {
  Book? book,
  BookChapter? chapter,
  CancelToken? cancelToken,
}) async {
  final bookBefore = book == null ? null : _readFields(bookRuleFields, book);
  final chapterBefore = chapter == null
      ? null
      : _readFields(chapterRuleFields, chapter);
  final ran = await SourceIsolate.run(task, cancelToken: cancelToken);
  final ranBook = ran.book;
  if (book != null && ranBook != null && !identical(ranBook, book)) {
    _copyChangedFields(bookRuleFields, bookBefore!, from: ranBook, to: book);
  }
  final ranChapter = ran.chapter;
  if (chapter != null &&
      ranChapter != null &&
      !identical(ranChapter, chapter)) {
    _copyChangedFields(
      chapterRuleFields,
      chapterBefore!,
      from: ranChapter,
      to: chapter,
    );
  }
  return ran.result;
}

Map<String, Object?> _readFields<T>(
  Map<String, RuleDataField<T>> fields,
  T target,
) => {
  for (final MapEntry(:key, :value) in fields.entries) key: value.read(target),
};

void _copyChangedFields<T>(
  Map<String, RuleDataField<T>> fields,
  Map<String, Object?> before, {
  required T from,
  required T to,
}) {
  for (final MapEntry(:key, :value) in fields.entries) {
    final now = value.read(from);
    if (now != before[key]) value.write(to, now);
  }
}
