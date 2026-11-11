import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ExploreKindsLoader = Future<List<ExploreKind>> Function(
  String? exploreUrl, {
  BookSource? source,
});

/// ExploreProvider - 發現主頁面的狀態管理
/// (對標 Android ExploreFragment + ExploreAdapter + ExploreViewModel)
///
/// 管理「書源列表 → 展開分類標籤」的互動。
class ExploreProvider extends ChangeNotifier {
  final BookSourceDao _sourceDao;
  final ExploreKindsLoader _kindsLoader;
  StreamSubscription<List<BookSource>>? _sourceSubscription;

  /// 所有參與發現的書源，不分類別。
  List<BookSource> _discoverable = [];

  /// 目前這一類（[kind]）的發現書源；分組與篩選都在這裡面。
  List<BookSource> _allSources = [];
  List<BookSource> _filteredSources = [];
  String _searchQuery = '';
  bool _isLoadingSources = true;
  String? _sourceLoadError;

  int _expandedIndex = -1;
  List<ExploreKind> _expandedKinds = [];
  bool _isLoadingKinds = false;
  int _kindsRequestGeneration = 0;

  List<String> _groups = [];
  Map<String, int> _groupCounts = {};
  String? _selectedGroup;

  /// 各類別的發現書源數；還沒讀到書源時是上次記下的。
  Map<BookSourceKind, int> _kindCounts = {};

  /// 使用者選的類別，記在 [_kindKey]；那一類沒有發現書源時 [kind] 改列
  /// 第一個有書源的類別，這裡不改。
  BookSourceKind _chosenKind = BookSourceKind.novel;

  /// 選的類別存在偏好設定的鍵，值是 [BookSourceKind.name]。
  static const String _kindKey = 'explore_source_kind';

  /// 切換書源類型時可選的類別，照小說、漫畫、有聲的順序。
  static const List<BookSourceKind> switchableKinds = [
    BookSourceKind.novel,
    BookSourceKind.comic,
    BookSourceKind.audio,
  ];

  final Map<String, List<ExploreKind>> _kindsCache = {};
  final Map<String, int> _latestKindsRequestByCacheKey = {};

  List<BookSource> get sources => _filteredSources;
  List<String> get groups => _groups;

  /// 清單列的是哪一類書源：選的那一類有發現書源就是它，否則是第一個有的。
  BookSourceKind get kind {
    if ((_kindCounts[_chosenKind] ?? 0) > 0) return _chosenKind;
    return kinds.firstOrNull ?? _chosenKind;
  }

  /// 有發現書源的類別；不只一類時頁首才有類型鈕。
  List<BookSourceKind> get kinds => [
    for (final kind in switchableKinds)
      if ((_kindCounts[kind] ?? 0) > 0) kind,
  ];

  /// 各類別的發現書源數。
  Map<BookSourceKind, int> get kindCounts => _kindCounts;

  /// 各分組內的發現書源數。
  Map<String, int> get groupCounts => _groupCounts;
  int get totalSourceCount => _allSources.length;

  /// 分組選單「全部」的書源數：還沒讀到書源時用上次記下的數字。
  int get allGroupCount => _isLoadingSources && _allSources.isEmpty
      ? _lastAllCount
      : totalSourceCount;
  int _lastAllCount = 0;

  /// 載入前用上次儲存的數量；第一次沒有紀錄時才交給骨架鋪滿畫面。
  /// 資料到齊後用這一輪篩出的真正列數。
  int? get skeletonSourceCount => _isLoadingSources && _allSources.isEmpty
      ? (_savedGroupRecord == null ? null : _lastAllCount)
      : _filteredSources.length;

  /// 上次讀完時的版面：目前這一類「全部」的書源數與各分組的名稱、書源數，
  /// 以及各類別的書源數，JSON `{"all": n, "groups": [[分組, 書源數], ...],
  /// "kinds": [[類別, 書源數], ...]}`（類別是 [BookSourceKind.name]）。開 App
  /// 建立時同步讀出，第一次讀到書源前照它決定頁首有沒有分組鈕與類型鈕，
  /// 不會讀完才長出來。沒有 `kinds` 的舊紀錄照樣用，類型鈕等書源讀完。鍵名
  /// 沿用分組還是一排膠囊時的名字。
  static const String _groupRecordKey = 'explore_filter_bar';

  /// 最後一次讀出或送去寫的內容。送出時就記下：寫入還沒完成又換回原本
  /// 那一類時，比的是最後送出的，不會以為舊的那份還在而略過。偏好設定照
  /// 送出的順序寫，最後送出的留下；寫入失敗時清掉，下次讀到書源再寫一次。
  String? _savedGroupRecord;
  String? get selectedGroup => _selectedGroup;
  int get expandedIndex => _expandedIndex;
  List<ExploreKind> get expandedKinds => _expandedKinds;
  bool get isLoadingKinds => _isLoadingKinds;
  bool get isLoadingSources => _isLoadingSources;
  String? get sourceLoadError => _sourceLoadError;
  String get searchQuery => _searchQuery;
  bool get isEmpty => _filteredSources.isEmpty;

  ExploreProvider({BookSourceDao? sourceDao, ExploreKindsLoader? kindsLoader})
    : _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
      _kindsLoader = kindsLoader ?? BookSourceService().exploreKinds {
    _readChosenKind();
    _readGroupRecord();
    _bindSources();
  }

  void _readChosenKind() {
    final stored = getIt<SharedPreferences>().get(_kindKey);
    _chosenKind = switchableKinds.firstWhere(
      (kind) => kind.name == stored,
      orElse: () => BookSourceKind.novel,
    );
  }

  void _readGroupRecord() {
    // 型別不對的紀錄（不是字串）和讀不懂的內容一樣，當作沒有紀錄。
    final stored = getIt<SharedPreferences>().get(_groupRecordKey);
    final saved = stored is String ? stored : null;
    _savedGroupRecord = saved;
    if (saved == null) {
      if (stored != null) AppLog.w('發現分組的紀錄型別不對，這次等書源讀完');
      return;
    }
    try {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      final counts = <String, int>{
        for (final entry in json['groups'] as List<dynamic>)
          entry[0] as String: entry[1] as int,
      };
      final all = json['all'] as int;
      final kinds = <BookSourceKind, int>{
        for (final entry in json['kinds'] as List<dynamic>? ?? const [])
          switchableKinds.firstWhere(
            (kind) => kind.name == entry[0],
            orElse: () => throw FormatException('不認得的類別', saved),
          ): entry[1] as int,
      };
      if (all < 0 ||
          counts.values.any((count) => count < 0) ||
          kinds.values.any((count) => count < 0)) {
        throw FormatException('書源數是負的', saved);
      }
      _lastAllCount = all;
      _groupCounts = counts;
      _groups = counts.keys.toList()..sort();
      _kindCounts = kinds;
    } catch (error) {
      AppLog.w('發現分組的紀錄讀不懂，這次等書源讀完: $error');
      // 當作沒有紀錄：骨架照第一次的樣子鋪滿畫面，不是畫 0 列。
      _savedGroupRecord = null;
      _lastAllCount = 0;
      _groupCounts = {};
      _groups = [];
      _kindCounts = {};
    }
  }

  void _rememberGroupRecord() {
    final encoded = jsonEncode({
      'all': _allSources.length,
      'groups': [
        for (final group in _groups) [group, _groupCounts[group]],
      ],
      'kinds': [
        for (final kind in kinds) [kind.name, _kindCounts[kind]],
      ],
    });
    if (_savedGroupRecord == encoded) return;
    _savedGroupRecord = encoded;
    unawaited(_saveGroupRecord(encoded));
  }

  Future<void> _saveGroupRecord(String encoded) async {
    var saved = false;
    try {
      saved = await getIt<SharedPreferences>().setString(
        _groupRecordKey,
        encoded,
      );
      if (!saved) AppLog.w('發現分組沒有寫進偏好設定');
    } catch (error, stackTrace) {
      AppLog.e('發現分組寫入失敗: $error', error: error, stackTrace: stackTrace);
    }
    if (!saved && _savedGroupRecord == encoded) _savedGroupRecord = null;
  }

  void _bindSources() {
    _sourceSubscription = _sourceDao.watchDiscoveryPart().listen(
      (sources) {
        _isLoadingSources = false;
        _sourceLoadError = null;
        _reloadFromSnapshot(sources);
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLog.e('載入發現書源失敗', error: error, stackTrace: stackTrace);
        _isLoadingSources = false;
        _sourceLoadError = '發現書源載入失敗';
        notifyListeners();
      },
    );
  }

  Future<void> _loadSources() async {
    _isLoadingSources = true;
    _sourceLoadError = null;
    notifyListeners();
    try {
      final allSources = await _sourceDao.getDiscoveryPart();
      _isLoadingSources = false;
      _reloadFromSnapshot(allSources);
    } catch (error, stackTrace) {
      AppLog.e('重新載入發現書源失敗', error: error, stackTrace: stackTrace);
      _isLoadingSources = false;
      _sourceLoadError = '發現書源載入失敗';
      notifyListeners();
    }
  }

  Future<BookSource?> getFullSource(String url) {
    return _sourceDao.getByUrl(url);
  }

  void _reloadFromSnapshot(List<BookSource> sources) {
    final expandedSource =
        _expandedIndex >= 0 && _expandedIndex < _filteredSources.length
        ? _filteredSources[_expandedIndex]
        : null;
    final expandedSourceUrl = expandedSource?.bookSourceUrl;
    final expandedCacheKey = expandedSource == null
        ? null
        : _cacheKeyForSource(expandedSource);
    final previousKind = kind;

    _discoverable =
        sources.where((source) => source.canParticipateInDiscovery).toList()
          ..sort((a, b) => a.customOrder.compareTo(b.customOrder));
    final kindCounts = <BookSourceKind, int>{};
    for (final source in _discoverable) {
      final kind = source.sourceKind;
      kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
    }
    _kindCounts = kindCounts;
    if (kind != previousKind) {
      // 列的類別跟著書源變了（那一類的書源停用、刪除或改了類型，或記下的
      // 那一類又有書源）：和從類型鈕換的一樣收起、重新篩。
      _switchKind();
      notifyListeners();
      return;
    }
    _selectKindSources();
    if (expandedSourceUrl != null) {
      final newIndex = _filteredSources.indexWhere(
        (source) => source.bookSourceUrl == expandedSourceUrl,
      );
      if (newIndex >= 0) {
        _expandedIndex = newIndex;
        final nextSource = _filteredSources[newIndex];
        final nextCacheKey = _cacheKeyForSource(nextSource);
        if (expandedCacheKey != nextCacheKey) {
          if (expandedCacheKey != null) {
            _kindsCache.remove(expandedCacheKey);
            _latestKindsRequestByCacheKey.remove(expandedCacheKey);
          }
          final requestGeneration = ++_kindsRequestGeneration;
          _expandedKinds = [];
          _isLoadingKinds = true;
          notifyListeners();
          unawaited(_loadKindsForSource(nextSource, requestGeneration));
          return;
        }
      } else {
        _invalidateKindsRequest();
        _expandedIndex = -1;
        _expandedKinds = [];
      }
    }
    notifyListeners();
  }

  /// 從 [_discoverable] 取出目前這一類，重算分組並記下版面。
  void _selectKindSources() {
    final kind = this.kind;
    _allSources = _discoverable
        .where((source) => source.sourceKind == kind)
        .toList();

    final counts = <String, int>{};
    for (final source in _allSources) {
      for (final group in splitSourceGroups(source.bookSourceGroup)) {
        counts[group] = (counts[group] ?? 0) + 1;
      }
    }
    _groupCounts = counts;
    _groups = counts.keys.toList()..sort();
    _rememberGroupRecord();
    // 選中的分組已不存在（書源被刪除、改分組或換了類別）時回到「全部」。
    if (_selectedGroup != null && !counts.containsKey(_selectedGroup)) {
      _selectedGroup = null;
    }

    _applyFilter();
  }

  /// 換成列 [kind] 這一類的書源，並記住選擇。展開的書源收起；選的分組在
  /// 這一類裡沒有就回到「全部」。
  void setKind(BookSourceKind kind) {
    if (!switchableKinds.contains(kind)) return;
    final changed = kind != this.kind;
    if (kind != _chosenKind) {
      _chosenKind = kind;
      unawaited(_saveChosenKind(kind));
    }
    if (!changed) return;
    _switchKind();
    notifyListeners();
  }

  /// 換成列 [kind] 這一類：清掉搜尋、收起展開的書源，再照這一類重新篩。
  void _switchKind() {
    _searchQuery = '';
    _invalidateKindsRequest();
    _expandedIndex = -1;
    _expandedKinds = [];
    if (_isLoadingSources && _discoverable.isEmpty) {
      // 還沒讀到書源，類型鈕是照上次的紀錄先出現的：記下的分組屬於上一類，
      // 拿掉；骨架照這一類記下的書源數。版面等讀到書源才記。
      _allSources = [];
      _filteredSources = [];
      _groups = [];
      _groupCounts = {};
      _selectedGroup = null;
      _lastAllCount = _kindCounts[kind] ?? 0;
      return;
    }
    _selectKindSources();
  }

  Future<void> _saveChosenKind(BookSourceKind kind) async {
    try {
      if (!await getIt<SharedPreferences>().setString(_kindKey, kind.name)) {
        AppLog.w('發現的書源類型沒有寫進偏好設定');
      }
    } catch (error, stackTrace) {
      AppLog.e('發現的書源類型寫入失敗: $error', error: error, stackTrace: stackTrace);
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _invalidateKindsRequest();
    _expandedIndex = -1;
    _expandedKinds = [];
    _applyFilter();
    notifyListeners();
  }

  void setGroupFilter(String? group) {
    // 選單開著時書源可能剛讀完、這個分組已經不在：不接受，免得整個清單被
    // 濾空。重讀書源時也會把不存在的分組清掉（見上面）。
    if (group != null && !_groupCounts.containsKey(group)) return;
    if (_selectedGroup == group) {
      _selectedGroup = null;
    } else {
      _selectedGroup = group;
    }
    _searchQuery = '';
    _invalidateKindsRequest();
    _expandedIndex = -1;
    _expandedKinds = [];
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    if (_selectedGroup != null) {
      _filteredSources = _allSources
          .where(
            (source) =>
                splitSourceGroups(source.bookSourceGroup)
                    .contains(_selectedGroup),
          )
          .toList();
    } else if (_searchQuery.isNotEmpty) {
      final key = _searchQuery.toLowerCase();
      _filteredSources = _allSources.where((source) {
        return source.bookSourceName.toLowerCase().contains(key) ||
            (source.bookSourceGroup?.toLowerCase().contains(key) ?? false);
      }).toList();
    } else {
      _filteredSources = List.from(_allSources);
    }
  }

  Future<void> toggleExpand(int index) async {
    if (_expandedIndex == index) {
      _invalidateKindsRequest();
      _expandedIndex = -1;
      _expandedKinds = [];
      notifyListeners();
      return;
    }

    _expandedIndex = index;
    _expandedKinds = [];
    _isLoadingKinds = true;
    final requestGeneration = ++_kindsRequestGeneration;
    notifyListeners();

    final source = _filteredSources[index];
    await _loadKindsForSource(source, requestGeneration);
  }

  Future<void> _loadKindsForSource(
    BookSource source,
    int requestGeneration,
  ) async {
    final cacheKey = _cacheKeyForSource(source);
    _latestKindsRequestByCacheKey[cacheKey] = requestGeneration;

    if (_kindsCache.containsKey(cacheKey)) {
      if (_isCurrentKindsRequest(source, requestGeneration)) {
        _expandedKinds = _kindsCache[cacheKey]!;
        _isLoadingKinds = false;
        notifyListeners();
      }
      return;
    }

    try {
      final kinds = await _kindsLoader(source.exploreUrl, source: source);
      // 解析失敗時解析器回傳 ERROR: 分類而不丟例外；這種結果不快取，
      // 收合再展開就會重新請求。
      final failed = kinds.any((kind) => kind.title.startsWith('ERROR:'));
      if (!failed &&
          _latestKindsRequestByCacheKey[cacheKey] == requestGeneration) {
        _kindsCache[cacheKey] = kinds;
      }
      if (_isCurrentKindsRequest(source, requestGeneration)) {
        _expandedKinds = kinds;
      }
    } catch (error) {
      AppLog.e('載入探索分類失敗', error: error);
      if (_isCurrentKindsRequest(source, requestGeneration)) {
        _expandedKinds = [
          ExploreKind(title: 'ERROR:$error', url: error.toString()),
        ];
      }
    } finally {
      if (_isCurrentKindsRequest(source, requestGeneration)) {
        _isLoadingKinds = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentKindsRequest(BookSource source, int requestGeneration) {
    return requestGeneration == _kindsRequestGeneration &&
        _expandedIndex >= 0 &&
        _expandedIndex < _filteredSources.length &&
        _cacheKeyForSource(_filteredSources[_expandedIndex]) ==
            _cacheKeyForSource(source);
  }

  void _invalidateKindsRequest() {
    _kindsRequestGeneration++;
    _isLoadingKinds = false;
  }

  String _cacheKeyForSource(BookSource source) {
    return '${source.bookSourceUrl}\n${source.exploreUrl ?? ''}';
  }

  Future<void> refreshKindsCache(BookSource source) async {
    final cacheKey = _cacheKeyForSource(source);
    _kindsCache.remove(cacheKey);
    _latestKindsRequestByCacheKey.remove(cacheKey);
    await ExploreUrlParser.clearCache(source, exploreUrl: source.exploreUrl);
    if (_expandedIndex >= 0 &&
        _expandedIndex < _filteredSources.length &&
        _filteredSources[_expandedIndex].bookSourceUrl ==
            source.bookSourceUrl) {
      final requestGeneration = ++_kindsRequestGeneration;
      _isLoadingKinds = true;
      _expandedKinds = [];
      notifyListeners();
      await _loadKindsForSource(source, requestGeneration);
    }
  }

  Future<void> topSource(BookSource source) async {
    final minOrder = _discoverable.isEmpty
        ? 0
        : _discoverable
              .map((item) => item.customOrder)
              .reduce((a, b) => a < b ? a : b);
    // 清單由 watchDiscoveryPart 推送新快照更新，不必整頁重新載入。
    await _sourceDao.updateCustomOrderByUrl(source.bookSourceUrl, minOrder - 1);
  }

  Future<void> deleteSource(BookSource source) async {
    await _sourceDao.deleteByUrl(source.bookSourceUrl);
    _kindsCache.removeWhere(
      (cacheKey, _) => cacheKey.startsWith('${source.bookSourceUrl}\n'),
    );
    _latestKindsRequestByCacheKey.removeWhere(
      (cacheKey, _) => cacheKey.startsWith('${source.bookSourceUrl}\n'),
    );
  }

  Future<void> refresh() async {
    _expandedIndex = -1;
    _expandedKinds = [];
    await _loadSources();
  }

  @override
  void dispose() {
    _kindsRequestGeneration++;
    _sourceSubscription?.cancel();
    super.dispose();
  }
}
