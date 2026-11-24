import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/source/source_site.dart';
import 'package:night_reader/core/source/source_dedupe.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_repair/repair_runs.dart';
import 'source_check_job.dart';
import 'source_share.dart';
import 'widgets/import_preview_sheet.dart';
import 'widgets/source_list_skeleton.dart';

/// 匯入的 JSON 文字去掉前後空白與 BOM（有些網站與檔案會帶），書源解析與
/// 外部匯入的類型判斷都先過這一步。
String normalizeImportJson(String value) {
  var normalized = value.trim();
  while (normalized.isNotEmpty && normalized.codeUnitAt(0) == 0xFEFF) {
    normalized = normalized.substring(1).trim();
  }
  return normalized;
}

Map<String, List<Map<String, dynamic>>> _parseSourcesPayloadForIsolate(
  String jsonStr,
) {
  final normalized = normalizeImportJson(jsonStr);
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
    source.prepareIncoming();
    if (source.sourceKind == BookSourceKind.unsupported) {
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

/// 一次匯入：匯入幾個書源，接著併掉幾個重複書源（ADR 0062）。
typedef SourceImportCount = ({int imported, int merged});

/// 匯入完的一句話，書源管理與從外部打開的匯入共用。
String sourceImportMessage(SourceImportCount count, {int unsupported = 0}) {
  if (count.imported == 0) return '未匯入有效書源';
  return [
    '成功匯入 ${count.imported} 個書源',
    if (unsupported > 0) '其中 $unsupported 個已標記為不支援並停用',
    if (count.merged > 0) '合併了 ${count.merged} 個同網站重複的書源',
  ].join('，');
}

class SourceImportService {
  SourceImportService({BookSourceDao? dao, this._networkService})
    : _dao = dao ?? getIt<BookSourceDao>();

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

  /// 預覽匯入：照更新時間（規則這一版的時間）分成新增、檔案比這台新、比這台
  /// 舊、無變化（同 Legado 的 ImportBookSourceViewModel）。
  Future<ImportPreviewResult> previewImport(List<BookSource> incoming) async {
    final newSources = <BookSource>[];
    final updatedSources = <BookSource>[];
    final olderSources = <BookSource>[];
    final unchangedSources = <BookSource>[];
    final existingByUrl = <String, int>{};
    for (final source in await _dao.getAllPart()) {
      existingByUrl[source.bookSourceUrl] = source.lastUpdateTime;
    }

    // 檔案裡同一個網址有好幾筆：留更新時間最晚的（一樣晚的留後面那筆，同
    // 寫進資料庫時後面蓋前面）。
    final latest = <String, BookSource>{};
    for (final s in incoming) {
      final kept = latest[s.bookSourceUrl];
      if (kept == null || s.lastUpdateTime >= kept.lastUpdateTime) {
        latest[s.bookSourceUrl] = s;
      }
    }

    for (final s in latest.values) {
      final existingUpdateTime = existingByUrl[s.bookSourceUrl];
      if (existingUpdateTime == null) {
        newSources.add(s);
      } else if (s.lastUpdateTime > existingUpdateTime) {
        updatedSources.add(s);
      } else if (s.lastUpdateTime < existingUpdateTime) {
        olderSources.add(s);
      } else {
        unchangedSources.add(s);
      }
    }

    return ImportPreviewResult(
      newSources: newSources,
      updatedSources: updatedSources,
      olderSources: olderSources,
      unchangedSources: unchangedSources,
    );
  }

  /// 匯入書源，接著把重複書源併成一個（ADR 0062）。
  Future<SourceImportCount> importSources(List<BookSource> sources) async {
    if (sources.isEmpty) return (imported: 0, merged: 0);
    final preparedSources = await _prepareImportSources(sources);
    await _dao.insertOrUpdateAll(preparedSources);
    final merged = await mergeDuplicateSources();
    return (imported: preparedSources.length, merged: merged);
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
    return normalizeImportJson(value);
  }
}

/// 書源身上的一個標籤：類別（[kind]）或分組名稱（[group]，含校驗標記），
/// 兩者擇一。
typedef SourceTag = ({BookSourceKind? kind, String? group});

/// 整份書源清單現在被誰占著（`docs/state-machines.md`「書源管理」）。占著的
/// 由自己收：第一次讀與重讀由最新一次讀清單收尾時收；匯入與批次作業做完收，
/// 這時最新一次讀清單還沒讀完就換成重讀、交給它收。批次作業裡的重讀不碰階段。
enum _ListWork {
  /// 第一次讀：骨架照上次的樣子畫，什麼都不能改。
  opening,

  /// 閒著：都能改，改一列時只鎖那一列。
  idle,

  /// 重讀：讀完第一次之後要等它的讀清單（改了書源之後、從編輯頁回來、
  /// 按了重試、匯入寫完之後）。清單留著，選單灰掉。
  reloading,

  /// 匯入：寫進資料庫（含匯入自己併重複書源），寫完換成重讀。
  importing,

  /// 批次作業：刪、移動、改分組、校驗、清標記；每一列都鎖住。
  batch,
}

class SourceManagerProvider with ChangeNotifier {
  final BookSourceDao _dao = getIt<BookSourceDao>();
  final SourceImportService _importService;
  final CheckSourceService checkService;

  List<BookSource> _sources = [];
  List<BookSource>? _visibleSourcesCache;
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
  int _seenCheckRunCount = 0;
  SourceCheckReport get lastCheckReport => checkService.lastReport;
  bool get hasLastCheckReport => checkService.hasLastReport;
  SourceCheckConfig get checkConfig => checkService.config;
  int get totalSourceCount => _sources.length;

  /// 全部書源（依手動順序，不受目前的搜尋與篩選影響）。
  List<BookSource> get allSources => List<BookSource>.unmodifiable(
    List<BookSource>.from(_sources)
      ..sort((a, b) => a.customOrder.compareTo(b.customOrder)),
  );
  String? get loadErrorMessage => _loadError == null ? null : '載入書源失敗，請稍後重試';

  List<BookSource> get sources {
    if (_visibleSourcesDirty || _visibleSourcesCache == null) {
      _visibleSourcesCache = List<BookSource>.unmodifiable(
        _computeVisibleSources(),
      );
      _visibleSourcesDirty = false;
    }
    return _visibleSourcesCache!;
  }

  List<BookSource> _computeVisibleSources() {
    var list = List<BookSource>.from(_sources);

    // 全文搜尋
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
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
    } else if (filterGroup == '已停用') {
      list = list.where((s) => !s.enabled).toList();
    } else if (filterGroup == '已啟用發現') {
      list = list.where((s) => s.enabledExplore && s.hasExploreUrl).toList();
    } else if (filterGroup == '已停用發現') {
      list = list.where((s) => !s.enabledExplore && s.hasExploreUrl).toList();
    } else if (kindFilters[filterGroup] case final kind?) {
      list = list.where((s) => s.sourceKind == kind).toList();
    } else if (filterGroup == noAbnormalFilter) {
      list = list
          .where((s) => !_hasGroup(s.bookSourceGroup, abnormalSourceGroupTag))
          .toList();
    } else if (filterGroup == '無分組') {
      list = list
          .where((s) => _groupLabels(s.bookSourceGroup).isEmpty)
          .toList();
    } else if (filterGroup != '全部') {
      list = list
          .where((s) => _hasGroup(s.bookSourceGroup, filterGroup))
          .toList();
    }

    final comparator = _buildComparator();
    if (groupByDomain) {
      list.sort((a, b) {
        final hostCompare = getSourceHost(a.bookSourceUrl)
            .compareTo(getSourceHost(b.bookSourceUrl));
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

  /// 整份清單現在被誰占著。一建立就是第一次讀：書源等進場動畫播完才讀，
  /// 這段期間不能當成沒有書源。
  _ListWork _work = _ListWork.opening;

  /// 清單在讀：骨架（沒有書源時）與 [expectsSources] 看它。
  bool get isLoading => switch (_work) {
    _ListWork.opening || _ListWork.reloading || _ListWork.importing => true,
    _ListWork.idle || _ListWork.batch => false,
  };

  /// 正在改的那幾列：一次可以好幾列，和閒著、重讀同時成立。
  final Set<String> _pendingSourceMutations = <String>{};

  /// 正在併重複書源（ADR 0062）：在讀清單裡做，會和第一次讀、重讀同時成立，
  /// 所以不是 [_work] 的一個階段。這段時間其他改書源的動作等它，別的讀清單
  /// 等它併完再讀。
  Future<int>? _merging;

  /// 併完過幾次：讀清單時用來看讀的期間有沒有合併跑完。
  int _mergesDone = 0;

  Future<int> _merge(List<BookSource> sources) =>
      _merging = _mergeDuplicates(sources).whenComplete(() {
        _merging = null;
        _mergesDone++;
      });

  /// 最新一次讀清單收尾時的序號；和 [_loadGeneration] 不同就是最新一次還在讀。
  int _settledGeneration = 0;

  /// [owner]（匯入、批次作業）做完了，放開清單；最新一次讀清單還在讀（例如
  /// 背景重讀蓋過了自己的重讀）就交給它收，清單到它讀完都算重讀。
  void _release(_ListWork owner) {
    if (_work != owner) return;
    _work = _settledGeneration == _loadGeneration
        ? _ListWork.idle
        : _ListWork.reloading;
    notifyListeners();
  }

  /// 讀清單時能不能併重複書源：書源管理自己在改書源（匯入、批次作業、
  /// 校驗、有一列在改、編輯頁開著）時不併，做完重讀時再併。
  bool get _canMerge =>
      switch (_work) {
        _ListWork.opening || _ListWork.idle || _ListWork.reloading => true,
        _ListWork.importing || _ListWork.batch => false,
      } &&
      _merging == null &&
      !checkService.isChecking &&
      _pendingSourceMutations.isEmpty &&
      _editingUrls.isEmpty;

  /// 整份清單忙著：選單、多選工具列、分組管理灰掉，不能開始批次作業與匯入。
  bool get isMutationBusy =>
      _work != _ListWork.idle ||
      _merging != null ||
      checkService.isChecking ||
      _pendingSourceMutations.isNotEmpty;

  /// 上次讀完時的書源數，存在偏好設定、開頁時同步讀出；第一次讀取完成前
  /// 照它畫骨架的列數，並決定要不要先留出搜尋框與底部工具列。沒有紀錄
  /// （第一次開新版）時當作有書源。
  int? lastSourceCount;
  static const String _lastCountKey = 'source_manager_last_count';

  /// 頁面要不要畫「有書源」的版面（頁首搜尋框、底部工具列）。還沒有資料的
  /// 載入中照上次的紀錄，版面從第一幀就和讀完時一樣，清單出現時不被推動。
  bool get expectsSources => isLoading && _sources.isEmpty
      ? (lastSourceCount ?? 1) > 0
      : _sources.isNotEmpty;

  /// 讀出 [lastSourceCount]；型別不對或是負數的紀錄壞了，當作沒有紀錄。
  static int? _readLastCount() {
    final value = getIt<SharedPreferences>().get(_lastCountKey);
    if (value is int && value >= 0) return value;
    if (value != null) AppLog.w('書源數的紀錄讀不懂，當作沒有紀錄: $value');
    return null;
  }

  void _rememberCount(int count) {
    if (lastSourceCount == count) return;
    lastSourceCount = count;
    unawaited(
      getIt<SharedPreferences>().setInt(_lastCountKey, count).catchError((
        Object error,
      ) {
        AppLog.w('書源數的紀錄寫入失敗: $error');
        return false;
      }),
    );
  }

  /// 上次讀完時清單前面幾列的字（[SourceRowLook]），存在偏好設定、開頁時
  /// 同步讀出；第一次讀取完成前骨架照它畫，換場時每一條剛好換成那段字
  /// （ADR 0024）。沒有紀錄或讀不懂時是空的，骨架畫一般書源列的預覽。
  List<SourceRowLook> lastRows;
  static const String _lastRowsKey = 'source_manager_last_rows';

  /// 記下（與骨架照資料畫）的列數：最高的平板一個畫面也放不到 20 列書源，
  /// 再多也畫不到。
  static const int lastRowsLimit = 20;

  /// 確定寫進偏好設定的內容；一樣就不再寫。
  String? _savedRows = switch (getIt<SharedPreferences>().get(_lastRowsKey)) {
    final String saved => saved,
    _ => null,
  };

  static List<SourceRowLook> _readLastRows() {
    final saved = getIt<SharedPreferences>().get(_lastRowsKey);
    if (saved == null) return const [];
    try {
      return [
        for (final row in jsonDecode(saved as String) as List<dynamic>)
          SourceRowLook.fromJson(row),
      ];
    } catch (error) {
      AppLog.w('書源列的紀錄讀不懂，當作沒有紀錄: $error');
      return const [];
    }
  }

  void _rememberRows(List<BookSource> shown) {
    lastRows = [
      for (final source in shown.take(lastRowsLimit)) SourceRowLook.of(source),
    ];
    final encoded = jsonEncode([for (final row in lastRows) row.toJson()]);
    if (_savedRows == encoded) return;
    _savedRows = encoded;
    unawaited(
      getIt<SharedPreferences>().setString(_lastRowsKey, encoded).catchError((
        Object error,
      ) {
        AppLog.w('書源列的紀錄寫入失敗: $error');
        _savedRows = null;
        return false;
      }),
    );
  }

  /// 清單是否照手動順序完整列出；決定清單用可拖曳排序的版面。與一時的忙碌
  /// 狀態無關，切開關時版面才不會整個換掉重建。
  bool get showsManualOrder =>
      sortMode == 0 &&
      !sortDesc &&
      !groupByDomain &&
      filterGroup == '全部' &&
      _searchQuery.isEmpty &&
      sources.length == _sources.length;
  bool get canReorder => showsManualOrder && !isMutationBusy;

  /// 這一列此刻能不能操作：批次作業或校驗進行中全部鎖住；單一書源的修改
  /// 只鎖住那一列。
  bool isSourceLocked(String url) =>
      _work == _ListWork.batch ||
      checkService.isChecking ||
      _pendingSourceMutations.contains(url);
  final Set<String> _selectedUrls = {};
  Set<String> get selectedUrls => Set<String>.unmodifiable(_selectedUrls);
  List<String> _allGroups = [];
  List<String> get allGroups => List<String>.unmodifiable(_allGroups);

  /// 篩選「沒有異常」：校驗沒有標上「異常」的書源（含還沒校驗過的）。
  static const String noAbnormalFilter = '沒有異常';

  /// 帶「異常」標記的書源網址（修復異常書源修的就是這些）。
  List<String> get abnormalSourceUrls => [
    for (final source in _sources)
      if (_hasGroup(source.bookSourceGroup, abnormalSourceGroupTag))
        source.bookSourceUrl,
  ];

  /// 篩選某一類非小說書源（ADR 0051），名稱就是類別名稱。
  static final Map<String, BookSourceKind> kindFilters = {
    BookSourceKind.comic.sourceLabel: BookSourceKind.comic,
    BookSourceKind.audio.sourceLabel: BookSourceKind.audio,
  };

  /// 書源裡有的 [kindFilters]，照漫畫、有聲的順序。
  List<String> get presentKindFilters => [
    for (final MapEntry(key: label, value: kind) in kindFilters.entries)
      if (_sources.any((s) => s.sourceKind == kind)) label,
  ];

  /// 書源上出現的校驗結果標記，照 [sourceRuntimeStatusTags] 的順序
  /// （「異常」在最前）；篩選選單把它們和使用者自己的分組分開列。
  List<String> get checkResultTags => [
    for (final tag in sourceRuntimeStatusTags)
      if (_allGroups.contains(tag)) tag,
  ];

  /// 有沒有書源校驗過（有校驗時間或校驗標記）：「沒有異常」篩選據此能不能選。
  bool get anySourceChecked =>
      checkResultTags.isNotEmpty || _sources.any((s) => s.lastCheckTime > 0);

  /// 使用者自己的分組，不含校驗結果標記。
  List<String> get userGroups => [
    for (final group in _allGroups)
      if (!sourceRuntimeStatusTags.contains(group)) group,
  ];

  /// [entrance] 是書源管理頁的進場動畫；播完才讀書源（ADR 0018）。
  /// [uncovered] 在這一頁沒被別的頁面蓋著（或蓋著的頁面的換頁動畫播完）時
  /// 完成：同步套用了另一台的書源後等它才重讀，不疊在換頁動畫上；沒給就
  /// 馬上讀。
  SourceManagerProvider({
    required Future<void> entrance,
    this._uncovered,
    SourceImportService? importService,
    CheckSourceService? sourceCheckService,
    RepairRuns? repairRuns,
    PausedSourceCheck? pausedCheck,
    Future<int> Function(List<BookSource> sources)? mergeDuplicates,
  }) : _importService = importService ?? SourceImportService(),
       _mergeDuplicates =
           mergeDuplicates ??
           ((sources) => mergeDuplicateSources(sources: sources)),
       checkService = sourceCheckService ?? getIt<CheckSourceService>(),
       _repairRuns = repairRuns ?? RepairRuns.instance,
       pausedCheck = pausedCheck ?? PausedSourceCheck.instance,
       lastSourceCount = _readLastCount(),
       lastRows = _readLastRows() {
    _seenCheckRunCount = checkService.finishedRunCount;
    checkService.addListener(_handleCheckServiceChanged);
    _repairRuns.addListener(_handleRepairRunsChanged);
    this.pausedCheck.addListener(notifyListeners);
    BackgroundWork.instance.addListener(_handleSlotChanged);
    unawaited(
      entrance.then((_) {
        if (_disposed) return;
        loadSources();
        checkService.loadConfig();
        // 進場前同步套用的，上面這一次讀已經讀到；之後的才需要重讀。
        SourceSync.applied.addListener(_handleSourcesSynced);
        _listeningSync = true;
      }),
    );
  }

  final Future<void> Function()? _uncovered;
  final RepairRuns _repairRuns;

  /// 暫停中的校驗（ADR 0058）：校驗膠囊照它顯示已暫停。
  final PausedSourceCheck pausedCheck;
  final Future<int> Function(List<BookSource> sources) _mergeDuplicates;

  /// 讀清單時併掉了重複書源（ADR 0062）：每併一次加一，頁面聽它從底部提示
  /// 「已合併 [lastMergedDuplicates] 個同網站重複的書源」。
  final ValueNotifier<int> duplicatesMerged = ValueNotifier(0);
  int lastMergedDuplicates = 0;

  /// 已經為它重讀過清單的那一件修復，與那時它刪、併過幾次書源。
  RepairRun? _reloadedRun;
  int _reloadedEdits = 0;
  Set<String> _aiRepairedUrls = const {};
  bool _listeningSync = false;
  bool _syncReloadPending = false;

  /// 同步套用了另一台的書源：安靜地重讀清單（不顯示載入中，選取與篩選
  /// 留著）。連續幾次通知、或被別的頁面蓋著期間的通知合併成一次，等露出來
  /// 才讀（ADR 0018）。
  void _handleSourcesSynced() {
    if (_disposed || _syncReloadPending) return;
    _syncReloadPending = true;
    unawaited(_reloadAfterSync());
  }

  Future<void> _reloadAfterSync() async {
    try {
      await _uncovered?.call();
    } catch (error, stackTrace) {
      AppLog.e('等書源管理露出來失敗', error: error, stackTrace: stackTrace);
    }
    _syncReloadPending = false;
    if (_disposed) return;
    await loadSources(showLoading: false);
  }

  /// 修復在背景做完了（ADR 0058）：存進去的、標了「AI 修不好」的都要重讀；
  /// 做完之後在結果頁刪了或併了書源也重讀。
  void _handleRepairRunsChanged() {
    if (_disposed) return;
    final run = _repairRuns.current;
    if (run == null || !run.isFinished) return;
    if (identical(run, _reloadedRun) && run.sourceEdits == _reloadedEdits) {
      return;
    }
    _reloadedRun = run;
    _reloadedEdits = run.sourceEdits;
    unawaited(loadSources(showLoading: false));
  }

  void _handleCheckServiceChanged() {
    if (_disposed) return;
    // 校驗結果寫進資料庫後才重新讀取；這一頁中途才打開也一樣。
    if (checkService.finishedRunCount != _seenCheckRunCount) {
      _seenCheckRunCount = checkService.finishedRunCount;
      unawaited(loadSources(showLoading: false));
    }
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
    _repairRuns.removeListener(_handleRepairRunsChanged);
    pausedCheck.removeListener(notifyListeners);
    BackgroundWork.instance.removeListener(_handleSlotChanged);
    if (_listeningSync) SourceSync.applied.removeListener(_handleSourcesSynced);
    duplicatesMerged.dispose();
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
    // 匯入、批次作業裡的重讀不碰階段：清單已經被它們占著，由它們收。
    if (showLoading && _work == _ListWork.idle) {
      _work = _ListWork.reloading;
      notifyListeners();
    }
    bool stale() => _disposed || generation != _loadGeneration;
    try {
      var mergesSeen = _mergesDone;
      var loadedSources = await _dao.getAllPart();
      if (stale()) return;
      // 讀的期間有合併在跑或跑完了：讀到的可能是併之前的清單，等它併完
      // 重讀，直到讀的期間沒有合併。合併出錯由開始併的那一次記。
      while (_merging != null || _mergesDone != mergesSeen) {
        await _merging?.then<void>((_) {}, onError: (Object _) {});
        if (stale()) return;
        mergesSeen = _mergesDone;
        loadedSources = await _dao.getAllPart();
        if (stale()) return;
      }
      // 重複書源每次讀清單都併（ADR 0062），書源管理自己在改書源時除外
      // （[_canMerge]）；校驗、修復這類批次工作在跑時由
      // [mergeDuplicateSources] 擋下，等它們做完重讀時再併。
      if (_canMerge && duplicateSourceGroups(loadedSources).isNotEmpty) {
        final int merged;
        try {
          merged = await _merge(loadedSources);
        } catch (error, stackTrace) {
          AppLog.e('併重複書源失敗', error: error, stackTrace: stackTrace);
          rethrow;
        }
        if (_disposed) return;
        if (merged > 0) {
          lastMergedDuplicates = merged;
          duplicatesMerged.value++;
        }
        if (generation != _loadGeneration) return;
        if (merged > 0) {
          loadedSources = await _dao.getAllPart();
          if (_disposed || generation != _loadGeneration) return;
        }
      }
      _sources = loadedSources;
      checkService.forgetOutdatedProgress(loadedSources);
      _rememberCount(loadedSources.length);
      _selectedUrls.retainAll(
        loadedSources.map((source) => source.bookSourceUrl).toSet(),
      );
      _loadError = null;
      _updateGroups();
      _markVisibleSourcesDirty();
      // 記下次打開時的樣子：搜尋、篩選與排序都回到預設，是全部書源照手動
      // 順序，不是現在篩選過的清單。
      _rememberRows(allSources);
      unawaited(_refreshAiRepaired(loadedSources));
    } catch (error) {
      if (!_disposed && generation == _loadGeneration) {
        _loadError = error;
        _markVisibleSourcesDirty();
      }
    } finally {
      // 最新一次讀取收尾：一律發布結果，也收掉第一次讀與重讀，含被它取代
      // 的那幾次留下的（匯入、批次作業由它們自己收）。
      if (!_disposed && generation == _loadGeneration) {
        _settledGeneration = generation;
        if (_work case _ListWork.opening || _ListWork.reloading) {
          _work = _ListWork.idle;
        }
        notifyListeners();
      }
    }
  }

  /// 這個書源留著 AI 改之前的版本，長按選單有「還原 AI 修改前」（ADR 0054）。
  bool hasAiRepairBackup(String url) => _aiRepairedUrls.contains(url);

  /// 讀完書源後在背景整理改前版本：刪掉的書源它的也刪。不擋清單的讀取，
  /// 讀不到就當沒有；它只決定長按選單有沒有「還原 AI 修改前」。
  Future<void> _refreshAiRepaired(List<BookSource> sources) async {
    try {
      await AiRepairBackups.instance.keepOnly({
        for (final source in sources) source.bookSourceUrl,
      });
      final urls = await AiRepairBackups.instance.urls();
      if (_disposed || setEquals(urls, _aiRepairedUrls)) return;
      _aiRepairedUrls = urls;
      notifyListeners();
    } catch (error, stack) {
      AppLog.e('整理 AI 修書源的改前版本失敗', error: error, stackTrace: stack);
    }
  }

  /// 獲取完整書源 (用於編輯或除錯)
  Future<BookSource?> getFullSource(String url) => _dao.getByUrl(url);

  /// 編輯頁開著的書源：開著時不併重複書源（[_canMerge]），存的時候它可能
  /// 已經被併掉，存了的修改會在下次合併時隨它刪掉。
  final Set<String> _editingUrls = {};

  /// 打開 [url] 的編輯頁前呼叫，傳回要編輯的完整書源；編輯頁關掉後呼叫
  /// [endEditing]。正在併重複書源時等它併完（ADR 0062），被併掉的傳回
  /// null，不開。
  Future<BookSource?> beginEditing(String url) async {
    for (var merging = _merging; merging != null; merging = _merging) {
      await merging.then<void>((_) {}, onError: (Object _) {});
      if (_disposed) return null;
    }
    _editingUrls.add(url);
    try {
      final full = await _dao.getByUrl(url);
      if (full == null) _editingUrls.remove(url);
      return full;
    } catch (_) {
      _editingUrls.remove(url);
      rethrow;
    }
  }

  /// [url] 的編輯頁關掉了：存過（[changed]）或開著的期間有重複書源沒併，
  /// 重讀清單（照常併）。
  Future<void> endEditing(String url, {required bool changed}) async {
    _editingUrls.remove(url);
    if (_disposed) return;
    if (changed ||
        (_editingUrls.isEmpty && duplicateSourceGroups(_sources).isNotEmpty)) {
      await loadSources();
    }
  }

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
    final normalized = query.trim();
    if (_searchQuery == normalized) return;
    _searchQuery = normalized;
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  void toggleGroupByDomain() {
    groupByDomain = !groupByDomain;
    _markVisibleSourcesDirty();
    notifyListeners();
  }

  /// 「按域名分組」的組：和重複書源同一個分法（[siteHost]，ADR 0062）。
  String getSourceHost(String url) => siteHost(url) ?? '其他';

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

  /// 校驗膠囊的「暫停」：正在校驗的那幾個停下，做完的留著，按繼續校驗剩下的
  /// （ADR 0058）。
  void pauseSourceCheck() {
    final job = SourceCheckJob.current;
    if (job == null) return;
    job.pauseFromSystem();
    clearSelection();
  }

  /// 校驗膠囊與校驗詳情的「結束」：校驗中的停下、暫停中的收尾，做完的結果
  /// 寫成上次校驗摘要。
  void endSourceCheck() {
    final job = SourceCheckJob.current;
    if (job != null) {
      job.endFromSystem();
      // 正在暫停時按的：校驗服務已經停了、不會再通知，狀態列要換成「正在結束…」。
      notifyListeners();
    } else if (pausedCheck.isPaused) {
      unawaited(pausedCheck.end(service: checkService));
    } else {
      checkService.cancel();
    }
    clearSelection();
  }

  /// 別件背景工作（AI 找書、自動換源…）佔住或空出位置：暫停中校驗的「繼續」
  /// 跟著灰掉或亮起來。
  void _handleSlotChanged() {
    if (pausedCheck.isPaused) notifyListeners();
  }

  /// 暫停中的校驗按了繼續：沒有別的背景工作在跑才接著校驗剩下的。
  bool get canResumeSourceCheck =>
      pausedCheck.isPaused && backgroundWorkIdle() && !isMutationBusy;

  Future<void> resumeSourceCheck() async {
    if (!canResumeSourceCheck || !_beginBatchOperation()) return;
    try {
      final taken = pausedCheck.take();
      if (taken == null) return;
      final (plan, file) = taken;
      await SourceCheckJob.of(checkService, plan, file: file).run();
    } finally {
      _endBatchOperation();
    }
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
      final selected = all
          .where((s) => selectedUrls.contains(s.bookSourceUrl))
          .toList();
      final rest = all
          .where((s) => !selectedUrls.contains(s.bookSourceUrl))
          .toList();
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
      final selected = all
          .where((s) => selectedUrls.contains(s.bookSourceUrl))
          .toList();
      final rest = all
          .where((s) => !selectedUrls.contains(s.bookSourceUrl))
          .toList();
      final reordered = [...rest, ...selected];
      await _dao.updateCustomOrder(reordered);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  // 置頂／置底會改寫所有書源的順序，必須獨占執行。
  Future<void> moveToTop(String url) async {
    if (!_beginBatchOperation()) return;
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
      _endBatchOperation();
    }
  }

  Future<void> moveToBottom(String url) async {
    if (!_beginBatchOperation()) return;
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
      _endBatchOperation();
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
    await shareBookSources(sources, fileName: fileName);
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
    if (_shouldShareExportPayload(json, limitBytes: clipboardSafeBytes)) {
      final fileName = selectedFullSources.length == 1
          ? selectedFullSources.first.bookSourceName
          : 'export_${selectedFullSources.length}_sources';
      await shareBookSources(selectedFullSources, fileName: fileName);
      return false; // false = 已改走分享，非剪貼簿
    }
    await Clipboard.setData(ClipboardData(text: json));
    return true; // true = 已複製至剪貼簿
  }

  static bool _shouldShareExportPayload(
    String value, {
    int limitBytes = 512 * 1024,
  }) => utf8.encode(value).length > limitBytes;

  Future<void> reorderSource(int oldIndex, int newIndex) async {
    final list = List<BookSource>.from(sources);
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

  /// 開始新的一次校驗：先佔住背景工作的位置，佔不到（按下去之後別件剛好
  /// 開始）就不做，暫停中的那次與勾選照舊；佔到了才存設定、結束暫停中的那次
  /// （做完的那些不再接著校驗）。傳回校驗有沒有跑。
  Future<bool> _checkAnew(List<String> urls, SourceCheckConfig? config) async {
    final job = SourceCheckJob.of(checkService, SourceCheckPlan(urls));
    if (!job.reserve()) return false;
    try {
      if (config != null) await checkService.updateConfig(config);
      await pausedCheck.end();
      await job.run();
      return true;
    } finally {
      job.release();
    }
  }

  Future<void> checkSelectedSources({SourceCheckConfig? config}) async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    if (selectedUrls.isEmpty || !_beginBatchOperation()) return;
    var checked = false;
    try {
      checked = await _checkAnew(selectedUrls.toList(growable: false), config);
    } finally {
      if (checked) _selectedUrls.removeAll(selectedUrls);
      _endBatchOperation();
    }
  }

  /// 校驗一個書源（登入完用）。和批次校驗一樣先鎖住清單；已有其他工作、
  /// 校驗或背景工作（修書源，ADR 0058）在跑時不跑。
  Future<void> checkSource(String url) async {
    if (!backgroundWorkIdle() || !_beginBatchOperation()) return;
    try {
      await checkService.check([url]);
    } catch (error, stackTrace) {
      AppLog.e('校驗書源失敗', error: error, stackTrace: stackTrace);
    } finally {
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
          s.addGroup(normalizedGroup);
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
          s.removeGroup(normalizedGroup);
          await _dao.upsert(s);
        }
      }
      _selectedUrls.removeAll(selectedUrls);
      await loadSources();
    } finally {
      _endBatchOperation();
    }
  }

  /// 「刪除書源」可勾的標籤，各有幾個書源：先是類別（小說、漫畫、有聲、
  /// 影視與文件），再是校驗標記，最後是自己的分組；沒有書源的標籤不列。
  List<({SourceTag tag, int count})> get sourceTagCounts {
    final counts = <SourceTag, int>{};
    for (final source in _sources) {
      final kindTag = (kind: source.sourceKind, group: null);
      counts[kindTag] = (counts[kindTag] ?? 0) + 1;
      for (final group in _groupLabels(source.bookSourceGroup)) {
        final groupTag = (kind: null, group: group);
        counts[groupTag] = (counts[groupTag] ?? 0) + 1;
      }
    }
    return [
      for (final kind in BookSourceKind.values)
        if (counts[(kind: kind, group: null)] case final count?)
          (tag: (kind: kind, group: null), count: count),
      for (final group in [...checkResultTags, ...userGroups])
        if (counts[(kind: null, group: group)] case final count?)
          (tag: (kind: null, group: group), count: count),
    ];
  }

  /// 帶 [tags] 任一個標籤的書源有幾個。
  int countSourcesWithTags(Set<SourceTag> tags) =>
      _sources.where((source) => _hasAnyTag(source, tags)).length;

  bool _hasAnyTag(BookSource source, Set<SourceTag> tags) => tags.any(
    (tag) => tag.kind != null
        ? source.sourceKind == tag.kind
        : _hasGroup(source.bookSourceGroup, tag.group!),
  );

  /// 刪掉帶 [tags] 任一個標籤的書源，回傳刪了幾個。
  Future<int> deleteSourcesWithTags(Set<SourceTag> tags) async {
    if (tags.isEmpty || !_beginBatchOperation()) return 0;
    try {
      final urlsToDelete = [
        for (final source in await _dao.getAllPart())
          if (_hasAnyTag(source, tags)) source.bookSourceUrl,
      ];
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
    var checked = false;
    try {
      checked = await _checkAnew(urls, config);
    } finally {
      if (checked) _selectedUrls.removeAll(selectedAtStart);
      _endBatchOperation();
    }
  }

  /// 清掉校驗留下的狀態分組、「AI 修不好」與錯誤註解，書源回到可用；不給網址就清全部，
  /// 連上次的校驗摘要一起收起。有清掉標記的書源連校驗時間一起歸零：那次校驗的
  /// 結論已經不算數，整批修復要重新校驗它（ADR 0054）。回傳實際有變動的書源數。
  Future<int> clearCheckMarks([Set<String>? urls]) async {
    if (!_beginBatchOperation()) return 0;
    try {
      final targets = urls == null
          ? await _dao.getAll()
          : [for (final url in urls) ?await _dao.getByUrl(url)];
      final changed = <BookSource>[];
      for (final source in targets) {
        final group = source.bookSourceGroup;
        final comment = source.bookSourceComment;
        source
          ..removeInvalidGroups()
          ..removeGroup(aiUnfixableSourceGroupTag)
          ..removeErrorComment();
        if (source.bookSourceGroup != group ||
            source.bookSourceComment != comment) {
          source.lastCheckTime = 0;
          changed.add(source);
        }
      }
      if (changed.isNotEmpty) await _dao.upsertAll(changed);
      if (urls == null) {
        checkService.clearLastReport();
      } else {
        _selectedUrls.removeAll(urls);
      }
      await loadSources();
      return changed.length;
    } finally {
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

  /// 直接匯入書源列表（跳過預覽）。清單忙著時丟出 [StateError]：選單在忙時
  /// 灰掉，會走到這裡的是預覽面板開著時才忙起來的（例如背景工作開始校驗）。
  Future<SourceImportCount> importSources(List<BookSource> sources) async {
    if (sources.isEmpty) return (imported: 0, merged: 0);
    if (isMutationBusy) throw StateError('書源管理正在改書源，等它做完再匯入');
    _work = _ListWork.importing;
    notifyListeners();
    try {
      final count = await _importService.importSources(sources);
      // 寫完了：剩下的重讀和一般的重讀一樣，可以併重複書源（背景工作在跑
      // 時匯入自己沒併、這時剛做完的），由最新一次讀清單收。
      _work = _ListWork.reloading;
      await loadSources(showLoading: false);
      return count;
    } finally {
      _release(_ListWork.importing);
    }
  }

  Future<String> fetchImportTextFromUrl(String url) async {
    return _importService.fetchImportTextFromUrl(url);
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
    _work = _ListWork.batch;
    notifyListeners();
    return true;
  }

  void _endBatchOperation() => _release(_ListWork.batch);

  /// 不同書源的單筆修改可以同時進行；同一筆、清單被占著（[_work] 不是閒著）、
  /// 併重複書源中或校驗中則拒絕。
  bool _beginSourceMutation(String url) {
    if (_work != _ListWork.idle ||
        _merging != null ||
        checkService.isChecking ||
        !_pendingSourceMutations.add(url)) {
      return false;
    }
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

  Set<String> _groupLabels(String? value) => splitSourceGroups(value);

  bool _hasGroup(String? value, String group) =>
      _groupLabels(value).contains(group);

  int Function(BookSource a, BookSource b) _buildComparator() {
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
