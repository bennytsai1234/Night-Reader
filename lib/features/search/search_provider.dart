import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/search_keyword_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/models/search_keyword.dart';
import 'package:reader/core/services/bookshelf_state_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/search_scope.dart';
import 'search_model.dart';

enum SearchResultSortMode {
  relevance,
  sourceCount,
  sourceOrder,
  name,
  author,
  latestChapter,
}

extension SearchResultSortModeDisplay on SearchResultSortMode {
  String get displayName {
    switch (this) {
      case SearchResultSortMode.relevance:
        return '相關度';
      case SearchResultSortMode.sourceCount:
        return '書源數';
      case SearchResultSortMode.sourceOrder:
        return '書源順序';
      case SearchResultSortMode.name:
        return '書名';
      case SearchResultSortMode.author:
        return '作者';
      case SearchResultSortMode.latestChapter:
        return '最新章節';
    }
  }
}

/// SearchProvider - 搜尋頁面狀態管理
/// (對標 Legado SearchViewModel.kt)
///
/// 職責：UI 狀態管理、搜尋歷史 CRUD、委派 [SearchModel] 執行搜尋。
/// 搜尋引擎邏輯已提取到 [SearchModel]。
class SearchProvider extends ChangeNotifier implements SearchModelCallback {
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final SearchKeywordDao _keywordDao = getIt<SearchKeywordDao>();
  final BookshelfStateTracker _bookshelfTracker;

  late final SearchModel _searchModel;
  late SearchScope _searchScope;
  final SearchScope? _initialScope;
  bool _scopeLoaded = false;

  // --- UI State ---
  List<SearchKeyword> _history = [];
  List<SearchBook> _results = [];
  bool _isSearching = false;
  String _currentSource = '';
  String _lastSearchKey = '';
  int _failedSources = 0;
  int _totalSources = 0;
  int _completedSources = 0;
  final List<SearchFailure> _sourceFailures = [];

  // --- 搜尋設定 ---
  bool _precisionSearch = false;
  List<String> _sourceGroups = [];
  SearchResultSortMode _sortMode = SearchResultSortMode.relevance;
  final Set<String> _sourceFilters = {};
  String _authorFilter = '';
  String _kindFilter = '';
  bool _onlyInBookshelf = false;
  bool _onlyWithCover = false;

  // --- Getters ---
  List<SearchKeyword> get historyKeywords => _history;
  List<String> get history => _history.map((e) => e.word).toList();
  List<SearchBook> get results => _sortedResults(_filteredResults());
  int get unfilteredResultCount => _results.length;
  int get resultCount => results.length;
  bool get hasUnfilteredResults => _results.isNotEmpty;
  bool get isSearching => _isSearching;
  String get currentSource => _currentSource;
  String get lastSearchKey => _lastSearchKey;
  double get progress =>
      _totalSources == 0
          ? 0
          : (_completedSources / _totalSources).clamp(0.0, 1.0);
  int get failedSources => _failedSources;
  int get totalSources => _totalSources;
  bool get precisionSearch => _precisionSearch;
  List<String> get sourceGroups => _sourceGroups;
  SearchScope get searchScope => _searchScope;
  bool get scopeLoaded => _scopeLoaded;
  SearchResultSortMode get sortMode => _sortMode;
  Set<String> get sourceFilters => Set.unmodifiable(_sourceFilters);
  String get authorFilter => _authorFilter;
  String get kindFilter => _kindFilter;
  bool get onlyInBookshelf => _onlyInBookshelf;
  bool get onlyWithCover => _onlyWithCover;
  List<SearchFailure> get sourceFailures => List.unmodifiable(_sourceFailures);
  bool get hasActiveResultFilters =>
      _sourceFilters.isNotEmpty ||
      _authorFilter.trim().isNotEmpty ||
      _kindFilter.trim().isNotEmpty ||
      _onlyInBookshelf ||
      _onlyWithCover;
  List<String> get availableSourceFilters {
    final labels = <String>{};
    for (final book in _results) {
      labels.addAll(_sourceLabelsFor(book));
    }
    return labels.toList()..sort();
  }

  SearchProvider({
    BookshelfStateTracker? bookshelfTracker,
    SearchScope? initialScope,
  }) : _bookshelfTracker = bookshelfTracker ?? BookshelfStateTracker(),
       _initialScope = initialScope {
    _searchModel = SearchModel(callback: this);
    _searchScope = initialScope ?? SearchScope();
    _init();
  }

  Future<void> _init() async {
    if (_initialScope == null) {
      _searchScope = await SearchScope.load();
    }
    _scopeLoaded = true;
    await _bookshelfTracker.initialize(onChanged: notifyListeners);
    await _loadGroups();
    await _loadPrecisionPreference();
    await loadHistory();
  }

  bool isInBookshelf(SearchBook book) =>
      _bookshelfTracker.containsSearchBook(book);

  List<String> _sourceLabelsFor(SearchBook book) =>
      book.sourceLabels.isNotEmpty
          ? book.sourceLabels
          : [book.originName ?? book.origin];

  List<SearchBook> _filteredResults() {
    final authorKey = normalizeSearchText(_authorFilter);
    final kindKey = normalizeSearchText(_kindFilter);
    return _results.where((book) {
      if (_sourceFilters.isNotEmpty) {
        final labels = _sourceLabelsFor(book).toSet();
        if (!_sourceFilters.any(labels.contains)) return false;
      }
      if (_onlyInBookshelf && !isInBookshelf(book)) return false;
      if (_onlyWithCover && (book.coverUrl ?? '').trim().isEmpty) return false;
      if (authorKey.isNotEmpty &&
          !normalizeSearchText(book.author).contains(authorKey)) {
        return false;
      }
      if (kindKey.isNotEmpty &&
          !normalizeSearchText(book.kind).contains(kindKey)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<SearchBook> _sortedResults(List<SearchBook> books) {
    if (_sortMode == SearchResultSortMode.relevance) return books;
    final sorted = List<SearchBook>.from(books);
    int compareText(String? left, String? right) =>
        normalizeSearchText(left).compareTo(normalizeSearchText(right));
    sorted.sort((a, b) {
      switch (_sortMode) {
        case SearchResultSortMode.relevance:
          return 0;
        case SearchResultSortMode.sourceCount:
          final byCount = b.origins.length.compareTo(a.origins.length);
          return byCount != 0
              ? byCount
              : a.originOrder.compareTo(b.originOrder);
        case SearchResultSortMode.sourceOrder:
          return a.originOrder.compareTo(b.originOrder);
        case SearchResultSortMode.name:
          return compareText(a.name, b.name);
        case SearchResultSortMode.author:
          return compareText(a.author, b.author);
        case SearchResultSortMode.latestChapter:
          return compareText(a.latestChapterTitle, b.latestChapterTitle);
      }
    });
    return sorted;
  }

  void updateSortMode(SearchResultSortMode mode) {
    if (_sortMode == mode) return;
    _sortMode = mode;
    notifyListeners();
  }

  void toggleSourceFilter(String sourceLabel) {
    if (_sourceFilters.contains(sourceLabel)) {
      _sourceFilters.remove(sourceLabel);
    } else {
      _sourceFilters.add(sourceLabel);
    }
    notifyListeners();
  }

  void setAuthorFilter(String value) {
    _authorFilter = value;
    notifyListeners();
  }

  void setKindFilter(String value) {
    _kindFilter = value;
    notifyListeners();
  }

  void setOnlyInBookshelf(bool value) {
    _onlyInBookshelf = value;
    notifyListeners();
  }

  void setOnlyWithCover(bool value) {
    _onlyWithCover = value;
    notifyListeners();
  }

  void clearResultFilters() {
    _sourceFilters.clear();
    _authorFilter = '';
    _kindFilter = '';
    _onlyInBookshelf = false;
    _onlyWithCover = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  // 搜尋範圍管理
  // ═══════════════════════════════════════════

  Future<void> _loadGroups() async {
    final sources = await _sourceDao.getAllPart();
    final groups = <String>{};
    for (var s in sources) {
      if (s.bookSourceGroup != null && s.bookSourceGroup!.isNotEmpty) {
        groups.addAll(s.bookSourceGroup!.split(',').map((e) => e.trim()));
      }
    }
    _sourceGroups = groups.toList()..sort();
    notifyListeners();
  }

  void updateSearchScope(SearchScope scope) {
    _searchScope = scope;
    notifyListeners();
    // 若正在顯示搜尋結果，自動以新範圍重新搜尋
    if (_lastSearchKey.isNotEmpty && !_isSearching) {
      search(_lastSearchKey);
    }
  }

  // ═══════════════════════════════════════════
  // 精準搜尋
  // ═══════════════════════════════════════════

  Future<void> _loadPrecisionPreference() async {
    final p = await SharedPreferences.getInstance();
    _precisionSearch = p.getBool('precision_search') ?? false;
    notifyListeners();
  }

  Future<void> togglePrecisionSearch() async {
    _precisionSearch = !_precisionSearch;
    final p = await SharedPreferences.getInstance();
    await p.setBool('precision_search', _precisionSearch);
    notifyListeners();
    if (_lastSearchKey.isNotEmpty) {
      search(_lastSearchKey);
    }
  }

  // ═══════════════════════════════════════════
  // 搜尋操作
  // ═══════════════════════════════════════════

  Future<void> search(String keyword) async {
    if (keyword.isEmpty) return;
    _lastSearchKey = keyword;
    _results = [];
    _sourceFailures.clear();
    clearResultFilters();
    notifyListeners();

    // 儲存搜尋歷史
    await _keywordDao.saveKeyword(keyword);
    await loadHistory();

    // 委派搜尋引擎
    await _searchModel.search(
      key: keyword,
      scope: _searchScope,
      precisionSearch: _precisionSearch,
    );
  }

  /// 在指定書源內搜尋
  Future<void> searchInSource(BookSource source, String keyword) async {
    if (keyword.isEmpty) return;
    _lastSearchKey = keyword;
    _results = [];
    _sourceFailures.clear();
    clearResultFilters();

    // 使用單一書源的 scope
    final singleScope = SearchScope.fromSource(source);
    notifyListeners();

    await _searchModel.search(
      key: keyword,
      scope: singleScope,
      precisionSearch: _precisionSearch,
    );
  }

  Future<void> retryFailedSources() async {
    if (_lastSearchKey.isEmpty || _sourceFailures.isEmpty || _isSearching) {
      return;
    }
    final sources =
        _sourceFailures
            .map((failure) => failure.source)
            .where((source) => source.isSearchEnabledByRuntime)
            .toList();
    if (sources.isEmpty) return;

    final existingResults = List<SearchBook>.from(_results);
    _sourceFailures.clear();
    notifyListeners();
    await _searchModel.searchSources(
      key: _lastSearchKey,
      sources: sources,
      precisionSearch: _precisionSearch,
      initialResults: existingResults,
    );
  }

  void stopSearch() {
    _searchModel.cancelSearch();
    _isSearching = false;
    _currentSource = '已停止';
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  // 搜尋歷史管理
  // ═══════════════════════════════════════════

  Future<void> loadHistory() async {
    _history = await _keywordDao.getByTime();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _keywordDao.clearAll();
    _history = [];
    notifyListeners();
  }

  Future<void> deleteHistoryKeyword(SearchKeyword keyword) async {
    await _keywordDao.deleteByWord(keyword.word);
    _history.removeWhere((e) => e.word == keyword.word);
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  // SearchModelCallback 實現
  // ═══════════════════════════════════════════

  @override
  void onSearchStart() {
    _isSearching = true;
    _failedSources = 0;
    _completedSources = 0;
    _totalSources = 0;
    _currentSource = '';
    _sourceFailures.clear();
    notifyListeners();
  }

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) {
    _results = searchBooks;
    notifyListeners();
  }

  @override
  void onSearchFailure(SearchFailure failure) {
    _sourceFailures.add(failure);
    notifyListeners();
  }

  @override
  void onSearchFinish({required bool isEmpty}) {
    _isSearching = false;
    notifyListeners();
  }

  @override
  void onSearchProgress({
    required String currentSource,
    required int completed,
    required int total,
    required int failed,
  }) {
    _currentSource = currentSource;
    _completedSources = completed;
    _totalSources = total;
    _failedSources = failed;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchModel.cancelSearch();
    _isSearching = false;
    _bookshelfTracker.dispose();
    _searchModel.dispose();
    super.dispose();
  }
}
