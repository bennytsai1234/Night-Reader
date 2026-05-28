import 'dart:async';
import 'package:dio/dio.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/engine/web_book/web_book_service.dart';
import 'package:reader/core/database/dao/search_book_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/utils/string_utils.dart';
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
    _searchBooks = List<SearchBook>.from(initialResults);
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

  /// 合併搜尋結果 — 三級排序 (對標 Legado SearchModel.mergeItems)
  ///
  /// 排序優先級：
  /// 1. 完全匹配（書名或作者 == 搜尋關鍵字）
  /// 2. 包含匹配（書名或作者包含搜尋關鍵字）
  /// 3. 其他結果（非精準搜尋時才保留）
  ///
  /// 每級內部按來源數量降序排列。
  void _mergeItems(
    List<SearchBook> newBooks,
    String searchKey,
    bool precision,
  ) {
    // 分類現有結果
    final equalData = <SearchBook>[];
    final containsData = <SearchBook>[];
    final otherData = <SearchBook>[];

    for (final book in _searchBooks) {
      final rank = searchRelevanceRank(book, searchKey);
      if (rank == 0) {
        equalData.add(book);
      } else if (rank == 1) {
        containsData.add(book);
      } else {
        otherData.add(book);
      }
    }

    // 合併新結果
    for (final newBook in newBooks) {
      final rank = searchRelevanceRank(newBook, searchKey);

      if (rank == 0) {
        _mergeIntoList(equalData, newBook);
      } else if (rank == 1) {
        _mergeIntoList(containsData, newBook);
      } else if (!precision) {
        _mergeIntoList(otherData, newBook);
      }
    }

    // 排序並合併
    equalData.sort((a, b) => b.origins.length.compareTo(a.origins.length));
    containsData.sort((a, b) => b.origins.length.compareTo(a.origins.length));

    final result = <SearchBook>[];
    result.addAll(equalData);
    result.addAll(containsData);
    if (!precision) {
      result.addAll(otherData);
    }

    _searchBooks = result;
  }

  /// 將新書合併到指定列表中。
  ///
  /// 書架模型把每個書源的書視為獨立書籍，因此只合併同一來源的重複
  /// 結果，不合併同名同作者的不同書源。
  void _mergeIntoList(List<SearchBook> list, SearchBook newBook) {
    final index = list.indexWhere((b) => _isSameSourceDuplicate(b, newBook));
    if (index != -1) {
      list[index].addOrigin(newBook.origin, name: newBook.originName);
    } else {
      list.add(newBook);
    }
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
