import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/search_keyword.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';
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

/// 輸入框下方的一條建議：搜尋紀錄或書架上的書名。
class SearchSuggestion {
  const SearchSuggestion(this.word, {required this.fromBookshelf});

  final String word;
  final bool fromBookshelf;
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
  List<String> _waitingSources = const [];
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

  /// 篩選並排序後的結果。一次畫面更新會讀好幾次，算一次就快取；任何狀態
  /// 變更都會經過 [notifyListeners]，在那裡失效。
  List<SearchBook> get results =>
      _resultsCache ??= _filteredResults(_orderedResults());
  List<SearchBook>? _resultsCache;

  /// 使用者開始捲動後固定下來的結果順序（合併卡身分）。之後串流進來的書
  /// 接在尾端，已經出現的書不再換位置；新的一次搜尋或重選排序時解除。
  List<String>? _heldOrder;

  @override
  void notifyListeners() {
    _resultsCache = null;
    super.notifyListeners();
  }

  /// 這次搜尋的書源總數；重試失敗書源時不會被縮成重試的數量。
  int get searchedSourceCount => _searchedSourceCount;
  int _searchedSourceCount = 0;
  bool _retrying = false;
  int get unfilteredResultCount => _results.length;
  int get resultCount => results.length;
  bool get hasUnfilteredResults => _results.isNotEmpty;
  bool get isSearching => _isSearching;

  /// 已經送出、還沒回來的書源名稱。
  List<String> get waitingSources => _waitingSources;
  int get completedSources => _completedSources;
  String get lastSearchKey => _lastSearchKey;
  double get progress => _totalSources == 0
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

  /// 打字時的建議：包含輸入文字的搜尋紀錄在前，再來是書架上的書名；
  /// 繁簡、全半形、大小寫與空白都不分，同一個詞只出現一次。
  List<SearchSuggestion> suggestionsFor(String input) {
    final key = normalizeSearchText(input);
    if (key.isEmpty) return const [];
    final seen = <String>{};
    bool matches(String word) {
      final normalized = normalizeSearchText(word);
      return normalized.contains(key) && seen.add(normalized);
    }

    return [
      for (final keyword in _history)
        if (matches(keyword.word))
          SearchSuggestion(keyword.word, fromBookshelf: false),
      for (final name in _bookshelfTracker.bookNames)
        if (matches(name)) SearchSuggestion(name, fromBookshelf: true),
    ];
  }

  List<String> _sourceLabelsFor(SearchBook book) => book.sourceLabels.isNotEmpty
      ? book.sourceLabels
      : [book.originName ?? book.origin];

  List<SearchBook> _filteredResults(List<SearchBook> books) {
    final authorKey = normalizeSearchText(_authorFilter);
    final kindKey = normalizeSearchText(_kindFilter);
    return books.where((book) {
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

  List<SearchBook> _orderedResults() {
    final held = _heldOrder;
    if (held == null) return _sortedResults(_results);
    final byIdentity = {
      for (final book in _results) searchResultIdentity(book): book,
    };
    return [for (final identity in held) ?byIdentity[identity]];
  }

  /// 相關度排序時這本書屬於哪一段（0 完全相符、1 部分相符、2 其他）；
  /// 其他排序不分段，回傳 null。
  int? relevanceTierOf(SearchBook book) =>
      _sortMode == SearchResultSortMode.relevance
      ? searchRelevanceRank(book, _lastSearchKey)
      : null;

  /// 固定目前的結果順序；使用者開始捲動結果時由頁面呼叫。
  void holdResultOrder() {
    if (_heldOrder != null) return;
    _heldOrder = [
      for (final book in _sortedResults(_results)) searchResultIdentity(book),
    ];
  }

  /// 順序固定時，把這次新出現的書照目前的排序接到尾端。
  void _appendToHeldOrder() {
    final held = _heldOrder;
    if (held == null) return;
    final known = held.toSet();
    for (final book in _sortedResults(_results)) {
      final identity = searchResultIdentity(book);
      if (known.add(identity)) held.add(identity);
    }
  }

  /// 重選排序（包括選回同一種）都照新的排序重排，解除固定的順序。
  void updateSortMode(SearchResultSortMode mode) {
    _sortMode = mode;
    _heldOrder = null;
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
      groups.addAll(splitSourceGroups(s.bookSourceGroup));
    }
    _sourceGroups = groups.toList()..sort();
    notifyListeners();
  }

  void updateSearchScope(SearchScope scope) {
    _searchScope = scope;
    unawaited(scope.save());
    notifyListeners();
    // 已經搜尋過就以新範圍重搜；搜尋中也一樣，舊的那次會被取消。
    if (_lastSearchKey.isNotEmpty) {
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
      unawaited(search(_lastSearchKey));
    }
  }

  // ═══════════════════════════════════════════
  // 搜尋操作
  // ═══════════════════════════════════════════

  String? _normalizedSearchKey(String keyword) {
    final normalized = keyword.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> search(String keyword) async {
    final searchKey = _normalizedSearchKey(keyword);
    if (searchKey == null) return;
    _lastSearchKey = searchKey;
    _results = [];
    _heldOrder = null;
    _sourceFailures.clear();
    _markSearchPending();
    clearResultFilters();
    notifyListeners();

    // 儲存搜尋歷史
    await _keywordDao.saveKeyword(searchKey);
    await loadHistory();

    // 委派搜尋引擎
    await _searchModel.search(
      key: searchKey,
      scope: _searchScope,
      precisionSearch: _precisionSearch,
    );
  }

  /// 在指定書源內搜尋
  Future<void> searchInSource(BookSource source, String keyword) async {
    final searchKey = _normalizedSearchKey(keyword);
    if (searchKey == null) return;
    _lastSearchKey = searchKey;
    _results = [];
    _heldOrder = null;
    _sourceFailures.clear();
    _markSearchPending();
    clearResultFilters();

    // 使用單一書源的 scope
    final singleScope = SearchScope.fromSource(source);
    notifyListeners();

    await _searchModel.search(
      key: searchKey,
      scope: singleScope,
      precisionSearch: _precisionSearch,
    );
  }

  Future<void> retryFailedSources() async {
    if (_lastSearchKey.isEmpty || _sourceFailures.isEmpty || _isSearching) {
      return;
    }
    final sources = _sourceFailures
        .map((failure) => failure.source)
        .where((source) => source.isSearchEnabledByRuntime)
        .toList();
    if (sources.isEmpty) return;

    final existingResults = List<SearchBook>.from(_results);
    _sourceFailures.clear();
    notifyListeners();
    _retrying = true;
    try {
      await _searchModel.searchSources(
        key: _lastSearchKey,
        sources: sources,
        precisionSearch: _precisionSearch,
        initialResults: existingResults,
      );
    } finally {
      _retrying = false;
    }
  }

  /// 送出搜尋後、引擎真正開始前（存歷史、讀書源清單）就先進入搜尋中，
  /// 這段空檔才不會閃出空狀態，也擋住重複送出。
  void _markSearchPending() {
    _isSearching = true;
    _completedSources = 0;
    _totalSources = 0;
    _failedSources = 0;
    _waitingSources = const [];
  }

  void stopSearch() {
    _searchModel.cancelSearch();
    _isSearching = false;
    _waitingSources = const [];
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
    _waitingSources = const [];
    _sourceFailures.clear();
    notifyListeners();
  }

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) {
    _results = searchBooks;
    _appendToHeldOrder();
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
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {
    _waitingSources = waitingSources;
    _completedSources = completed;
    _totalSources = total;
    _failedSources = failed;
    if (!_retrying) _searchedSourceCount = total;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchModel.cancelSearch();
    _isSearching = false;
    _bookshelfTracker.dispose();
    _searchModel.dispose();
    // 存下的搜尋結果只在搜尋頁開著時有用（從結果進詳情後，換源與換封面先
    // 列出剛搜到的來源），離開搜尋頁就清掉，不在手機裡越積越多。
    unawaited(getIt<SearchBookDao>().clearAll());
    super.dispose();
  }
}
