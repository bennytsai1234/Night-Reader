import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/services/app_log_service.dart';

typedef ExploreKindsLoader =
    Future<List<ExploreKind>> Function(
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

  // --- 書源列表 ---
  List<BookSource> _allSources = [];
  List<BookSource> _filteredSources = [];
  String _searchQuery = '';

  // --- 展開狀態 (同一時間只展開一個書源) ---
  int _expandedIndex = -1;
  List<ExploreKind> _expandedKinds = [];
  bool _isLoadingKinds = false;
  int _kindsRequestGeneration = 0;

  // --- 分組 ---
  List<String> _groups = [];
  String? _selectedGroup;

  // --- ExploreKind 快取 (對標 Android exploreKindsMap) ---
  // Legado 以 bookSourceUrl + exploreUrl 作為分類快取鍵，規則變更後會自動
  // 重新解析，不會沿用舊分類。
  final Map<String, List<ExploreKind>> _kindsCache = {};
  final Map<String, int> _latestKindsRequestByCacheKey = {};

  // --- Getters ---
  List<BookSource> get sources => _filteredSources;
  List<String> get groups => _groups;
  String? get selectedGroup => _selectedGroup;
  int get expandedIndex => _expandedIndex;
  List<ExploreKind> get expandedKinds => _expandedKinds;
  bool get isLoadingKinds => _isLoadingKinds;
  String get searchQuery => _searchQuery;
  bool get isEmpty => _filteredSources.isEmpty;

  ExploreProvider({BookSourceDao? sourceDao, ExploreKindsLoader? kindsLoader})
    : _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
      _kindsLoader = kindsLoader ?? ExploreUrlParser.parseAsync {
    _bindSources();
  }

  void _bindSources() {
    _sourceSubscription = _sourceDao.watchDiscoveryPart().listen((sources) {
      _reloadFromSnapshot(sources);
    });
  }

  /// 載入所有啟用探索的書源
  Future<void> _loadSources() async {
    final allSources = await _sourceDao.getDiscoveryPart();
    _reloadFromSnapshot(allSources);
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
    final expandedCacheKey =
        expandedSource == null ? null : _cacheKeyForSource(expandedSource);

    _allSources =
        sources.where((source) => source.canParticipateInDiscovery).toList()
          ..sort((a, b) => a.customOrder.compareTo(b.customOrder));

    // 提取分組
    final groupSet = <String>{};
    for (final s in _allSources) {
      if (s.bookSourceGroup != null && s.bookSourceGroup!.isNotEmpty) {
        for (final g in s.bookSourceGroup!.split(RegExp(r'[,，]'))) {
          final trimmed = g.trim();
          if (trimmed.isNotEmpty) groupSet.add(trimmed);
        }
      }
    }
    _groups = groupSet.toList()..sort();

    _applyFilter();
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

  /// 搜索過濾 (對標 Android SearchView onQueryTextChange)
  void setSearchQuery(String query) {
    _searchQuery = query;
    _invalidateKindsRequest();
    _expandedIndex = -1;
    _expandedKinds = [];
    _applyFilter();
    notifyListeners();
  }

  /// 分組過濾 (對標 Android groupsMenu)
  void setGroupFilter(String? group) {
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

  /// 應用過濾邏輯
  void _applyFilter() {
    if (_selectedGroup != null) {
      // 按分組過濾 (對標 Android flowGroupExplore)
      _filteredSources =
          _allSources.where((s) {
            if (s.bookSourceGroup == null) return false;
            final groups = s.bookSourceGroup!
                .split(RegExp(r'[,，]'))
                .map((e) => e.trim());
            return groups.contains(_selectedGroup);
          }).toList();
    } else if (_searchQuery.isNotEmpty) {
      // 按關鍵字過濾 (對標 Android flowExplore(key))
      final key = _searchQuery.toLowerCase();
      _filteredSources =
          _allSources.where((s) {
            return s.bookSourceName.toLowerCase().contains(key) ||
                (s.bookSourceGroup?.toLowerCase().contains(key) ?? false);
          }).toList();
    } else {
      _filteredSources = List.from(_allSources);
    }
  }

  /// 展開/收合書源 (對標 Android ExploreAdapter llTitle.setOnClickListener)
  Future<void> toggleExpand(int index) async {
    if (_expandedIndex == index) {
      // 收合
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

  /// 為書源載入分類標籤 (帶快取，對標 Android exploreKinds())
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
      if (_latestKindsRequestByCacheKey[cacheKey] == requestGeneration) {
        _kindsCache[cacheKey] = kinds;
      }
      if (_isCurrentKindsRequest(source, requestGeneration)) {
        _expandedKinds = kinds;
      }
    } catch (e) {
      AppLog.e('載入探索分類失敗', error: e);
      if (_isCurrentKindsRequest(source, requestGeneration)) {
        _expandedKinds = [
          ExploreKind(title: 'ERROR:${e.toString()}', url: e.toString()),
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

  /// 刷新分類快取 (對標 Android menu_refresh / clearExploreKindsCache)
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

  /// 置頂書源 (對標 Android ExploreViewModel.topSource)
  Future<void> topSource(BookSource source) async {
    final minOrder =
        _allSources.isEmpty
            ? 0
            : _allSources
                .map((s) => s.customOrder)
                .reduce((a, b) => a < b ? a : b);
    await _sourceDao.updateCustomOrderByUrl(source.bookSourceUrl, minOrder - 1);
    await _loadSources();
  }

  /// 刪除書源 (對標 Android ExploreViewModel.deleteSource)
  Future<void> deleteSource(BookSource source) async {
    await _sourceDao.deleteByUrl(source.bookSourceUrl);
    _kindsCache.removeWhere(
      (cacheKey, _) => cacheKey.startsWith('${source.bookSourceUrl}\n'),
    );
    _latestKindsRequestByCacheKey.removeWhere(
      (cacheKey, _) => cacheKey.startsWith('${source.bookSourceUrl}\n'),
    );
    await _loadSources();
  }

  /// 重新載入所有書源
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
