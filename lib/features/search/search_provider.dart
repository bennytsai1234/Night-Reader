import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/background_work/work_phase.dart';
import 'package:night_reader/core/source_switch/same_book.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/features/search/ai_find/ai_find_run.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/search/ai_find_record.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/search/search_keyword.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/bookshelf_state_tracker.dart';
import 'package:night_reader/shared/widgets/book/book_cover_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_search.dart';
import 'models/search_scope.dart';
import 'search_model.dart';
import 'search_run.dart';

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

/// 搜尋頁的進度那一列、頁首「結束」與頁首下緣的進度條照哪個樣子
/// （[SearchProvider.stage]；階段表在 `docs/state-machines.md`「搜尋」）。
enum SearchStage {
  /// 沒在搜：還沒搜過，或搜完、按了結束。結果工具列，頁首「搜尋」。
  idle,

  /// 搜尋頁自己的搜尋在搜：「正在搜尋」與「放到背景」，頁首「結束」。
  searching,

  /// 放到背景、做著：「正在搜尋」與「暫停」。
  inBackground,

  /// 放到背景、按了暫停還沒停好：「正在暫停…」，不放動作。
  pausing,

  /// 放到背景、按了結束還沒停好：「正在結束…」。
  ending,

  /// 放到背景、暫停中（含按了繼續正在讀回）：「已暫停 124/396」與「繼續」。
  paused;

  /// 還沒搜完：頁首是「結束」，進度那一列與進度條還在。
  bool get unfinished => this != idle;
}

/// 搜尋頁怎麼看著放到背景的那一件（[SearchProvider]）。
enum _Attachment {
  /// 沒有接回、放到背景的那一件，或已經放掉了。
  none,

  /// 接回了，結果等進場播完才放出來；這一頁還不算看著，換頁中返回不算看過
  /// （ADR 0070）。
  holding,

  /// 看著：結果放出來了，離開時算這一頁不看了（[RepairRun.detach]）。
  watching,
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
/// 職責：UI 狀態管理、搜尋歷史 CRUD。搜尋本身與結果在 [SearchRun]，這裡訂閱
/// 它；放到背景時那一份交給背景工作，頁面關了照跑（ADR 0070）。
class SearchProvider extends ChangeNotifier implements SearchModelCallback {
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final SearchKeywordDao _keywordDao = getIt<SearchKeywordDao>();
  final AiFindDao _aiFindDao = getIt<AiFindDao>();
  List<AiFindRecord> _pastFinds = const [];

  /// 過去的找書，新的在前（搜尋歷史頁最上面一段，ADR 0060）。
  List<AiFindRecord> get pastFinds => _pastFinds;
  final BookshelfStateTracker _bookshelfTracker;

  /// 現在畫的這一次搜尋：自己的，或接回、放到背景的那一件的（[_background]）。
  late SearchRun _run;
  BackgroundSearchRun? _background;
  final BackgroundSearches _backgroundSearches;
  final SearchBookLoader? _loader;
  late SearchScope _searchScope;
  final SearchScope? _initialScope;

  // --- UI State ---
  List<SearchKeyword> _history = [];

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
  int get searchedSourceCount => _run.searchedSourceCount;

  /// 畫面上的結果：接回放到背景的那一次時，進場播完才放出來，換頁的那幾幀
  /// 不建結果卡（ADR 0018、0070）。
  List<SearchBook> get _shownResults =>
      _attachment == _Attachment.holding ? const [] : _run.results;
  _Attachment _attachment = _Attachment.none;

  int get unfilteredResultCount => _shownResults.length;
  int get resultCount => results.length;
  bool get hasUnfilteredResults => _shownResults.isNotEmpty;
  bool get isSearching => _run.isSearching;

  /// 已經送出、還沒回來的書源名稱。
  List<String> get waitingSources => _run.waitingSources;
  int get completedSources => _run.completed;
  String get lastSearchKey => _run.key;
  double get progress =>
      _run.total == 0 ? 0 : (_run.completed / _run.total).clamp(0.0, 1.0);
  int get failedSources => _run.failed;
  int get totalSources => _run.total;

  /// 進度那一列、頁首「結束」與進度條的樣子：放到背景的那一件照它的階段，
  /// 否則照這一次搜尋在不在搜。
  SearchStage get stage {
    final background = _background;
    if (background == null) {
      return _run.isSearching ? SearchStage.searching : SearchStage.idle;
    }
    return switch (background.phase) {
      WorkPhase.paused || WorkPhase.resuming => SearchStage.paused,
      WorkPhase.ending => SearchStage.ending,
      // 搜尋本身搜完了，背景那件還在寫結果檔。
      _ when !_run.isSearching => SearchStage.idle,
      WorkPhase.pausing => SearchStage.pausing,
      _ => SearchStage.inBackground,
    };
  }

  /// 還沒搜完（[stage]），或接回的結果還沒放出來：列結果，不列空狀態。
  bool get isUnfinished =>
      stage.unfinished || _attachment == _Attachment.holding;

  /// 進度那一列的「放到背景」能不能按：別的背景工作在跑時灰掉（ADR 0070）。
  bool get canMoveToBackground =>
      stage == SearchStage.searching && _backgroundSearches.canMoveToBackground;

  /// 暫停中的「繼續」能不能按：別的背景工作在跑、結果還沒放出來時灰掉。
  bool get canResumeBackground =>
      _attachment != _Attachment.holding && (_background?.canResume ?? false);
  bool get precisionSearch => _precisionSearch;

  /// 頁首膠囊與結果照哪一類：畫面上這一次搜尋的（接回的、重試的也是），
  /// 不管現在哪一類還有書源；還沒搜過照 [_kindToSearch]。
  BookSourceKind get kind => _run.conditions?.kind ?? _kindToSearch;

  /// 新的一次搜哪一類：選的那一類有可搜尋的書源就是它，否則是第一個有的。
  BookSourceKind get _kindToSearch {
    if (_kindCounts.isEmpty || _kindCounts.containsKey(_chosenKind)) {
      return _chosenKind;
    }
    return _kindCounts.keys.first;
  }

  /// 有可搜尋書源的類別；不只一類時頁首才有類別膠囊、才照類別篩。
  List<BookSourceKind> get kinds => _kindCounts.keys.toList();

  /// 每一類可搜尋的書源數，給類別選單。
  Map<BookSourceKind, int> get kindCounts => _kindCounts;

  /// 結果照不照類別篩：照畫面上這一次搜尋的；還沒搜過照 [_filtersKindToSearch]。
  bool get _filtersByKind => _run.conditions?.byKind ?? _filtersKindToSearch;

  /// 新的一次照不照類別篩：書源只有一類時不篩，聚合源搜到的其他類別照樣列出。
  bool get _filtersKindToSearch => _kindCounts.length > 1;
  List<String> get sourceGroups => _sourceGroups;

  /// 頁首與範圍面板的範圍：畫面上這一次搜尋實際搜的（分組沒有可搜尋的書源
  /// 時清掉或退回全部）；還沒搜過照選的。新的一次照選的 [_searchScope]。
  SearchScope get searchScope => switch (_run.conditions) {
    final conditions? => SearchScope(conditions.scope),
    null => _searchScope,
  };
  SearchResultSortMode get sortMode => _sortMode;
  Set<String> get sourceFilters => Set.unmodifiable(_sourceFilters);
  String get authorFilter => _authorFilter;
  bool get onlyInBookshelf => _onlyInBookshelf;
  List<SearchFailure> get sourceFailures => List.unmodifiable(_run.failures);
  bool get hasActiveResultFilters =>
      _sourceFilters.isNotEmpty ||
      _authorFilter.trim().isNotEmpty ||
      _onlyInBookshelf;
  List<String> get availableSourceFilters {
    final labels = <String>{};
    for (final book in _shownResults) {
      labels.addAll(_sourceLabelsFor(book));
    }
    return labels.toList()..sort();
  }

  /// [entrance] 是搜尋頁的進場動畫；播完才讀書架、分組與搜尋紀錄（ADR 0018）。
  /// [searchLoader] 換掉向書源搜尋的那一步（測試從記憶體回傳）。
  /// [initialKind] 是一開始搜哪一類書（沒給是小說）。[resumeBackground] 時
  /// 接回放到背景的那一次搜尋（沒帶關鍵字打開的搜尋頁，ADR 0070）。
  SearchProvider({
    required Future<void> entrance,
    BookshelfStateTracker? bookshelfTracker,
    SearchScope? initialScope,
    BookSourceKind? initialKind,
    SearchBookLoader? searchLoader,
    BackgroundSearches? backgroundSearches,
    bool resumeBackground = false,
  }) : _bookshelfTracker = bookshelfTracker ?? BookshelfStateTracker(),
       _initialScope = initialScope,
       _loader = searchLoader,
       _backgroundSearches = backgroundSearches ?? BackgroundSearches.instance,
       _chosenKind = initialKind ?? BookSourceKind.novel {
    _searchScope = initialScope ?? SearchScope();
    _readPreferences(getIt<SharedPreferences>());
    final resumable = resumeBackground ? _backgroundSearches.resumable : null;
    if (resumable != null) {
      _attach(resumable);
    } else {
      _listen(_run = _newRun());
      // 開 App 後馬上打開的搜尋頁：上次的那一件可能還在讀回，讀好了再接回。
      if (resumeBackground) {
        unawaited(_backgroundSearches.restored.then((_) => _attachLate()));
      }
    }
    _backgroundSearches.work.addListener(_slotChanged);
    _backgroundSearches.runs.addListener(_slotChanged);
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
    _entered = true;
    if (_attachment == _Attachment.holding) await _reveal();
    if (_disposed) return;
    await _bookshelfTracker.initialize(onChanged: notifyListeners);
    await _loadGroups();
    // 先讀過去的找書再讀紀錄：紀錄讀完才決定畫不畫空頁，兩段一起出現。
    _pastFinds = await _aiFindDao.getNewestFirst();
    await loadHistory();
    if (_disposed) return;
    aiFindRuns.addListener(_onFindRunsChanged);
  }

  /// 背景的找書做完時已經存成一筆：搜尋頁開著也要看到它（Codex 審查）。
  /// 每次找書的背景工作只在做完、頁面開關時通知，重讀的次數很少。
  void _onFindRunsChanged() {
    if (aiFindRuns.current?.isFinished ?? false) unawaited(loadPastFinds());
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
    if (held == null) return _sortedResults(_shownResults);
    final byIdentity = {
      for (final book in _shownResults) searchResultIdentity(book): book,
    };
    return [for (final identity in held) ?byIdentity[identity]];
  }

  /// 相關度排序時這本書屬於哪一段（0 完全相符、1 部分相符、2 其他）；
  /// 其他排序不分段，回傳 null。
  int? relevanceTierOf(SearchBook book) =>
      _sortMode == SearchResultSortMode.relevance
      ? searchRelevanceRank(book, lastSearchKey)
      : null;

  /// 結果順序是否已經固定（使用者捲動過）。
  bool get resultOrderHeld => _heldOrder != null;

  /// 固定目前的結果順序；使用者開始捲動結果時由頁面呼叫。
  void holdResultOrder() {
    if (_heldOrder != null) return;
    _heldOrder = [
      for (final book in _sortedResults(_shownResults))
        searchResultIdentity(book),
    ];
  }

  /// 順序固定時，把這次新出現的書照目前的排序接到尾端。
  void _appendToHeldOrder() {
    final held = _heldOrder;
    if (held == null) return;
    final known = held.toSet();
    for (final book in _sortedResults(_shownResults)) {
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
    // 搜過的由新的一次開始時通知：頁首照畫面上那一次的類別，開始前先通知會讀到舊的。
    if (lastSearchKey.isEmpty) {
      notifyListeners();
    } else {
      unawaited(search(lastSearchKey));
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
    if (lastSearchKey.isNotEmpty) {
      unawaited(search(lastSearchKey));
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
    if (lastSearchKey.isNotEmpty) {
      unawaited(search(lastSearchKey));
    }
  }

  // ═══════════════════════════════════════════
  // 搜尋操作
  // ═══════════════════════════════════════════

  String? _normalizedSearchKey(String keyword) {
    final normalized = keyword.trim();
    return normalized.isEmpty ? null : normalized;
  }

  SearchRun _newRun() => SearchRun(
    loader: _loader ?? _backgroundSearches.loader,
    readingFetches: _backgroundSearches.readingFetches,
  );

  SearchConditions _conditions(SearchScope scope) => (
    kind: _kindToSearch,
    byKind: _filtersKindToSearch,
    scope: scope.toString(),
    precision: _precisionSearch,
  );

  /// 新的一次搜尋開始前清掉上一次的：詳情帶回的封面、固定的順序與篩選。
  /// 條件在這時定下，照使用者現在選的（[_conditions]）。傳回給
  /// [SearchRun.start] 的號碼。
  int _beginSearch(String searchKey, SearchScope scope) {
    // 上一次選的分組沒有書源、頁首改寫了實際搜的範圍：沒換過範圍就照頁首的
    // 搜，選的也換成它（同 Legado 改掉範圍；不寫回偏好）。
    if ((_run.scopeAsked, _run.conditions?.scope)
        case (final asked?, final shown?) when asked == scope.toString()) {
      final adopted = SearchScope(shown);
      if (_searchScope.toString() == asked) _searchScope = adopted;
      scope = adopted;
    }
    _leaveBackground();
    final ticket = _run.begin(searchKey, _conditions(scope));
    _resetCovers();
    _heldOrder = null;
    clearResultFilters();
    notifyListeners();
    return ticket;
  }

  Future<void> search(String keyword) async {
    final searchKey = _normalizedSearchKey(keyword);
    if (searchKey == null) return;
    final ticket = _beginSearch(searchKey, _searchScope);
    final run = _run;

    // 儲存搜尋歷史
    await _keywordDao.saveKeyword(searchKey);
    await loadHistory();

    // 存紀錄的時候按了結束、暫停或開始了新的一次，就不開始。
    await run.start(ticket);
  }

  /// 在指定書源內搜尋
  Future<void> searchInSource(BookSource source, String keyword) async {
    final searchKey = _normalizedSearchKey(keyword);
    if (searchKey == null) return;
    _followSourceKind(source);
    // 使用單一書源的 scope
    final ticket = _beginSearch(searchKey, SearchScope.fromSource(source));
    await _run.start(ticket);
  }

  /// 「重試失敗」：普通的搜尋。接回的背景搜尋做完後重試，另開一份帶著它的
  /// 結果與失敗，背景那件就此收掉（ADR 0070）。
  Future<void> retryFailedSources() async {
    final background = _background;
    if (background != null) {
      if (!background.isFinished) return;
      // 沒有重試得了的書源就不收掉背景那件。
      final sources = await _run.retryableSources();
      if (_disposed || _background != background || sources.isEmpty) return;
      _leaveBackground(next: SearchRun.copyOf(_run));
    }
    await _run.retryFailed();
  }

  /// 搜尋頁被整頁蓋住（書籍詳情、閱讀器）時暫停還沒送出的書源，回到搜尋頁
  /// 再接著送；放到背景的不暫停。進度與結果照舊，不通知畫面。
  void pauseSearch() => _run.pause();

  void resumeSearch() => _run.resume();

  bool get isSearchPaused => _run.isPaused;

  /// 頁首的「結束」：搜尋結束，已找到的結果留著；放到背景的那件也一樣。
  void stopSearch() {
    final background = _background;
    if (background != null && !background.isFinished) {
      unawaited(background.end());
    } else {
      _run.stop();
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  // 放到背景（ADR 0070）
  // ═══════════════════════════════════════════

  /// 搜尋頁的路由：點通知時它已經在最上面就不再推一頁。
  Route<void>? _route;
  set route(Route<void>? route) {
    _route = route;
    _background?.route = route;
  }

  void moveToBackground() {
    if (!canMoveToBackground) return;
    final background = _backgroundSearches.moveToBackground(_run);
    if (background == null) return;
    _adopt(background);
    background.start();
    notifyListeners();
  }

  void pauseBackground() => _background?.pauseNow();

  Future<void> resumeBackground() async => _background?.resume();

  /// 進場播完了：之後才接回的那一件直接放出結果。
  bool _entered = false;

  /// 接回：結果先不放，進場播完才放（[_reveal]）。
  void _attach(BackgroundSearchRun background) {
    _listen(_run = background.search);
    _adopt(background, attach: false);
    // 類別、範圍、精準照那一次的，不寫回偏好。
    if (_run.conditions case final conditions?) {
      _chosenKind = conditions.kind;
      _searchScope = SearchScope(conditions.scope);
      _precisionSearch = conditions.precision;
    }
  }

  /// 開 App 後馬上打開的搜尋頁：讀回好了、使用者還沒開始搜，就接回。
  void _attachLate() {
    if (_disposed || _background != null || lastSearchKey.isNotEmpty) return;
    final background = _backgroundSearches.resumable;
    if (background == null) return;
    _unlisten(_run);
    _run.dispose();
    _attach(background);
    onResumedLate?.call(background.search.key);
    notifyListeners();
    if (_entered) unawaited(_reveal());
  }

  /// 接回的搜尋頁晚一點才接回時（開 App 時還在讀回），把關鍵字交給輸入框。
  void Function(String key)? onResumedLate;

  /// 讀回的結果合併成卡（進場播完才做，ADR 0018），放出結果，這一頁才算看著。
  Future<void> _reveal() async {
    if (_run.isRestoring) await _run.mergeRestored();
    final background = _background;
    if (_disposed || background == null || _attachment != _Attachment.holding) {
      return;
    }
    if (background.isDisposed) {
      _attachment = _Attachment.none;
    } else {
      background.attach();
      _attachment = _Attachment.watching;
    }
    notifyListeners();
  }

  void _adopt(BackgroundSearchRun background, {bool attach = true}) {
    _background = background
      ..route = _route
      ..addListener(notifyListeners);
    if (attach) background.attach();
    _attachment = attach ? _Attachment.watching : _Attachment.holding;
  }

  /// 不再看著那一件：背景那件照它自己的生命週期收掉。
  void _release(BackgroundSearchRun background) {
    background.removeListener(notifyListeners);
    final watching = _attachment == _Attachment.watching;
    _attachment = _Attachment.none;
    if (background.isDisposed) return;
    background.route = null;
    if (watching) background.detach();
  }

  /// 接回或放到背景之後開始了別的搜尋：背景那次結束、不留，換成 [next]
  /// （沒給是新的一份）。
  void _leaveBackground({SearchRun? next}) {
    final background = _background;
    if (background == null) return;
    _background = null;
    background.abandon();
    _release(background);
    _unlisten(_run);
    _listen(_run = next ?? _newRun());
  }

  void _listen(SearchRun run) {
    run
      ..addListener(_runChanged)
      ..progressUpdates.addListener(_notifySoon);
  }

  void _unlisten(SearchRun run) {
    run
      ..removeListener(_runChanged)
      ..progressUpdates.removeListener(_notifySoon);
  }

  void _runChanged() {
    _appendToHeldOrder();
    notifyListeners();
  }

  /// 別的背景工作開始或結束：「放到背景」「繼續」跟著能不能按。
  void _slotChanged() {
    if (stage.unfinished) notifyListeners();
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
    // 搜尋頁關了才讀完（送出搜尋後馬上放到背景、返回）。
    if (_disposed) return;
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
  void onSearchStart() => _run.onSearchStart();

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) =>
      _run.onSearchSuccess(searchBooks);

  @override
  void onSearchFailure(SearchFailure failure) => _run.onSearchFailure(failure);

  @override
  void onSearchFinish({required bool isEmpty}) =>
      _run.onSearchFinish(isEmpty: isEmpty);

  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) => _run.onSearchProgress(
    waitingSources: waitingSources,
    completed: completed,
    total: total,
    failed: failed,
  );

  @override
  void dispose() {
    _disposed = true;
    _progressNotify?.cancel();
    _progressUpdates.dispose();
    _coverSubscription?.cancel();
    aiFindRuns.removeListener(_onFindRunsChanged);
    _backgroundSearches.work.removeListener(_slotChanged);
    _backgroundSearches.runs.removeListener(_slotChanged);
    _unlisten(_run);
    final background = _background;
    if (background == null) {
      _run.dispose();
    } else {
      _release(background);
    }
    _bookshelfTracker.dispose();
    // 存下的搜尋結果只在搜尋頁開著時有用（從結果進詳情後，換源與換封面先
    // 列出剛搜到的來源），離開搜尋頁就清掉，不在手機裡越積越多；接回的背景
    // 搜尋還沒看完時不清，之後還會回來看（ADR 0070）。
    if (background == null || background.isDone) {
      unawaited(getIt<SearchBookDao>().clearAll());
    }
    super.dispose();
  }
}
