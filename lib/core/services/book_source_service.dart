import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/base_source.dart';
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
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    source: source,
    book: book,
    cancelToken: cancelToken,
  );

  /// 從書籍詳情頁取封面與字數（和 [getBookInfo] 同一條解析），給清單補上
  /// 清單規則沒給的；只把這兩個欄位傳回畫面執行緒，不帶整頁 HTML。沒抓到
  /// 的是空字串。
  Future<({String coverUrl, String wordCount})> getCoverAndWordCount(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) => _runOnSource(
    _coverAndWordCountTask(source, book),
    source: source,
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
    source: source,
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
    source: source,
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
    source: source,
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
    source: source,
    cancelToken: cancelToken,
  );

  /// 發現頁的分類（對標 BookSource.getExploreKinds）；`<js>`、`@js:` 規則
  /// 也在書源 isolate 執行。
  Future<List<ExploreKind>> exploreKinds(
    String? exploreUrl, {
    BookSource? source,
  }) => _runOnSource(_exploreKindsTask(exploreUrl, source), source: source);

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

  /// 儲存編輯後的書源。網址改過時，以原網址記的一切跟著搬到新網址（書架上
  /// 的書、搜尋結果、已下載的正文見 [BookSourceDao.saveEdited]，登入資訊與
  /// 變數見 [BaseSource.moveCachedIdentity]）；搬的時候這些書的下載先停住，
  /// 搬完照原本的狀態接著下載，不會有一輪用舊網址寫正文。
  Future<void> saveEditedSource(
    BookSource source, {
    String? previousUrl,
  }) async {
    final sourceDao = getIt<BookSourceDao>();
    if (previousUrl == null || previousUrl == source.bookSourceUrl) {
      return sourceDao.saveEdited(source);
    }
    final books = await getIt<BookDao>().bookUrlsFromOrigin(previousUrl);
    final otherSources = [
      for (final other in await sourceDao.getAllPart()) other.bookSourceUrl,
    ];
    final release = books.isEmpty
        ? null
        : await DownloadService().holdBooks(books);
    try {
      await BaseSource.moveCachedIdentity(
        previousUrl,
        source.getKey(),
        otherKeys: otherSources,
        commit: () => sourceDao.saveEdited(source, previousUrl: previousUrl),
      );
    } finally {
      release?.call();
    }
    // 同步時別台照這份紀錄把舊網址的書搬過去（ADR 0039）。
    await SourceMoves(await SharedPreferences.getInstance())
        .record(from: previousUrl, to: source.bookSourceUrl);
  }

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
// 到書源 isolate。

typedef _Work<R> = Future<R> Function(CancelToken cancelToken);

_Work<Book> _bookInfoTask(BookSource source, Book book) =>
    (cancelToken) =>
        WebBook.getBookInfoAwait(source, book, cancelToken: cancelToken);

_Work<({String coverUrl, String wordCount})> _coverAndWordCountTask(
  BookSource source,
  Book book,
) => (cancelToken) async {
  final info = await WebBook.getBookInfoAwait(
    source,
    book,
    cancelToken: cancelToken,
  );
  // 字數照書籍詳情的寫法：字數欄沒有時從分類（例如「玄幻,25萬字」）取。
  return (
    coverUrl: info.coverUrl ?? '',
    wordCount: StringUtils.displayWordCount(info.wordCount, info.kind),
  );
};

_Work<List<BookChapter>> _chapterListTask(
  BookSource source,
  Book book, {
  required int? chapterLimit,
  required int? pageConcurrency,
  required bool requireComplete,
}) =>
    (cancelToken) => WebBook.getChapterListAwait(
      source,
      book,
      chapterLimit: chapterLimit,
      pageConcurrency: pageConcurrency,
      cancelToken: cancelToken,
      requireComplete: requireComplete,
    );

_Work<String> _contentTask(
  BookSource source,
  Book book,
  BookChapter chapter, {
  required String? nextChapterUrl,
  required int? pageConcurrency,
}) =>
    (cancelToken) => CompleteContentFetcher.fetch(
      source,
      book,
      chapter,
      nextChapterUrl: nextChapterUrl,
      pageConcurrency: pageConcurrency,
      cancelToken: cancelToken,
    );

_Work<List<SearchBook>> _searchTask(
  BookSource source,
  String key, {
  required int page,
  required bool Function(String name, String author)? filter,
  required bool Function(int size)? shouldBreak,
}) =>
    (cancelToken) => WebBook.searchBookAwait(
      source,
      key,
      page: page,
      filter: filter,
      shouldBreak: shouldBreak,
      cancelToken: cancelToken,
    );

_Work<List<SearchBook>> _exploreTask(
  BookSource source,
  String url, {
  required int? page,
}) =>
    (cancelToken) => WebBook.exploreBookAwait(
      source,
      url,
      page: page,
      cancelToken: cancelToken,
    );

_Work<List<ExploreKind>> _exploreKindsTask(
  String? exploreUrl,
  BookSource? source,
) =>
    (cancelToken) => ExploreUrlParser.parseAsync(exploreUrl, source: source);

// ── 規則改過的欄位抄回呼叫端 ───────────────────────────────────────

/// 一個欄位在工作開始與結束時的值。
typedef _Change = (Object? before, Object? after);

final class _Ran<R> {
  const _Ran(
    this.result,
    this.bookChanges,
    this.chapterChanges,
    this.requestUrls,
  );

  final R result;
  final Map<String, _Change> bookChanges;
  final Map<String, _Change> chapterChanges;

  /// 工作實際送出的請求網址；只有 [withSourceRequestLog] 裡才記。
  final List<String> requestUrls;
}

/// 書源除錯用：[body] 裡經由 [BookSourceService] 跑的書源工作，跑完後把
/// 實際送出的請求網址依序交給 [onRequest]。工作失敗時不交，出錯的那個網址
/// 在錯誤（[DioException.requestOptions]）裡。
Future<T> withSourceRequestLog<T>(
  void Function(String url) onRequest,
  Future<T> Function() body,
) => runZoned(body, zoneValues: {_requestLogZoneKey: onRequest});

final Object _requestLogZoneKey = Object();

/// 在書源 isolate 執行 [work]，把規則在 [book]、[chapter] 上改的欄位
/// （[bookRuleFields]、[chapterRuleFields]）抄回傳入的物件。
///
/// 改了什麼由工作本身在開始與結束時比對（[_tracked]），所以送出前排隊的
/// 這段時間、以及執行期間畫面執行緒改了這本書（例如閱讀進度），都不會被當
/// 成規則的改動、被複本的舊值蓋掉。同一個 [source] 的工作送到同一條書源
/// isolate（[SourceIsolate.run] 的 `affinity`）。
Future<R> _runOnSource<R>(
  _Work<R> work, {
  BookSource? source,
  Book? book,
  BookChapter? chapter,
  CancelToken? cancelToken,
}) async {
  // 原地執行時，書源工作裡又叫回來的工作（規則 JS 這類）的請求記進外層
  // 工作的清單，照送出的順序列。
  final onRequest = isRecordingRequestUrls
      ? null
      : Zone.current[_requestLogZoneKey] as void Function(String url)?;
  final _Ran<R> ran;
  try {
    ran = await SourceIsolate.run(
      _tracked(work, book, chapter, recordRequests: onRequest != null),
      affinity: source?.bookSourceUrl,
      cancelToken: cancelToken,
    );
  } on SourceVerificationException catch (error) {
    // 取消後才交回的：書源 isolate 停在等網路時還沒收到取消，認不出來。
    if (cancelToken?.cancelError case final cancelled?) throw cancelled;
    // 記下要開的網頁，閱讀器的失敗提示旁給「前往驗證」。
    final request = error.request;
    if (source != null && request != null) {
      SourceInteraction.rememberVerification(source.bookSourceUrl, request);
    }
    rethrow;
  }
  if (book != null) _apply(bookRuleFields, ran.bookChanges, book);
  if (chapter != null) _apply(chapterRuleFields, ran.chapterChanges, chapter);
  if (onRequest != null) ran.requestUrls.forEach(onRequest);
  return ran.result;
}

/// 包住 [work]：在執行它的 isolate 裡，開始前與結束後各讀一次 [book]、
/// [chapter] 的規則欄位，只傳回有變的。[book]、[chapter] 和 [work] 捕捉的是
/// 同一份（同一則訊息複製過去的物件仍是同一個）。[recordRequests] 時一併
/// 傳回實際送出的請求網址。
_Work<_Ran<R>> _tracked<R>(
  _Work<R> work,
  Book? book,
  BookChapter? chapter, {
  required bool recordRequests,
}) => (cancelToken) async {
  final bookBefore = book == null ? null : _readFields(bookRuleFields, book);
  final chapterBefore = chapter == null
      ? null
      : _readFields(chapterRuleFields, chapter);
  final requestUrls = <String>[];
  // 書源要使用者驗證而失敗時，失敗照實說是要驗證（ADR 0038）。
  Future<R> run() => SourceInteraction.watchVerification(
    () => work(cancelToken),
    cancelToken: cancelToken,
  );
  final result = recordRequests
      ? await recordRequestUrls(requestUrls, run)
      : await run();
  return _Ran(
    result,
    book == null ? const {} : _changes(bookRuleFields, bookBefore!, book),
    chapter == null
        ? const {}
        : _changes(chapterRuleFields, chapterBefore!, chapter),
    requestUrls,
  );
};

Map<String, Object?> _readFields<T>(
  Map<String, RuleDataField<T>> fields,
  T target,
) => {
  for (final MapEntry(:key, :value) in fields.entries) key: value.read(target),
};

Map<String, _Change> _changes<T>(
  Map<String, RuleDataField<T>> fields,
  Map<String, Object?> before,
  T target,
) => {
  for (final MapEntry(:key, :value) in fields.entries)
    if (value.read(target) case final now when now != before[key])
      key: (before[key], now),
};

/// 原地執行時規則已經改在 [target] 上，再寫一次值相同，不影響結果。
void _apply<T>(
  Map<String, RuleDataField<T>> fields,
  Map<String, _Change> changes,
  T target,
) {
  for (final MapEntry(key: name, value: (before, after)) in changes.entries) {
    final field = fields[name]!;
    final merge = field.merge;
    field.write(
      target,
      merge == null ? after : merge(field.read(target), before, after),
    );
  }
}
