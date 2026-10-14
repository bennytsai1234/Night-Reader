import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_model.dart';
import 'package:pool/pool.dart';

class BookDetailChangeSourceProvider extends ChangeNotifier {
  BookDetailChangeSourceProvider(
    this.book, {
    BookSourceService? service,
    BookSourceDao? sourceDao,
    SearchBookDao? searchBookDao,
    this._sourceSearchTimeout = const Duration(seconds: 15),
    bool autoStart = true,
  }) : service = service ?? BookSourceService(),
       _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       searchBookDao = searchBookDao ?? getIt<SearchBookDao>() {
    if (autoStart) {
      // 一建立就算搜尋中：startSearch 要先等資料庫查詢才會標記，這段空檔
      // 不能讓面板閃出「未找到其他來源」。
      isSearching = true;
      unawaited(loadGroups());
      unawaited(startSearch());
    }
  }

  static const int _maxConcurrentSearches = 6;

  final Book book;
  final BookSourceService service;
  final BookSourceDao _sourceDao;
  final SearchBookDao searchBookDao;
  final Duration _sourceSearchTimeout;

  List<SearchBook> allResults = <SearchBook>[];
  List<SearchBook> filteredResults = <SearchBook>[];
  static const String allGroups = '全部';

  /// 已啟用書源的分組（不含「全部」）與各分組的書源數。
  List<String> groups = <String>[];
  Map<String, int> groupCounts = <String, int>{};
  int enabledSourceCount = 0;
  String selectedGroup = allGroups;
  bool isSearching = false;
  String status = '正在初始化...';
  bool checkAuthor = true;

  String _filterQuery = '';
  int _activeSearchId = 0;
  bool _disposed = false;
  final Set<CancelToken> _activeSearchTokens = <CancelToken>{};

  Future<void> loadGroups() async {
    final sources = await _sourceDao.getEnabled();
    if (_disposed) return;

    final counts = <String, int>{};
    for (final source in sources) {
      for (final group in _splitGroups(source.bookSourceGroup ?? '').toSet()) {
        counts[group] = (counts[group] ?? 0) + 1;
      }
    }

    groupCounts = counts;
    enabledSourceCount = sources.length;
    groups = counts.keys.toList()..sort();
    if (!counts.containsKey(selectedGroup)) {
      selectedGroup = allGroups;
    }
    _notifySafely();
  }

  void applyFilter(String key) {
    _filterQuery = key.trim().toLowerCase();
    _rebuildFilteredResults();
    _notifySafely();
  }

  Future<void> startSearch() async {
    _cancelActiveSearch();
    final searchId = ++_activeSearchId;
    final enabledSources = await _loadEnabledSources();
    if (!_isSearchActive(searchId)) return;

    // 搜尋把繁簡兩種寫法的同一本書併成一張卡，這本書可能是任一種寫法：
    // 兩種書名都要搜，比對時繁簡視為相同。字典還在背景載入時先等它，載入
    // 失敗就只用原文。
    if (!ChineseUtils.isInitialized) {
      try {
        await ChineseUtils.initialize();
      } catch (error) {
        AppLog.w('繁簡字典載入失敗，這次換源只用原文書名: $error');
      }
      if (!_isSearchActive(searchId)) return;
    }
    final names = searchKeyVariants(book.name);

    final cached = await searchBookDao.getByNames(names);
    if (!_isSearchActive(searchId)) return;

    final allowedOrigins = enabledSources
        .map((source) => source.bookSourceUrl)
        .toSet();
    final cachedResults = _sortResults(
      cached
          .where(
            (result) =>
                allowedOrigins.contains(result.origin) &&
                _isSameBook(result.name, result.author, checkAuthor: true),
          )
          .toList(),
    );
    allResults = cachedResults;
    _rebuildFilteredResults();

    isSearching = true;
    if (enabledSources.isEmpty) {
      status = '目前範圍沒有可用書源';
    } else if (cachedResults.isNotEmpty) {
      status = '已載入 ${cachedResults.length} 個快取來源，正在同步更新...';
    } else {
      status = '正在搜尋可用書源...';
    }
    _notifySafely();

    if (enabledSources.isEmpty) {
      isSearching = false;
      _notifySafely();
      return;
    }

    try {
      var failedSources = 0;
      var completedSources = 0;
      final searchPool = Pool(_maxConcurrentSearches);
      try {
        final searchTasks = enabledSources.map((source) {
          return searchPool.withResource(() async {
            if (!_isSearchActive(searchId)) return;

            try {
              final shouldCheckAuthor =
                  checkAuthor && book.author.trim().isNotEmpty;
              final results = await _searchNames(
                source,
                names,
                (name, author) =>
                    _isSameBook(name, author, checkAuthor: shouldCheckAuthor),
              );
              if (!_isSearchActive(searchId)) return;
              _replaceSourceResults(source.bookSourceUrl, results);
            } catch (_) {
              if (_isSearchActive(searchId)) {
                failedSources++;
                _replaceSourceResults(
                  source.bookSourceUrl,
                  const <SearchBook>[],
                );
              }
            } finally {
              if (_isSearchActive(searchId)) {
                completedSources++;
                _updateSearchingStatus(completedSources, enabledSources.length);
              }
            }
          });
        }).toList();

        await Future.wait(searchTasks);
        if (!_isSearchActive(searchId)) return;

        isSearching = false;
        if (allResults.isEmpty) {
          status = failedSources == enabledSources.length
              ? '搜尋完成，但所有書源都失敗'
              : '未找到備用書源';
        } else if (failedSources > 0) {
          status = '搜尋完成 ($failedSources 個書源失敗)';
        } else {
          status = '搜尋完成 (已自動優選)';
        }
        _notifySafely();
      } finally {
        await searchPool.close();
      }
    } catch (e) {
      if (!_isSearchActive(searchId)) return;
      isSearching = false;
      status = '搜尋出錯: $e';
      _notifySafely();
    }
  }

  /// 每種書名各搜一次、各自計時，合起來；全部失敗或逾時才算這個書源失敗，
  /// 一種寫法卡住不會丟掉另一種已經找到的結果。
  Future<List<SearchBook>> _searchNames(
    BookSource source,
    List<String> names,
    bool Function(String name, String author) filter,
  ) async {
    (Object, StackTrace)? firstError;
    Future<List<SearchBook>?> searchName(String name) async {
      final cancelToken = CancelToken();
      _activeSearchTokens.add(cancelToken);
      try {
        return await service
            .searchBooks(
              source,
              name,
              filter: filter,
              shouldBreak: (size) => size >= 1,
              cancelToken: cancelToken,
            )
            .timeout(
              _sourceSearchTimeout,
              onTimeout: () {
                cancelToken.cancel('換源搜尋逾時');
                throw TimeoutException('換源搜尋逾時');
              },
            );
      } catch (error, stackTrace) {
        firstError ??= (error, stackTrace);
        return null;
      } finally {
        _activeSearchTokens.remove(cancelToken);
      }
    }

    final found = await Future.wait([
      for (final name in names) searchName(name),
    ]);
    final succeeded = found.nonNulls;
    if (succeeded.isEmpty) {
      final (error, stackTrace) = firstError!;
      Error.throwWithStackTrace(error, stackTrace);
    }
    return [for (final books in succeeded) ...books];
  }

  bool _isSameBook(String name, String? author, {required bool checkAuthor}) {
    if (normalizeSearchText(name) != normalizeSearchText(book.name)) {
      return false;
    }
    return !checkAuthor ||
        normalizeSearchText(author) == normalizeSearchText(book.author);
  }

  Future<BookSource?> findSourceByUrl(String url) => _sourceDao.getByUrl(url);

  void toggleCheckAuthor() {
    checkAuthor = !checkAuthor;
    unawaited(startSearch());
  }

  void updateSelectedGroup(String group) {
    if (selectedGroup == group) return;
    selectedGroup = group;
    unawaited(startSearch());
  }

  @override
  void dispose() {
    _disposed = true;
    _activeSearchId++;
    _cancelActiveSearch();
    super.dispose();
  }

  bool _isSearchActive(int searchId) =>
      !_disposed && searchId == _activeSearchId;

  Future<List<BookSource>> _loadEnabledSources() async {
    var enabledSources = (await _sourceDao.getEnabled())
        .where(
          (source) =>
              source.isSearchEnabledByRuntime &&
              source.bookSourceUrl != book.origin,
        )
        .toList();
    if (selectedGroup == allGroups) {
      return enabledSources;
    }
    enabledSources = enabledSources
        .where(
          (source) =>
              _splitGroups(source.bookSourceGroup ?? '')
                  .contains(selectedGroup),
        )
        .toList();
    return enabledSources;
  }

  void _replaceSourceResults(String sourceUrl, List<SearchBook> results) {
    final merged = <String, SearchBook>{
      for (final result in allResults)
        if (result.origin != sourceUrl) _resultKey(result): result,
    };
    for (final result in results) {
      if (result.origin == book.origin ||
          !_isSameBook(result.name, result.author, checkAuthor: false)) {
        continue;
      }
      merged[_resultKey(result)] = result;
    }
    allResults = _sortResults(merged.values.toList());
    _rebuildFilteredResults();
  }

  void _updateSearchingStatus(int completedSources, int totalSources) {
    if (allResults.isEmpty) {
      status = '正在搜尋可用書源... ($completedSources/$totalSources)';
    } else {
      status =
          '已找到 ${allResults.length} 個來源，仍在搜尋... ($completedSources/$totalSources)';
    }
    _notifySafely();
  }

  void _cancelActiveSearch() {
    for (final token in _activeSearchTokens.toList()) {
      if (!token.isCancelled) {
        token.cancel('換源搜尋已取消');
      }
    }
    _activeSearchTokens.clear();
  }

  String _resultKey(SearchBook result) => '${result.origin}\n${result.bookUrl}';

  void _rebuildFilteredResults() {
    if (_filterQuery.isEmpty) {
      filteredResults = List<SearchBook>.from(allResults);
      return;
    }

    filteredResults = allResults.where((result) {
      return <String>[
        result.originName ?? '',
        result.latestChapterTitle ?? '',
        result.author ?? '',
        result.wordCount ?? '',
        result.kind ?? '',
      ].any((field) => field.toLowerCase().contains(_filterQuery));
    }).toList();
  }

  List<SearchBook> _sortResults(List<SearchBook> results) {
    results.sort((a, b) {
      final orderCompare = a.originOrder.compareTo(b.originOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }

      final chapterCompare = (b.latestChapterTitle?.length ?? 0).compareTo(
        a.latestChapterTitle?.length ?? 0,
      );
      if (chapterCompare != 0) {
        return chapterCompare;
      }

      return a.name.compareTo(b.name);
    });
    return results;
  }

  Set<String> _splitGroups(String value) => splitSourceGroups(value);

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
