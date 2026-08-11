import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets/import_preview_dialog.dart';

String _normalizeImportJson(String value) {
  var normalized = value.trim();
  while (normalized.isNotEmpty && normalized.codeUnitAt(0) == 0xFEFF) {
    normalized = normalized.substring(1).trim();
  }
  return normalized;
}

Map<String, List<Map<String, dynamic>>> _parseSourcesPayloadForIsolate(
  String jsonStr,
) {
  final normalized = _normalizeImportJson(jsonStr);
  if (normalized.isEmpty) {
    throw const FormatException('匯入內容為空');
  }
  final decoded = jsonDecode(normalized);
  final List<dynamic> list = decoded is List ? decoded : [decoded];
  final importable = <Map<String, dynamic>>[];
  final unsupported = <Map<String, dynamic>>[];
  for (final e in list) {
    if (e is! Map<String, dynamic>) continue;
    final source = BookSource.fromJson(e);
    if (source.bookSourceUrl.isEmpty || source.bookSourceName.isEmpty) {
      continue;
    }
    if (!source.isNovelTextSource) {
      source.enabled = false;
      source.enabledExplore = false;
      source.addGroup(nonNovelSourceGroupTag);
      unsupported.add(source.toJson());
      continue;
    }
    importable.add(source.toJson());
  }
  return <String, List<Map<String, dynamic>>>{
    'importable': importable,
    'unsupported': unsupported,
  };
}

class ParsedSourceImportResult {
  final List<BookSource> importableSources;
  final List<BookSource> unsupportedSources;

  const ParsedSourceImportResult({
    required this.importableSources,
    required this.unsupportedSources,
  });

  List<BookSource> get allSources => <BookSource>[
    ...importableSources,
    ...unsupportedSources,
  ];
}

class SourceImportService {
  SourceImportService({BookSourceDao? dao, NetworkService? networkService})
    : _dao = dao ?? getIt<BookSourceDao>(),
      _networkService = networkService;

  final BookSourceDao _dao;
  NetworkService? _networkService;

  NetworkService get _network => _networkService ??= getIt<NetworkService>();

  /// 解析 JSON 字串為書源列表 (不匯入)
  List<BookSource> parseSources(String jsonStr) {
    return parseSourcesDetailed(jsonStr).allSources;
  }

  Future<ParsedSourceImportResult> parseSourcesDetailedAsync(
    String jsonStr,
  ) async {
    final payload = await compute(_parseSourcesPayloadForIsolate, jsonStr);
    List<BookSource> decodeList(String key) {
      final rawList = payload[key] ?? const <Map<String, dynamic>>[];
      return rawList
          .map((item) => BookSource.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    }

    return ParsedSourceImportResult(
      importableSources: decodeList('importable'),
      unsupportedSources: decodeList('unsupported'),
    );
  }

  ParsedSourceImportResult parseSourcesDetailed(String jsonStr) {
    final payload = _parseSourcesPayloadForIsolate(jsonStr);
    List<BookSource> decodeList(String key) {
      final rawList = payload[key] ?? const <Map<String, dynamic>>[];
      return rawList
          .map((item) => BookSource.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    }

    return ParsedSourceImportResult(
      importableSources: decodeList('importable'),
      unsupportedSources: decodeList('unsupported'),
    );
  }

  /// 預覽匯入：分類為新增、更新、無變化
  Future<ImportPreviewResult> previewImport(
    List<BookSource> incoming, {
    List<BookSource> unsupportedSources = const <BookSource>[],
  }) async {
    final newSources = <BookSource>[];
    final updatedSources = <BookSource>[];
    final unchangedSources = <BookSource>[];
    final existingByUrl = <String, int>{};
    for (final source in await _dao.getAllPart()) {
      existingByUrl[source.bookSourceUrl] = source.lastUpdateTime;
    }

    for (final s in incoming) {
      final existingUpdateTime = existingByUrl[s.bookSourceUrl];
      if (existingUpdateTime == null) {
        newSources.add(s);
      } else if (existingUpdateTime != s.lastUpdateTime) {
        updatedSources.add(s);
      } else {
        unchangedSources.add(s);
      }
    }

    return ImportPreviewResult(
      newSources: newSources,
      updatedSources: updatedSources,
      unchangedSources: unchangedSources,
      unsupportedSources: unsupportedSources,
    );
  }

  Future<int> importSources(List<BookSource> sources) async {
    if (sources.isEmpty) return 0;
    final preparedSources = await _prepareImportSources(sources);
    await _dao.insertOrUpdateAll(preparedSources);
    return preparedSources.length;
  }

  Future<int> importFromJson(String jsonStr) async {
    try {
      final parsed = await parseSourcesDetailedAsync(jsonStr);
      if (parsed.allSources.isEmpty) return 0;
      return importSources(parsed.allSources);
    } catch (_) {
      return 0;
    }
  }

  Future<int> importFromUrl(String url) async {
    try {
      final text = await fetchImportTextFromUrl(url);
      return await importFromJson(text);
    } catch (_) {}
    return 0;
  }

  Future<String> fetchImportTextFromUrl(String url) async {
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw FormatException('無效的匯入網址', url);
    }

    final response = await _network.dio.getUri<dynamic>(
      uri,
      options: Options(responseType: ResponseType.plain),
    );
    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw StateError('匯入網址回應異常：HTTP $statusCode');
    }
    return _importPayloadToText(response.data);
  }

  @visibleForTesting
  String importPayloadToTextForTest(dynamic data) => _importPayloadToText(data);

  Future<List<BookSource>> _prepareImportSources(
    List<BookSource> sources,
  ) async {
    final orderByUrl = <String, int>{};
    var maxOrder = -1;
    for (final source in await _dao.getAllPart()) {
      orderByUrl[source.bookSourceUrl] = source.customOrder;
      if (source.customOrder > maxOrder) {
        maxOrder = source.customOrder;
      }
    }

    final assignedOrderByUrl = Map<String, int>.from(orderByUrl);
    var nextOrder = maxOrder + 1;
    for (final source in sources) {
      final existingOrder = assignedOrderByUrl[source.bookSourceUrl];
      if (existingOrder != null) {
        source.customOrder = existingOrder;
      } else {
        source.customOrder = nextOrder++;
        assignedOrderByUrl[source.bookSourceUrl] = source.customOrder;
      }
    }
    return sources;
  }

  String _importPayloadToText(dynamic data) {
    if (data == null) return '';
    if (data is String) {
      return _stripBom(data);
    }
    if (data is Uint8List) {
      return _stripBom(utf8.decode(data, allowMalformed: true));
    }
    if (data is List<int>) {
      return _stripBom(utf8.decode(data, allowMalformed: true));
    }
    return jsonEncode(data);
  }

  String _stripBom(String value) {
    return _normalizeImportJson(value);
  }
}

class SourceManagerProvider with ChangeNotifier {
  final BookSourceDao _dao = getIt<BookSourceDao>();
  final SourceImportService _importService;
  final CheckSourceService checkService;

  List<BookSourcePart> _sources = [];
  List<BookSourcePart>? _visibleSourcesCache;
  bool _visibleSourcesDirty = true;
  bool _disposed = false;
  int _loadGeneration = 0;
  Object? _loadError;

  String filterGroup = '全部';
  String _searchQuery = '';
  int sortMode = 0;
  bool sortDesc = false;
  bool groupByDomain = false;
  Timer? _checkNotifyTimer;
  SourceCheckReport get lastCheckReport => checkService.lastReport;
  bool get hasLastCheckReport => checkService.hasLastReport;
  SourceCheckConfig get checkConfig => checkService.config;
  int get totalSourceCount => _sources.length;
  String? get loadErrorMessage => _loadError == null ? null : '載入書源失敗，請稍後重試';

  List<BookSourcePart> get sources {
    if (_visibleSourcesDirty || _visibleSourcesCache == null) {
      _visibleSourcesCache = List<BookSourcePart>.unmodifiable(
        _computeVisibleSources(),
      );
      _visibleSourcesDirty = false;
    }
    return _visibleSourcesCache!;
  }

  List<BookSourcePart> _computeVisibleSources() {
    var list = List<BookSourcePart>.from(_sources);

    // 全文搜尋
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list =
          list
              .where(
                (s) =>
                    s.bookSourceName.toLowerCase().contains(q) ||
                    s.bookSourceUrl.toLowerCase().contains(q) ||
                    (s.bookSourceComment?.toLowerCase().contains(q) ?? false),
              )
              .toList();
    }

    if (filterGroup == '已啟用') {
      list = list.where((s) => s.enabled).toList();
    } else if (filterGroup == '已禁用') {
      list = list.where((s) => !s.enabled).toList();
    } else if (filterGroup == '已啟用發現') {
      list = list.where((s) => s.enabledExplore && s.hasExploreUrl).toList();
    } else if (filterGroup == '已禁用發現') {
      list = list.where((s) => !s.enabledExplore && s.hasExploreUrl).toList();
    } else if (filterGroup == '無分組') {
      list =
          list.where((s) => _groupLabels(s.bookSourceGroup).isEmpty).toList();
    } else if (filterGroup != '全部') {
      list =
          list.where((s) => _hasGroup(s.bookSourceGroup, filterGroup)).toList();
    }

    final comparator = _buildComparator();
    if (groupByDomain) {
      list.sort((a, b) {
        final hostCompare = getSourceHost(
          a.bookSourceUrl,
        ).compareTo(getSourceHost(b.bookSourceUrl));
        if (hostCompare != 0) {
          return hostCompare;
        }
        return comparator(a, b);
      });
    } else {
      list.sort(comparator);
    }
    return list;
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _isBatchOperationInProgress = false;
  bool get isBatchOperationInProgress => _isBatchOperationInProgress;
  final Set<String> _pendingSourceMutations = <String>{};
  bool get _hasActiveMutation =>
      _isBatchOperationInProgress ||
      checkService.isChecking ||
      _pendingSourceMutations.isNotEmpty;
  bool get isMutationBusy => _isLoading || _hasActiveMutation;
  bool get canReorder =>
      sortMode == 0 &&
      !sortDesc &&
      !groupByDomain &&
      filterGroup == '全部' &&
      _searchQuery.isEmpty &&
      sources.length == _sources.length &&
      !isMutationBusy;
  final Set<String> _selectedUrls = {};
  Set<String> get selectedUrls => Set<String>.unmodifiable(_selectedUrls);
  List<String> _allGroups = [];
  List<String> get allGroups => List<String>.unmodifiable(_allGroups);

  SourceManagerProvider({
    SourceImportService? importService,
    CheckSourceService? sourceCheckService,
  }) : _importService = importService ?? SourceImportService(),
       checkService = sourceCheckService ?? CheckSourceService() {
    checkService.addListener(_handleCheckServiceChanged);
    loadSources();
    checkService.loadConfig();
  }

  void _handleCheckServiceChanged() {
    if (_disposed) return;
    if (!checkService.isChecking) {
      _checkNotifyTimer?.cancel();
      _checkNotifyTimer = null;
      notifyListeners();
      return;
    }

    if (_checkNotifyTimer?.isActive ?? false) return;
    _checkNotifyTimer = Timer(const Duration(milliseconds: 500), () {
      _checkNotifyTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _checkNotifyTimer?.cancel();
    checkService.removeListener(_handleCheckServiceChanged);
    checkService.cancel();
    checkService.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> loadSources({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final loadedSources = await _dao.getAllPart();
      if (_disposed || generation != _loadGeneration) return;
      _sources = loadedSources;
      _selectedUrls.retainAll(
        loadedSources.map((source) => source.bookSourceUrl).toSet(),
      );
      _loadError = null;
      _updateGroups();
      _markVisibleSourcesDirty();
    } catch (error) {
      if (!_disposed && generation == _loadGeneration) {
        _loadError = error;
        _markVisibleSourcesDirty();
      }
    } finally {
      if (showLoading && !_disposed && generation == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 獲取完整書源 (用於編輯或調試)
  Future<BookSource?> getFullSource(String url) => _dao.getByUrl(url);

  void _updateGroups() {
    final groupSet = <String>{};
    for (var s in _sources) {
      if (s.bookSourceGroup != null && s.bookSourceGroup!.isNotEmpty) {
        groupSet.addAll(_groupLabels(s.bookSourceGroup));
      }
    }
    _allGroups = groupSet.toList()..sort();
  }

  void setFilterGroup(String group) {
    filterGroup = group.trim();
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  void setSortMode(int mode) {
    sortMode = mode;
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  void toggleSortDesc() {
    sortDesc = !sortDesc;
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  void toggleGroupByDomain() {
    groupByDomain = !groupByDomain;
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  String getSourceHost(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.trim();
      return host.isEmpty ? '其他' : host;
    } catch (_) {
      return '其他';
    }
  }

  bool shouldShowHostHeaderAt(int index) {
    final visible = sources;
    if (!groupByDomain || index < 0 || index >= visible.length) {
      return false;
    }
    if (index == 0) {
      return true;
    }
    return getSourceHost(visible[index - 1].bookSourceUrl) !=
        getSourceHost(visible[index].bookSourceUrl);
  }

  void toggleSelect(String url) {
    if (_selectedUrls.contains(url)) {
      _selectedUrls.remove(url);
    } else {
      _selectedUrls.add(url);
    }
    notifyListeners();
  }

  void selectAll() {
    final visibleUrls = sources.map((source) => source.bookSourceUrl).toSet();
    if (visibleUrls.isEmpty) return;
    if (visibleUrls.every(_selectedUrls.contains)) {
      _selectedUrls.removeAll(visibleUrls);
    } else {
      _selectedUrls.addAll(visibleUrls);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedUrls.isEmpty) return;
    _selectedUrls.clear();
    notifyListeners();
  }

  void cancelSourceCheck() {
    checkService.cancel();
    clearSelection();
  }

  /// 反選 (對標 legado revertSelection)
  void revertSelection() {
    final visibleUrls = sources.map((s) => s.bookSourceUrl).toSet();
    final selectedVisible = visibleUrls.intersection(_selectedUrls);
    _selectedUrls.removeAll(selectedVisible);
    _selectedUrls.addAll(visibleUrls.difference(selectedVisible));
    notifyListeners();
  }

  Future<void> toggleEnabled(dynamic source) async {
    final String url = source.bookSourceUrl;
    final index = _sources.indexWhere((s) => s.bookSourceUrl == url);
    if (index < 0 || !_beginSourceMutation(url)) return;
    final nextEnabled = !_sources[index].enabled;
    try {
      await _dao.updateEnabledByUrl(url, nextEnabled);
      final currentIndex = _sources.indexWhere((s) => s.bookSourceUrl == url);
      if (currentIndex >= 0) {
        _sources[currentIndex].enabled = nextEnabled;
        _refreshVisibleSources();
      }
    } finally {
      _endSourceMutation(url);
    }
  }

  Future<void> toggleEnabledExplore(dynamic source) async {
    final String url = source.bookSourceUrl;
    final index = _sources.indexWhere((s) => s.bookSourceUrl == url);
    if (index < 0 || !_beginSourceMutation(url)) return;
    final nextEnabledExplore = !_sources[index].enabledExplore;
    try {
      await _dao.updateEnabledExploreByUrl(url, nextEnabledExplore);
      final currentIndex = _sources.indexWhere((s) => s.bookSourceUrl == url);
      if (currentIndex >= 0) {
        _sources[currentIndex].enabledExplore = nextEnabledExplore;
        _refreshVisibleSources();
      }
    } finally {
      _endSourceMutation(url);
    }
  }

  Future<void> deleteSource(dynamic source) async {
    final String url = source.bookSourceUrl;
    if (!_beginSourceMutation(url)) return;
    try {
      await _dao.deleteByUrl(url);
      _selectedUrls.remove(url);
      await loadSources();
    } finally {
      _endSourceMutation(url);
    }
  }

  Future<void> deleteSelected() async {
    final selected = Set<String>.from(_selectedUrls);
    if (selected.isEmpty || !_beginBatchOperation()) return;
    try {
      await _dao.deleteByUrls(selected.toList(growable: false));
      _selectedUrls.removeAll(selected);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> batchSetEnabled(bool enabled) async {
    if (_selectedUrls.isEmpty || !_beginBatchOperation()) return;
    final urls = _selectedUrls.toList(growable: false);
    try {
      await _dao.updateEnabledByUrls(urls, enabled);
      final selected = urls.toSet();
      for (final source in _sources) {
        if (selected.contains(source.bookSourceUrl)) {
          source.enabled = enabled;
        }
      }
      _refreshVisibleSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> batchSetEnabledExplore(bool enabled) async {
    if (_selectedUrls.isEmpty || !_beginBatchOperation()) return;
    final urls = _selectedUrls.toList(growable: false);
    try {
      await _dao.updateEnabledExploreByUrls(urls, enabled);
      final selected = urls.toSet();
      for (final source in _sources) {
        if (selected.contains(source.bookSourceUrl)) {
          source.enabledExplore = enabled;
        }
      }
      _refreshVisibleSources();
    } finally {
      _endBatchOperation();
    }
  }

  void checkSelectedInterval() {
    if (_selectedUrls.length < 2) return;
    final visibleSources = sources;
    final selectedIndices =
        visibleSources
            .asMap()
            .entries
            .where((entry) => _selectedUrls.contains(entry.value.bookSourceUrl))
            .map((entry) => entry.key)
            .toList()
          ..sort();
    if (selectedIndices.length < 2) return;
    final start = selectedIndices.first;
    final end = selectedIndices.last;
    for (var index = start; index <= end; index++) {
      _selectedUrls.add(visibleSources[index].bookSourceUrl);
    }
    notifyListeners();
  }

  Future<void> moveSelectedToTop() async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    if (selectedUrls.isEmpty || !_beginBatchOperation()) return;
    try {
      final all = await _dao.getAll();
      all.sort((a, b) => a.customOrder.compareTo(b.customOrder));
      final selected =
          all.where((s) => selectedUrls.contains(s.bookSourceUrl)).toList();
      final rest =
          all.where((s) => !selectedUrls.contains(s.bookSourceUrl)).toList();
      final reordered = [...selected, ...rest];
      await _dao.updateCustomOrder(reordered);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> moveSelectedToBottom() async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    if (selectedUrls.isEmpty || !_beginBatchOperation()) return;
    try {
      final all = await _dao.getAll();
      all.sort((a, b) => a.customOrder.compareTo(b.customOrder));
      final selected =
          all.where((s) => selectedUrls.contains(s.bookSourceUrl)).toList();
      final rest =
          all.where((s) => !selectedUrls.contains(s.bookSourceUrl)).toList();
      final reordered = [...rest, ...selected];
      await _dao.updateCustomOrder(reordered);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> moveToTop(String url) async {
    if (!_beginSourceMutation(url)) return;
    try {
      final all = await _dao.getAll();
      all.sort((a, b) => a.customOrder.compareTo(b.customOrder));
      final idx = all.indexWhere((s) => s.bookSourceUrl == url);
      if (idx <= 0) return;
      final item = all.removeAt(idx);
      all.insert(0, item);
      await _dao.updateCustomOrder(all);
      await loadSources();
    } finally {
      _endSourceMutation(url);
    }
  }

  Future<void> moveToBottom(String url) async {
    if (!_beginSourceMutation(url)) return;
    try {
      final all = await _dao.getAll();
      all.sort((a, b) => a.customOrder.compareTo(b.customOrder));
      final idx = all.indexWhere((s) => s.bookSourceUrl == url);
      if (idx < 0 || idx == all.length - 1) return;
      final item = all.removeAt(idx);
      all.add(item);
      await _dao.updateCustomOrder(all);
      await loadSources();
    } finally {
      _endSourceMutation(url);
    }
  }

  /// 通用分享方法：按 URL 集合分享書源 (對標 Android 分享)
  Future<void> shareSourcesByUrls(
    Set<String> urls, {
    String fileName = 'sources',
  }) async {
    final requestedUrls = Set<String>.from(urls);
    if (requestedUrls.isEmpty) return;

    final sources = <BookSource>[];
    for (var url in requestedUrls) {
      final full = await _dao.getByUrl(url);
      if (full != null) sources.add(full);
    }

    if (sources.isEmpty) return;
    await _shareSourceObjects(sources, fileName: fileName);
  }

  Future<void> _shareSourceObjects(
    List<BookSource> sources, {
    String fileName = 'sources',
  }) async {
    final jsonStr = jsonEncode(sources.map((s) => s.toJson()).toList());
    final baseName = sanitizeExportBaseName(fileName);
    final file = await AppStoragePaths.shareExportFile('$baseName.json');
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: '分享夜讀書源 ($baseName.json)'),
    );
  }

  @visibleForTesting
  static String sanitizeExportBaseName(String fileName) {
    var baseName =
        fileName
            .replaceAll(RegExp(r'\.(legado|json)$', caseSensitive: false), '')
            .trim()
            .replaceAll(RegExp(r'[\x00-\x1F\x7F\\/:*?"<>|]'), '_')
            .trim();
    if (baseName.isEmpty || baseName == '.' || baseName == '..') {
      baseName = 'source';
    }
    return baseName;
  }

  /// 批量分享目前選中的書源
  Future<void> shareSelectedSources() async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    if (selectedUrls.isEmpty) return;
    String fileName;
    if (selectedUrls.length == 1) {
      final source = await _dao.getByUrl(selectedUrls.single);
      fileName = source?.bookSourceName ?? 'source';
    } else {
      fileName = 'export_${selectedUrls.length}_sources';
    }
    await shareSourcesByUrls(selectedUrls, fileName: fileName);
  }

  Future<bool> exportSelected() async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    final selectedFullSources = <BookSource>[];
    for (var url in selectedUrls) {
      final full = await _dao.getByUrl(url);
      if (full != null) selectedFullSources.add(full);
    }
    final json = jsonEncode(
      selectedFullSources.map((s) => s.toJson()).toList(),
    );
    // Android Binder IPC 上限約 1 MB；超過時改走檔案分享。
    const clipboardSafeBytes = 512 * 1024;
    if (shouldShareExportPayload(json, limitBytes: clipboardSafeBytes)) {
      final fileName =
          selectedFullSources.length == 1
              ? selectedFullSources.first.bookSourceName
              : 'export_${selectedFullSources.length}_sources';
      await _shareSourceObjects(selectedFullSources, fileName: fileName);
      return false; // false = 已改走分享，非剪貼簿
    }
    await Clipboard.setData(ClipboardData(text: json));
    return true; // true = 已複製至剪貼簿
  }

  @visibleForTesting
  static bool shouldShareExportPayload(
    String value, {
    int limitBytes = 512 * 1024,
  }) => utf8.encode(value).length > limitBytes;

  Future<void> reorderSource(int oldIndex, int newIndex) async {
    final list = List<BookSourcePart>.from(sources);
    if (!canReorder ||
        oldIndex < 0 ||
        oldIndex >= list.length ||
        newIndex < 0 ||
        newIndex > list.length ||
        !_beginBatchOperation()) {
      return;
    }
    try {
      final item = list.removeAt(oldIndex);
      list.insert(newIndex.clamp(0, list.length), item);
      await _dao.updateCustomOrder(list);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> addGroup(String name) async {
    final normalizedName = name.trim();
    if (isMutationBusy ||
        normalizedName.isEmpty ||
        _allGroups.contains(normalizedName)) {
      return;
    }
    // 這裡只需要更新本地緩存並刷新即可
    _allGroups.add(normalizedName);
    _allGroups.sort();
    notifyListeners();
  }

  Future<void> renameGroup(String oldName, String newName) async {
    final normalizedOldName = oldName.trim();
    final normalizedNewName = newName.trim();
    if (normalizedNewName.isEmpty || normalizedOldName == normalizedNewName) {
      return;
    }
    if (!_beginBatchOperation()) return;
    try {
      await _dao.renameGroup(normalizedOldName, normalizedNewName);
      if (filterGroup == normalizedOldName) {
        filterGroup = normalizedNewName;
      }
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> deleteGroup(String name) async {
    if (!_beginBatchOperation()) return;
    try {
      await _dao.removeGroupLabel(name);
      if (filterGroup == name) filterGroup = '全部';
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> checkSelectedSources({SourceCheckConfig? config}) async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    if (selectedUrls.isEmpty || !_beginBatchOperation()) return;
    try {
      if (config != null) {
        await checkService.updateConfig(config);
      }
      await checkService.check(selectedUrls.toList(growable: false));
      await loadSources();
    } finally {
      _selectedUrls.removeAll(selectedUrls);
      _endBatchOperation();
    }
  }

  List<String> get groups => _allGroups;

  Future<void> selectionAddToGroups(Set<String> urls, String g) async {
    final normalizedGroup = g.trim();
    if (normalizedGroup.isEmpty) return;
    final selectedUrls = urls.toSet();
    if (selectedUrls.isEmpty || !_beginBatchOperation()) return;
    try {
      for (var url in selectedUrls) {
        final s = await _dao.getByUrl(url);
        if (s != null) {
          final groups =
              (s.bookSourceGroup ?? '')
                  .split(RegExp(r'[,，\s]+'))
                  .where((e) => e.isNotEmpty)
                  .toSet();
          groups.add(normalizedGroup);
          s.bookSourceGroup = groups.join(',');
          await _dao.upsert(s);
        }
      }
      _selectedUrls.removeAll(selectedUrls);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> selectionRemoveFromGroups(Set<String> urls, String g) async {
    final normalizedGroup = g.trim();
    if (normalizedGroup.isEmpty) return;
    final selectedUrls = urls.toSet();
    if (selectedUrls.isEmpty || !_beginBatchOperation()) return;
    try {
      for (var url in selectedUrls) {
        final s = await _dao.getByUrl(url);
        if (s != null) {
          final groups =
              (s.bookSourceGroup ?? '')
                  .split(RegExp(r'[,，\s]+'))
                  .where((e) => e.isNotEmpty)
                  .toSet();
          groups.remove(normalizedGroup);
          s.bookSourceGroup = groups.join(',');
          await _dao.upsert(s);
        }
      }
      _selectedUrls.removeAll(selectedUrls);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> clearInvalidSources() async {
    if (!_beginBatchOperation()) return;
    try {
      final all = await _dao.getAll();
      final urlsToDelete = <String>[];
      for (final s in all) {
        if (s.isCleanupCandidate) {
          urlsToDelete.add(s.bookSourceUrl);
        }
      }
      if (urlsToDelete.isNotEmpty) {
        await _dao.deleteByUrls(urlsToDelete);
        await loadSources();
      }
    } finally {
      _endBatchOperation();
    }
  }

  Future<int> deleteNonNovelSources() async {
    if (!_beginBatchOperation()) return 0;
    try {
      final all = await _dao.getAll();
      final urlsToDelete = <String>[];
      for (final source in all) {
        if (source.isNovelTextSource) continue;
        urlsToDelete.add(source.bookSourceUrl);
      }
      if (urlsToDelete.isNotEmpty) {
        await _dao.deleteByUrls(urlsToDelete);
        await loadSources();
      }
      return urlsToDelete.length;
    } finally {
      _endBatchOperation();
    }
  }

  Future<void> checkAllSources({SourceCheckConfig? config}) async {
    final urls = _sources.map((s) => s.bookSourceUrl).toList();
    if (urls.isEmpty || !_beginBatchOperation()) return;
    final selectedAtStart = Set<String>.from(_selectedUrls);
    try {
      if (config != null) {
        await checkService.updateConfig(config);
      }
      await checkService.check(urls);
      await loadSources();
    } finally {
      _selectedUrls.removeAll(selectedAtStart);
      _endBatchOperation();
    }
  }

  Future<void> deleteSourcesByUrls(Iterable<String> urls) async {
    final normalized = urls.toSet().toList();
    if (normalized.isEmpty || !_beginBatchOperation()) return;
    try {
      await _dao.deleteByUrls(normalized);
      _selectedUrls.removeAll(normalized);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  /// 解析 JSON 字串為書源列表 (不匯入)
  List<BookSource> parseSources(String jsonStr) =>
      _importService.parseSources(jsonStr);

  Future<ParsedSourceImportResult> parseSourcesDetailedAsync(String jsonStr) =>
      _importService.parseSourcesDetailedAsync(jsonStr);

  ParsedSourceImportResult parseSourcesDetailed(String jsonStr) =>
      _importService.parseSourcesDetailed(jsonStr);

  /// 預覽匯入：分類為新增、更新、無變化
  Future<ImportPreviewResult> previewImport(
    List<BookSource> incoming, {
    List<BookSource> unsupportedSources = const <BookSource>[],
  }) => _importService.previewImport(
    incoming,
    unsupportedSources: unsupportedSources,
  );

  /// 直接匯入書源列表（跳過預覽）
  Future<int> importSources(List<BookSource> sources) async {
    if (sources.isEmpty || isMutationBusy) return 0;
    _isLoading = true;
    notifyListeners();
    try {
      final count = await _importService.importSources(sources);
      await loadSources(showLoading: false);
      return count;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> importFromJson(String jsonStr) async {
    if (isMutationBusy) return 0;
    _isLoading = true;
    notifyListeners();
    try {
      final count = await _importService.importFromJson(jsonStr);
      if (count <= 0) return 0;
      await loadSources(showLoading: false);
      return count;
    } catch (_) {
      return 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> importFromUrl(String url) async {
    try {
      final text = await fetchImportTextFromUrl(url);
      return await importFromJson(text);
    } catch (_) {}
    return 0;
  }

  Future<String> fetchImportTextFromUrl(String url) async {
    return _importService.fetchImportTextFromUrl(url);
  }

  @visibleForTesting
  String importPayloadToTextForTest(dynamic data) =>
      _importService.importPayloadToTextForTest(data);

  Future<int> importFromText(String text) async {
    return await importFromJson(text);
  }

  void _markVisibleSourcesDirty() {
    _visibleSourcesDirty = true;
    _visibleSourcesCache = null;
  }

  void _refreshVisibleSources() {
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  bool _beginBatchOperation() {
    if (isMutationBusy) return false;
    _isBatchOperationInProgress = true;
    notifyListeners();
    return true;
  }

  void _endBatchOperation() {
    if (!_isBatchOperationInProgress) return;
    _isBatchOperationInProgress = false;
    notifyListeners();
  }

  bool _beginSourceMutation(String url) {
    if (isMutationBusy || !_pendingSourceMutations.add(url)) return false;
    notifyListeners();
    return true;
  }

  void _endSourceMutation(String url) {
    if (_pendingSourceMutations.remove(url)) notifyListeners();
  }

  Set<String> sourceUrlsInGroup(String group) {
    final normalizedGroup = group.trim();
    if (normalizedGroup.isEmpty) return const <String>{};
    return Set<String>.unmodifiable(
      _sources
          .where((source) => _hasGroup(source.bookSourceGroup, normalizedGroup))
          .map((source) => source.bookSourceUrl),
    );
  }

  Set<String> _groupLabels(String? value) {
    if (value == null || value.trim().isEmpty) return const <String>{};
    return value
        .split(RegExp(r'[,，\s]+'))
        .map((group) => group.trim())
        .where((group) => group.isNotEmpty)
        .toSet();
  }

  bool _hasGroup(String? value, String group) =>
      _groupLabels(value).contains(group);

  int Function(BookSourcePart a, BookSourcePart b) _buildComparator() {
    final multiplier = sortDesc ? -1 : 1;
    switch (sortMode) {
      case 0:
        return (a, b) => a.customOrder.compareTo(b.customOrder) * multiplier;
      case 1:
        return (a, b) => b.weight.compareTo(a.weight) * multiplier;
      case 2:
        return (a, b) =>
            a.bookSourceName.compareTo(b.bookSourceName) * multiplier;
      case 3:
        return (a, b) =>
            a.bookSourceUrl.compareTo(b.bookSourceUrl) * multiplier;
      case 4:
        return (a, b) =>
            a.lastUpdateTime.compareTo(b.lastUpdateTime) * multiplier;
      default:
        return (a, b) => a.customOrder.compareTo(b.customOrder) * multiplier;
    }
  }
}
