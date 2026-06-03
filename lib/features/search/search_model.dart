import 'dart:async';
import 'package:dio/dio.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:pool/pool.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/search_scope.dart';

String normalizeSearchText(String? value) {
  if (value == null) return '';
  return StringUtils.fullToHalf(
    value,
  ).replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

bool matchesPrecisionSearch(SearchBook book, String key) {
  final keyword = normalizeSearchText(key);
  if (keyword.isEmpty) return false;
  return normalizeSearchText(book.name) == keyword ||
      normalizeSearchText(book.author) == keyword;
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

String _normalizeBookUrl(String value) => value.trim().toLowerCase();

bool _isSameSourceDuplicate(SearchBook a, SearchBook b) {
  if (a.origin != b.origin) return false;
  final leftUrl = _normalizeBookUrl(a.bookUrl);
  final rightUrl = _normalizeBookUrl(b.bookUrl);
  if (leftUrl.isNotEmpty && rightUrl.isNotEmpty) {
    return leftUrl == rightUrl;
  }
  return normalizeSearchText(a.name) == normalizeSearchText(b.name) &&
      normalizeSearchText(a.author) == normalizeSearchText(b.author);
}

class SearchFailure {
  final BookSource source;
  final String message;

  const SearchFailure({required this.source, required this.message});
}

/// SearchModel - 多書源並行搜尋引擎
/// (對標 Legado model/webBook/SearchModel.kt)
///
/// 純邏輯層，不依賴 Flutter UI。
/// 透過 [SearchModelCallback] 回報搜尋進度與結果。
class SearchModel {
  final SearchModelCallback callback;

  /// 每源、同源內已去重的原始搜尋結果（重算式合併的輸入）。
  /// 合併僅在呈現層；此清單保留逐源回傳的原始書本，從不被分組污染。
  final List<SearchBook> _rawBooks = [];
  List<SearchBook> _searchBooks = [];
  CancelToken? _cancelToken;
  bool _isCancelled = false;
  int _failedCount = 0;
  int _completedCount = 0;
  int _totalCount = 0;
  String _currentSourceName = '';

  SearchModel({required this.callback});

  /// 執行搜尋
  Future<void> search({
    required String key,
    required SearchScope scope,
    required bool precisionSearch,
  }) async {
    cancelSearch();
    final sources = await scope.getBookSources();
    await _searchSources(
      key: key,
      sources: sources,
      precisionSearch: precisionSearch,
    );
  }

  Future<void> searchSources({
    required String key,
    required List<BookSource> sources,
    required bool precisionSearch,
    List<SearchBook> initialResults = const [],
  }) async {
    await _searchSources(
      key: key,
      sources: sources,
      precisionSearch: precisionSearch,
      initialResults: initialResults,
    );
  }

  Future<void> _searchSources({
    required String key,
    required List<BookSource> sources,
    required bool precisionSearch,
    List<SearchBook> initialResults = const [],
  }) async {
    cancelSearch();

    _isCancelled = false;
    _rawBooks.clear();
    _rawBooks.addAll(_expandInitialResults(initialResults));
    _searchBooks = _rebuild(key, precisionSearch);
    _failedCount = 0;
    _completedCount = 0;
    _cancelToken = CancelToken();

    callback.onSearchStart();

    _totalCount = sources.length;

    if (sources.isEmpty) {
      callback.onSearchFinish(isEmpty: true);
      return;
    }

    // 取得並行數
    final threadCount = await SharedPreferences.getInstance().then(
      (p) => p.getInt('thread_count') ?? 8,
    );
    final searchPool = Pool(threadCount);

    final tasks = <Future<void>>[];
    for (final source in sources) {
      if (_isCancelled) break;
      tasks.add(
        searchPool.withResource(() async {
          if (_isCancelled) return;
          await _searchSingleSource(source, key, precisionSearch);
        }),
      );
    }

    await Future.wait(tasks);

    if (!_isCancelled) {
      callback.onSearchFinish(isEmpty: _searchBooks.isEmpty);
    }
  }

  Future<void> _searchSingleSource(
    BookSource source,
    String key,
    bool precisionSearch,
  ) async {
    if (_isCancelled) return;

    _currentSourceName = source.bookSourceName;
    callback.onSearchProgress(
      currentSource: _currentSourceName,
      completed: _completedCount,
      total: _totalCount,
      failed: _failedCount,
    );

    try {
      if (_isCancelled) return;

      final books = await WebBook.searchBookAwait(
        source,
        key,
        cancelToken: _cancelToken,
      ).timeout(const Duration(seconds: 30));

      if (_isCancelled) return;

      // 精準搜尋過濾
      final filteredBooks =
          precisionSearch
              ? books.where((b) => matchesPrecisionSearch(b, key)).toList()
              : books;

      if (filteredBooks.isNotEmpty) {
        // 持久化到搜尋快取
        await getIt<SearchBookDao>().insertList(filteredBooks);
        // 合併結果
        _mergeItems(filteredBooks, key, precisionSearch);
        callback.onSearchSuccess(List.from(_searchBooks));
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      _failedCount++;
      callback.onSearchFailure(
        SearchFailure(source: source, message: e.message ?? e.toString()),
      );
      AppLog.e('搜尋失敗 [${source.bookSourceName}]: $e', error: e);
    } catch (e) {
      _failedCount++;
      callback.onSearchFailure(
        SearchFailure(source: source, message: e.toString()),
      );
      AppLog.e('搜尋失敗 [${source.bookSourceName}]: $e', error: e);
    } finally {
      _completedCount++;
      callback.onSearchProgress(
        currentSource: _currentSourceName,
        completed: _completedCount,
        total: _totalCount,
        failed: _failedCount,
      );
    }
  }

  /// 合併單一書源剛回傳的結果。
  ///
  /// 重算式（取代舊的漸進併入）：先把新結果 append 進 [_rawBooks]（同源去重），
  /// 再從頭重建整個 [_searchBooks]。這讓「作者缺失唯一性」能反映當下整個結果集
  /// （唯一作者時缺作者書併入；出現第二作者時缺作者書退出）。
  void _mergeItems(
    List<SearchBook> newBooks,
    String searchKey,
    bool precision,
  ) {
    for (final book in newBooks) {
      // 同源去重：沿用既有 bookUrl / 同名同作者判定，群組內同源只算一個 origin。
      final isDuplicate = _rawBooks.any((b) => _isSameSourceDuplicate(b, book));
      if (!isDuplicate) {
        _rawBooks.add(book);
      }
    }
    _searchBooks = _rebuild(searchKey, precision);
  }

  /// 從 [_rawBooks] 從頭重建呈現用的合併卡清單。
  ///
  /// 步驟（對應計畫演算法）：
  /// 1. 有作者的書按「(正規化書名, 正規化作者)」分組。
  /// 2. 統計每個書名底下的相異作者數。
  /// 3. 依「作者缺失三分支」安置缺作者的書。
  /// 4. 每組選 representative（[SearchBook.aggregate]）。
  /// 5. 三級相關度排序（完全 > 包含 > 其他）+ 組內 origins.length 降序；
  ///    精準搜尋丟棄「其他」級。
  List<SearchBook> _rebuild(String searchKey, bool precision) {
    // 1 + 2：依正規化書名收集「群組」與「相異作者集合」。
    //   authorGroups[name][author] = 同名同作者的原始書清單
    //   authorlessByName[name]     = 同名但缺作者的原始書清單
    final authorGroups = <String, Map<String, List<SearchBook>>>{};
    final authorlessByName = <String, List<SearchBook>>{};

    for (final book in _rawBooks) {
      final nameKey = normalizeSearchText(book.name);
      final authorKey = normalizeSearchText(book.author);
      if (authorKey.isEmpty) {
        authorlessByName.putIfAbsent(nameKey, () => []).add(book);
      } else {
        authorGroups
            .putIfAbsent(nameKey, () => {})
            .putIfAbsent(authorKey, () => [])
            .add(book);
      }
    }

    // 3：安置缺作者的書（每次重算從頭判定唯一性）。
    authorlessByName.forEach((nameKey, authorlessBooks) {
      final distinctAuthors = authorGroups[nameKey];
      final authorCount = distinctAuthors?.length ?? 0;
      if (authorCount == 1) {
        // 書名只對應 1 個作者 → 缺作者同名書併入該作者群組。
        distinctAuthors!.values.first.addAll(authorlessBooks);
      } else if (authorCount == 0) {
        // 書名完全沒人有作者 → 同名缺作者書併成一張「作者不詳」卡。
        authorGroups
            .putIfAbsent(nameKey, () => {})
            .putIfAbsent('', () => [])
            .addAll(authorlessBooks);
      } else {
        // 書名有 ≥2 個不同作者 → 缺作者同名書退出、單獨成「作者不詳」卡，
        // 不硬塞任一作者。
        authorGroups[nameKey]!.putIfAbsent('', () => []).addAll(authorlessBooks);
      }
    });

    // 4：每組選 representative，建立呈現用合併卡。
    final cards = <SearchBook>[];
    for (final byAuthor in authorGroups.values) {
      for (final group in byAuthor.values) {
        if (group.isEmpty) continue;
        cards.add(SearchBook.aggregate(group));
      }
    }

    // 5：三級相關度排序 + 組內 origins.length 降序。
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

  /// 取消搜尋
  void cancelSearch() {
    _isCancelled = true;
    _cancelToken?.cancel('搜尋取消');
    _cancelToken = null;
  }

  void dispose() {
    cancelSearch();
  }

  // ── 測試接縫（純邏輯層，便於 TDD 直接驅動重算式合併）──

  /// 目前的呈現用合併卡清單（唯讀視圖，測試用）。
  List<SearchBook> get searchBooksForTest => List.unmodifiable(_searchBooks);

  /// 驅動一次「單源回傳 → append + 從頭重建」流程（測試用）。
  void mergeForTest(List<SearchBook> newBooks, String searchKey, bool precision) {
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
    model._rawBooks.addAll(rawBooks);
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
    required String currentSource,
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
    required String currentSource,
    required int completed,
    required int total,
    required int failed,
  });
}
