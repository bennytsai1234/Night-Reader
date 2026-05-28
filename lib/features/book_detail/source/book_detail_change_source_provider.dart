import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/search_book_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/services/book_source_service.dart';
import 'package:pool/pool.dart';

class BookDetailChangeSourceProvider extends ChangeNotifier {
  BookDetailChangeSourceProvider(
    this.book, {
    BookSourceService? service,
    BookSourceDao? sourceDao,
    SearchBookDao? searchBookDao,
    bool autoStart = true,
  }) : service = service ?? BookSourceService(),
       _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       searchBookDao = searchBookDao ?? getIt<SearchBookDao>() {
    if (autoStart) {
      unawaited(loadGroups());
      unawaited(startSearch());
    }
  }

  static const int _maxConcurrentSearches = 6;

  final Book book;
  final BookSourceService service;
  final BookSourceDao _sourceDao;
  final SearchBookDao searchBookDao;

  List<SearchBook> allResults = <SearchBook>[];
  List<SearchBook> filteredResults = <SearchBook>[];
  List<String> groups = <String>['全部'];
  String selectedGroup = '全部';
  bool isSearching = false;
  String status = '正在初始化...';
  bool checkAuthor = true;

  String _filterQuery = '';
  int _activeSearchId = 0;
  bool _disposed = false;

  Future<void> loadGroups() async {
    final sources = await _sourceDao.getEnabled();
    if (_disposed) return;

    final groupSet = <String>{};
    for (final source in sources) {
      groupSet.addAll(_splitGroups(source.bookSourceGroup ?? ''));
    }

    final sortedGroups = groupSet.toList()..sort();
    groups = <String>['全部', ...sortedGroups];
    if (!groups.contains(selectedGroup)) {
      selectedGroup = '全部';
    }
    _notifySafely();
  }

  void applyFilter(String key) {
    _filterQuery = key.trim().toLowerCase();
    _rebuildFilteredResults();
    _notifySafely();
  }

  Future<void> startSearch() async {
    final searchId = ++_activeSearchId;
    final enabledSources = await _loadEnabledSources();
    if (!_isSearchActive(searchId)) return;

    final cached = await searchBookDao.getSearchBooks(book.name, book.author);
    if (!_isSearchActive(searchId)) return;

    final allowedOrigins =
        enabledSources.map((source) => source.bookSourceUrl).toSet();
    final cachedResults = _sortResults(
      cached.where((result) => allowedOrigins.contains(result.origin)).toList(),
    );

    if (cachedResults.isNotEmpty) {
      allResults = cachedResults;
      _rebuildFilteredResults();
      status = '載入快取來源... 正在同步更新...';
      _notifySafely();
    }

    isSearching = true;
    if (enabledSources.isEmpty) {
      status = '目前範圍沒有可用書源';
    } else if (allResults.isEmpty) {
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
      final searchPool = Pool(_maxConcurrentSearches);
      try {
        final searchTasks =
            enabledSources.map((source) {
              return searchPool.withResource(() async {
                try {
                  return await service.preciseSearch(
                    source,
                    book.name,
                    checkAuthor ? book.author : '',
                  );
                } catch (_) {
                  failedSources++;
                  return const <SearchBook>[];
                }
              });
            }).toList();

        final resultsList = await Future.wait(searchTasks);
        if (!_isSearchActive(searchId)) return;

        final results = _sortResults(
          resultsList.expand((item) => item).toList(),
        );
        allResults = results;
        _rebuildFilteredResults();
        isSearching = false;

        if (results.isEmpty) {
          status =
              failedSources == enabledSources.length
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
    super.dispose();
  }

  bool _isSearchActive(int searchId) =>
      !_disposed && searchId == _activeSearchId;

  Future<List<BookSource>> _loadEnabledSources() async {
    var enabledSources =
        (await _sourceDao.getEnabled())
            .where((source) => source.isSearchEnabledByRuntime)
            .toList();
    if (selectedGroup == '全部') {
      return enabledSources;
    }
    enabledSources =
        enabledSources
            .where(
              (source) => _splitGroups(
                source.bookSourceGroup ?? '',
              ).contains(selectedGroup),
            )
            .toList();
    return enabledSources;
  }

  void _rebuildFilteredResults() {
    if (_filterQuery.isEmpty) {
      filteredResults = List<SearchBook>.from(allResults);
      return;
    }

    filteredResults =
        allResults.where((result) {
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

  Iterable<String> _splitGroups(String value) sync* {
    for (final group in value.split(RegExp(r'[,，]'))) {
      final trimmed = group.trim();
      if (trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
