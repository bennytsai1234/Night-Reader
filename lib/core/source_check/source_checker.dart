import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/error_text.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source/chapter_content_kind.dart';
import 'package:night_reader/core/source/content_next_page.dart';
import 'package:night_reader/core/source/source_interaction.dart';

import 'content_samples.dart';
import 'source_check_isolate.dart';
import 'source_check_verdict.dart';

/// 校驗搜尋時多搜的一個詞：站上不可能有這本書，跟著關鍵字的搜尋回不出
/// 搜正常關鍵字時的那幾本（ADR 0064）。
const String nonsenseKeyword = '夜讀查無此書ㄅㄆㄇㄈ';

/// 搜什麼都回同樣的書時，校驗的結論（「搜尋失效」的原因）。
const String searchIgnoresKeywordMessage =
    '搜尋結果跟關鍵字無關：搜一個不可能有的詞也回同樣的書，抓到的是頁面上固定的書';

/// 一個書源的校驗判定：依序測搜尋、發現、詳情、目錄與正文，把結果寫成
/// 書源的狀態分組與錯誤註解。背景 isolate 用它跑校驗；抓取都經過
/// [BookSourceService]，可以換成別的實作。
class SourceChecker {
  final BookSource _source;
  final IsolateCheckConfig _config;
  final BookSourceService _service;
  final List<String> _logs = [];
  final List<String> _diagnostics = [];

  /// 校驗送出的請求與網站的回應，依序（`recordRequestUrls`）。也記送出的
  /// 標頭：AI 修書源照方法、網址、內容與標頭認同一個請求，開場校驗和試抓
  /// 才對得上（換了 User-Agent 就通的不算時好時壞）。
  final RequestLog _requests = RequestLog(
    responsePreview: RequestLog.diagnosisPreview,
    sentHeaders: true,
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

    _log('⇒ 正在校驗 [${_source.bookSourceName}] ...');

    final preflight = _resolvePreflightStatus();
    if (preflight != null) {
      _applyHealthToSource(preflight.health, preflight.message);
      _log('  ✕ [${_source.bookSourceName}] ${preflight.message}');
      return _buildResult(preflight.stage, preflight.message, isHealthy: false);
    }

    final issues = <CheckIssue>[];

    if (_config.checkSearch) {
      await _runSearchCheck(issues);
    } else {
      _log('  ≡ 跳過搜尋檢查');
    }

    if (hasTerminalIssue(issues)) {
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

    final primary = primaryIssue(issues);
    final mergedMessage = composeIssueMessage(issues);
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
  CheckIssue? _resolvePreflightStatus() {
    if (_source.sourceKind != BookSourceKind.unsupported) return null;
    return const CheckIssue(
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

  Future<void> _runSearchCheck(List<CheckIssue> issues) async {
    final searchWord = _source.getCheckKeyword(_config.keyword);
    final searchUrl = _source.searchUrl?.trim() ?? '';
    if (searchUrl.isEmpty) {
      _recordIssue(
        issues,
        const CheckIssue(
          stage: 'search',
          message: '搜尋連結規則為空',
          health: searchRuleBrokenHealth,
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
          CheckIssue(
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

      final fixedBooks = await _booksForAnyWord(searchResults);
      if (fixedBooks != null) {
        _recordIssue(
          issues,
          CheckIssue(
            stage: 'search',
            message:
                '$searchIgnoresKeywordMessage（搜「$searchWord」和「$nonsenseKeyword」'
                '前 ${fixedBooks.length} 本都是：${fixedBooks.join('、')}）',
            health: const SourceRuntimeHealth(
              category: SourceHealthCategory.searchBroken,
              label: searchBrokenSourceGroupTag,
              description: searchIgnoresKeywordMessage,
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
      _recordFailure(issues, stage: 'search', error: e, mode: CheckMode.search);
    }
  }

  /// 再搜一次不可能有的詞（[nonsenseKeyword]）：前 [_fixedBookCompareCount]
  /// 本書名和 [found] 一模一樣時，規則抓到的是頁面上固定的書、不是搜尋結果，
  /// 回那幾本的書名；不一樣是 null。這樣的書源搜什麼都回同一份書單，混進
  /// 每一次搜尋的結果（ADR 0064）。搜不到、出錯或逾時都算跟著關鍵字：網站
  /// 搜不到時回推薦書沒關係，有的規則在搜不到時出錯（悅讀小說，同 Legado
  /// 把空的搜尋頁改當詳情頁解析）。這次不重試，網站一時不穩就當成沒問題。
  Future<List<String>?> _booksForAnyWord(List<SearchBook> found) async {
    _log('  ◇ 測試搜尋不可能有的詞: $nonsenseKeyword');
    final List<SearchBook> nonsense;
    try {
      nonsense = await _service
          .searchBooks(_source, nonsenseKeyword)
          .timeout(_config.timeoutDuration);
    } catch (e) {
      _log('  ≡ 搜「$nonsenseKeyword」沒有結果: ${compactCheckMessage(errorText(e))}');
      return null;
    }
    List<String> leading(List<SearchBook> books) => [
      for (final book in books.take(_fixedBookCompareCount)) book.name,
    ];
    final names = leading(found);
    return nonsense.isNotEmpty && listEquals(names, leading(nonsense))
        ? names
        : null;
  }

  static const int _fixedBookCompareCount = 5;

  /// 拿搜尋到的第一本書測詳情、目錄與正文。這本書打不開時換一本再測：
  /// 可能只是那本書的問題（例如還沒有章節、書號代進規則後出錯），兩本都
  /// 打不開才照書源壞了處理。
  Future<void> _checkSearchedBooks(
    List<SearchBook> searchResults,
    List<CheckIssue> issues,
  ) async {
    final first = searchResults.first;
    final firstIssues = <CheckIssue>[];
    await _checkBookFlow(
      _seedBook(first),
      mode: CheckMode.search,
      issues: firstIssues,
    );
    final second = searchResults
        .skip(1)
        .where((book) => book.bookUrl != first.bookUrl)
        .firstOrNull;
    if (second == null || !firstIssues.any(bookCannotOpen)) {
      issues.addAll(firstIssues);
      return;
    }

    _log('  ◇ 第一本書打不開，改測第二本: ${second.name}');
    final secondIssues = <CheckIssue>[];
    await _checkBookFlow(
      _seedBook(second),
      mode: CheckMode.search,
      issues: secondIssues,
    );
    if (secondIssues.any(bookCannotOpen)) {
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
    List<CheckIssue> issues, {
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
          const CheckIssue(
            stage: 'discovery',
            message: '發現規則為空或沒有可用入口',
            health: discoveryBrokenHealth,
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
          const CheckIssue(
            stage: 'discovery',
            message: '發現頁沒有結果',
            health: discoveryBrokenHealth,
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
        mode: CheckMode.discovery,
        issues: issues,
      );
    } catch (e) {
      _recordFailure(
        issues,
        stage: 'discovery',
        error: e,
        mode: CheckMode.discovery,
      );
    }
  }

  // ── Book flow ────────────────────────────────────────────────────

  Future<void> _checkBookFlow(
    Book seedBook, {
    required CheckMode mode,
    required List<CheckIssue> issues,
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
          CheckIssue(
            stage: checkStage(mode, 'detail'),
            message: mode == CheckMode.search ? '詳情頁返回空資料' : '發現詳情頁返回空資料',
            health: detailHealthFor(mode),
          ),
        );
        return;
      }
    } catch (e) {
      _recordFailure(
        issues,
        stage: checkStage(mode, 'detail'),
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
        stage: checkStage(mode, 'toc'),
        error: e,
        mode: mode,
      );
      return;
    }

    if (readableChapters.isEmpty) {
      final health = looksLikeDownloadOnly(book, readableChapters)
          ? downloadOnlyHealth
          : tocHealthFor(mode);
      final message = health.category == SourceHealthCategory.downloadOnly
          ? '來源為下載站，不提供線上目錄'
          : mode == CheckMode.search
          ? '目錄抓取失敗或沒有可閱讀章節'
          : '發現書籍目錄抓取失敗或沒有可閱讀章節';
      _recordIssue(
        issues,
        CheckIssue(
          stage: checkStage(mode, 'toc'),
          message: message,
          health: health,
        ),
      );
      return;
    }

    if (looksLikeDownloadOnly(book, readableChapters)) {
      _recordIssue(
        issues,
        const CheckIssue(
          stage: 'toc',
          message: '來源為下載站，不提供線上正文',
          health: downloadOnlyHealth,
        ),
      );
      return;
    }

    // 書源標了付費、還沒買的章節（ADR 0057）：夜讀不接付費內容，整個書源
    // 標成付費。只看書源自己標的；章名的「VIP」這類字樣只用來挑抽查的章，
    // 猜錯不會丟掉整個書源。
    if (readableChapters.where((c) => c.isLocked).firstOrNull case final c?) {
      _recordIssue(issues, paidChapterIssue(mode, c));
      return;
    }

    // 章名寫了 VIP 這類字樣、書源沒標付費的：先讀其他章；每一章都這樣寫
    // 時照樣讀它們。章名的字樣只用來挑章，不單憑章名判付費（ADR 0057），
    // 真的付費由讀到的正文判斷。
    final titledFree = [
      for (final chapter in readableChapters)
        if (!looksLikeLockedChapter(chapter)) chapter,
    ];
    final freeChapters = titledFree.isEmpty ? readableChapters : titledFree;

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
  /// 是公告、楔子這種短章）；章數多於 前 5 章 時再抽中段、後段
  /// （[laterSampleIndexes]），每一章都要讀得到，最後比對抽到的章有沒有
  /// 一半以上是同一段文字（[_checkRepeatedText]）。使用者 2026-11-14：只看
  /// 前段時，前幾章免費、後面付費，或後半段全是別本書的廣告的書源都會過。
  Future<void> _runContentProbeCheck(
    Book book,
    List<BookChapter> freeChapters,
    List<BookChapter> readableChapters, {
    required CheckMode mode,
    required List<CheckIssue> issues,
  }) async {
    final head = await _probeHead(
      book,
      freeChapters,
      toc: readableChapters,
      mode: mode,
      issues: issues,
    );
    if (head == null) return;
    // 一章一章抓：同時抓時，往後試的那一章可能被別的抽樣佔走，共用的
    // 「這一段的請求從哪開始」也會讓診斷列出別章的請求（Codex 審查）。
    final taken = <String>{head.chapter.url};
    final later = <({BookChapter chapter, String content})>[];
    for (final index in laterSampleIndexes(readableChapters)) {
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
    required List<BookChapter> toc,
    required CheckMode mode,
    required List<CheckIssue> issues,
  }) async {
    final probeIndexes = buildContentProbeIndexes(
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
        toc: toc,
        mode: mode,
        issues: issues,
      );
      if (content == null) return null;
      if (content.usable) return (chapter: chapter, content: content.text);
    }

    _recordIssue(
      issues,
      CheckIssue(
        stage: checkStage(mode, 'content'),
        message: mode == CheckMode.search
            ? '前 $probedCount 個候選章節正文內容過短或為空'
            : '發現書籍前 $probedCount 個候選章節正文內容過短或為空',
        health: contentHealthFor(mode),
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
    required CheckMode mode,
    required List<CheckIssue> issues,
  }) async {
    for (final at in [index, index + 1]) {
      if (at >= chapters.length || !taken.add(chapters[at].url)) continue;
      final content = await _probeContent(
        book,
        chapters,
        chapters[at],
        toc: chapters,
        mode: mode,
        issues: issues,
      );
      if (content == null) return null;
      if (content.usable) return (chapter: chapters[at], content: content.text);
    }
    final title = compactChapterTitle(chapters[index].title);
    _recordIssue(
      issues,
      CheckIssue(
        stage: checkStage(mode, 'content'),
        message:
            '${mode == CheckMode.search ? '' : '發現書籍'}'
            '$title（與下一章）正文內容過短或為空',
        health: contentHealthFor(mode),
      ),
    );
    return null;
  }

  /// 抓一章正文：抓到的內容與讀不讀得到；出錯，或讀得到卻只抓了第一頁
  /// （[chapterCutAtFirstPage]）時記下、傳回 null。[toc] 是整份目錄。
  Future<({String text, bool usable})?> _probeContent(
    Book book,
    List<BookChapter> chapters,
    BookChapter chapter, {
    required List<BookChapter> toc,
    required CheckMode mode,
    required List<CheckIssue> issues,
  }) async {
    final nextChapterUrl = _nextReadableChapterUrl(chapters, chapter);
    // 這一章抓取時的請求，每個回應帶整頁；重試時換一份，只看最後一次。
    var pages = <LoggedPage>[];
    try {
      _log('  ◇ 測試${mode.label}正文: ${chapter.title}');
      final content = await _fetch(
        '${mode.label}正文',
        (_) => _requests.keepingPages(
          pages = <LoggedPage>[],
          () => _service.getContent(
            _source,
            book,
            chapter,
            nextChapterUrl: nextChapterUrl,
            pageConcurrency: _validationPageConcurrency,
          ),
        ),
        cameBackEmpty: (content) =>
            !chapterContentUsable(_kindShownBy(content, book), content),
      );
      // 被登入牆擋住的正文在抓的時候就丟出 LoginCheckException（ADR 0038），
      // 抓得到的正文裡提到「訂閱」「VIP」這類字不算。
      final kind = _kindShownBy(content, book);
      _reclassify(kind);
      final next = chapterCutAtFirstPage(
        _source,
        book,
        content,
        pages,
        toc: [for (final chapter in toc) chapter.url],
      );
      if (next != null) {
        _recordIssue(issues, _unjoinedPageIssue(chapter, next, mode));
        return null;
      }
      return (text: content, usable: chapterContentUsable(kind, content));
    } catch (e) {
      _recordFailure(
        issues,
        stage: checkStage(mode, 'content'),
        error: e,
        mode: mode,
      );
      return null;
    }
  }

  CheckIssue _unjoinedPageIssue(
    BookChapter chapter,
    String next,
    CheckMode mode,
  ) {
    final hasRule = (_source.ruleContent?.nextContentUrl ?? '')
        .trim()
        .isNotEmpty;
    return CheckIssue(
      stage: checkStage(mode, 'content'),
      message:
          '${mode == CheckMode.search ? '' : '發現書籍'}'
          '${compactChapterTitle(chapter.title)}只抓到第一頁：正文頁有指向同一章'
          '下一頁的連結（$next），'
          '${hasRule ? '下一頁規則（nextContentUrl）沒有抓到它' : '書源沒有下一頁規則（nextContentUrl）'}',
      health: contentHealthFor(mode),
    );
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
    required CheckMode mode,
    required List<CheckIssue> issues,
  }) {
    for (var i = 0; i < samples.length; i++) {
      for (var j = i + 1; j < samples.length; j++) {
        final shared = sharedSentences(samples[i].content, samples[j].content);
        if (shared == null) continue;
        for (final sample in [samples[i], samples[j]]) {
          final text = flatText(sample.content);
          _log(
            '  ◇ ${sample.chapter.title}：${text.length} 字，開頭「'
            '${text.length > 40 ? text.substring(0, 40) : text}」',
          );
        }
        _recordIssue(
          issues,
          repeatedTextIssue(samples[i], samples[j], shared, mode),
        );
        return;
      }
    }
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
    // 類型是規則的一部分：改了就是新的一版（匯到別台才認得出來）。
    _source
      ..bookSourceType = type
      ..lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
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
      _log('  ↻ $label暫時失敗，重試一次: ${compactCheckMessage(errorText(e))}');
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
      blockedBySite(error, error.toString().toLowerCase());

  void _recordFailure(
    List<CheckIssue> issues, {
    required String stage,
    required Object error,
    required CheckMode mode,
  }) => _recordIssue(
    issues,
    issueFromException(
      stage: stage,
      error: error,
      mode: mode,
      networkDown: _networkDown == true,
    ),
    error: error,
  );

  /// 記下一個問題，連同診斷：沒截斷的錯誤、出錯時實際執行的 JS、這一段
  /// 送出的請求與網站的回應。診斷寫在崩潰日誌旁的另一個檔
  /// （`SourceCheckDiagnostics`），不混進崩潰日誌。
  void _recordIssue(
    List<CheckIssue> issues,
    CheckIssue issue, {
    Object? error,
  }) {
    issues.add(issue);
    _log(
      '  ! [${_source.bookSourceName}] ${checkStageLabel(issue.stage)}: ${issue.message}',
    );
    _diagnostics.add(_diagnosis(issue, error));
  }

  String _diagnosis(CheckIssue issue, Object? error) {
    final buffer = StringBuffer()
      ..writeln('[${checkStageLabel(issue.stage)}] ${issue.message}');
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
