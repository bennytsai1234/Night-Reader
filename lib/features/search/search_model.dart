import 'dart:async';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/source_switch/same_book.dart';
import 'package:pool/pool.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/search_scope.dart';

import 'package:night_reader/core/constant/source_wait.dart';

/// 一張搜尋合併卡的身分，與 [SearchModel] 分組用的鍵相同（類別前綴＋正規化
/// 書名＋作者）。代表書會隨書源陸續回傳而更換，bookUrl 跟著變，這個值不變。
///
/// 搜尋頁每次重建都會對每張卡問一次；合併卡建立時已把分組鍵記在
/// [SearchBook.groupIdentity]，直接取用。
String searchResultIdentity(SearchBook book) =>
    book.groupIdentity ??
    '${_nameKeyOf(book)}\u0000${normalizeSearchText(book.author)}';

/// 合卡用的書名鍵：同名的小說、漫畫、有聲是不同的書，分成不同的卡
/// （ADR 0053）。
String _nameKeyOf(SearchBook book) =>
    '${book.bookKind.keyPrefix}${normalizeSearchText(book.name)}';

/// 精準搜尋留哪些書：書名或作者含關鍵字（同 Legado `SearchModel`），比之前
/// 先拿掉繁簡與空白的差別。
bool matchesPrecisionSearch(SearchBook book, String key) {
  final keyword = normalizeSearchText(key);
  if (keyword.isEmpty) return false;
  return normalizeSearchText(book.name).contains(keyword) ||
      normalizeSearchText(book.author).contains(keyword);
}

int searchRelevanceRank(SearchBook book, String key) {
  final keyword = normalizeSearchText(key);
  if (keyword.isEmpty) return 2;
  final name = normalizeSearchText(book.name);
  final author = normalizeSearchText(book.author);
  if (name == keyword || author == keyword) return 0;
  if (name.contains(keyword) || author.contains(keyword)) return 1;
  return 2;
}

/// 同一本書的網址：協定與主機不分大小寫，路徑與參數照原樣（`/book/A`、
/// `/book/a` 是兩本不同的書）。
String _normalizeBookUrl(String value) {
  final url = value.trim();
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return url;
  return uri
      .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
      .toString();
}

/// 同源去重的索引：同一書源裡網址相同（兩邊都有網址時），或任一邊沒有網址
/// 而書名與作者相同，就算同一本。每個書源回來都要比對，用雜湊查找，不逐本
/// 掃過所有已收到的結果（上千筆時一次合併要幾十毫秒）。
class _SameSourceIndex {
  final Set<String> _urls = {};
  final Set<String> _names = {};
  final Set<String> _namesWithoutUrl = {};

  void clear() {
    _urls.clear();
    _names.clear();
    _namesWithoutUrl.clear();
  }

  /// 不是重複時記下並回傳 true。
  bool add(SearchBook book) {
    final url = _normalizeBookUrl(book.bookUrl);
    final name =
        '${book.origin}\u0000${normalizeSearchText(book.name)}'
        '\u0000${normalizeSearchText(book.author)}';
    if (url.isEmpty) {
      if (_names.contains(name)) return false;
      _namesWithoutUrl.add(name);
    } else {
      final urlKey = '${book.origin}\u0000$url';
      if (_urls.contains(urlKey) || _namesWithoutUrl.contains(name)) {
        return false;
      }
      _urls.add(urlKey);
    }
    _names.add(name);
    return true;
  }
}

/// 搜尋結果依類別與正規化書名分組，產生呈現用的合併卡。
///
/// 每個書名：有作者的書按正規化作者分組；缺作者的書依同名的相異作者數
/// 安置——只有 1 個作者時併入那一組，沒有作者時自成一張「作者不詳」卡，
/// 2 個以上時也自成一張，不硬塞任一作者。每組選代表（[SearchBook.aggregate]）。
///
/// 新結果只重算它所屬的書名：搜尋常見字時結果上千筆，每回來一個書源就從頭
/// 分組會在畫面執行緒上卡住。卡片順序與從頭分組相同——先是有作者的書名
/// （依第一本有作者的書到達的順序），再是只有缺作者書的書名。
class _ResultGroups {
  final Map<String, _NameGroup> _byName = {};
  final Set<String> _namesWithAuthors = {};
  final Set<String> _namesWithoutAuthors = {};
  final Set<String> _dirty = {};

  void clear() {
    _byName.clear();
    _namesWithAuthors.clear();
    _namesWithoutAuthors.clear();
    _dirty.clear();
  }

  void add(SearchBook book) {
    final nameKey = _nameKeyOf(book);
    final authorKey = normalizeSearchText(book.author);
    final group = _byName.putIfAbsent(nameKey, _NameGroup.new);
    if (authorKey.isEmpty) {
      group.authorless.add(book);
      _namesWithoutAuthors.add(nameKey);
    } else {
      group.authored.putIfAbsent(authorKey, () => []).add(book);
      _namesWithAuthors.add(nameKey);
    }
    _dirty.add(nameKey);
  }

  List<SearchBook> cards() {
    for (final nameKey in _dirty) {
      _byName[nameKey]!.rebuildCards(nameKey);
    }
    _dirty.clear();
    return [
      for (final nameKey in _namesWithAuthors) ..._byName[nameKey]!.cards,
      for (final nameKey in _namesWithoutAuthors)
        if (!_namesWithAuthors.contains(nameKey)) ..._byName[nameKey]!.cards,
    ];
  }
}

class _NameGroup {
  final Map<String, List<SearchBook>> authored = {};
  final List<SearchBook> authorless = [];
  List<SearchBook> cards = const [];

  void rebuildCards(String nameKey) {
    final result = <SearchBook>[];
    void addCard(String authorKey, List<SearchBook> books) {
      final card = SearchBook.aggregate(books);
      // 身分就是分組鍵，直接記上，搜尋頁不必再對每張卡重算一次（見
      // [searchResultIdentity]）。
      card.groupIdentity = '$nameKey\u0000$authorKey';
      result.add(card);
    }

    if (authored.length == 1) {
      final only = authored.entries.first;
      addCard(only.key, [...only.value, ...authorless]);
    } else {
      for (final entry in authored.entries) {
        addCard(entry.key, entry.value);
      }
      if (authorless.isNotEmpty) addCard('', authorless);
    }
    cards = result;
  }
}

class SearchFailure {
  final BookSource source;
  final String message;

  const SearchFailure({required this.source, required this.message});
}

/// 向一個書源搜尋一個關鍵字；預設是 [BookSourceService.searchBooks]（在書源
/// isolate 執行），測試換成直接從記憶體回傳。
typedef SearchBookLoader = Future<List<SearchBook>> Function(
  BookSource source,
  String key, {
  CancelToken? cancelToken,
  int page,
});

/// SearchModel - 多書源並行搜尋引擎
/// (對標 Legado model/webBook/SearchModel.kt)
///
/// 純邏輯層，不依賴 Flutter UI。
/// 透過 [SearchModelCallback] 回報搜尋進度與結果。
class SearchModel {
  /// 一次搜尋同時送幾個書源，換封面也用同一個數字。App 沒有地方改它，
  /// 偏好鍵 [PreferKey.threadCount] 只給實跑測試換數字量。照 Legado 的
  /// `AppConfig.threadCount` 預設 16：兩個搜尋一起送時，50 秒內沒回來的書源
  /// 從 8 個時的約 170 個降到約 50 個（2026-11-15 實跑，396 個書源）。
  static Future<int> threadCount() async =>
      (await SharedPreferences.getInstance()).getInt(PreferKey.threadCount) ??
      16;

  final SearchModelCallback callback;

  /// 每源、同源內已去重的原始搜尋結果，依書名分組。合併僅在呈現層；
  /// 分組裡保留逐源回傳的原始書本，合併卡另外複製。
  final _ResultGroups _groups = _ResultGroups();
  final _SameSourceIndex _rawIndex = _SameSourceIndex();
  final SearchBookLoader _searchSource;
  List<SearchBook> _searchBooks = [];
  CancelToken? _cancelToken;

  /// 每次搜尋或取消都遞增；工作完成時代號已過期，就丟掉結果、不更新進度、
  /// 不回呼，舊搜尋晚到的結果不會混進新搜尋。
  int _generation = 0;
  int _failedCount = 0;
  int _completedCount = 0;
  int _totalCount = 0;

  /// 已經送出、還沒回來的書源名稱，照送出順序。
  final List<String> _waitingSources = [];

  /// 暫停中時不為 null，[resume] 時完成。
  Completer<void>? _resumed;

  /// [persist] 是 false 時搜到的書不存進搜尋快取：快取給從搜尋頁進詳情後換源、
  /// 換封面先列剛搜到的來源；AI 找書一次搜好幾十次全部書源，存了用不到、
  /// 還在主執行緒寫幾萬列。
  SearchModel({
    required this.callback,
    SearchBookLoader? loader,
    this.persist = true,
  }) : _searchSource = loader ?? BookSourceService().searchBooks;

  final bool persist;

  /// 這次要搜的書源排好順序、開始送之前呼叫（放到背景的搜尋記下要搜哪些）。
  void Function(List<BookSource> sources)? onSourcesChosen;

  /// [search] 實際搜的範圍和給的不同時呼叫：範圍裡的分組沒有可搜尋的書源，
  /// 清掉那些分組、一個都不剩就搜全部（[SearchScope.getBookSources]）。
  void Function(String scope)? onScopeNarrowed;

  /// 一個書源搜完時呼叫，零本也算；[books] 是精準搜尋篩過、要併進結果的那些。
  /// 和併進結果在同一處，記下的與畫面上的不會對不上。
  void Function(BookSource source, List<SearchBook> books)? onSourceSearched;

  /// 一個書源搜完、結果併好時呼叫：[foundNew] 是這次有沒有搜到結果裡還沒
  /// 有的書（同源去重後），決定它還要不要往下一頁搜。
  void Function(BookSource source, bool foundNew)? onSourceMerged;

  /// 每個書源送出前等它：放到背景的搜尋先等閱讀時的抓章（ADR 0070）。
  Future<void> Function()? beforeSource;

  /// 執行搜尋。給了 [kind] 就只送給那一類的書源；聚合源每一類都送
  /// （ADR 0056），它搜到的書由搜尋頁照類別篩。
  Future<void> search({
    required String key,
    required SearchScope scope,
    required bool precisionSearch,
    BookSourceKind? kind,
  }) async {
    cancelSearch();
    final generation = _generation;
    final asked = scope.toString();
    final scoped = await scope.getBookSources();
    if (generation == _generation && scope.toString() != asked) {
      onScopeNarrowed?.call(scope.toString());
    }
    final sources = kind == null
        ? scoped
        : [
            for (final source in scoped)
              if (source.isSearchableFor(kind, includeAggregates: true)) source,
          ];
    // 等書源清單時又送出了新的搜尋或被取消，這次就不開始。
    if (generation != _generation) return;
    await _searchSources(
      key: key,
      sources: sources,
      precisionSearch: precisionSearch,
    );
  }

  /// 搜 [sources]；[initialResults] 是先放進結果的書：合併卡（重試失敗書源）
  /// 或逐源原始結果（接著搜暫停的搜尋）都可以。
  ///
  /// [pages] 是各書源（網址）這次搜第幾頁，沒列的搜第 1 頁（接著搜下一頁，
  /// 同 Legado `SearchModel.searchPage`）。
  Future<void> searchSources({
    required String key,
    required List<BookSource> sources,
    required bool precisionSearch,
    List<SearchBook> initialResults = const [],
    Map<String, int> pages = const {},
  }) async {
    await _searchSources(
      key: key,
      sources: sources,
      precisionSearch: precisionSearch,
      initialResults: initialResults,
      pages: pages,
    );
  }

  Future<void> _searchSources({
    required String key,
    required List<BookSource> sources,
    required bool precisionSearch,
    List<SearchBook> initialResults = const [],
    Map<String, int> pages = const {},
  }) async {
    cancelSearch();

    final generation = _generation;
    // 繁簡兩種寫法都要搜、比對時也要轉換；字典還在背景載入時先等它。載入
    // 失敗就照原文搜（轉換會原樣返回），不擋住搜尋。
    if (!ChineseUtils.isInitialized) {
      try {
        await ChineseUtils.initialize();
      } catch (error) {
        AppLog.w('繁簡字典載入失敗，這次搜尋只用原文: $error');
      }
      if (generation != _generation) return;
    }
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    clearNormalizedSearchText();
    _groups.clear();
    _rawIndex.clear();
    for (final book in _expandInitialResults(initialResults)) {
      _rawIndex.add(book);
      _groups.add(book);
    }
    _searchBooks = _rebuild(key, precisionSearch);
    _failedCount = 0;
    _completedCount = 0;
    _waitingSources.clear();

    callback.onSearchStart();
    // 先放進去的結果（重試、接著搜暫停的）先給頁面：剩下的書源都沒回書時
    // 也看得到。
    if (initialResults.isNotEmpty) {
      callback.onSearchSuccess(List.from(_searchBooks));
    }

    _totalCount = sources.length;

    if (sources.isEmpty) {
      callback.onSearchFinish(isEmpty: true);
      return;
    }

    final threadCount = await SearchModel.threadCount();
    if (generation != _generation) return;
    final searchPool = Pool(threadCount);
    final respondTimes = <String, int>{};
    final ordered = _fastestFirst(sources);
    onSourcesChosen?.call(ordered);

    final tasks = <Future<void>>[
      for (final source in ordered)
        searchPool.withResource(() async {
          while (_resumed != null) {
            await _resumed!.future;
          }
          if (generation != _generation) return;
          if (beforeSource case final wait?) {
            // 按了暫停或結束就不再等。
            await Future.any<Object?>([wait(), cancelToken.whenCancel]);
            if (generation != _generation) return;
          }
          await _searchSingleSource(
            source,
            key,
            pages[source.bookSourceUrl] ?? 1,
            precisionSearch,
            generation,
            cancelToken,
            respondTimes,
          );
        }),
    ];

    await Future.wait(tasks);

    if (generation == _generation) {
      _flushPublish();
      callback.onSearchFinish(isEmpty: _searchBooks.isEmpty);
    }
    unawaited(getIt<BookSourceDao>().updateRespondTimes(respondTimes));
  }

  /// 上次搜尋回得快的書源先送，結果早點出現；還沒量過的照使用者排的
  /// 書源順序排在後面。
  static List<BookSource> _fastestFirst(List<BookSource> sources) {
    // 0 是舊版書源校驗留下的值，180000 是預設值，兩者都代表沒量過。
    int speed(BookSource source) =>
        source.respondTime <= 0 ? _unmeasuredRespondTime : source.respondTime;
    return [...sources]..sort((a, b) {
      final bySpeed = speed(a).compareTo(speed(b));
      return bySpeed != 0 ? bySpeed : a.customOrder.compareTo(b.customOrder);
    });
  }

  static const _unmeasuredRespondTime = 180000;

  /// 這次量到的時間與上次的平均，偶爾一次慢回應不會讓平常快的書源掉到
  /// 最後；沒量過的直接取這次。
  static int _smoothedRespondTime(int previous, int measured) =>
      previous <= 0 || previous >= _unmeasuredRespondTime
      ? measured
      : (previous + measured) ~/ 2;

  Future<void> _searchSingleSource(
    BookSource source,
    String key,
    int page,
    bool precisionSearch,
    int generation,
    CancelToken cancelToken,
    Map<String, int> respondTimes,
  ) async {
    bool stale() => generation != _generation;
    if (stale()) return;

    _waitingSources.add(source.bookSourceName);
    _reportProgress();

    try {
      final stopwatch = Stopwatch()..start();
      final books = await _searchKeyVariants(source, key, page, cancelToken);
      final elapsed = stopwatch.elapsedMilliseconds;
      respondTimes[source.bookSourceUrl] = _smoothedRespondTime(
        source.respondTime,
        elapsed,
      );
      // 合併卡挑預設來源時，同樣新的來源取這次回得快的。
      for (final book in books) {
        book.respondTime = elapsed;
      }

      if (stale()) return;

      // 精準搜尋過濾
      final filteredBooks = precisionSearch
          ? books.where((b) => matchesPrecisionSearch(b, key)).toList()
          : books;

      if (filteredBooks.isNotEmpty && persist) {
        // 持久化到搜尋快取
        await getIt<SearchBookDao>().insertList(filteredBooks);
        if (stale()) return;
      }
      onSourceSearched?.call(source, filteredBooks);
      var foundNew = false;
      if (filteredBooks.isNotEmpty) {
        // 合併結果：書源常常幾個一起回來，合併與通知頁面集中在一段時間內
        // 做一次（見 [_publishDelay]）。
        foundNew = _appendRawBooks(filteredBooks);
        _schedulePublish(key, precisionSearch);
      }
      onSourceMerged?.call(source, foundNew);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || stale()) return;
      _failedCount++;
      callback.onSearchFailure(
        SearchFailure(source: source, message: userErrorReason(e)),
      );
      AppLog.e('搜尋失敗 [${source.bookSourceName}]: $e', error: e);
    } catch (e) {
      if (stale()) return;
      _failedCount++;
      callback.onSearchFailure(
        SearchFailure(source: source, message: userErrorReason(e)),
      );
      AppLog.e('搜尋失敗 [${source.bookSourceName}]: $e', error: e);
    } finally {
      if (!stale()) {
        _completedCount++;
        _waitingSources.remove(source.bookSourceName);
        _reportProgress();
      }
    }
  }

  /// 在同一個書源同時搜關鍵字的每種寫法。有一種成功就算這個書源成功；
  /// 全部失敗才拋出第一個錯誤，照原本的失敗流程處理。
  Future<List<SearchBook>> _searchKeyVariants(
    BookSource source,
    String key,
    int page,
    CancelToken cancelToken,
  ) async {
    (Object, StackTrace)? firstError;
    final found = await Future.wait([
      for (final variant in searchKeyVariants(key))
        _searchSource(source, variant, cancelToken: cancelToken, page: page)
            .timeout(const Duration(seconds: sourceWaitSeconds))
            .then<List<SearchBook>?>(
              (books) => books,
              onError: (Object error, StackTrace stackTrace) {
                firstError ??= (error, stackTrace);
                return null;
              },
            ),
    ]);
    final succeeded = found.nonNulls;
    if (succeeded.isEmpty) {
      final (error, stackTrace) = firstError!;
      Error.throwWithStackTrace(error, stackTrace);
    }
    return [for (final books in succeeded) ...books];
  }

  /// 合併單一書源剛回傳的結果：新結果放進 [_groups]（同源去重），再重建
  /// [_searchBooks]。「作者缺失唯一性」反映當下整個結果集（唯一作者時缺
  /// 作者書併入；出現第二作者時缺作者書退出）。
  void _mergeItems(
    List<SearchBook> newBooks,
    String searchKey,
    bool precision,
  ) {
    _appendRawBooks(newBooks);
    _searchBooks = _rebuild(searchKey, precision);
  }

  /// 傳回有沒有加進新的書。
  bool _appendRawBooks(List<SearchBook> newBooks) {
    var added = false;
    for (final book in newBooks) {
      // 同源去重：沿用既有 bookUrl / 同名同作者判定，群組內同源只算一個 origin。
      if (_rawIndex.add(book)) {
        _groups.add(book);
        added = true;
      }
    }
    return added;
  }

  /// 每次重建要把所有結果重新排序，頁面也跟著整份重排；上百個書源陸續
  /// 回來時逐一重建會讓畫面一直掉幀。100ms 內回來的書源合成一次，結果晚
  /// 出現的時間短到看不出來。
  static const Duration _publishDelay = Duration(milliseconds: 100);
  Timer? _publishTimer;
  void Function()? _pendingPublish;

  void _schedulePublish(String searchKey, bool precision) {
    _pendingPublish = () {
      _searchBooks = _rebuild(searchKey, precision);
      callback.onSearchSuccess(List.from(_searchBooks));
    };
    _publishTimer ??= Timer(_publishDelay, _flushPublish);
  }

  void _flushPublish() {
    _publishTimer?.cancel();
    _publishTimer = null;
    final publish = _pendingPublish;
    _pendingPublish = null;
    publish?.call();
  }

  void _dropPendingPublish() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _pendingPublish = null;
  }

  void _reportProgress() => callback.onSearchProgress(
    waitingSources: List.unmodifiable(_waitingSources),
    completed: _completedCount,
    total: _totalCount,
    failed: _failedCount,
  );

  /// 依 [_groups] 列出呈現用的合併卡並排序。
  ///
  /// 分組與合併卡見 [_ResultGroups]；這裡做三級相關度排序（完全 > 包含 >
  /// 其他）+ 組內 origins.length 降序，精準搜尋丟棄「其他」級。
  List<SearchBook> _rebuild(String searchKey, bool precision) {
    final cards = _groups.cards();

    // 三級相關度排序 + 組內 origins.length 降序。
    final equalData = <SearchBook>[];
    final containsData = <SearchBook>[];
    final otherData = <SearchBook>[];
    for (final card in cards) {
      final rank = searchRelevanceRank(card, searchKey);
      if (rank == 0) {
        equalData.add(card);
      } else if (rank == 1) {
        containsData.add(card);
      } else if (!precision) {
        otherData.add(card);
      }
    }

    int byOrigins(SearchBook a, SearchBook b) =>
        b.origins.length.compareTo(a.origins.length);
    equalData.sort(byOrigins);
    containsData.sort(byOrigins);
    otherData.sort(byOrigins);

    final result = <SearchBook>[];
    result.addAll(equalData);
    result.addAll(containsData);
    if (!precision) {
      result.addAll(otherData);
    }
    return result;
  }

  /// 把（retry 用的）既有合併卡展開回「每源一本」的原始書，
  /// 以便重算式重建時 origins 數正確。代表卡只保有 representative 的中繼資料，
  /// 重試成功的源稍後會以新鮮原始書覆寫，屬可接受的降級路徑。
  List<SearchBook> _expandInitialResults(List<SearchBook> initialResults) {
    final expanded = <SearchBook>[];
    for (final card in initialResults) {
      final labels = card.sourceLabels;
      final origins = card.origins.toList();
      for (var i = 0; i < origins.length; i++) {
        final originUrl = origins[i];
        final label = i < labels.length ? labels[i] : null;
        if (originUrl == card.origin) {
          expanded.add(card);
        } else {
          expanded.add(
            SearchBook(
              bookUrl: card.bookUrl,
              name: card.name,
              author: card.author,
              kind: card.kind,
              coverUrl: card.coverUrl,
              intro: card.intro,
              wordCount: card.wordCount,
              latestChapterTitle: card.latestChapterTitle,
              origin: originUrl,
              originName: label,
              originOrder: card.originOrder,
              type: card.type,
              addTime: card.addTime,
              variable: card.variable,
              tocUrl: card.tocUrl,
              respondTime: card.respondTime,
            ),
          );
        }
      }
    }
    return expanded;
  }

  /// 使用者停止搜尋：已經收到、還在等下一次送出的結果照常送出，再取消。
  void stopSearch() {
    _flushPublish();
    cancelSearch();
  }

  /// 取消搜尋，還沒送出的結果丟掉（開始新搜尋或離開頁面時用）。
  void cancelSearch() {
    _generation++;
    _dropPendingPublish();
    _cancelToken?.cancel('搜尋取消');
    _cancelToken = null;
  }

  /// 暫停送出還沒開始的書源；已經送出的照常跑完，結果照常併入。搜尋頁被
  /// 書籍詳情、閱讀器這類整頁蓋住時用：搜尋的請求會跟上面那一頁搶網路，
  /// 合併結果也要用畫面執行緒。
  void pause() => _resumed ??= Completer<void>();

  bool get isPaused => _resumed != null;

  /// 接著送出剩下的書源。
  void resume() {
    _resumed?.complete();
    _resumed = null;
  }

  void dispose() {
    cancelSearch();
    // 讓等著繼續的工作醒來，看到搜尋已取消就結束。
    resume();
  }

  // ── 測試接縫（純邏輯層，便於 TDD 直接驅動重算式合併）──

  /// 目前的呈現用合併卡清單（唯讀視圖，測試用）。
  List<SearchBook> get searchBooksForTest => List.unmodifiable(_searchBooks);

  /// 驅動一次「單源回傳 → append + 從頭重建」流程（測試用）。
  void mergeForTest(
    List<SearchBook> newBooks,
    String searchKey,
    bool precision,
  ) {
    _mergeItems(newBooks, searchKey, precision);
  }

  /// 對一組原始書直接執行重算式合併並回傳結果，
  /// 不經網路 / DB / callback（測試用純函式）。
  static List<SearchBook> aggregateForTest(
    List<SearchBook> rawBooks,
    String searchKey,
    bool precision,
  ) {
    final model = SearchModel(callback: const _SilentCallback());
    rawBooks.forEach(model._groups.add);
    return model._rebuild(searchKey, precision);
  }

  /// 逐源原始結果 [rawBooks] 合成搜尋頁的合併卡，和同一次搜尋邊收邊併的
  /// 結果一樣（同源去重、分組；讀回暫停的搜尋時用）。
  static List<SearchBook> cardsOf(
    List<SearchBook> rawBooks,
    String searchKey,
    bool precision,
  ) {
    final model = SearchModel(callback: const _SilentCallback())
      .._appendRawBooks(rawBooks);
    return model._rebuild(searchKey, precision);
  }
}

class _SilentCallback implements SearchModelCallback {
  const _SilentCallback();
  @override
  void onSearchStart() {}
  @override
  void onSearchSuccess(List<SearchBook> searchBooks) {}
  @override
  void onSearchFailure(SearchFailure failure) {}
  @override
  void onSearchFinish({required bool isEmpty}) {}
  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {}
}

/// 搜尋引擎回調介面
abstract class SearchModelCallback {
  void onSearchStart();
  void onSearchSuccess(List<SearchBook> searchBooks);
  void onSearchFailure(SearchFailure failure);
  void onSearchFinish({required bool isEmpty});
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  });
}
