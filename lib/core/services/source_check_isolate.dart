import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/error_text.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/source_interaction.dart';

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

  /// 每個問題一段診斷（`SourceChecker._diagnosis`），主 isolate 寫進
  /// `SourceCheckDiagnostics`。
  final List<String> diagnostics;

  const SourceCheckIsolateResult({
    required this.stage,
    required this.message,
    required this.isHealthy,
    required this.updatedSourceJson,
    required this.logs,
    this.diagnostics = const [],
  });

  Map<String, dynamic> toMap() => {
    'stage': stage,
    'message': message,
    'isHealthy': isHealthy,
    'updatedSourceJson': updatedSourceJson,
    'logs': logs,
    'diagnostics': diagnostics,
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
        diagnostics: List<String>.from(map['diagnostics'] as List),
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

/// 開一個書源 worker（[SourceWorker]）校驗 [source]：和閱讀時一樣的環境，
/// 網頁渲染、Cloudflare 檢查、Cookie 與資料庫都交給主 isolate。到了
/// [timeout] 還沒做完就結束 worker，結果不再等它（[SourceWorker.kill]）。
/// 逾時、取消或開不起來時結果是 null，呼叫端當成逾時或異常。
Future<SourceCheckIsolateHandle> spawnSourceCheck(
  BookSource source,
  IsolateCheckConfig config,
  Duration timeout,
) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SourceCheck',
      withDictionaries: false,
    );
  } catch (e, stack) {
    AppLog.e('書源校驗 worker 開不起來: $e', error: e, stackTrace: stack);
    return SourceCheckIsolateHandle(
      result: Future<SourceCheckIsolateResult?>.value(null),
      abort: () {},
    );
  }

  final completer = Completer<SourceCheckIsolateResult?>();
  late final Timer timer;

  void finish(SourceCheckIsolateResult? result) {
    if (completer.isCompleted) return;
    timer.cancel();
    worker.kill(StateError('書源校驗已結束'));
    completer.complete(result);
  }

  timer = Timer(timeout, () => finish(null));
  unawaited(
    worker
        .run(_checkTask(source.toJson(), config.toMap()))
        .then(
          (map) => finish(SourceCheckIsolateResult.fromMap(map)),
          onError: (Object error, StackTrace stack) {
            // 先把真實錯誤寫進崩潰日誌，再以 null 收尾，避免被誤判為「整體校驗
            // 超時」；結束 worker 的那一次不算。
            if (!completer.isCompleted) {
              CrashHandler.recordError(
                '書源校驗失敗 [${source.bookSourceName}] '
                '(${source.bookSourceUrl}): $error',
                stack,
              );
            }
            finish(null);
          },
        ),
  );

  return SourceCheckIsolateHandle(
    result: completer.future,
    abort: () => finish(null),
  );
}

/// 在 worker 裡跑的校驗；只捕捉書源與設定的資料（`CODING_STANDARDS.md`）。
Future<Map<String, dynamic>> Function(CancelToken) _checkTask(
  Map<String, dynamic> sourceJson,
  Map<String, dynamic> configMap,
) => (_) async {
  final checker = SourceChecker(
    source: BookSource.fromJson(sourceJson),
    config: IsolateCheckConfig.fromMap(configMap),
  );
  return (await checker.run()).toMap();
};

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

/// 一個書源的校驗判定：依序測搜尋、發現、詳情、目錄與正文，把結果寫成
/// 書源的狀態分組與錯誤註解。背景 isolate 用它跑校驗；抓取都經過
/// [BookSourceService]，可以換成別的實作。
class SourceChecker {
  final BookSource _source;
  final IsolateCheckConfig _config;
  final BookSourceService _service;
  final List<String> _logs = [];
  final List<String> _diagnostics = [];

  /// 校驗送出的請求與網站的回應，依序（`recordRequestUrls`）。
  final RequestLog _requests = RequestLog(
    responsePreview: RequestLog.diagnosisPreview,
  );

  /// 網域查不到時查過網路本身通不通：true 是手機斷網了，null 是還沒查過。
  bool? _networkDown;

  /// 目前這一段（[_fetch]）的請求從 [_requests] 的哪一行開始。
  int _stageRequestStart = 0;

  static const int _validationPageConcurrency = 1;
  static const int _validationChapterLimit = 8;
  static const int _validationContentProbeLimit = 5;
  static const int _diagnosisRequestLimit = 16;
  static const int _diagnosisCodeLimit = 3000;
  static const Duration _transientRetryDelay = Duration(seconds: 1);

  SourceChecker({
    required this._source,
    required this._config,
    BookSourceService? service,
    Future<bool> Function()? networkCheck,
  }) : _service = service ?? BookSourceService(),
       _networkCheck = networkCheck ?? networkReachable;

  /// 網路本身通不通（[networkReachable]）。
  final Future<bool> Function() _networkCheck;

  Future<SourceCheckIsolateResult> run() => _requests.run(_run);

  Future<SourceCheckIsolateResult> _run() async {
    _source.removeInvalidGroups();
    _source.removeErrorComment();
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
      diagnostics: List<String>.from(_diagnostics),
    );
  }

  // ── Pre-flight ──────────────────────────────────────────────────

  /// 夜讀不支援的書源（影視、文件）不抓任何東西；漫畫、有聲源和小說一樣
  /// 跑完整流程，正文照抓到的內容判斷類型（ADR 0051）。
  _IssueData? _resolvePreflightStatus() {
    if (_source.sourceKind != BookSourceKind.unsupported) return null;
    return const _IssueData(
      stage: 'filter',
      message: '夜讀不支援的書源（影視、文件）',
      health: SourceRuntimeHealth(
        category: SourceHealthCategory.nonNovel,
        label: nonNovelSourceGroupTag,
        description: '夜讀不支援的書源（影視、文件）',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: true,
        quarantined: false,
      ),
    );
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
      final searchResults = await _fetch(
        '搜尋「$searchWord」',
        (_) => _service.searchBooks(_source, searchWord),
        cameBackEmpty: (results) => results.isEmpty,
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

      await _checkSearchedBooks(searchResults, issues);
    } catch (e) {
      _recordFailure(
        issues,
        stage: 'search',
        error: e,
        mode: _CheckMode.search,
      );
    }
  }

  /// 拿搜尋到的第一本書測詳情、目錄與正文。這本書打不開時換一本再測：
  /// 可能只是那本書的問題（例如還沒有章節、書號代進規則後出錯），兩本都
  /// 打不開才照書源壞了處理。
  Future<void> _checkSearchedBooks(
    List<SearchBook> searchResults,
    List<_IssueData> issues,
  ) async {
    final first = searchResults.first;
    final firstIssues = <_IssueData>[];
    await _checkBookFlow(
      _seedBook(first),
      mode: _CheckMode.search,
      issues: firstIssues,
    );
    final second = searchResults
        .skip(1)
        .where((book) => book.bookUrl != first.bookUrl)
        .firstOrNull;
    if (second == null || !firstIssues.any(_bookCannotOpen)) {
      issues.addAll(firstIssues);
      return;
    }

    _log('  ◇ 第一本書打不開，改測第二本: ${second.name}');
    final secondIssues = <_IssueData>[];
    await _checkBookFlow(
      _seedBook(second),
      mode: _CheckMode.search,
      issues: secondIssues,
    );
    if (secondIssues.any(_bookCannotOpen)) {
      issues.addAll(firstIssues);
      return;
    }
    _log('  ✓ 第二本書的詳情、目錄與正文沒有失效，第一本的失敗只算那本書的問題');
    issues.addAll(secondIssues);
  }

  Book _seedBook(SearchBook found) => found.toBook().copyWith(
    origin: _source.bookSourceUrl,
    originName: _source.bookSourceName,
    originOrder: _source.customOrder,
  );

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
      final kinds = await _fetch(
        '發現',
        (_) => ExploreUrlParser.parseAsync(exploreUrl, source: _source),
      );

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
      final books = await _fetch(
        '發現',
        (_) => _service.exploreBooks(_source, targetUrl!),
        cameBackEmpty: (books) => books.isEmpty,
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

      await _checkBookFlow(
        _seedBook(books.first),
        mode: _CheckMode.discovery,
        issues: issues,
      );
    } catch (e) {
      _recordFailure(
        issues,
        stage: 'discovery',
        error: e,
        mode: _CheckMode.discovery,
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
    final transientBeforeDetail = _requests.transientResponses;
    try {
      _log('  ◇ 測試${mode.label}詳情: ${book.name}');
      final seed = book;
      book = await _fetch(
        '${mode.label}詳情',
        (retrying) => _service.getBookInfo(
          _source,
          retrying ? _withoutStoredPages(seed) : seed,
        ),
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
    } catch (e) {
      _recordFailure(
        issues,
        stage: _stageFor(mode, 'detail'),
        error: e,
        mode: mode,
      );
      return;
    }

    if (!_config.checkCategory) return;

    List<BookChapter> readableChapters;
    try {
      _log('  ◇ 測試${mode.label}目錄: ${book.name}');
      final detailed = book;
      final chapters = await _fetch(
        '${mode.label}目錄',
        (retrying) => _service.getChapterList(
          _source,
          // 詳情頁抓回來時存著的目錄頁可能就是那份壞掉的，重試要重抓。
          retrying ? _withoutStoredPages(detailed) : detailed,
          // 要抽中段、後段的正文時讀完整目錄，分頁照讀書時同時抓：只讀前 8
          // 章時，「中後段」是第 6～8 章，第 8 章也沒有下一章當翻頁的停止點
          // （2026-11-14 改前改後整批校驗，47 個書源因此逾時）。
          chapterLimit: _config.checkContent ? null : _validationChapterLimit,
          pageConcurrency: _config.checkContent
              ? null
              : _validationPageConcurrency,
          // 有一頁抓不到時不拿殘缺的目錄抽樣（Codex 審查）。
          requireComplete: _config.checkContent,
        ),
        cameBackEmpty: (chapters) => chapters.every((c) => c.isVolume),
        falteredSince: transientBeforeDetail,
      );
      readableChapters = chapters.where((c) => !c.isVolume).toList();
    } catch (e) {
      _recordFailure(
        issues,
        stage: _stageFor(mode, 'toc'),
        error: e,
        mode: mode,
      );
      return;
    }

    if (readableChapters.isEmpty) {
      final health = _looksLikeDownloadOnly(book, readableChapters)
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
      final message = health.category == SourceHealthCategory.downloadOnly
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

    // 書源標了付費、還沒買的章節（ADR 0057）：夜讀不接付費內容，整個書源
    // 標成付費。只看書源自己標的；章名的「VIP」這類字樣只用來挑抽查的章，
    // 猜錯不會丟掉整個書源。
    if (readableChapters.where((c) => c.isLocked).firstOrNull case final c?) {
      _recordIssue(issues, _paidChapterIssue(mode, c));
      return;
    }

    final freeChapters = [
      for (final chapter in readableChapters)
        if (!_looksLikeLockedChapter(chapter)) chapter,
    ];
    if (freeChapters.isEmpty) {
      _recordIssue(issues, _lockedChapterIssue(mode, readableChapters.first));
      return;
    }

    if (!_config.checkContent) return;

    await _runContentProbeCheck(
      book,
      freeChapters,
      readableChapters,
      mode: mode,
      issues: issues,
    );
  }

  // ── Content probe ────────────────────────────────────────────────

  /// 正文抽查：第 1 章在 [freeChapters] 的前幾章裡找第一個讀得到的（開頭常
  /// 是公告、楔子這種短章）；章數多於 [_headProbeSpan] 時再抽中段、後段
  /// （[_laterSampleIndexes]），每一章都要讀得到，最後比對抽到的章有沒有
  /// 一半以上是同一段文字（[_checkRepeatedText]）。使用者 2026-11-14：只看
  /// 前段時，前幾章免費、後面付費，或後半段全是別本書的廣告的書源都會過。
  Future<void> _runContentProbeCheck(
    Book book,
    List<BookChapter> freeChapters,
    List<BookChapter> readableChapters, {
    required _CheckMode mode,
    required List<_IssueData> issues,
  }) async {
    final head = await _probeHead(
      book,
      freeChapters,
      mode: mode,
      issues: issues,
    );
    if (head == null) return;
    // 一章一章抓：同時抓時，往後試的那一章可能被別的抽樣佔走，共用的
    // 「這一段的請求從哪開始」也會讓診斷列出別章的請求（Codex 審查）。
    final taken = <String>{head.chapter.url};
    final later = <({BookChapter chapter, String content})>[];
    for (final index in _laterSampleIndexes(readableChapters)) {
      // 前一個位置往後試時已經抽過這一章。
      if (taken.contains(readableChapters[index].url)) continue;
      final sample = await _probeLater(
        book,
        readableChapters,
        index,
        taken,
        mode: mode,
        issues: issues,
      );
      if (sample == null) return;
      later.add(sample);
    }
    _checkRepeatedText([head, ...later], mode: mode, issues: issues);
  }

  Future<({BookChapter chapter, String content})?> _probeHead(
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
      probedCount++;
      final content = await _probeContent(
        book,
        readableChapters,
        chapter,
        mode: mode,
        issues: issues,
      );
      if (content == null) return null;
      if (content.usable) return (chapter: chapter, content: content.text);
    }

    _recordIssue(
      issues,
      _IssueData(
        stage: _stageFor(mode, 'content'),
        message: mode == _CheckMode.search
            ? '前 $probedCount 個候選章節正文內容過短或為空'
            : '發現書籍前 $probedCount 個候選章節正文內容過短或為空',
        health: _contentHealthFor(mode),
      ),
    );
    return null;
  }

  /// 中段、後段的一章：讀不到時往後試一章（抽到請假條、短番外不算壞），
  /// 兩章都讀不到就記成正文失效。
  Future<({BookChapter chapter, String content})?> _probeLater(
    Book book,
    List<BookChapter> chapters,
    int index,
    Set<String> taken, {
    required _CheckMode mode,
    required List<_IssueData> issues,
  }) async {
    for (final at in [index, index + 1]) {
      if (at >= chapters.length || !taken.add(chapters[at].url)) continue;
      final content = await _probeContent(
        book,
        chapters,
        chapters[at],
        mode: mode,
        issues: issues,
      );
      if (content == null) return null;
      if (content.usable) return (chapter: chapters[at], content: content.text);
    }
    final title = _compactChapterTitle(chapters[index].title);
    _recordIssue(
      issues,
      _IssueData(
        stage: _stageFor(mode, 'content'),
        message:
            '${mode == _CheckMode.search ? '' : '發現書籍'}'
            '$title（與下一章）正文內容過短或為空',
        health: _contentHealthFor(mode),
      ),
    );
    return null;
  }

  /// 抓一章正文：抓到的內容與讀不讀得到；出錯時記下、傳回 null。
  Future<({String text, bool usable})?> _probeContent(
    Book book,
    List<BookChapter> chapters,
    BookChapter chapter, {
    required _CheckMode mode,
    required List<_IssueData> issues,
  }) async {
    final nextChapterUrl = _nextReadableChapterUrl(chapters, chapter);
    try {
      _log('  ◇ 測試${mode.label}正文: ${chapter.title}');
      final content = await _fetch(
        '${mode.label}正文',
        (_) => _service.getContent(
          _source,
          book,
          chapter,
          nextChapterUrl: nextChapterUrl,
          pageConcurrency: _validationPageConcurrency,
        ),
        cameBackEmpty: (content) =>
            !chapterContentUsable(_kindShownBy(content, book), content),
      );
      // 被登入牆擋住的正文在抓的時候就丟出 LoginCheckException（ADR 0038），
      // 抓得到的正文裡提到「訂閱」「VIP」這類字不算。
      final kind = _kindShownBy(content, book);
      _reclassify(kind);
      return (text: content, usable: chapterContentUsable(kind, content));
    } catch (e) {
      _recordFailure(
        issues,
        stage: _stageFor(mode, 'content'),
        error: e,
        mode: mode,
      );
      return null;
    }
  }

  /// 抽到的章裡有兩章一半以上是同一段文字，就不是這一章該有的正文：
  /// - 一章的正文裡有另一章的開頭：下一頁的規則抓過頭、跨到別章（2026-11-14
  ///   独步小说第 97 章 26,810 字，把第 98 章也抓進來），記成正文失效；
  /// - 共同的句子三分之一以上帶付費字樣：付費提示（整個書源標付費，ADR
  ///   0057）；
  /// - 其他（別本書的廣告這類一章一章重複的）：記成正文失效。
  /// 真正的章節兩章不會一半以上一樣，作者的話這類固定文字只佔一小段；只比
  /// 文字，圖與音訊網址不比。
  void _checkRepeatedText(
    List<({BookChapter chapter, String content})> samples, {
    required _CheckMode mode,
    required List<_IssueData> issues,
  }) {
    for (var i = 0; i < samples.length; i++) {
      for (var j = i + 1; j < samples.length; j++) {
        final shared = _sharedSentences(samples[i].content, samples[j].content);
        if (shared == null) continue;
        for (final sample in [samples[i], samples[j]]) {
          final text = _flat(sample.content);
          _log(
            '  ◇ ${sample.chapter.title}：${text.length} 字，開頭「'
            '${text.length > 40 ? text.substring(0, 40) : text}」',
          );
        }
        _recordIssue(
          issues,
          _repeatedTextIssue(samples[i], samples[j], shared, mode),
        );
        return;
      }
    }
  }

  _IssueData _repeatedTextIssue(
    ({BookChapter chapter, String content}) a,
    ({BookChapter chapter, String content}) b,
    List<String> shared,
    _CheckMode mode,
  ) {
    final prefix = mode == _CheckMode.search ? '' : '發現書籍';
    String title(BookChapter chapter) => _compactChapterTitle(chapter.title);
    String quote(String text) =>
        text.length > 30 ? '${text.substring(0, 30)}…' : text;
    // 一章把另一章的開頭也抓進來：說哪一章跨到哪一章。
    for (final (whole, part) in [(a, b), (b, a)]) {
      final opening = _flat(part.content);
      final head = opening.length > 30 ? opening.substring(0, 30) : opening;
      if (head.isNotEmpty &&
          !_flat(whole.content).startsWith(head) &&
          _flat(whole.content).contains(head)) {
        return _IssueData(
          stage: _stageFor(mode, 'content'),
          message:
              '$prefix${title(whole.chapter)}的正文把${title(part.chapter)}也抓進來了'
              '（下一頁的規則抓過頭，跨到別章）：「${quote(head)}」',
          health: _contentHealthFor(mode),
        );
      }
    }
    final both = '${title(a.chapter)}與${title(b.chapter)}';
    final sharedText = shared.join('。');
    // 付費提示的句子不一定每句都有付費字樣（「開通會員可免費閱讀全站作品」），
    // 照句數算：三分之一以上帶付費字樣才算。故事重複時，帶「訂閱」的頁尾只是
    // 幾百句裡的一句。
    final paid = shared.where(_hasPaidMarker).length;
    if (paid * 3 >= shared.length) {
      return _IssueData(
        stage: _stageFor(mode, 'content'),
        message: '$prefix$both的正文一半以上是同一段付費提示：「${quote(sharedText)}」',
        health: paidSourceHealth,
      );
    }
    return _IssueData(
      stage: _stageFor(mode, 'content'),
      message:
          '$prefix$both的正文一半以上是同一段文字（一章一章重複的內容）：'
          '「${quote(sharedText)}」',
      health: _contentHealthFor(mode),
    );
  }

  BookSourceKind _kindShownBy(String content, Book book) =>
      chapterKindShownBy(_source, book, content);

  late final bool _isAggregate = _source.isAggregateSource;

  /// 正文和書源的類型不符時改寫類型（ADR 0051）：手動改的、匯入時照字樣
  /// 判的都一樣，誰最後改算誰的。聚合源照作者寫的類型，不改（ADR 0056）：
  /// 正文是哪一類看使用者在登入表單選的模式。
  void _reclassify(BookSourceKind kind) {
    if (_isAggregate || kind == _source.sourceKind) return;
    final type = switch (kind) {
      BookSourceKind.novel => SourceType.book,
      BookSourceKind.comic => SourceType.image,
      BookSourceKind.audio => SourceType.audio,
      BookSourceKind.unsupported => null,
    };
    if (type == null) return;
    _source.bookSourceType = type;
    _log('  ≡ 正文看起來是${kind.sourceLabel}，改寫書源類型');
  }

  // ── Issue helpers ────────────────────────────────────────────────

  /// 跑一段抓取，[label] 是這一段的名稱（例如「搜尋詳情」）。這一段網站的
  /// 回應看起來是暫時性的失敗（[RequestLog.transientResponses]：429、5xx、
  /// 空白、連不上），或直接丟出這類網路錯誤（[_looksTransient]），而這一段
  /// 失敗或結果是空的（[cameBackEmpty]），就隔一秒再試一次：網站偶爾回一次
  /// 空白不會讓書源被隔離。重試時 [fetch] 拿到 true，不沿用存著的頁面。
  ///
  /// 整段超過設定的時間不重試（慢的網站再試多半一樣慢）；被網站擋下、要登入
  /// 或要驗證也不重試。網站好好回了內容、規則自己解析不出來，也不重試。
  ///
  /// [falteredSince] 是從哪裡開始算網站的回應：目錄可能用詳情那一段存下的
  /// 頁面，詳情那一段網站回了空白，目錄才解析不出來，所以從詳情開始算。
  Future<T> _fetch<T>(
    String label,
    Future<T> Function(bool retrying) fetch, {
    bool Function(T result)? cameBackEmpty,
    int? falteredSince,
  }) async {
    _stageRequestStart = _requests.lines.length;
    final transientBefore = falteredSince ?? _requests.transientResponses;
    bool siteFaltered() => _requests.transientResponses > transientBefore;
    Future<T> attempt(bool retrying) => fetch(retrying).timeout(
      _config.timeoutDuration,
      // 寫出時限：2026-11-13 御书屋的搜尋要 48 秒，AI 不知道校驗只等 20 秒，
      // 原樣重跑、改 Cookie 猜了好幾輪。
      onTimeout: () => throw TimeoutException(
        '$label檢查超時：超過 ${_config.timeoutSeconds} 秒（校驗設定的時限）',
      ),
    );
    try {
      final result = await attempt(false);
      if (cameBackEmpty == null || !cameBackEmpty(result) || !siteFaltered()) {
        return result;
      }
      _log('  ↻ $label網站回了空白或錯誤，重試一次');
    } catch (e) {
      if (hostNotFound(e)) _networkDown ??= !await _networkCheck();
      if (_neverRetried(e) || !(_looksTransient(e) || siteFaltered())) {
        rethrow;
      }
      _log('  ↻ $label暫時失敗，重試一次: ${_compactMessage(errorText(e))}');
    }
    await Future<void>.delayed(_transientRetryDelay);
    return attempt(true);
  }

  /// 再試也沒用的失敗：整段逾時、網域查不到（網路是通的）、網站擋下夜讀、
  /// 要登入或驗證。
  bool _neverRetried(Object error) =>
      error is TimeoutException ||
      (hostNotFound(error) && _networkDown != true) ||
      error is SourceVerificationException ||
      error is LoginCheckException ||
      _blockedBySite(error, error.toString().toLowerCase());

  void _recordFailure(
    List<_IssueData> issues, {
    required String stage,
    required Object error,
    required _CheckMode mode,
  }) => _recordIssue(
    issues,
    _issueFromException(stage: stage, error: error, mode: mode),
    error: error,
  );

  /// 記下一個問題，連同診斷：沒截斷的錯誤、出錯時實際執行的 JS、這一段
  /// 送出的請求與網站的回應。診斷寫在崩潰日誌旁的另一個檔
  /// （`SourceCheckDiagnostics`），不混進崩潰日誌。
  void _recordIssue(
    List<_IssueData> issues,
    _IssueData issue, {
    Object? error,
  }) {
    issues.add(issue);
    _log(
      '  ! [${_source.bookSourceName}] ${_stageLabel(issue.stage)}: ${issue.message}',
    );
    _diagnostics.add(_diagnosis(issue, error));
  }

  String _diagnosis(_IssueData issue, Object? error) {
    final buffer = StringBuffer()
      ..writeln('[${_stageLabel(issue.stage)}] ${issue.message}');
    if (error != null) buffer.writeln('錯誤: $error');
    if (_ruleJsError(error)?.code case final code?) {
      buffer
        ..writeln('實際執行的 JS:')
        ..writeln(_clip(code, _diagnosisCodeLimit));
    }
    final lines = _requests.lines;
    final requests = lines.sublist(
      math.max(_stageRequestStart, lines.length - _diagnosisRequestLimit),
    );
    if (requests.isNotEmpty) {
      buffer.writeln('這一段的請求與回應:');
      requests.forEach(buffer.writeln);
    }
    return buffer.toString().trimRight();
  }

  void _log(String msg) => _logs.add(msg);

  _IssueData _issueFromException({
    required String stage,
    required Object error,
    required _CheckMode mode,
  }) {
    final normalized = error.toString().toLowerCase();
    final message = _compactMessage(
      error is TimeoutException
          ? error.message ?? '${_stageLabel(stage)}檢查超時'
          : errorText(error),
    );

    // 網站要真人勾選、封鎖了目前的網路或瀏覽器檢查沒過（CloudflareInterceptor）：
    // 夜讀不替使用者勾選，當成暫時不能用的書源，換網路或網站改設定後再校驗
    // 就會恢復。
    // 網域查不到：網站多半已經不在了。手機自己斷網時每個網域都查不到，
    // 這時當成連不上（[_networkDown]）。
    if (hostNotFound(error) && _networkDown != true) {
      return _IssueData(
        stage: 'upstream',
        message: '網域查不到，網站可能已經關了',
        health: upstreamHealth(siteBrokenSourceGroupTag),
      );
    }

    if (_blockedBySite(error, normalized)) {
      return _IssueData(
        stage: 'upstream',
        message: message,
        health: upstreamHealth(upstreamBlockedSourceGroupTag),
      );
    }

    // 書源要使用者驗證：校驗不跳畫面、不等人，只標狀態；閱讀時讓使用者
    // 自己去網頁上驗證（ADR 0038）。
    if (error is SourceVerificationException) {
      return _IssueData(
        stage: stage,
        message: error.message,
        health: verificationRequiredSourceHealth,
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
        health: loginRequiredSourceHealth,
      );
    }

    if (_looksLikeTimeout(normalized)) {
      return _IssueData(
        stage: 'timeout',
        message: '校驗超時或來源響應過慢',
        health: upstreamHealth(timeoutSourceGroupTag),
      );
    }

    if (_looksLikeBlockedUpstream(normalized)) {
      return _IssueData(
        stage: 'upstream',
        message: message,
        health: upstreamHealth(upstreamBlockedSourceGroupTag),
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
      _source.addHealthGroups(h);
    }
    if (message.trim().isNotEmpty) {
      _source.addErrorComment(message.trim());
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

_IssueData _paidChapterIssue(_CheckMode mode, BookChapter chapter) {
  final title = _compactChapterTitle(chapter.title);
  return _IssueData(
    stage: _stageFor(mode, 'toc'),
    message: title.isEmpty ? '目錄有付費章節' : '目錄有付費章節: $title',
    health: paidSourceHealth,
  );
}

_IssueData _lockedChapterIssue(_CheckMode mode, BookChapter chapter) {
  final title = _compactChapterTitle(chapter.title);
  return _IssueData(
    stage: _stageFor(mode, 'content'),
    message: title.isEmpty ? '章節都是付費章節' : '章節都是付費章節: $title',
    health: loginRequiredSourceHealth,
  );
}

bool _looksLikeLockedChapter(BookChapter chapter) {
  if (chapter.isVip && !chapter.isPay) return true;
  final normalized = chapter.title.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return _hasPaidMarker(normalized);
}

/// 第 1 章在前幾章裡找；比這多章的書才抽中段、後段。
const int _headProbeSpan = 5;

/// 中段、後段抽哪幾章：50%、75%、90% 的位置；章名寫了 VIP 這類字樣的
/// （書源沒標付費，只是章名這樣寫）優先，頂替後兩個位置。
List<int> _laterSampleIndexes(List<BookChapter> chapters) {
  final count = chapters.length;
  if (count <= _headProbeSpan) return const [];
  int at(double share) =>
      math.max(_headProbeSpan, (count * share).floor()).clamp(0, count - 1);
  final positions = [at(0.5), at(0.75), at(0.9)];
  final titled = [
    for (var i = _headProbeSpan; i < count; i++)
      if (_looksLikeLockedChapter(chapters[i])) i,
  ];
  if (titled.isNotEmpty) {
    positions[2] = titled.last;
    if (titled.length > 1) positions[1] = titled.first;
  }
  return positions.toSet().toList();
}

/// 兩段文字有一半以上（各自的字數）是同一些句子時，傳回共同的句子；
/// 是圖或音訊網址的、或沒有共同到一半的是 null。
List<String>? _sharedSentences(String a, String b) {
  // 付費提示只有幾十字，類型看不出來（不到小說的字數）也要比。
  bool media(String text) => switch (ChapterContentKind.of(text)) {
    ChapterContentKind.images || ChapterContentKind.audio => true,
    _ => false,
  };
  if (media(a) || media(b)) return null;
  // 照每句出現的次數算：章內重複的台詞先去重的話，作者的話只佔一小段也會
  // 算成一半以上（Codex 審查）。
  Map<String, int> sentences(String text) {
    final counts = <String, int>{};
    for (final part in text.split(RegExp(r'[\n。！？!?；;]'))) {
      final sentence = part.trim();
      if (sentence.isNotEmpty) {
        counts.update(sentence, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  final left = sentences(a);
  final right = sentences(b);
  int length(Map<String, int> counts) => counts.entries.fold(
    0,
    (sum, entry) => sum + entry.key.length * entry.value,
  );
  final shared = [
    for (final sentence in left.keys)
      if (right.containsKey(sentence)) sentence,
  ];
  if (shared.isEmpty) return null;
  final sharedLength = shared.fold(
    0,
    (sum, sentence) =>
        sum + sentence.length * math.min(left[sentence]!, right[sentence]!),
  );
  if (sharedLength * 2 < length(left) || sharedLength * 2 < length(right)) {
    return null;
  }
  return shared;
}

/// 拿掉空白，比對開頭用。
String _flat(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// 付費提示的字樣（章名與正文共用）。
const List<String> _paidMarkers = [
  '🔒',
  'vip',
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

bool _hasPaidMarker(String text) {
  final lower = text.toLowerCase();
  return _paidMarkers.any(lower.contains);
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
  for (var i = 0; i < headCount; i++) {
    addProbe(i);
  }

  final tailStart = math.max(chapters.length - maxProbe, 0);
  for (var i = tailStart; i < chapters.length; i++) {
    addProbe(i);
  }

  return <int>[...preferred, ...fallback].take(maxProbe).toList();
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

/// 這本書的詳情、目錄或正文打不開（會讓書源被隔離的那幾種）。
bool _bookCannotOpen(_IssueData issue) => const {
  SourceHealthCategory.detailBroken,
  SourceHealthCategory.tocBroken,
  SourceHealthCategory.contentBroken,
}.contains(issue.health.category);

/// 網域查不到（DNS 沒有這個名字）：Dart 的訊息一律是 `Failed host lookup`。
bool hostNotFound(Object error) =>
    error.toString().contains('Failed host lookup');

/// 網路本身通不通：查兩個大網站的網域，一個查得到就算通。網域查不到時用來
/// 分辨「網站不在了」和「手機斷網」。
Future<bool> networkReachable() async {
  for (final host in const ['www.google.com', 'www.baidu.com']) {
    try {
      final found = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (found.isNotEmpty) return true;
    } catch (_) {
      // 換下一個。
    }
  }
  return false;
}

/// 本身就是再試一次多半就好的網路錯誤：連線中途斷掉、網站一時忙碌（429、
/// 5xx）。逾時、憑證錯誤、被網站擋下都不算。經過網路層送出的請求另外由
/// [RequestLog.transientResponses] 認出（規則 JS 自己抓的 503 這類也算）。
bool _looksTransient(Object error) => switch (error) {
  DioException(type: DioExceptionType.connectionError) => true,
  DioException(type: DioExceptionType.badResponse, :final response) =>
    response?.statusCode == 429 || (response?.statusCode ?? 0) >= 500,
  DioException(type: DioExceptionType.unknown, error: IOException()) => true,
  IOException() => true,
  _ => false,
};

/// 錯誤裡包著的規則 JS 錯誤（解析錯誤、網路錯誤會把它包在裡面）。
RuleJsException? _ruleJsError(Object? error) {
  for (var depth = 0; depth < 6 && error != null; depth++) {
    switch (error) {
      case RuleJsException():
        return error;
      case ParsingException(originalError: final Object? inner):
        error = inner;
      case DioException(error: final inner):
        error = inner;
      default:
        return null;
    }
  }
  return null;
}

/// 同一本書，拿掉詳情與目錄抓回來時存著的頁面，再抓一次就會重新請求。
Book _withoutStoredPages(Book book) => book.copyWith()
  ..infoHtml = null
  ..tocHtml = null;

String _clip(String text, int limit) =>
    text.length > limit ? '${text.substring(0, limit)}…（以下省略）' : text;

bool _looksLikeTimeout(String normalized) =>
    normalized.contains('timeout') ||
    normalized.contains('timed out') ||
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
    // 連不上（連線被拒、加密連線失敗）：網站那邊的問題，不是太慢。書源的
    // 連線不驗憑證（sourceHttpClient），憑證有問題不會走到這裡。
    normalized.contains('socketexception') ||
    normalized.contains('handshakeexception');

int _issuePriority(SourceHealthCategory category) {
  switch (category) {
    case SourceHealthCategory.nonNovel:
      return 100;
    case SourceHealthCategory.loginRequired:
      return 95;
    case SourceHealthCategory.verificationRequired:
      return 94;
    case SourceHealthCategory.downloadOnly:
      return 90;
    case SourceHealthCategory.paid:
      return 89;
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

/// 網站擋下了夜讀（`CloudflareInterceptor` 判斷的那幾種）。先看錯誤本身的
/// 種類；包進解析錯誤後只剩文字時，比對它們的訊息。
bool _blockedBySite(Object error, String normalized) {
  final inner = error is DioException ? error.error : error;
  if (inner is HumanVerificationRequiredException ||
      inner is SiteBlockedException ||
      inner is ChallengeNotPassedException) {
    return true;
  }
  return [
    HumanVerificationRequiredException().message,
    SiteBlockedException().message,
    ChallengeNotPassedException().message,
  ].any(normalized.contains);
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
