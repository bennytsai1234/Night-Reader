import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reader/core/constant/prefer_key.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/services/crash_handler.dart';
import 'package:reader/core/services/event_bus.dart';
import 'package:reader/core/services/source_check_isolate.dart';
import 'package:reader/core/services/source_validation_context.dart';
import 'package:reader/core/engine/js/js_engine.dart';
import 'package:reader/core/engine/js/js_extensions_base.dart';

Map<String, bool> _classifySourceExecutionTraitsForIsolate(
  List<Map<String, dynamic>> sourcePayloads,
) {
  final result = <String, bool>{};
  for (final payload in sourcePayloads) {
    final url = payload['bookSourceUrl']?.toString() ?? '';
    if (url.isEmpty) continue;
    result[url] = _payloadMapContainsRuleJs(payload);
  }
  return result;
}

bool _payloadMapContainsRuleJs(Map<dynamic, dynamic> payload) {
  for (final entry in payload.entries) {
    final key = entry.key.toString().toLowerCase();
    final value = entry.value;
    if (value == null) continue;
    if (key.contains('js') && value.toString().trim().isNotEmpty) {
      return true;
    }
    if (value is Map) {
      if (_payloadMapContainsRuleJs(value)) return true;
      continue;
    }
    if (value is Iterable && value is! String) {
      if (_payloadContainsRuleJs(value)) return true;
      continue;
    }
    if (_payloadStringLooksJsHeavy(value.toString())) {
      return true;
    }
  }
  return false;
}

bool _payloadContainsRuleJs(Iterable<dynamic> values) {
  for (final value in values) {
    if (value == null) continue;
    if (value is Map) {
      if (_payloadMapContainsRuleJs(value)) return true;
      continue;
    }
    if (value is Iterable && value is! String) {
      if (_payloadContainsRuleJs(value)) return true;
      continue;
    }
    if (_payloadStringLooksJsHeavy(value.toString())) {
      return true;
    }
  }
  return false;
}

// Matches legeado-style JS bridge invocations like `java.ajax(`, `java.put(`,
// but skips bare prose containing "java." such as URLs or category names.
final RegExp _kJsBridgeCallPattern = RegExp(r'java\.[a-z_][a-z0-9_]*\s*\(');

bool _payloadStringLooksJsHeavy(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('<js>') ||
      normalized.contains('@js:') ||
      normalized.startsWith('@js') ||
      normalized.contains('"jslib"') ||
      normalized.contains('"logincheckjs"') ||
      normalized.contains('"coverdecodejs"') ||
      normalized.contains('"preupdatejs"') ||
      normalized.contains('"formatjs"') ||
      normalized.contains('"webjs"') ||
      _kJsBridgeCallPattern.hasMatch(normalized);
}

class SourceCheckEntry {
  final String sourceUrl;
  final String sourceName;
  final String stage;
  final String message;
  final SourceRuntimeHealth health;

  const SourceCheckEntry({
    required this.sourceUrl,
    required this.sourceName,
    required this.stage,
    required this.message,
    required this.health,
  });

  bool get isHealthy => health.category == SourceHealthCategory.healthy;
  bool get cleanupCandidate => health.cleanupCandidate;
}

class SourceCheckReport {
  final List<SourceCheckEntry> entries;

  const SourceCheckReport(this.entries);

  static const empty = SourceCheckReport(<SourceCheckEntry>[]);

  int get total => entries.length;
  int get healthyCount => entries.where((entry) => entry.isHealthy).length;
  int get affectedCount => total - healthyCount;
  int get cleanupCandidateCount =>
      entries.where((entry) => entry.cleanupCandidate).length;
  int get quarantinedCount =>
      entries.where((entry) => entry.health.quarantined).length;

  List<SourceCheckEntry> get affectedEntries =>
      entries.where((entry) => !entry.isHealthy).toList();

  List<SourceCheckEntry> get cleanupCandidates =>
      entries.where((entry) => entry.cleanupCandidate).toList();

  List<String> get cleanupCandidateUrls =>
      cleanupCandidates.map((entry) => entry.sourceUrl).toList();

  bool get hasEntries => entries.isNotEmpty;

  String get summary =>
      '可用 $healthyCount / 異常 $affectedCount / 建議清理 $cleanupCandidateCount';
}

class SourceCheckLogEntry {
  final DateTime time;
  final String message;

  const SourceCheckLogEntry({required this.time, required this.message});

  String get formattedTime =>
      '[${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:${_twoDigits(time.second)}.${_threeDigits(time.millisecond)}]';
}

class SourceCheckProgress {
  final String sourceName;
  final String message;
  final bool isFinal;
  final bool hasIssue;

  const SourceCheckProgress({
    required this.sourceName,
    required this.message,
    required this.isFinal,
    required this.hasIssue,
  });
}

class SourceCheckConfig {
  final String keyword;
  final int timeoutSeconds;
  final bool checkSearch;
  final bool checkDiscovery;
  final bool checkInfo;
  final bool checkCategory;
  final bool checkContent;

  const SourceCheckConfig({
    required this.keyword,
    required this.timeoutSeconds,
    required this.checkSearch,
    required this.checkDiscovery,
    required this.checkInfo,
    required this.checkCategory,
    required this.checkContent,
  });

  static const SourceCheckConfig defaults = SourceCheckConfig(
    keyword: '我的',
    timeoutSeconds: 15,
    checkSearch: true,
    checkDiscovery: true,
    checkInfo: true,
    checkCategory: true,
    checkContent: true,
  );

  factory SourceCheckConfig.fromPreferences(SharedPreferences prefs) {
    return SourceCheckConfig(
      keyword:
          prefs.getString(PreferKey.checkSourceKeyword) ?? defaults.keyword,
      timeoutSeconds:
          prefs.getInt(PreferKey.checkSourceTimeout) ?? defaults.timeoutSeconds,
      checkSearch:
          prefs.getBool(PreferKey.checkSourceSearch) ?? defaults.checkSearch,
      checkDiscovery:
          prefs.getBool(PreferKey.checkSourceDiscovery) ??
          defaults.checkDiscovery,
      checkInfo: prefs.getBool(PreferKey.checkSourceInfo) ?? defaults.checkInfo,
      checkCategory:
          prefs.getBool(PreferKey.checkSourceCategory) ??
          defaults.checkCategory,
      checkContent:
          prefs.getBool(PreferKey.checkSourceContent) ?? defaults.checkContent,
    ).normalized();
  }

  SourceCheckConfig copyWith({
    String? keyword,
    int? timeoutSeconds,
    bool? checkSearch,
    bool? checkDiscovery,
    bool? checkInfo,
    bool? checkCategory,
    bool? checkContent,
  }) {
    return SourceCheckConfig(
      keyword: keyword ?? this.keyword,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      checkSearch: checkSearch ?? this.checkSearch,
      checkDiscovery: checkDiscovery ?? this.checkDiscovery,
      checkInfo: checkInfo ?? this.checkInfo,
      checkCategory: checkCategory ?? this.checkCategory,
      checkContent: checkContent ?? this.checkContent,
    );
  }

  SourceCheckConfig normalized() {
    var normalizedSearch = checkSearch;
    var normalizedDiscovery = checkDiscovery;
    if (!normalizedSearch && !normalizedDiscovery) {
      normalizedSearch = true;
    }

    var normalizedInfo = checkInfo;
    var normalizedCategory = checkCategory;
    var normalizedContent = checkContent;
    if (!normalizedInfo) {
      normalizedCategory = false;
      normalizedContent = false;
    } else if (!normalizedCategory) {
      normalizedContent = false;
    }

    final trimmedKeyword =
        keyword.trim().isEmpty ? defaults.keyword : keyword.trim();
    final normalizedTimeout = timeoutSeconds < 1 ? 1 : timeoutSeconds;
    return SourceCheckConfig(
      keyword: trimmedKeyword,
      timeoutSeconds: normalizedTimeout,
      checkSearch: normalizedSearch,
      checkDiscovery: normalizedDiscovery,
      checkInfo: normalizedInfo,
      checkCategory: normalizedCategory,
      checkContent: normalizedContent,
    );
  }

  Duration get timeoutDuration => Duration(seconds: timeoutSeconds);

  /// Upper bound for one source check.
  ///
  /// Stage-level checks still use [timeoutDuration]. This budget prevents a
  /// single source from occupying a worker for the full sum of every stage.
  Duration get sourceTimeoutDuration {
    final activeFlows = (checkSearch ? 1 : 0) + (checkDiscovery ? 1 : 0);
    final stageBudget =
        activeFlows +
        (checkInfo ? activeFlows : 0) +
        (checkCategory ? activeFlows : 0) +
        (checkContent ? activeFlows : 0);
    final multiplier = math.max(2, math.min(stageBudget, 6));
    final seconds = math.min(timeoutSeconds * multiplier, 90);
    return Duration(seconds: math.max(timeoutSeconds, seconds));
  }

  String get summary {
    final parts = <String>[
      if (checkSearch) '搜尋',
      if (checkDiscovery) '發現',
      if (checkInfo) '詳情',
      if (checkCategory) '目錄',
      if (checkContent) '正文',
    ];
    return '超時 ${timeoutSeconds}s · ${parts.join('/')}';
  }
}

class _SourceCheckTask {
  final int index;
  final String sourceUrl;

  const _SourceCheckTask({required this.index, required this.sourceUrl});
}

class _SourceCheckTaskQueue {
  final List<String> _sourceUrls;
  int _nextIndex = 0;

  _SourceCheckTaskQueue(this._sourceUrls);

  _SourceCheckTask? takeNext() {
    final index = _nextIndex;
    if (index >= _sourceUrls.length) return null;
    _nextIndex = index + 1;
    return _SourceCheckTask(index: index, sourceUrl: _sourceUrls[index]);
  }
}

class _AsyncSemaphore {
  final int _maxPermits;
  int _activePermits = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  _AsyncSemaphore(int permits) : _maxPermits = math.max(1, permits);

  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_activePermits < _maxPermits) {
      _activePermits++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    if (_activePermits > 0) {
      _activePermits--;
    }
  }
}

class _SourceCheckExecutionPool {
  final int workerCount;
  final Future<SourceCheckEntry?> Function(String sourceUrl) checkSource;
  final Future<SourceCheckEntry?> Function(String sourceUrl, Object error)
  recordFailure;
  final void Function() onTaskDone;
  final bool Function() shouldContinue;
  final bool Function(String sourceUrl) isJsHeavySource;
  final String Function(String sourceUrl) domainOf;
  final int sameDomainConcurrency;
  final int jsConcurrency;

  final Map<String, _AsyncSemaphore> _domainSemaphores =
      <String, _AsyncSemaphore>{};
  late final _AsyncSemaphore _jsSemaphore = _AsyncSemaphore(jsConcurrency);

  _SourceCheckExecutionPool({
    required this.workerCount,
    required this.checkSource,
    required this.recordFailure,
    required this.onTaskDone,
    required this.shouldContinue,
    required this.isJsHeavySource,
    required this.domainOf,
    required this.sameDomainConcurrency,
    required this.jsConcurrency,
  });

  Future<List<SourceCheckEntry?>> run(List<String> sourceUrls) async {
    final queue = _SourceCheckTaskQueue(sourceUrls);
    final results = List<SourceCheckEntry?>.filled(sourceUrls.length, null);
    final effectiveWorkerCount = math.min(
      workerCount,
      math.max(1, sourceUrls.length),
    );

    Future<void> worker() async {
      while (shouldContinue()) {
        final task = queue.takeNext();
        if (task == null) break;
        try {
          results[task.index] = await _runTask(task.sourceUrl);
        } catch (error, stack) {
          AppLog.e(
            '書源校驗任務失敗: ${task.sourceUrl}',
            error: error,
            stackTrace: stack,
          );
          results[task.index] = await recordFailure(task.sourceUrl, error);
        } finally {
          onTaskDone();
        }
      }
    }

    await Future.wait(List.generate(effectiveWorkerCount, (_) => worker()));
    return results;
  }

  Future<SourceCheckEntry?> _runTask(String sourceUrl) {
    final domainSemaphore = _domainSemaphores.putIfAbsent(
      domainOf(sourceUrl),
      () => _AsyncSemaphore(sameDomainConcurrency),
    );
    return domainSemaphore.run(() {
      if (!isJsHeavySource(sourceUrl)) {
        return checkSource(sourceUrl);
      }
      return _jsSemaphore.run(() => checkSource(sourceUrl));
    });
  }
}

/// CheckSourceService - 書源校驗服務
/// 參考 legado CheckSourceService，以 group/comment 持久化校驗結果，
/// 讓來源管理、搜尋池與執行期策略共用同一套狀態。
class CheckSourceService extends ChangeNotifier {
  static const int _sourceCheckConcurrency = 8;
  static const int _sameDomainSourceConcurrency = 8;
  static const int _jsHeavySourceConcurrency = 8;
  static const int _statusWriteBatchSize = 16;
  static const Duration _notifyThrottleInterval = Duration(milliseconds: 350);
  final BookSourceDao _sourceDao;
  final AppEventBus _eventBus;

  AppEventBus get eventBus => _eventBus;

  bool _isChecking = false;
  int _totalCount = 0;
  int _currentCount = 0;
  String _statusMsg = '';
  SourceCheckReport _lastReport = SourceCheckReport.empty;
  SourceCheckConfig _config = SourceCheckConfig.defaults;
  final List<SourceCheckLogEntry> _logs = <SourceCheckLogEntry>[];
  final Map<String, SourceCheckProgress> _sourceProgress =
      <String, SourceCheckProgress>{};
  final Set<String> _timedOutSourceUrls = <String>{};
  final Map<String, SourceCheckIsolateHandle> _activeTasks =
      <String, SourceCheckIsolateHandle>{};
  final Map<String, BookSource> _pendingStatusWrites = <String, BookSource>{};
  final Map<String, bool> _jsHeavySourceCache = <String, bool>{};
  Timer? _notifyTimer;
  bool _isDisposed = false;

  CheckSourceService({BookSourceDao? sourceDao, AppEventBus? eventBus})
    : _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
      _eventBus = eventBus ?? AppEventBus();

  bool get isChecking => _isChecking;
  int get totalCount => _totalCount;
  int get currentCount => _currentCount;
  String get statusMsg => _statusMsg;
  SourceCheckReport get lastReport => _lastReport;
  bool get hasLastReport => _lastReport.hasEntries;
  SourceCheckConfig get config => _config;
  UnmodifiableListView<SourceCheckLogEntry> get logs =>
      UnmodifiableListView<SourceCheckLogEntry>(_logs);
  UnmodifiableMapView<String, SourceCheckProgress> get sourceProgress =>
      UnmodifiableMapView<String, SourceCheckProgress>(_sourceProgress);

  SourceCheckProgress? progressOf(String sourceUrl) =>
      _sourceProgress[sourceUrl];

  Future<void> loadConfig() async {
    final prefs = await _safeGetPreferences();
    if (prefs == null) return;
    _config = SourceCheckConfig.fromPreferences(prefs);
    _notifyIfAlive();
  }

  Future<void> updateConfig(SourceCheckConfig next) async {
    final normalized = next.normalized();
    _config = normalized;
    final prefs = await _safeGetPreferences();
    if (prefs != null) {
      await prefs.setString(PreferKey.checkSourceKeyword, normalized.keyword);
      await prefs.setInt(
        PreferKey.checkSourceTimeout,
        normalized.timeoutSeconds,
      );
      await prefs.setBool(PreferKey.checkSourceSearch, normalized.checkSearch);
      await prefs.setBool(
        PreferKey.checkSourceDiscovery,
        normalized.checkDiscovery,
      );
      await prefs.setBool(PreferKey.checkSourceInfo, normalized.checkInfo);
      await prefs.setBool(
        PreferKey.checkSourceCategory,
        normalized.checkCategory,
      );
      await prefs.setBool(
        PreferKey.checkSourceContent,
        normalized.checkContent,
      );
      await prefs.setString(PreferKey.checkSource, normalized.summary);
    }
    _notifyIfAlive();
  }

  Future<SourceCheckReport> check(List<String> urls) async {
    if (_isChecking) return _lastReport;

    return SourceValidationContext.runNonInteractive(
      () => _checkNonInteractive(urls),
    );
  }

  Future<SourceCheckReport> _checkNonInteractive(List<String> urls) async {
    final normalizedUrls = LinkedHashSet<String>.from(
      urls.map((url) => url.trim()).where((url) => url.isNotEmpty),
    ).toList(growable: false);
    final config = _config.normalized();
    _isChecking = true;
    _totalCount = normalizedUrls.length;
    _currentCount = 0;
    _statusMsg = '準備校驗';
    _lastReport = SourceCheckReport.empty;
    _logs.clear();
    _sourceProgress.clear();
    _timedOutSourceUrls.clear();
    _activeTasks.clear();
    _pendingStatusWrites.clear();
    _jsHeavySourceCache.clear();
    // 清除上次校驗殘留的 JS 靜態快取，避免大量 jsLib / TTF 字型佔用記憶體。
    JsEngine.clearCaches();
    JsExtensionsBase.clearCaches();

    _appendLog('開始校驗，共 $_totalCount 個書源 (${config.summary})');
    _notifyIfAlive();
    await _primeSourceExecutionTraits(normalizedUrls);

    List<SourceCheckEntry?> results;
    try {
      results = await _SourceCheckExecutionPool(
        workerCount: _sourceCheckConcurrency,
        checkSource: (url) => _checkSingleSourceWithBudget(url, config),
        recordFailure: _recordUnexpectedSourceFailure,
        onTaskDone: () {
          _currentCount++;
          _notifyIfAlive();
        },
        shouldContinue: () => _isChecking,
        isJsHeavySource: _isJsHeavySource,
        domainOf: _sourceDomainKey,
        sameDomainConcurrency: _sameDomainSourceConcurrency,
        jsConcurrency: _jsHeavySourceConcurrency,
      ).run(normalizedUrls);
    } finally {
      // 校驗結束（無論正常、取消或例外）都清除 JS 靜態快取。
      // _resolvedJsLibCache 的 key 本身就是完整 jsLib 字串，
      // ttfCache 存放字型二進位；兩者在大量書源後會顯著佔用記憶體。
      JsEngine.clearCaches();
      JsExtensionsBase.clearCaches();
    }

    if (!_isChecking) {
      _appendLog('校驗已取消，已完成 $_currentCount / $_totalCount');
    }

    _isChecking = false;
    _activeTasks.clear();
    await _flushPendingStatusWrites();
    _lastReport = SourceCheckReport(
      results.whereType<SourceCheckEntry>().toList(growable: false),
    );
    _statusMsg = _lastReport.summary;
    _appendLog('校驗完成：${_lastReport.summary}');
    _eventBus.fire(AppEvent(AppEventBus.checkSourceDone, data: _lastReport));
    _notifyIfAlive();
    return _lastReport;
  }

  Future<SourceCheckEntry?> _checkSingleSourceWithBudget(
    String url,
    SourceCheckConfig config,
  ) async {
    final source = await _sourceDao.getByUrl(url);
    if (source == null || _shouldIgnoreSourceUpdate(url)) return null;

    _statusMsg = '正在校驗: ${source.bookSourceName}';
    _setSourceProgress(source, '等待校驗', isFinal: false, hasIssue: false);
    _notifyIfAlive();

    final isoConfig = IsolateCheckConfig(
      keyword: config.keyword,
      timeoutSeconds: config.timeoutSeconds,
      checkSearch: config.checkSearch,
      checkDiscovery: config.checkDiscovery,
      checkInfo: config.checkInfo,
      checkCategory: config.checkCategory,
      checkContent: config.checkContent,
    );

    SourceCheckIsolateHandle handle;
    try {
      handle = await spawnSourceCheck(
        source,
        isoConfig,
        config.sourceTimeoutDuration,
      );
    } catch (e, stack) {
      AppLog.e('書源校驗 Isolate 啟動失敗: $url', error: e, stackTrace: stack);
      return _recordUnexpectedSourceFailure(url, e);
    }

    if (_shouldIgnoreSourceUpdate(url)) {
      handle.abort();
      return null;
    }

    _activeTasks[url] = handle;
    try {
      final result = await handle.result;
      if (result == null) return _recordSourceTimeout(url, config);
      return _applyIsolateResult(url, result);
    } finally {
      _activeTasks.remove(url);
    }
  }

  Future<SourceCheckEntry?> _applyIsolateResult(
    String url,
    SourceCheckIsolateResult result,
  ) async {
    if (_shouldIgnoreSourceUpdate(url)) return null;
    final source = BookSource.fromJson(result.updatedSourceJson);
    for (final log in result.logs) {
      if (log.startsWith('§DIAG§')) {
        // 診斷：把未截斷的解析/JS 原始錯誤寫進崩潰日誌（主線程，path_provider 正常）。
        // 只挑解析/JS 類，避免登入/逾時等已知分類灌爆日誌。
        if (log.contains('解析') ||
            log.contains('原始錯誤') ||
            log.contains('[js]')) {
          CrashHandler.recordError(
            '書源校驗解析失敗 [${source.bookSourceName}] (${source.bookSourceUrl})\n$log',
            null,
          );
        }
        continue;
      }
      _appendLog(log, sourceUrl: url);
    }
    await _queueStatusWrite(source);
    final hasIssue = !result.isHealthy;
    final progressMsg =
        result.isHealthy
            ? '校驗成功'
            : '${source.runtimeHealth.label}: ${result.message}';
    _setSourceProgress(source, progressMsg, isFinal: true, hasIssue: hasIssue);
    return SourceCheckEntry(
      sourceUrl: source.bookSourceUrl,
      sourceName: source.bookSourceName,
      stage: result.stage,
      message: result.isHealthy ? '校驗成功' : result.message,
      health: source.runtimeHealth,
    );
  }

  Future<SourceCheckEntry?> _recordSourceTimeout(
    String url,
    SourceCheckConfig config,
  ) async {
    if (_isDisposed || !_isChecking) return null;
    _timedOutSourceUrls.add(url);
    final source = await _sourceDao.getByUrl(url);
    if (source == null) return null;

    final message =
        '整體校驗超時 (${config.sourceTimeoutDuration.inSeconds}s)，已停止此書源後續步驟';
    const health = SourceRuntimeHealth(
      category: SourceHealthCategory.upstreamUnstable,
      label: timeoutSourceGroupTag,
      description: '來源響應過慢或上游阻擋，先隔離避免拖慢批次校驗',
      allowsSearch: false,
      allowsReading: false,
      cleanupCandidate: false,
      quarantined: true,
    );

    await _persistStatus(source, health, message, force: true);
    _appendLog(
      '  ✕ [${source.bookSourceName}] $message',
      sourceUrl: url,
      force: true,
    );
    _setSourceProgress(
      source,
      message,
      isFinal: true,
      hasIssue: true,
      force: true,
    );
    return SourceCheckEntry(
      sourceUrl: source.bookSourceUrl,
      sourceName: source.bookSourceName,
      stage: 'timeout',
      message: message,
      health: source.runtimeHealth,
    );
  }

  Future<SourceCheckEntry?> _recordUnexpectedSourceFailure(
    String url,
    Object error,
  ) async {
    if (_shouldIgnoreSourceUpdate(url)) return null;
    final source = await _sourceDao.getByUrl(url);
    if (source == null || _shouldIgnoreSourceUpdate(url)) return null;

    final message = _compactMessage(
      error.toString().trim().isEmpty ? '校驗失敗' : error.toString(),
    );
    const health = SourceRuntimeHealth(
      category: SourceHealthCategory.upstreamUnstable,
      label: quarantineSourceGroupTag,
      description: '校驗流程異常，先隔離避免影響其他書源',
      allowsSearch: false,
      allowsReading: false,
      cleanupCandidate: false,
      quarantined: true,
    );

    await _persistStatus(source, health, message);
    _appendLog('  ✕ [${source.bookSourceName}] $message', sourceUrl: url);
    _setSourceProgress(source, message, isFinal: true, hasIssue: true);
    return SourceCheckEntry(
      sourceUrl: source.bookSourceUrl,
      sourceName: source.bookSourceName,
      stage: 'error',
      message: message,
      health: source.runtimeHealth,
    );
  }

  Future<void> _persistStatus(
    BookSource source,
    SourceRuntimeHealth health,
    String message, {
    Iterable<SourceRuntimeHealth> extraHealths = const <SourceRuntimeHealth>[],
    bool force = false,
  }) async {
    if (!force && _shouldIgnoreSourceUpdate(source.bookSourceUrl)) return;
    source.removeInvalidGroups();
    source.removeErrorComment();
    source.respondTime = 0;
    source.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

    final seenCategories = <SourceHealthCategory>{};
    for (final nextHealth in <SourceRuntimeHealth>[health, ...extraHealths]) {
      if (!seenCategories.add(nextHealth.category)) {
        continue;
      }
      _applyHealthGroup(source, nextHealth);
    }

    if (message.trim().isNotEmpty) {
      source.addErrorComment(message.trim());
    }
    await _queueStatusWrite(source);
  }

  Future<void> _queueStatusWrite(BookSource source) async {
    _pendingStatusWrites[source.bookSourceUrl] = source;
    if (_pendingStatusWrites.length >= _statusWriteBatchSize) {
      await _flushPendingStatusWrites();
    }
  }

  Future<void> _flushPendingStatusWrites() async {
    if (_pendingStatusWrites.isEmpty) return;
    final writes = _pendingStatusWrites.values.toList(growable: false);
    _pendingStatusWrites.clear();
    await _sourceDao.upsertAll(writes);
  }

  void _applyHealthGroup(BookSource source, SourceRuntimeHealth health) {
    if (health.category != SourceHealthCategory.healthy) {
      source.addGroup(abnormalSourceGroupTag);
    }

    switch (health.category) {
      case SourceHealthCategory.healthy:
        break;
      case SourceHealthCategory.nonNovel:
        source.addGroup(nonNovelSourceGroupTag);
        break;
      case SourceHealthCategory.loginRequired:
        source.addGroup(loginRequiredSourceGroupTag);
        break;
      case SourceHealthCategory.downloadOnly:
        source.addGroup(downloadOnlySourceGroupTag);
        break;
      case SourceHealthCategory.searchBroken:
        source.addGroup(searchBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryBroken:
        source.addGroup(discoveryBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryDetailBroken:
        source.addGroup(discoveryDetailBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryTocBroken:
        source.addGroup(discoveryTocBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryContentBroken:
        source.addGroup(discoveryContentBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.detailBroken:
        source.addGroup(
          '$detailBrokenSourceGroupTag,$quarantineSourceGroupTag',
        );
        break;
      case SourceHealthCategory.tocBroken:
        source.addGroup('$tocBrokenSourceGroupTag,$quarantineSourceGroupTag');
        break;
      case SourceHealthCategory.contentBroken:
        source.addGroup(
          '$contentBrokenSourceGroupTag,$quarantineSourceGroupTag',
        );
        break;
      case SourceHealthCategory.upstreamUnstable:
        source.addGroup(
          '$upstreamBlockedSourceGroupTag,$timeoutSourceGroupTag,$quarantineSourceGroupTag',
        );
        break;
    }
  }

  void cancel() {
    if (!_isChecking) return;
    _isChecking = false;
    for (final handle in _activeTasks.values) {
      handle.abort();
    }
    _activeTasks.clear();
    _appendLog('收到取消指令，停止派發新校驗任務');
    _notifyIfAlive(immediate: true);
  }

  Future<SharedPreferences?> _safeGetPreferences() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  bool _shouldIgnoreSourceUpdate(String sourceUrl) =>
      _isDisposed || !_isChecking || _timedOutSourceUrls.contains(sourceUrl);

  Future<void> _primeSourceExecutionTraits(List<String> sourceUrls) async {
    final payloads = <Map<String, dynamic>>[];
    for (final sourceUrl in sourceUrls) {
      if (_shouldIgnoreSourceUpdate(sourceUrl)) continue;
      final source = await _sourceDao.getByUrl(sourceUrl);
      if (source != null) {
        payloads.add(source.toJson());
      }
    }
    if (payloads.isEmpty) return;

    try {
      final classified = await compute(
        _classifySourceExecutionTraitsForIsolate,
        payloads,
      );
      _jsHeavySourceCache.addAll(classified);
    } catch (error, stack) {
      AppLog.e('書源校驗背景特徵分類失敗，改用主 isolate', error: error, stackTrace: stack);
      for (final payload in payloads) {
        final source = BookSource.fromJson(payload);
        _cacheSourceExecutionTraits(source);
      }
    }
  }

  bool _isJsHeavySource(String sourceUrl) {
    final cached = _jsHeavySourceCache[sourceUrl];
    if (cached != null) return cached;

    // Fallback when prime/classification missed this URL — only the most
    // specific markers, since URLs commonly contain unrelated "java" text.
    final normalized = sourceUrl.toLowerCase();
    final looksJsByUrl =
        normalized.contains('<js>') ||
        normalized.contains('@js:') ||
        _kJsBridgeCallPattern.hasMatch(normalized);
    _jsHeavySourceCache[sourceUrl] = looksJsByUrl;
    return looksJsByUrl;
  }

  void _cacheSourceExecutionTraits(BookSource source) {
    _jsHeavySourceCache[source.bookSourceUrl] = _sourceLooksJsHeavy(source);
  }

  bool _sourceLooksJsHeavy(BookSource source) {
    if (_hasExplicitJsFields(source)) {
      return true;
    }
    return _containsRuleJs(<String?>[
      source.searchUrl,
      source.exploreUrl,
      source.jsLib,
      source.loginCheckJs,
      source.coverDecodeJs,
      source.ruleSearch?.checkKeyWord,
      source.ruleSearch?.bookList,
      source.ruleSearch?.name,
      source.ruleSearch?.author,
      source.ruleSearch?.intro,
      source.ruleSearch?.kind,
      source.ruleSearch?.lastChapter,
      source.ruleSearch?.updateTime,
      source.ruleSearch?.bookUrl,
      source.ruleSearch?.coverUrl,
      source.ruleSearch?.wordCount,
      source.ruleExplore?.bookList,
      source.ruleExplore?.name,
      source.ruleExplore?.author,
      source.ruleExplore?.intro,
      source.ruleExplore?.kind,
      source.ruleExplore?.lastChapter,
      source.ruleExplore?.updateTime,
      source.ruleExplore?.bookUrl,
      source.ruleExplore?.coverUrl,
      source.ruleExplore?.wordCount,
      source.ruleBookInfo?.init,
      source.ruleBookInfo?.name,
      source.ruleBookInfo?.author,
      source.ruleBookInfo?.intro,
      source.ruleBookInfo?.kind,
      source.ruleBookInfo?.lastChapter,
      source.ruleBookInfo?.updateTime,
      source.ruleBookInfo?.coverUrl,
      source.ruleBookInfo?.tocUrl,
      source.ruleBookInfo?.wordCount,
      source.ruleBookInfo?.canReName,
      source.ruleBookInfo?.downloadUrls,
      source.ruleToc?.preUpdateJs,
      source.ruleToc?.chapterList,
      source.ruleToc?.chapterName,
      source.ruleToc?.chapterUrl,
      source.ruleToc?.formatJs,
      source.ruleToc?.isVolume,
      source.ruleToc?.isVip,
      source.ruleToc?.isPay,
      source.ruleToc?.updateTime,
      source.ruleToc?.nextTocUrl,
      source.ruleContent?.content,
      source.ruleContent?.title,
      source.ruleContent?.nextContentUrl,
      source.ruleContent?.webJs,
      source.ruleContent?.sourceRegex,
      source.ruleContent?.replaceRegex,
      source.ruleContent?.imageStyle,
      source.ruleContent?.imageDecode,
      source.ruleContent?.payAction,
    ]);
  }

  bool _hasExplicitJsFields(BookSource source) {
    return <String?>[
      source.jsLib,
      source.loginCheckJs,
      source.coverDecodeJs,
      source.ruleToc?.preUpdateJs,
      source.ruleToc?.formatJs,
      source.ruleContent?.webJs,
    ].any((value) => value != null && value.trim().isNotEmpty);
  }

  bool _containsRuleJs(Iterable<String?> values) {
    for (final value in values) {
      if (value == null || value.isEmpty) continue;
      final normalized = value.toLowerCase();
      if (normalized.contains('<js>') ||
          normalized.contains('@js:') ||
          normalized.startsWith('@js') ||
          _kJsBridgeCallPattern.hasMatch(normalized)) {
        return true;
      }
    }
    return false;
  }

  String _sourceDomainKey(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    final host = uri?.host.trim();
    if (host != null && host.isNotEmpty) {
      return host;
    }
    return sourceUrl.trim().isEmpty ? 'unknown' : sourceUrl.trim();
  }

  void _appendLog(String msg, {String? sourceUrl, bool force = false}) {
    if (_isDisposed) return;
    if (!force && sourceUrl != null && _shouldIgnoreSourceUpdate(sourceUrl)) {
      return;
    }
    _logs.add(SourceCheckLogEntry(time: DateTime.now(), message: msg));
    if (_logs.length > 400) {
      _logs.removeAt(0);
    }
    _eventBus.fire(AppEvent(AppEventBus.checkSource, data: msg));
    _notifyIfAlive();
  }

  void _setSourceProgress(
    BookSource source,
    String message, {
    required bool isFinal,
    required bool hasIssue,
    bool force = false,
  }) {
    if (_isDisposed) return;
    if (!force && _shouldIgnoreSourceUpdate(source.bookSourceUrl)) return;
    _sourceProgress[source.bookSourceUrl] = SourceCheckProgress(
      sourceName: source.bookSourceName,
      message: message,
      isFinal: isFinal,
      hasIssue: hasIssue,
    );
  }

  void _notifyIfAlive({bool immediate = false}) {
    if (_isDisposed) return;
    if (immediate || !_isChecking) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      notifyListeners();
      return;
    }
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(_notifyThrottleInterval, () {
      if (_isDisposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isChecking = false;
    for (final handle in _activeTasks.values) {
      handle.abort();
    }
    _activeTasks.clear();
    _pendingStatusWrites.clear();
    _notifyTimer?.cancel();
    _notifyTimer = null;
    super.dispose();
  }
}

String _compactMessage(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return '未知錯誤';
  }
  final firstLine = trimmed.split('\n').first.trim();
  return firstLine.length > 220
      ? '${firstLine.substring(0, 220)}...'
      : firstLine;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _threeDigits(int value) => value.toString().padLeft(3, '0');
