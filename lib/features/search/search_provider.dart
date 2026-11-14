import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/search_keyword.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
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

/// 進度的訂閱與結果清單分開，書源每次送出或回來不必重建搜尋結果。
class _ProgressUpdates extends ChangeNotifier {
  void publish() => notifyListeners();
}

/// SearchProvider - 搜尋頁面狀態管理
/// (對標 Legado SearchViewModel.kt)
///
/// 職責：UI 狀態管理、搜尋歷史 CRUD、委派 [SearchModel] 執行搜尋。
/// 搜尋引擎邏輯已提取到 [SearchModel]。
class SearchProvider extends ChangeNotifier implements SearchModelCallback {
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final SearchKeywordDao _keywordDao = getIt<SearchKeywordDao>();
  final AiFindDao _aiFindDao = getIt<AiFindDao>();
  List<AiFindRecord> _pastFinds = const [];

  /// 過去的找書，新的在前（搜尋歷史頁最上面一段，ADR 0060）。
  List<AiFindRecord> get pastFinds => _pastFinds;
  final BookshelfStateTracker _bookshelfTracker;

  late final SearchModel _searchModel;
  late SearchScope _searchScope;
  final SearchScope? _initialScope;

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

  /// 使用者選的類別：每次進搜尋頁從小說開始，從某本漫畫、有聲書或某個
  /// 書源進來時是它的類別。那一類沒有可搜尋的書源時 [kind] 改用第一個有的。
  BookSourceKind _chosenKind;

  /// 有可搜尋書源的類別與書源數，照小說、漫畫、有聲的順序；進場播完才讀。
  /// 推入的第一幀照上次讀到的（[_kindsHintKey]），類別膠囊不在進場後才冒出來。
  Map<BookSourceKind, int> _kindCounts = const {};
  List<String> _sourceGroups = [];
  SearchResultSortMode _sortMode = SearchResultSortMode.relevance;
  final Set<String> _sourceFilters = {};
  String _authorFilter = '';
  bool _onlyInBookshelf = false;

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
    _progressNotify?.cancel();
    _progressNotify = null;
    _resultsCache = null;
    _progressUpdates.publish();
    super.notifyListeners();
  }

  /// 每個書源送出、回來、失敗都會回報一次，100ms 內的回報合成一次進度
  /// 通知（與搜尋結果的合併間隔相同）；結果等其他變動照常立刻通知。
  static const Duration _progressNotifyDelay = Duration(milliseconds: 100);
  Timer? _progressNotify;
  final _progressUpdates = _ProgressUpdates();

  /// 只讀進度、等待書源與失敗數的小區塊訂閱這個訊號。
  Listenable get progressUpdates => _progressUpdates;

  void _notifySoon() {
    _progressNotify ??= Timer(_progressNotifyDelay, () {
      _progressNotify = null;
      _progressUpdates.publish();
    });
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

  /// 這次搜的是哪一類書：選的那一類有可搜尋的書源就是它，否則是第一個有的。
  BookSourceKind get kind {
    if (_kindCounts.isEmpty || _kindCounts.containsKey(_chosenKind)) {
      return _chosenKind;
    }
    return _kindCounts.keys.first;
  }

  /// 有可搜尋書源的類別；不只一類時頁首才有類別膠囊、才照類別篩。
  List<BookSourceKind> get kinds => _kindCounts.keys.toList();

  /// 每一類可搜尋的書源數，給類別選單。
  Map<BookSourceKind, int> get kindCounts => _kindCounts;

  /// 照類別篩（書源只有一類時不篩：聚合源搜到的其他類別照樣列出）。
  bool get _filtersByKind => _kindCounts.length > 1;
  List<String> get sourceGroups => _sourceGroups;
  SearchScope get searchScope => _searchScope;
  SearchResultSortMode get sortMode => _sortMode;
  Set<String> get sourceFilters => Set.unmodifiable(_sourceFilters);
  String get authorFilter => _authorFilter;
  bool get onlyInBookshelf => _onlyInBookshelf;
  List<SearchFailure> get sourceFailures => List.unmodifiable(_sourceFailures);
  bool get hasActiveResultFilters =>
      _sourceFilters.isNotEmpty ||
      _authorFilter.trim().isNotEmpty ||
      _onlyInBookshelf;
  List<String> get availableSourceFilters {
    final labels = <String>{};
    for (final book in _results) {
      labels.addAll(_sourceLabelsFor(book));
    }
    return labels.toList()..sort();
  }

  /// [entrance] 是搜尋頁的進場動畫；播完才讀書架、分組與搜尋紀錄（ADR 0018）。
  /// [searchLoader] 換掉向書源搜尋的那一步（測試從記憶體回傳）。
  /// [initialKind] 是一開始搜哪一類書（沒給是小說）。
  SearchProvider({
    required Future<void> entrance,
    BookshelfStateTracker? bookshelfTracker,
    SearchScope? initialScope,
    BookSourceKind? initialKind,
    SearchBookLoader? searchLoader,
  }) : _bookshelfTracker = bookshelfTracker ?? BookshelfStateTracker(),
       _initialScope = initialScope,
       _chosenKind = initialKind ?? BookSourceKind.novel {
    _searchModel = SearchModel(callback: this, loader: searchLoader);
    _searchScope = initialScope ?? SearchScope();
    _readPreferences(getIt<SharedPreferences>());
    if (_keywordDao.latestByTime case final history?) {
      _history = List.of(history);
      _historyLoaded = true;
    }
    _coverSubscription = AppEventBus()
        .onName(AppEventBus.bookCover)
        .listen((event) => _adoptDetailCover(event.data as BookCoverEvent));
    ready = entrance.then((_) => _disposed ? null : _init());
  }

  /// 進場動畫播完、搜尋範圍與書架都讀好時完成；帶關鍵字進來的搜尋等它。
  late final Future<void> ready;
  bool _disposed = false;

  /// 從書籍詳情帶回來的封面，依合併卡身分記下；新的一次搜尋清掉。
  final Map<String, String> _detailCovers = {};
  StreamSubscription<AppEvent>? _coverSubscription;

  /// 卡片要顯示的封面：進過書籍詳情的書用詳情頁的封面（搜尋結果常沒有
  /// 封面，或只有載不到的網址），否則用搜尋結果的。
  String? coverOf(SearchBook book) =>
      _detailCovers[searchResultIdentity(book)] ?? book.coverUrl;

  /// 點開詳情時的網址對應到哪張合併卡。詳情回報封面時，卡片的代表來源可能
  /// 已經換了（網址跟著變），不同作者的兩張卡也可能同網址；所以在點開的
  /// 當下記下身分，不用回報當時的結果去找。
  final Map<String, String> _openedCards = {};

  /// 搜尋頁點開一張卡、進書籍詳情之前呼叫。
  void rememberOpenedCard(SearchBook book) {
    _openedCards[book.bookUrl] = searchResultIdentity(book);
  }

  void _adoptDetailCover(BookCoverEvent event) {
    // 在詳情裡換了源的書網址不同，不屬於任何一張卡，不帶回來。
    final identity = _openedCards[event.bookUrl];
    if (identity == null || _detailCovers[identity] == event.cover) return;
    _detailCovers[identity] = event.cover;
    notifyListeners();
  }

  /// 新的一次搜尋：結果換了一批，詳情帶回的封面不再適用，載入失敗過的
  /// 封面也再試一次。
  void _resetCovers() {
    _detailCovers.clear();
    _openedCards.clear();
    BookCoverWidget.forgetFailedCovers();
  }

  Future<void> _init() async {
    await _bookshelfTracker.initialize(onChanged: notifyListeners);
    await _loadGroups();
    // 先讀過去的找書再讀紀錄：紀錄讀完才決定畫不畫空頁，兩段一起出現。
    _pastFinds = await _aiFindDao.getNewestFirst();
    await loadHistory();
  }

  /// 從找書頁回來、刪了一筆之後重讀。
  Future<void> loadPastFinds() async {
    final finds = await _aiFindDao.getNewestFirst();
    if (_disposed) return;
    _pastFinds = finds;
    notifyListeners();
  }

  Future<void> deletePastFind(AiFindRecord find) async {
    await _aiFindDao.deleteById(find.id);
    await loadPastFinds();
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
    final blocked = _blockedKeys;
    return books.where((book) {
      if (_filtersByKind && book.bookKind != kind) return false;
      if (blocked.isNotEmpty) {
        final name = normalizeSearchText(book.name);
        final author = normalizeSearchText(book.author);
        if (blocked.any((key) => name.contains(key) || author.contains(key))) {
          return false;
        }
      }
      if (_sourceFilters.isNotEmpty) {
        final labels = _sourceLabelsFor(book).toSet();
        if (!_sourceFilters.any(labels.contains)) return false;
      }
      if (_onlyInBookshelf && !isInBookshelf(book)) return false;
      if (authorKey.isNotEmpty &&
          !normalizeSearchText(book.author).contains(authorKey)) {
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

  /// 結果順序是否已經固定（使用者捲動過）。
  bool get resultOrderHeld => _heldOrder != null;

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

  void setOnlyInBookshelf(bool value) {
    _onlyInBookshelf = value;
    notifyListeners();
  }

  void clearResultFilters() {
    _sourceFilters.clear();
    _authorFilter = '';
    _onlyInBookshelf = false;
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
    _kindCounts = _countKinds(sources);
    unawaited(_saveKindsHint());
    notifyListeners();
  }

  /// 類別膠囊的選單照這個順序列。
  static const List<BookSourceKind> switchableKinds = [
    BookSourceKind.novel,
    BookSourceKind.comic,
    BookSourceKind.audio,
  ];

  static Map<BookSourceKind, int> _countKinds(Iterable<BookSource> sources) {
    final counts = <BookSourceKind, int>{};
    for (final source in sources) {
      if (source.isSearchEnabledByRuntime) {
        counts.update(source.sourceKind, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return {for (final kind in switchableKinds) kind: ?counts[kind]};
  }

  /// 上次讀到的類別與書源數，例如 `novel:42,comic:8`；只用來畫第一幀。
  static const String _kindsHintKey = 'search_source_kinds';

  static Map<BookSourceKind, int> _readKindsHint(SharedPreferences prefs) {
    final counts = <BookSourceKind, int>{};
    for (final entry in (prefs.getString(_kindsHintKey) ?? '').split(',')) {
      if (entry.split(':') case [final name, final count]) {
        final kind = BookSourceKind.values.asNameMap()[name];
        final n = int.tryParse(count);
        if (kind != null && switchableKinds.contains(kind) && n != null) {
          counts[kind] = n;
        }
      }
    }
    return counts;
  }

  Future<void> _saveKindsHint() async {
    final value = [
      for (final MapEntry(:key, :value) in _kindCounts.entries)
        '${key.name}:$value',
    ].join(',');
    try {
      await getIt<SharedPreferences>().setString(_kindsHintKey, value);
    } catch (error) {
      AppLog.w('搜尋的書源類別沒有寫進偏好設定: $error');
    }
  }

  /// 換搜哪一類書；搜過就照新的類別重搜。
  void setKind(BookSourceKind kind) {
    if (kind == this.kind) return;
    _chosenKind = kind;
    notifyListeners();
    if (_lastSearchKey.isNotEmpty) {
      unawaited(search(_lastSearchKey));
    }
  }

  /// 只搜 [source] 一個書源時搜哪一類：照書源的類別；聚合源什麼類別都搜得
  /// 到（ADR 0056）、夜讀打不開的類別，都是 null（不改）。
  static BookSourceKind? searchKindOf(BookSource source) =>
      source.isOpenableSource && !source.isAggregateSource
      ? source.sourceKind
      : null;

  void _followSourceKind(BookSource source) {
    _chosenKind = searchKindOf(source) ?? _chosenKind;
  }

  Future<void> updateSearchScope(SearchScope scope) async {
    _searchScope = scope;
    unawaited(scope.save());
    if (scope.isSource) {
      final url = scope.toString().split('::').last;
      final source = await _sourceDao.getByUrl(url);
      if (_disposed || _searchScope != scope) return;
      if (source != null) _followSourceKind(source);
    }
    notifyListeners();
    // 已經搜尋過就以新範圍重搜；搜尋中也一樣，舊的那次會被取消。
    if (_lastSearchKey.isNotEmpty) {
      unawaited(search(_lastSearchKey));
    }
  }

  // ═══════════════════════════════════════════
  // 精準搜尋
  // ═══════════════════════════════════════════

  /// 範圍、精準搜尋與屏蔽詞都在偏好設定裡，開 App 時已經讀好：推入的第一幀
  /// 就照它們畫，不等進場播完（原本範圍鈕先寫「載入中…」，播完才換）。
  void _readPreferences(SharedPreferences prefs) {
    if (_initialScope == null) _searchScope = SearchScope.fromPrefs(prefs);
    _kindCounts = _readKindsHint(prefs);
    _precisionSearch = prefs.getBool('precision_search') ?? false;
    _blockedWords = prefs.getString(_blockedWordsKey) ?? '';
  }

  // ═══════════════════════════════════════════
  // 屏蔽詞：書名或作者含有這些字的結果不列，記在手機上，每次搜尋都套用
  // ═══════════════════════════════════════════

  static const String _blockedWordsKey = 'search_blocked_words';
  String _blockedWords = '';

  /// 使用者打的屏蔽詞原文（逗號、頓號、空白或換行分開）。
  String get blockedWords => _blockedWords;

  List<String> get _blockedKeys => [
    for (final word in _blockedWords.split(RegExp(r'[,，、\s]+')))
      if (normalizeSearchText(word).isNotEmpty) normalizeSearchText(word),
  ];

  Future<void> setBlockedWords(String value) async {
    _blockedWords = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_blockedWordsKey, value);
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
    _resetCovers();
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
      kind: _filtersByKind ? kind : null,
    );
  }

  /// 在指定書源內搜尋
  Future<void> searchInSource(BookSource source, String keyword) async {
    final searchKey = _normalizedSearchKey(keyword);
    if (searchKey == null) return;
    _lastSearchKey = searchKey;
    _results = [];
    _resetCovers();
    _heldOrder = null;
    _sourceFailures.clear();
    _markSearchPending();
    clearResultFilters();
    _followSourceKind(source);

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

  /// 搜尋頁被整頁蓋住（書籍詳情、閱讀器）時暫停還沒送出的書源，回到搜尋頁
  /// 再接著送。進度與結果照舊，不通知畫面。
  void pauseSearch() => _searchModel.pause();

  void resumeSearch() => _searchModel.resume();

  bool get isSearchPaused => _searchModel.isPaused;

  void stopSearch() {
    _searchModel.stopSearch();
    _isSearching = false;
    _waitingSources = const [];
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  // 搜尋歷史管理
  // ═══════════════════════════════════════════

  /// 開 App 進場播完時讀一次搜尋紀錄：資料層記著最近一次讀到的
  /// （[SearchKeywordDao.latestByTime]），搜尋頁推入的第一幀就照它畫。原本推入
  /// 時畫「開始搜尋你想看的書吧」，進場播完才讀、一幀換成紀錄：2026-11-05
  /// 手機上那一幀主執行緒 25.7ms，畫面上整區突然換掉。
  static Future<void> prefetchHistory() async {
    try {
      final dao = getIt<SearchKeywordDao>();
      if (dao.latestByTime == null) await dao.getByTime();
    } catch (error, stackTrace) {
      AppLog.e('預先讀搜尋紀錄失敗: $error', error: error, stackTrace: stackTrace);
    }
  }

  /// 知道有沒有搜尋紀錄了；還不知道時不畫「沒有紀錄」的空頁。
  bool get historyLoaded => _historyLoaded;
  bool _historyLoaded = false;

  void _setHistory(List<SearchKeyword> history) {
    final unchanged =
        _historyLoaded &&
        history.length == _history.length &&
        [
          for (var i = 0; i < history.length; i++)
            history[i].word == _history[i].word,
        ].every((same) => same);
    _history = history;
    _historyLoaded = true;
    // 和推入時畫的一樣就不重建。
    if (!unchanged) notifyListeners();
  }

  Future<void> loadHistory() async {
    _setHistory(await _keywordDao.getByTime());
  }

  Future<void> clearHistory() async {
    await _keywordDao.clearAll();
    _setHistory([]);
  }

  /// 刪掉一筆後從資料庫重讀：紀錄最多列 50 筆，第 51 筆會補上來，畫面和下次
  /// 推入時記著的都是資料庫實際會給的那份。
  Future<void> deleteHistoryKeyword(SearchKeyword keyword) async {
    await _keywordDao.deleteByWord(keyword.word);
    await loadHistory();
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
    _notifySoon();
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
    _notifySoon();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressNotify?.cancel();
    _progressUpdates.dispose();
    _coverSubscription?.cancel();
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
