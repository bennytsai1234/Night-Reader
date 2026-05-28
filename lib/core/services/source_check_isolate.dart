import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/source_validation_context.dart';

// ═══════════════════════════════════════════════════════════════════
//  Public types
// ═══════════════════════════════════════════════════════════════════

class IsolateCheckConfig {
  final String keyword;
  final int timeoutSeconds;
  final bool checkSearch;
  final bool checkDiscovery;
  final bool checkInfo;
  final bool checkCategory;
  final bool checkContent;

  const IsolateCheckConfig({
    required this.keyword,
    required this.timeoutSeconds,
    required this.checkSearch,
    required this.checkDiscovery,
    required this.checkInfo,
    required this.checkCategory,
    required this.checkContent,
  });

  Duration get timeoutDuration => Duration(seconds: timeoutSeconds);

  Map<String, dynamic> toMap() => {
    'keyword': keyword,
    'timeoutSeconds': timeoutSeconds,
    'checkSearch': checkSearch,
    'checkDiscovery': checkDiscovery,
    'checkInfo': checkInfo,
    'checkCategory': checkCategory,
    'checkContent': checkContent,
  };

  factory IsolateCheckConfig.fromMap(Map<String, dynamic> map) =>
      IsolateCheckConfig(
        keyword: map['keyword'] as String,
        timeoutSeconds: map['timeoutSeconds'] as int,
        checkSearch: map['checkSearch'] as bool,
        checkDiscovery: map['checkDiscovery'] as bool,
        checkInfo: map['checkInfo'] as bool,
        checkCategory: map['checkCategory'] as bool,
        checkContent: map['checkContent'] as bool,
      );
}

class SourceCheckIsolateResult {
  final String stage;
  final String message;
  final bool isHealthy;
  final Map<String, dynamic> updatedSourceJson;
  final List<String> logs;

  const SourceCheckIsolateResult({
    required this.stage,
    required this.message,
    required this.isHealthy,
    required this.updatedSourceJson,
    required this.logs,
  });

  Map<String, dynamic> toMap() => {
    'stage': stage,
    'message': message,
    'isHealthy': isHealthy,
    'updatedSourceJson': updatedSourceJson,
    'logs': logs,
  };

  factory SourceCheckIsolateResult.fromMap(Map<String, dynamic> map) =>
      SourceCheckIsolateResult(
        stage: map['stage'] as String,
        message: map['message'] as String,
        isHealthy: map['isHealthy'] as bool,
        updatedSourceJson: Map<String, dynamic>.from(
          map['updatedSourceJson'] as Map,
        ),
        logs: List<String>.from(map['logs'] as List),
      );
}

class SourceCheckIsolateHandle {
  final Future<SourceCheckIsolateResult?> result;
  final void Function() abort;

  const SourceCheckIsolateHandle({required this.result, required this.abort});
}

// ═══════════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════════

/// Spawns a background [Isolate] that runs a full source check.
/// The [timeout] kills the isolate if it hasn't finished in time.
/// Returns null on timeout, cancel, or spawn failure — caller treats null as
/// a timeout/abnormal result.
Future<SourceCheckIsolateHandle> spawnSourceCheck(
  BookSource source,
  IsolateCheckConfig config,
  Duration timeout,
) async {
  final receivePort = ReceivePort();
  final completer = Completer<SourceCheckIsolateResult?>();

  late final Isolate isolate;
  late final Timer timer;

  void abort() {
    if (completer.isCompleted) return;
    timer.cancel();
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    completer.complete(null);
  }

  try {
    isolate = await Isolate.spawn(
      _sourceCheckIsolateEntry,
      <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'sourceJson': source.toJson(),
        'configJson': config.toMap(),
        'rootToken': RootIsolateToken.instance,
      },
      errorsAreFatal: false,
      onError: receivePort.sendPort,
    );
  } catch (_) {
    receivePort.close();
    return SourceCheckIsolateHandle(
      result: Future<SourceCheckIsolateResult?>.value(null),
      abort: () {},
    );
  }

  timer = Timer(timeout, abort);

  receivePort.listen((message) {
    if (completer.isCompleted) return;
    timer.cancel();
    receivePort.close();
    if (message is Map) {
      try {
        completer.complete(
          SourceCheckIsolateResult.fromMap(Map<String, dynamic>.from(message)),
        );
        return;
      } catch (_) {}
    }
    // message is List (isolate uncaught error / 內部捕捉錯誤) 或其他非預期型別。
    // 先把真實錯誤寫進 app 內置崩潰日誌，再以 null 收尾，避免被誤判為「整體校驗超時」。
    if (message is List) {
      final err = message.isNotEmpty ? message[0]?.toString() ?? '' : '';
      final stack = message.length > 1 ? message[1]?.toString() : null;
      CrashHandler.recordError(
        '書源校驗 isolate 失敗 [${source.bookSourceName}] '
        '(${source.bookSourceUrl}): $err',
        (stack == null || stack.isEmpty) ? null : StackTrace.fromString(stack),
      );
    }
    completer.complete(null);
  });

  return SourceCheckIsolateHandle(result: completer.future, abort: abort);
}

// ═══════════════════════════════════════════════════════════════════
//  Isolate entry (must be top-level)
// ═══════════════════════════════════════════════════════════════════

void _sourceCheckIsolateEntry(Map<String, dynamic> args) {
  final sendPort = args['sendPort'] as SendPort;
  final rootToken = args['rootToken'] as RootIsolateToken?;
  // 讓背景 isolate 能使用 platform channel（例如書源 JS 檔案 API 走的
  // path_provider）。get_it 仍為空，DAO 類依賴另以記憶體模式退化處理。
  if (rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  }
  final sourceJson = Map<String, dynamic>.from(args['sourceJson'] as Map);
  final configJson = Map<String, dynamic>.from(args['configJson'] as Map);

  SourceValidationContext.runNonInteractive(() async {
    try {
      // isolate 為全新記憶體空間，主 isolate 的 NetworkService.init() 不跨
      // isolate 生效，需在此自行初始化。用 ephemeral 記憶體 cookie jar，
      // 避開 path_provider 與多個校驗 isolate 的檔案競爭。
      await NetworkService().init(ephemeral: true);
      final source = BookSource.fromJson(sourceJson);
      final config = IsolateCheckConfig.fromMap(configJson);
      final checker = _IsolateSourceChecker(source: source, config: config);
      final result = await checker.run();
      sendPort.send(result.toMap());
    } catch (e, st) {
      // 把 isolate 內捕捉到的真實錯誤以 List 形式送回主線程（與 onError 同型別），
      // 由主線程寫進崩潰日誌；不再靜默吞錯造成「整體校驗超時」的假象。
      sendPort.send(<String>['SourceCheckIsolate caught: $e', st.toString()]);
    }
  });
}

// ═══════════════════════════════════════════════════════════════════
//  Private enums / types used inside the isolate
// ═══════════════════════════════════════════════════════════════════

enum _CheckMode { search, discovery }

extension on _CheckMode {
  String get label => this == _CheckMode.search ? '搜尋' : '發現';
}

class _IssueData {
  final String stage;
  final String message;
  final SourceRuntimeHealth health;

  const _IssueData({
    required this.stage,
    required this.message,
    required this.health,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  Core checker (runs inside the isolate)
// ═══════════════════════════════════════════════════════════════════

class _IsolateSourceChecker {
  final BookSource _source;
  final IsolateCheckConfig _config;
  final BookSourceService _service = BookSourceService();
  final List<String> _logs = [];

  static const int _validationPageConcurrency = 1;
  static const int _validationChapterLimit = 8;
  static const int _validationContentProbeLimit = 5;

  _IsolateSourceChecker({
    required BookSource source,
    required IsolateCheckConfig config,
  }) : _source = source,
       _config = config;

  Future<SourceCheckIsolateResult> run() async {
    _source.removeInvalidGroups();
    _source.removeErrorComment();
    _source.respondTime = 0;
    _source.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

    _log('⇒ 正在校驗 [${_source.bookSourceName}] ...');

    final preflight = _resolvePreflightStatus();
    if (preflight != null) {
      _applyHealthToSource(preflight.health, preflight.message);
      _log('  ✕ [${_source.bookSourceName}] ${preflight.message}');
      return _buildResult(preflight.stage, preflight.message, isHealthy: false);
    }

    final issues = <_IssueData>[];

    if (_config.checkSearch) {
      await _runSearchCheck(issues);
    } else {
      _log('  ≡ 跳過搜尋檢查');
    }

    if (_hasTerminalIssue(issues)) {
      _log('  ≡ 跳過發現檢查: 已判定來源需清理或隔離');
    } else if (_config.checkDiscovery) {
      await _runDiscoveryCheck(issues, runBookFlow: !_config.checkSearch);
    } else {
      _log('  ≡ 跳過發現檢查');
    }

    if (issues.isEmpty) {
      _applyHealthToSource(SourceRuntimeHealth.healthy, '');
      _log('  ✓ [${_source.bookSourceName}] 校驗成功');
      return _buildResult('done', '校驗成功', isHealthy: true);
    }

    final primary = _pickPrimary(issues);
    final mergedMessage = _composeMessage(issues);
    _applyHealthToSource(
      primary.health,
      mergedMessage,
      extraHealths: issues
          .where((i) => !identical(i, primary))
          .map((i) => i.health),
    );
    _log(
      '  ✕ [${_source.bookSourceName}] ${_source.runtimeHealth.label}: $mergedMessage',
    );
    return _buildResult(primary.stage, mergedMessage, isHealthy: false);
  }

  SourceCheckIsolateResult _buildResult(
    String stage,
    String message, {
    required bool isHealthy,
  }) {
    return SourceCheckIsolateResult(
      stage: stage,
      message: message,
      isHealthy: isHealthy,
      updatedSourceJson: _source.toJson(),
      logs: List<String>.from(_logs),
    );
  }

  // ── Pre-flight ──────────────────────────────────────────────────

  _IssueData? _resolvePreflightStatus() {
    if (!_source.isNovelTextSource) {
      return const _IssueData(
        stage: 'filter',
        message: '來源不是純文字小說書源',
        health: SourceRuntimeHealth(
          category: SourceHealthCategory.nonNovel,
          label: nonNovelSourceGroupTag,
          description: '來源不是純文字小說書源',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: true,
          quarantined: false,
        ),
      );
    }
    if (_source.bookSourceType != 0) {
      return const _IssueData(
        stage: 'filter',
        message: '來源不提供純文字正文',
        health: SourceRuntimeHealth(
          category: SourceHealthCategory.downloadOnly,
          label: downloadOnlySourceGroupTag,
          description: '來源不提供純文字正文',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: true,
          quarantined: false,
        ),
      );
    }
    return null;
  }

  // ── Search ──────────────────────────────────────────────────────

  Future<void> _runSearchCheck(List<_IssueData> issues) async {
    final searchWord = _source.getCheckKeyword(_config.keyword);
    final searchUrl = _source.searchUrl?.trim() ?? '';
    if (searchUrl.isEmpty) {
      _recordIssue(
        issues,
        const _IssueData(
          stage: 'search',
          message: '搜尋連結規則為空',
          health: SourceRuntimeHealth(
            category: SourceHealthCategory.searchBroken,
            label: searchBrokenSourceGroupTag,
            description: '搜尋規則已失效',
            allowsSearch: false,
            allowsReading: true,
            cleanupCandidate: false,
            quarantined: false,
          ),
        ),
      );
      return;
    }

    _log('  ◇ 測試搜尋: $searchWord');
    try {
      final searchResults = await _service
          .searchBooks(_source, searchWord)
          .timeout(
            _config.timeoutDuration,
            onTimeout: () => throw TimeoutException('搜尋超時'),
          );

      if (searchResults.isEmpty) {
        _recordIssue(
          issues,
          _IssueData(
            stage: 'search',
            message: '搜尋結果為空 ($searchWord)',
            health: const SourceRuntimeHealth(
              category: SourceHealthCategory.searchBroken,
              label: searchBrokenSourceGroupTag,
              description: '搜尋沒有結果',
              allowsSearch: false,
              allowsReading: true,
              cleanupCandidate: false,
              quarantined: false,
            ),
          ),
        );
        return;
      }

      final seedBook = searchResults.first.toBook().copyWith(
        origin: _source.bookSourceUrl,
        originName: _source.bookSourceName,
        originOrder: _source.customOrder,
      );
      await _checkBookFlow(seedBook, mode: _CheckMode.search, issues: issues);
    } on TimeoutException catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: 'search',
          error: e,
          fallbackMessage: '搜尋超時',
          mode: _CheckMode.search,
        ),
      );
    } catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: 'search',
          error: e,
          fallbackMessage: e.toString(),
          mode: _CheckMode.search,
        ),
      );
    }
  }

  // ── Discovery ───────────────────────────────────────────────────

  Future<void> _runDiscoveryCheck(
    List<_IssueData> issues, {
    required bool runBookFlow,
  }) async {
    final exploreUrl = _source.exploreUrl?.trim() ?? '';
    if (exploreUrl.isEmpty) {
      _log('  ≡ 跳過發現檢查: 未配置發現網址');
      return;
    }

    _log('  ◇ 解析發現規則');
    try {
      final kinds = await ExploreUrlParser.parseAsync(
        exploreUrl,
        source: _source,
        jsTimeout: _config.timeoutDuration,
      ).timeout(_config.timeoutDuration);

      String? targetUrl;
      for (final kind in kinds) {
        final candidate = kind.url?.trim();
        if (candidate == null || candidate.isEmpty) continue;
        if (kind.title.startsWith('ERROR:')) continue;
        targetUrl = candidate;
        break;
      }

      if (targetUrl == null || targetUrl.isEmpty) {
        _recordIssue(
          issues,
          const _IssueData(
            stage: 'discovery',
            message: '發現規則為空或沒有可用入口',
            health: SourceRuntimeHealth(
              category: SourceHealthCategory.discoveryBroken,
              label: discoveryBrokenSourceGroupTag,
              description: '發現規則已失效',
              allowsSearch: true,
              allowsReading: true,
              cleanupCandidate: false,
              quarantined: false,
            ),
          ),
        );
        return;
      }

      _log('  ◇ 測試發現: $targetUrl');
      final books = await _service
          .exploreBooks(_source, targetUrl)
          .timeout(
            _config.timeoutDuration,
            onTimeout: () => throw TimeoutException('發現檢查超時'),
          );

      if (books.isEmpty) {
        _recordIssue(
          issues,
          const _IssueData(
            stage: 'discovery',
            message: '發現頁沒有結果',
            health: SourceRuntimeHealth(
              category: SourceHealthCategory.discoveryBroken,
              label: discoveryBrokenSourceGroupTag,
              description: '發現規則已失效',
              allowsSearch: true,
              allowsReading: true,
              cleanupCandidate: false,
              quarantined: false,
            ),
          ),
        );
        return;
      }

      if (!runBookFlow) {
        _log('  ✓ 發現列表可用，standard 模式不重複詳情/目錄/正文');
        return;
      }

      final seedBook = books.first.toBook().copyWith(
        origin: _source.bookSourceUrl,
        originName: _source.bookSourceName,
        originOrder: _source.customOrder,
      );
      await _checkBookFlow(
        seedBook,
        mode: _CheckMode.discovery,
        issues: issues,
      );
    } on TimeoutException catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: 'discovery',
          error: e,
          fallbackMessage: '發現檢查超時',
          mode: _CheckMode.discovery,
        ),
      );
    } catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: 'discovery',
          error: e,
          fallbackMessage: e.toString(),
          mode: _CheckMode.discovery,
        ),
      );
    }
  }

  // ── Book flow ────────────────────────────────────────────────────

  Future<void> _checkBookFlow(
    Book seedBook, {
    required _CheckMode mode,
    required List<_IssueData> issues,
  }) async {
    if (!_config.checkInfo) return;

    Book book = seedBook;
    try {
      _log('  ◇ 測試${mode.label}詳情: ${book.name}');
      book = await _service
          .getBookInfo(_source, book)
          .timeout(
            _config.timeoutDuration,
            onTimeout: () => throw TimeoutException('${mode.label}詳情檢查超時'),
          );

      if (book.name.trim().isEmpty || book.bookUrl.trim().isEmpty) {
        _recordIssue(
          issues,
          _IssueData(
            stage: _stageFor(mode, 'detail'),
            message: mode == _CheckMode.search ? '詳情頁返回空資料' : '發現詳情頁返回空資料',
            health: _detailHealthFor(mode),
          ),
        );
        return;
      }
    } on TimeoutException catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: _stageFor(mode, 'detail'),
          error: e,
          fallbackMessage: '${mode.label}詳情檢查超時',
          mode: mode,
        ),
      );
      return;
    } catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: _stageFor(mode, 'detail'),
          error: e,
          fallbackMessage: e.toString(),
          mode: mode,
        ),
      );
      return;
    }

    if (!_config.checkCategory) return;

    List<BookChapter> readableChapters;
    try {
      _log('  ◇ 測試${mode.label}目錄: ${book.name}');
      final chapters = await _service
          .getChapterList(
            _source,
            book,
            chapterLimit: _validationChapterLimit,
            pageConcurrency: _validationPageConcurrency,
          )
          .timeout(
            _config.timeoutDuration,
            onTimeout: () => throw TimeoutException('${mode.label}目錄檢查超時'),
          );
      readableChapters = chapters.where((c) => !c.isVolume).toList();
    } on TimeoutException catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: _stageFor(mode, 'toc'),
          error: e,
          fallbackMessage: '${mode.label}目錄檢查超時',
          mode: mode,
        ),
      );
      return;
    } catch (e) {
      _recordIssue(
        issues,
        _issueFromException(
          stage: _stageFor(mode, 'toc'),
          error: e,
          fallbackMessage: e.toString(),
          mode: mode,
        ),
      );
      return;
    }

    if (readableChapters.isEmpty) {
      final health =
          _looksLikeDownloadOnly(book, readableChapters)
              ? const SourceRuntimeHealth(
                category: SourceHealthCategory.downloadOnly,
                label: downloadOnlySourceGroupTag,
                description: '來源只提供下載，不提供線上正文閱讀',
                allowsSearch: false,
                allowsReading: false,
                cleanupCandidate: true,
                quarantined: false,
              )
              : _tocHealthFor(mode);
      final message =
          health.category == SourceHealthCategory.downloadOnly
              ? '來源為下載站，不提供線上目錄'
              : mode == _CheckMode.search
              ? '目錄抓取失敗或沒有可閱讀章節'
              : '發現書籍目錄抓取失敗或沒有可閱讀章節';
      _recordIssue(
        issues,
        _IssueData(
          stage: _stageFor(mode, 'toc'),
          message: message,
          health: health,
        ),
      );
      return;
    }

    if (_looksLikeDownloadOnly(book, readableChapters)) {
      _recordIssue(
        issues,
        const _IssueData(
          stage: 'toc',
          message: '來源為下載站，不提供線上正文',
          health: SourceRuntimeHealth(
            category: SourceHealthCategory.downloadOnly,
            label: downloadOnlySourceGroupTag,
            description: '來源只提供下載，不提供線上正文閱讀',
            allowsSearch: false,
            allowsReading: false,
            cleanupCandidate: true,
            quarantined: false,
          ),
        ),
      );
      return;
    }

    final lockedChapter = _firstLockedChapter(readableChapters);
    if (lockedChapter != null) {
      _recordIssue(issues, _lockedChapterIssue(mode, lockedChapter));
      return;
    }

    if (!_config.checkContent) return;

    await _runContentProbeCheck(
      book,
      readableChapters,
      mode: mode,
      issues: issues,
    );
  }

  // ── Content probe ────────────────────────────────────────────────

  Future<void> _runContentProbeCheck(
    Book book,
    List<BookChapter> readableChapters, {
    required _CheckMode mode,
    required List<_IssueData> issues,
  }) async {
    final probeIndexes = _buildContentProbeIndexes(
      readableChapters,
      _validationContentProbeLimit,
    );
    var probedCount = 0;

    for (final chapterIndex in probeIndexes) {
      final chapter = readableChapters[chapterIndex];
      final nextChapterUrl = _nextReadableChapterUrl(readableChapters, chapter);

      try {
        probedCount++;
        _log('  ◇ 測試${mode.label}正文: ${chapter.title}');
        final content = await _service
            .getContent(
              _source,
              book,
              chapter,
              nextChapterUrl: nextChapterUrl,
              pageConcurrency: _validationPageConcurrency,
            )
            .timeout(
              _config.timeoutDuration,
              onTimeout: () => throw TimeoutException('${mode.label}正文檢查超時'),
            );

        if (_looksLikeLoginRequired(content)) {
          _recordIssue(
            issues,
            _IssueData(
              stage: _stageFor(mode, 'content'),
              message: '正文需要登入、VIP 或解鎖後閱讀',
              health: _kLoginRequiredHealth,
            ),
          );
          return;
        }

        if (_looksReadable(content)) return;
      } on TimeoutException catch (e) {
        _recordIssue(
          issues,
          _issueFromException(
            stage: _stageFor(mode, 'content'),
            error: e,
            fallbackMessage: '${mode.label}正文檢查超時',
            mode: mode,
          ),
        );
        return;
      } catch (e) {
        _recordIssue(
          issues,
          _issueFromException(
            stage: _stageFor(mode, 'content'),
            error: e,
            fallbackMessage: e.toString(),
            mode: mode,
          ),
        );
        return;
      }
    }

    _recordIssue(
      issues,
      _IssueData(
        stage: _stageFor(mode, 'content'),
        message:
            mode == _CheckMode.search
                ? '前 $probedCount 個候選章節正文內容過短或為空'
                : '發現書籍前 $probedCount 個候選章節正文內容過短或為空',
        health: _contentHealthFor(mode),
      ),
    );
  }

  // ── Issue helpers ────────────────────────────────────────────────

  void _recordIssue(List<_IssueData> issues, _IssueData issue) {
    issues.add(issue);
    _log(
      '  ! [${_source.bookSourceName}] ${_stageLabel(issue.stage)}: ${issue.message}',
    );
  }

  void _log(String msg) => _logs.add(msg);

  _IssueData _issueFromException({
    required String stage,
    required Object error,
    required String fallbackMessage,
    required _CheckMode mode,
  }) {
    final normalized = error.toString().toLowerCase();
    final message = _compactMessage(fallbackMessage);

    // 診斷：保留未截斷的原始錯誤。ParsingException.toString() 內含
    // originalError（真正的 JS/解析失敗原因），但 _compactMessage 只取首行會
    // 截掉它。標記後帶回主線程，由主線程過濾寫進崩潰日誌。
    _log('§DIAG§ [$stage] $error');

    if (error is SourceInteractionBlockedException ||
        _looksLikeInteractiveVerificationBlock(normalized)) {
      return _IssueData(
        stage: stage,
        message: message,
        health: const SourceRuntimeHealth(
          category: SourceHealthCategory.upstreamUnstable,
          label: quarantineSourceGroupTag,
          description: '批量校驗跳過人工驗證，來源先隔離但不視為永久失效',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: false,
          quarantined: true,
        ),
      );
    }

    if (error is LoginCheckException ||
        normalized.contains('需要登入後閱讀') ||
        normalized.contains('需要登录后阅读') ||
        normalized.contains('loginrequired') ||
        normalized.contains('permissionlimit') ||
        normalized.contains('vip') ||
        normalized.contains('鎖章') ||
        normalized.contains('锁章') ||
        normalized.contains('解鎖') ||
        normalized.contains('解锁') ||
        normalized.contains('付費') ||
        normalized.contains('付费')) {
      return const _IssueData(
        stage: 'content',
        message: '正文需要登入後閱讀',
        health: _kLoginRequiredHealth,
      );
    }

    if (_looksLikeTimeout(normalized)) {
      return const _IssueData(
        stage: 'timeout',
        message: '校驗超時或來源響應過慢',
        health: SourceRuntimeHealth(
          category: SourceHealthCategory.upstreamUnstable,
          label: quarantineSourceGroupTag,
          description: '上游暫時不可用，來源先隔離但不視為永久失效',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: false,
          quarantined: true,
        ),
      );
    }

    if (_looksLikeBlockedUpstream(normalized)) {
      return _IssueData(
        stage: 'upstream',
        message: message,
        health: const SourceRuntimeHealth(
          category: SourceHealthCategory.upstreamUnstable,
          label: quarantineSourceGroupTag,
          description: '上游暫時不可用，來源先隔離但不視為永久失效',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: false,
          quarantined: true,
        ),
      );
    }

    if (mode == _CheckMode.discovery) {
      if (stage.endsWith('detail')) {
        return _IssueData(
          stage: stage,
          message: message,
          health: const SourceRuntimeHealth(
            category: SourceHealthCategory.discoveryDetailBroken,
            label: discoveryDetailBrokenSourceGroupTag,
            description: '發現書籍詳情失效',
            allowsSearch: true,
            allowsReading: true,
            cleanupCandidate: false,
            quarantined: false,
          ),
        );
      }
      if (stage.endsWith('toc')) {
        return _IssueData(
          stage: stage,
          message: message,
          health: const SourceRuntimeHealth(
            category: SourceHealthCategory.discoveryTocBroken,
            label: discoveryTocBrokenSourceGroupTag,
            description: '發現書籍目錄失效',
            allowsSearch: true,
            allowsReading: true,
            cleanupCandidate: false,
            quarantined: false,
          ),
        );
      }
      if (stage.endsWith('content')) {
        return _IssueData(
          stage: stage,
          message: message,
          health: const SourceRuntimeHealth(
            category: SourceHealthCategory.discoveryContentBroken,
            label: discoveryContentBrokenSourceGroupTag,
            description: '發現書籍正文失效',
            allowsSearch: true,
            allowsReading: true,
            cleanupCandidate: false,
            quarantined: false,
          ),
        );
      }
      return _IssueData(
        stage: stage,
        message: message,
        health: const SourceRuntimeHealth(
          category: SourceHealthCategory.discoveryBroken,
          label: discoveryBrokenSourceGroupTag,
          description: '發現規則已失效',
          allowsSearch: true,
          allowsReading: true,
          cleanupCandidate: false,
          quarantined: false,
        ),
      );
    }

    if (stage == 'search') {
      return _IssueData(
        stage: stage,
        message: message,
        health: const SourceRuntimeHealth(
          category: SourceHealthCategory.searchBroken,
          label: searchBrokenSourceGroupTag,
          description: '搜尋規則已失效',
          allowsSearch: false,
          allowsReading: true,
          cleanupCandidate: false,
          quarantined: false,
        ),
      );
    }

    if (stage.endsWith('detail')) {
      return _IssueData(
        stage: stage,
        message: message,
        health: const SourceRuntimeHealth(
          category: SourceHealthCategory.detailBroken,
          label: detailBrokenSourceGroupTag,
          description: '詳情頁無法正常解析',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: false,
          quarantined: true,
        ),
      );
    }

    if (stage.endsWith('toc')) {
      return _IssueData(
        stage: stage,
        message: message,
        health: const SourceRuntimeHealth(
          category: SourceHealthCategory.tocBroken,
          label: tocBrokenSourceGroupTag,
          description: '目錄抓取失敗或沒有可閱讀章節',
          allowsSearch: false,
          allowsReading: false,
          cleanupCandidate: false,
          quarantined: true,
        ),
      );
    }

    return _IssueData(
      stage: stage,
      message: message,
      health: const SourceRuntimeHealth(
        category: SourceHealthCategory.contentBroken,
        label: contentBrokenSourceGroupTag,
        description: '正文抓取失敗或無法閱讀',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: false,
        quarantined: true,
      ),
    );
  }

  // ── Health application ───────────────────────────────────────────

  void _applyHealthToSource(
    SourceRuntimeHealth health,
    String message, {
    Iterable<SourceRuntimeHealth> extraHealths = const <SourceRuntimeHealth>[],
  }) {
    final seenCategories = <SourceHealthCategory>{};
    for (final h in <SourceRuntimeHealth>[health, ...extraHealths]) {
      if (!seenCategories.add(h.category)) continue;
      _applyHealthGroup(h);
    }
    if (message.trim().isNotEmpty) {
      _source.addErrorComment(message.trim());
    }
  }

  void _applyHealthGroup(SourceRuntimeHealth health) {
    if (health.category != SourceHealthCategory.healthy) {
      _source.addGroup(abnormalSourceGroupTag);
    }
    switch (health.category) {
      case SourceHealthCategory.healthy:
        break;
      case SourceHealthCategory.nonNovel:
        _source.addGroup(nonNovelSourceGroupTag);
        break;
      case SourceHealthCategory.loginRequired:
        _source.addGroup(loginRequiredSourceGroupTag);
        break;
      case SourceHealthCategory.downloadOnly:
        _source.addGroup(downloadOnlySourceGroupTag);
        break;
      case SourceHealthCategory.searchBroken:
        _source.addGroup(searchBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryBroken:
        _source.addGroup(discoveryBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryDetailBroken:
        _source.addGroup(discoveryDetailBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryTocBroken:
        _source.addGroup(discoveryTocBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.discoveryContentBroken:
        _source.addGroup(discoveryContentBrokenSourceGroupTag);
        break;
      case SourceHealthCategory.detailBroken:
        _source.addGroup(
          '$detailBrokenSourceGroupTag,$quarantineSourceGroupTag',
        );
        break;
      case SourceHealthCategory.tocBroken:
        _source.addGroup('$tocBrokenSourceGroupTag,$quarantineSourceGroupTag');
        break;
      case SourceHealthCategory.contentBroken:
        _source.addGroup(
          '$contentBrokenSourceGroupTag,$quarantineSourceGroupTag',
        );
        break;
      case SourceHealthCategory.upstreamUnstable:
        _source.addGroup(
          '$upstreamBlockedSourceGroupTag,$timeoutSourceGroupTag,$quarantineSourceGroupTag',
        );
        break;
    }
  }

  // ── Aggregation helpers ─────────────────────────────────────────

  _IssueData _pickPrimary(List<_IssueData> issues) {
    var primary = issues.first;
    for (final issue in issues.skip(1)) {
      if (_issuePriority(issue.health.category) >
          _issuePriority(primary.health.category)) {
        primary = issue;
      }
    }
    return primary;
  }

  String _composeMessage(List<_IssueData> issues) {
    final seen = <String>{};
    final parts = <String>[];
    for (final issue in issues) {
      final part = '${_stageLabel(issue.stage)}: ${issue.message}';
      if (seen.add(part)) parts.add(part);
    }
    return _compactMessage(parts.join('；'));
  }

  bool _hasTerminalIssue(List<_IssueData> issues) =>
      issues.any((i) => i.health.cleanupCandidate || i.health.quarantined);

  String? _nextReadableChapterUrl(
    List<BookChapter> chapters,
    BookChapter current,
  ) {
    final startIndex = chapters.indexOf(current);
    if (startIndex < 0) return null;
    for (var i = startIndex + 1; i < chapters.length; i++) {
      if (!chapters[i].isVolume && chapters[i].url.isNotEmpty) {
        return chapters[i].url;
      }
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Pure helper functions (private, duplicated from check logic)
// ═══════════════════════════════════════════════════════════════════

const _kLoginRequiredHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.loginRequired,
  label: loginRequiredSourceGroupTag,
  description: '來源需要登入、VIP 或解鎖後才能閱讀',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: true,
  quarantined: false,
);

String _stageFor(_CheckMode mode, String detailStage) =>
    mode == _CheckMode.search ? detailStage : 'discovery:$detailStage';

SourceRuntimeHealth _detailHealthFor(_CheckMode mode) {
  if (mode == _CheckMode.search) {
    return const SourceRuntimeHealth(
      category: SourceHealthCategory.detailBroken,
      label: detailBrokenSourceGroupTag,
      description: '詳情頁無法正常解析',
      allowsSearch: false,
      allowsReading: false,
      cleanupCandidate: false,
      quarantined: true,
    );
  }
  return const SourceRuntimeHealth(
    category: SourceHealthCategory.discoveryDetailBroken,
    label: discoveryDetailBrokenSourceGroupTag,
    description: '發現書籍詳情失效',
    allowsSearch: true,
    allowsReading: true,
    cleanupCandidate: false,
    quarantined: false,
  );
}

SourceRuntimeHealth _tocHealthFor(_CheckMode mode) {
  if (mode == _CheckMode.search) {
    return const SourceRuntimeHealth(
      category: SourceHealthCategory.tocBroken,
      label: tocBrokenSourceGroupTag,
      description: '目錄抓取失敗或沒有可閱讀章節',
      allowsSearch: false,
      allowsReading: false,
      cleanupCandidate: false,
      quarantined: true,
    );
  }
  return const SourceRuntimeHealth(
    category: SourceHealthCategory.discoveryTocBroken,
    label: discoveryTocBrokenSourceGroupTag,
    description: '發現書籍目錄失效',
    allowsSearch: true,
    allowsReading: true,
    cleanupCandidate: false,
    quarantined: false,
  );
}

SourceRuntimeHealth _contentHealthFor(_CheckMode mode) {
  if (mode == _CheckMode.search) {
    return const SourceRuntimeHealth(
      category: SourceHealthCategory.contentBroken,
      label: contentBrokenSourceGroupTag,
      description: '正文內容過短或為空',
      allowsSearch: false,
      allowsReading: false,
      cleanupCandidate: false,
      quarantined: true,
    );
  }
  return const SourceRuntimeHealth(
    category: SourceHealthCategory.discoveryContentBroken,
    label: discoveryContentBrokenSourceGroupTag,
    description: '發現書籍正文失效',
    allowsSearch: true,
    allowsReading: true,
    cleanupCandidate: false,
    quarantined: false,
  );
}

_IssueData _lockedChapterIssue(_CheckMode mode, BookChapter chapter) {
  final title = _compactChapterTitle(chapter.title);
  return _IssueData(
    stage: _stageFor(mode, 'content'),
    message:
        title.isEmpty ? '章節疑似 VIP/鎖章，需要登入或付費' : '章節疑似 VIP/鎖章，需要登入或付費: $title',
    health: _kLoginRequiredHealth,
  );
}

BookChapter? _firstLockedChapter(List<BookChapter> chapters) {
  for (final chapter in chapters) {
    if (_looksLikeLockedChapter(chapter)) return chapter;
  }
  return null;
}

bool _looksLikeLockedChapter(BookChapter chapter) {
  if (chapter.isVip && !chapter.isPay) return true;
  final normalized = chapter.title.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  const markers = <String>[
    '🔒',
    '[vip]',
    'vip',
    ' vip',
    'vip ',
    'vip章',
    'vip章节',
    'vip章節',
    'isvip',
    '鎖章',
    '锁章',
    '解鎖',
    '解锁',
    '付費',
    '付费',
    '收費',
    '收费',
    '訂閱',
    '订阅',
    '購買',
    '购买',
  ];
  return markers.any(normalized.contains);
}

List<int> _buildContentProbeIndexes(List<BookChapter> chapters, int maxProbe) {
  final preferred = <int>[];
  final fallback = <int>[];

  void addProbe(int index) {
    if (index < 0 || index >= chapters.length) return;
    if (preferred.contains(index) || fallback.contains(index)) return;
    if (_looksLikeLockedChapter(chapters[index])) {
      fallback.add(index);
    } else {
      preferred.add(index);
    }
  }

  final headCount = math.min(maxProbe, chapters.length);
  for (var i = 0; i < headCount; i++) addProbe(i);

  final tailStart = math.max(chapters.length - maxProbe, 0);
  for (var i = tailStart; i < chapters.length; i++) addProbe(i);

  return <int>[...preferred, ...fallback].take(maxProbe).toList();
}

bool _looksReadable(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('加載章節失敗')) return false;
  if (trimmed.startsWith('章節內容為空')) return false;
  return trimmed.runes.length >= 20;
}

bool _looksLikeLoginRequired(String content) {
  final normalized = content.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('permissionlimit') ||
      normalized.contains('loginrequired') ||
      normalized.contains('需要登入') ||
      normalized.contains('需要登录') ||
      normalized.contains('登入後閱讀') ||
      normalized.contains('登录后阅读') ||
      normalized.contains('請先登錄') ||
      normalized.contains('请先登录') ||
      normalized.contains('vip') ||
      normalized.contains('鎖章') ||
      normalized.contains('锁章') ||
      normalized.contains('解鎖') ||
      normalized.contains('解锁') ||
      normalized.contains('付費') ||
      normalized.contains('付费') ||
      normalized.contains('收費') ||
      normalized.contains('收费') ||
      normalized.contains('訂閱') ||
      normalized.contains('订阅') ||
      normalized.contains('購買') ||
      normalized.contains('购买');
}

bool _looksLikeDownloadOnly(Book book, List<BookChapter> readableChapters) {
  if (book.origin.isEmpty) return false;
  final urls = <String>[
    book.bookUrl.trim().toLowerCase(),
    book.tocUrl.trim().toLowerCase(),
    if (readableChapters.isNotEmpty)
      readableChapters.first.url.trim().toLowerCase(),
  ];
  const markers = <String>[
    'downbook.php',
    '/download/',
    'downajax',
    '.zip',
    '.rar',
    '.epub',
    '.txt',
  ];
  return urls.any((url) => markers.any(url.contains));
}

bool _looksLikeTimeout(String normalized) =>
    normalized.contains('timeout') ||
    normalized.contains('timed out') ||
    normalized.contains('socketexception') ||
    normalized.contains('handshakeexception') ||
    normalized.contains('ssl') ||
    normalized.contains('receivetimeout') ||
    normalized.contains('future not completed');

bool _looksLikeBlockedUpstream(String normalized) =>
    normalized.contains(' 401') ||
    normalized.contains(' 403') ||
    normalized.contains(' 404') ||
    normalized.contains(' 429') ||
    normalized.contains(' 502') ||
    normalized.contains(' 503') ||
    normalized.contains('forbidden') ||
    normalized.contains('cloudflare') ||
    normalized.contains('certificate_verify_failed');

bool _looksLikeInteractiveVerificationBlock(String normalized) =>
    normalized.contains('批量校驗不執行') ||
    normalized.contains('非互動校驗') ||
    normalized.contains('互動驗證') ||
    normalized.contains('人工驗證') ||
    normalized.contains('驗證碼') ||
    normalized.contains('验证码') ||
    normalized.contains('sourceinteractionblocked');

int _issuePriority(SourceHealthCategory category) {
  switch (category) {
    case SourceHealthCategory.nonNovel:
      return 100;
    case SourceHealthCategory.loginRequired:
      return 95;
    case SourceHealthCategory.downloadOnly:
      return 90;
    case SourceHealthCategory.contentBroken:
      return 80;
    case SourceHealthCategory.tocBroken:
      return 70;
    case SourceHealthCategory.detailBroken:
      return 60;
    case SourceHealthCategory.searchBroken:
      return 50;
    case SourceHealthCategory.upstreamUnstable:
      return 40;
    case SourceHealthCategory.discoveryDetailBroken:
      return 29;
    case SourceHealthCategory.discoveryTocBroken:
      return 28;
    case SourceHealthCategory.discoveryContentBroken:
      return 27;
    case SourceHealthCategory.discoveryBroken:
      return 26;
    case SourceHealthCategory.healthy:
      return 0;
  }
}

String _stageLabel(String stage) {
  switch (stage) {
    case 'search':
      return '搜尋';
    case 'discovery':
      return '發現';
    case 'detail':
      return '詳情';
    case 'toc':
      return '目錄';
    case 'content':
      return '正文';
    case 'discovery:detail':
      return '發現詳情';
    case 'discovery:toc':
      return '發現目錄';
    case 'discovery:content':
      return '發現正文';
    case 'filter':
      return '預檢';
    case 'timeout':
      return '超時';
    case 'upstream':
      return '上游';
    default:
      return stage;
  }
}

String _compactMessage(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '未知錯誤';
  final firstLine = trimmed.split('\n').first.trim();
  return firstLine.length > 220
      ? '${firstLine.substring(0, 220)}...'
      : firstLine;
}

String _compactChapterTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.length <= 40) return trimmed;
  return '${trimmed.substring(0, 40)}...';
}
