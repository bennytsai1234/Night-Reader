import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/engine/analyze_rule.dart';
import 'package:reader/core/engine/analyze_url.dart';
import 'package:reader/core/engine/explore_url_parser.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/services/book_source_service.dart';
import 'package:reader/core/services/network_service.dart';

import '../test/test_helper.dart';

const String sourceListUrl =
    'https://shuyuan.nyasama.net/shuyuan/382015f6ff010d7fee368c6daabd5081.json';
const String _sourceListCacheRelativePath =
    '.cache/inkpage_reader/source_lists/382015f6ff010d7fee368c6daabd5081.json';
const String legadoValidationDefaultKeyword = '我的';
const int sourceValidationChapterLimit = 128;
const int validationPageConcurrency = 1;

enum SourceValidationOutcome { pass, skip, fail }

class SearchKeywordSeed {
  final String keyword;
  final List<SearchBook> searchBooks;

  const SearchKeywordSeed({required this.keyword, required this.searchBooks});
}

class ValidationFailureClassification {
  final SourceValidationOutcome outcome;
  final String category;

  const ValidationFailureClassification({
    required this.outcome,
    required this.category,
  });
}

class SourceValidationResult {
  final int index;
  final String sourceName;
  final SourceValidationOutcome outcome;
  final String stage;
  final String? keyword;
  final String? bookName;
  final String? bookUrl;
  final int? chapterCount;
  final String? firstChapterTitle;
  final String? secondChapterTitle;
  final String? failure;
  final String? category;
  final Duration duration;

  bool get passed => outcome == SourceValidationOutcome.pass;
  bool get skipped => outcome == SourceValidationOutcome.skip;

  const SourceValidationResult({
    required this.index,
    required this.sourceName,
    required this.outcome,
    required this.stage,
    required this.duration,
    this.keyword,
    this.bookName,
    this.bookUrl,
    this.chapterCount,
    this.firstChapterTitle,
    this.secondChapterTitle,
    this.failure,
    this.category,
  });

  String toSummaryLine() {
    final status = switch (outcome) {
      SourceValidationOutcome.pass => 'PASS',
      SourceValidationOutcome.skip => 'SKIP',
      SourceValidationOutcome.fail => 'FAIL',
    };
    final info = <String>[
      '#$index',
      sourceName,
      status,
      'stage=$stage',
      if (category != null && category!.isNotEmpty) 'category=$category',
      if (keyword != null && keyword!.isNotEmpty) 'keyword="$keyword"',
      if (bookName != null && bookName!.isNotEmpty) 'book="$bookName"',
      if (chapterCount != null) 'chapters=$chapterCount',
      if (firstChapterTitle != null && firstChapterTitle!.isNotEmpty)
        'first="$firstChapterTitle"',
      if (failure != null && failure!.isNotEmpty) 'reason="$failure"',
      'time=${duration.inSeconds}s',
    ];
    return info.join(' | ');
  }
}

class _FallbackChapterDao implements ChapterDao {
  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async =>
      const <BookChapter>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> initSourceValidationEnvironment() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  if (!getIt.isRegistered<ChapterDao>()) {
    getIt.registerLazySingleton<ChapterDao>(() => _FallbackChapterDao());
  }
  HttpOverrides.global = _PassthroughHttpOverrides();
  await NetworkService().init();
}

List<BookSource> decodeSourcesPayload(String payload, {int? limit}) {
  final decoded = jsonDecode(normalizeSourcesPayload(payload));
  final items = decoded is List<dynamic> ? decoded : <dynamic>[decoded];
  return items
      .take(limit ?? items.length)
      .map((item) => BookSource.fromJson(item as Map<String, dynamic>))
      .toList();
}

Future<List<BookSource>> fetchSources({required int limit}) async {
  final singleSourceFile = Platform.environment['SOURCE_JSON_FILE']?.trim();
  if (singleSourceFile != null && singleSourceFile.isNotEmpty) {
    return _loadSourcesFromFile(singleSourceFile, limit: limit);
  }

  final sourceListFile = Platform.environment['SOURCE_LIST_FILE']?.trim();
  if (sourceListFile != null && sourceListFile.isNotEmpty) {
    try {
      return await _loadSourcesFromFile(sourceListFile, limit: limit);
    } catch (_) {
      final cached = await _tryLoadCachedSources(limit: limit);
      if (cached != null) return cached;
      rethrow;
    }
  }

  final cacheFile = _resolveSourceListCacheFile();
  final result = await Process.run('curl', <String>[
    '-L',
    '--fail',
    '--silent',
    '--show-error',
    '--max-time',
    '30',
    sourceListUrl,
  ]);
  if (result.exitCode != 0) {
    final cached = await _tryLoadCachedSources(limit: limit);
    if (cached != null) return cached;
    throw StateError('fetch source list failed: ${result.stderr}');
  }
  try {
    final payload = normalizeSourcesPayload(result.stdout as String);
    await _writeSourceListCache(cacheFile, payload);
    return decodeSourcesPayload(payload, limit: limit);
  } catch (error) {
    final cached = await _tryLoadCachedSources(limit: limit);
    if (cached != null) return cached;
    throw StateError('fetch source list returned invalid payload: $error');
  }
}

String normalizeSourcesPayload(String payload) {
  final trimmed = payload.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('source list payload is empty');
  }
  final normalized = _extractJsonPayload(trimmed);
  final first = normalized[0];
  if (first != '[' && first != '{') {
    throw FormatException(
      'source list payload is not JSON: ${normalized.substring(0, math.min(80, normalized.length))}',
    );
  }
  return normalized;
}

Future<List<BookSource>> _loadSourcesFromFile(
  String filePath, {
  required int limit,
}) async {
  final payload = await File(filePath).readAsString();
  final normalized = normalizeSourcesPayload(payload);
  if (filePath != _resolveSourceListCacheFile().path &&
      _looksLikeSourceListPayload(normalized)) {
    await _writeSourceListCache(_resolveSourceListCacheFile(), normalized);
  }
  return decodeSourcesPayload(normalized, limit: limit);
}

Future<List<BookSource>?> _tryLoadCachedSources({required int limit}) async {
  final cacheFile = _resolveSourceListCacheFile();
  if (!await cacheFile.exists()) return null;
  try {
    return await _loadSourcesFromFile(cacheFile.path, limit: limit);
  } catch (_) {
    return null;
  }
}

File _resolveSourceListCacheFile() {
  final override = Platform.environment['SOURCE_LIST_CACHE_FILE']?.trim();
  if (override != null && override.isNotEmpty) {
    return File(override);
  }
  final homeDir =
      Platform.environment['HOME']?.trim().isNotEmpty == true
          ? Platform.environment['HOME']!.trim()
          : Directory.current.path;
  return File('$homeDir/$_sourceListCacheRelativePath');
}

Future<void> _writeSourceListCache(File file, String payload) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(payload);
}

String _extractJsonPayload(String payload) {
  if (payload.startsWith('[') || payload.startsWith('{')) {
    return payload;
  }

  final htmlEnd = payload.lastIndexOf('</html>');
  if (htmlEnd != -1) {
    final trailing = payload.substring(htmlEnd + '</html>'.length).trim();
    if (trailing.startsWith('[') || trailing.startsWith('{')) {
      return trailing;
    }
  }

  final firstSourceName = payload.indexOf('"bookSourceName"');
  if (firstSourceName != -1) {
    final arrayStart = payload.lastIndexOf('[', firstSourceName);
    final objectStart = payload.lastIndexOf('{', firstSourceName);
    final start =
        arrayStart != -1 && arrayStart < objectStart ? arrayStart : objectStart;
    if (start != -1) {
      final candidate = payload.substring(start).trim();
      if (candidate.startsWith('[') || candidate.startsWith('{')) {
        return candidate;
      }
    }
  }

  return payload;
}

bool _looksLikeSourceListPayload(String payload) =>
    payload.contains('"bookSourceName"') && payload.contains('"bookSourceUrl"');

Future<SourceValidationResult> validateSourceFlow(
  BookSourceService service,
  BookSource source, {
  required int index,
  CancelToken? cancelToken,
}) async {
  if (!source.isNovelTextSource) {
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: SourceValidationOutcome.skip,
      stage: 'source-filter',
      duration: Duration.zero,
      failure: source.nonNovelExclusionReason,
      category: 'non-novel-source',
    );
  }

  if (_sourceMarkedBrokenForStage(source, 'keyword')) {
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: SourceValidationOutcome.skip,
      stage: 'source-filter',
      duration: Duration.zero,
      failure: '書源已標記失效或校驗超時',
      category: 'source-marked-broken',
    );
  }

  final stopwatch = Stopwatch()..start();
  const maxContentProbe = 5;
  var stage = 'init';
  String? keyword;
  Book? selectedBook;
  Book? hydratedBook;
  List<BookChapter> chapters = const <BookChapter>[];
  List<BookChapter> readableChapters = const <BookChapter>[];
  BookChapter? firstReadableChapter;
  BookChapter? secondReadableChapter;
  int? firstReadableIndex;
  final contentCache = <int, String>{};

  try {
    stage = 'keyword';
    final searchSeed = await pickKeywordSeed(
      service,
      source,
      cancelToken: cancelToken,
    );
    keyword = searchSeed.keyword;

    stage = 'search';
    final searchBooks = searchSeed.searchBooks;
    if (searchBooks.isEmpty) {
      throw StateError('搜尋 "$keyword" 沒有結果');
    }

    final matchedBook = selectMatchingSearchBook(searchBooks, keyword);
    if (matchedBook == null) {
      throw StateError('搜尋結果未命中關鍵詞 "$keyword"');
    }
    selectedBook = matchedBook.toBook();

    stage = 'detail';
    hydratedBook = await service.getBookInfo(
      source,
      selectedBook,
      cancelToken: cancelToken,
    );
    if (hydratedBook.name.trim().isEmpty) {
      throw StateError('詳情頁書名為空');
    }
    if (hydratedBook.bookUrl.trim().isEmpty) {
      throw StateError('詳情頁 bookUrl 為空');
    }

    stage = 'toc';
    chapters = await service.getChapterList(
      source,
      hydratedBook,
      chapterLimit: sourceValidationChapterLimit,
      pageConcurrency: validationPageConcurrency,
      cancelToken: cancelToken,
    );
    readableChapters = chapters.where((chapter) => !chapter.isVolume).toList();
    if (readableChapters.isEmpty) {
      if (looksLikeBrokenBookShell(hydratedBook)) {
        throw StateError('命中的書籍詳情為空殼頁');
      }
      throw StateError('目錄沒有可閱讀章節');
    }
    if (looksLikeDownloadOnlySource(hydratedBook, readableChapters)) {
      throw StateError('來源為下載站，非線上正文書源');
    }
    final lockedChapter = firstLikelyLockedChapter(readableChapters);
    if (lockedChapter != null) {
      throw StateError('章節疑似 VIP/鎖章，需要登入或付費: ${lockedChapter.title}');
    }

    Future<String> loadChapterContent(int chapterIndex) async {
      final cached = contentCache[chapterIndex];
      if (cached != null) {
        return cached;
      }
      final chapter = readableChapters[chapterIndex];
      final content = await service.getContent(
        source,
        hydratedBook!,
        chapter,
        pageConcurrency: validationPageConcurrency,
        cancelToken: cancelToken,
        nextChapterUrl:
            readableChapters.length > chapterIndex + 1
                ? readableChapters[chapterIndex + 1].url
                : null,
      );
      contentCache[chapterIndex] = content;
      return content;
    }

    stage = 'content:first';
    final firstProbeIndexes = buildContentProbeIndexes(
      readableChapters,
      maxContentProbe,
    );
    for (final i in firstProbeIndexes) {
      final chapter = readableChapters[i];
      final content = await loadChapterContent(i);
      if (looksLikeLoginRequiredContent(content)) {
        throw StateError('正文需要登入後閱讀');
      }
      if (looksReadable(content)) {
        firstReadableChapter = chapter;
        firstReadableIndex = i;
        if (readableChapters.length <= 1) {
          break;
        }

        stage = 'content:second';
        final secondProbeIndexes = buildNeighborProbeIndexes(
          readableChapters,
          i,
          maxContentProbe,
        );
        for (final secondIndex in secondProbeIndexes) {
          final secondChapter = readableChapters[secondIndex];
          final secondContent = await loadChapterContent(secondIndex);
          if (looksLikeLoginRequiredContent(secondContent)) {
            throw StateError('正文需要登入後閱讀');
          }
          if (looksReadable(secondContent)) {
            secondReadableChapter = secondChapter;
            break;
          }
        }
        if (secondReadableChapter != null || secondProbeIndexes.isEmpty) {
          break;
        }
        stage = 'content:first';
      }
    }
    if (firstReadableChapter == null) {
      throw StateError('前幾章正文疑似解析失敗');
    }

    if (readableChapters.length > 1 && secondReadableChapter == null) {
      stage = 'content:second';
      final secondProbeIndexes = buildNeighborProbeIndexes(
        readableChapters,
        firstReadableIndex!,
        maxContentProbe,
      );
      if (secondProbeIndexes.isNotEmpty) {
        throw StateError('後續章節正文疑似解析失敗');
      }
    }

    stopwatch.stop();
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: SourceValidationOutcome.pass,
      stage: stage,
      duration: stopwatch.elapsed,
      keyword: keyword,
      bookName: hydratedBook.name,
      bookUrl: hydratedBook.bookUrl,
      chapterCount: chapters.length,
      firstChapterTitle: firstReadableChapter.title,
      secondChapterTitle: secondReadableChapter?.title,
    );
  } catch (error) {
    stopwatch.stop();
    final classification = classifyValidationFailure(
      error,
      source: source,
      stage: stage,
    );
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: classification.outcome,
      stage: stage,
      duration: stopwatch.elapsed,
      keyword: keyword,
      bookName: hydratedBook?.name ?? selectedBook?.name,
      bookUrl: hydratedBook?.bookUrl ?? selectedBook?.bookUrl,
      chapterCount: chapters.isEmpty ? null : chapters.length,
      firstChapterTitle:
          firstReadableChapter?.title ??
          (readableChapters.isNotEmpty ? readableChapters.first.title : null),
      secondChapterTitle: secondReadableChapter?.title,
      failure: compactError(error),
      category: classification.category,
    );
  }
}

String compactError(Object error) {
  final message = error.toString().trim();
  if (message.isEmpty) return 'unknown error';
  final firstLine = message.split('\n').first.trim();
  return firstLine.length > 160 ? firstLine.substring(0, 160) : firstLine;
}

ValidationFailureClassification classifyValidationFailure(
  Object error, {
  required BookSource source,
  required String stage,
}) {
  final rawNormalized = error.toString().toLowerCase();

  if (_sourceMarkedBrokenForStage(source, stage)) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'source-marked-broken',
    );
  }

  if (rawNormalized.contains('libquickjs_c_bridge_plugin.so') ||
      rawNormalized.contains('js_error: library not available')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'env-js-runtime',
    );
  }

  if (rawNormalized.contains('webviewplatform.instance != null') ||
      rawNormalized.contains('headlesswebviewservice') ||
      rawNormalized.contains('plugins.flutter.io/webview')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'env-webview',
    );
  }

  if (rawNormalized.contains('missingpluginexception') &&
      (rawNormalized.contains('gettemporarydirectory') ||
          rawNormalized.contains('plugins.flutter.io/path_provider'))) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'env-path-provider',
    );
  }

  if (rawNormalized.contains('找不到可用測試關鍵詞') || rawNormalized.contains('沒有結果')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'source-search-empty',
    );
  }

  if (rawNormalized.contains('搜尋結果未命中關鍵詞') ||
      rawNormalized.contains('搜索结果未命中关键词')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'source-search-mismatch',
    );
  }

  if (rawNormalized.contains('命中的書籍詳情為空殼頁') ||
      rawNormalized.contains('detail page resolved to empty shell')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'source-book-empty',
    );
  }

  if (rawNormalized.contains('來源為下載站') ||
      rawNormalized.contains('来源为下载站') ||
      rawNormalized.contains('非線上正文書源') ||
      rawNormalized.contains('非线上正文书源')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'download-only-source',
    );
  }

  if (rawNormalized.contains('正文需要登入後閱讀') ||
      rawNormalized.contains('正文需要登录后阅读') ||
      rawNormalized.contains('書源需要登入後使用') ||
      rawNormalized.contains('书源需要登录后使用') ||
      rawNormalized.contains('需要登入後閱讀') ||
      rawNormalized.contains('需要登录后阅读') ||
      rawNormalized.contains('loginrequired') ||
      rawNormalized.contains('permissionlimit') ||
      rawNormalized.contains('vip') ||
      rawNormalized.contains('鎖章') ||
      rawNormalized.contains('锁章') ||
      rawNormalized.contains('解鎖') ||
      rawNormalized.contains('解锁') ||
      rawNormalized.contains('付費') ||
      rawNormalized.contains('付费')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'login-required-source',
    );
  }

  if (rawNormalized.contains('receivetimeout') ||
      rawNormalized.contains('timeoutexception') ||
      rawNormalized.contains('future not completed') ||
      rawNormalized.contains('timed out waiting for') ||
      rawNormalized.contains('connection timeout') ||
      rawNormalized.contains('timed out') ||
      rawNormalized.contains('socketexception') ||
      rawNormalized.contains('handshakeexception') ||
      rawNormalized.contains('certificate_verify_failed') ||
      rawNormalized.contains('handshake error') ||
      rawNormalized.contains('ssl')) {
    if (stage == 'timeout' ||
        stage.startsWith('content') ||
        stage.startsWith('toc')) {
      return const ValidationFailureClassification(
        outcome: SourceValidationOutcome.skip,
        category: 'slow-source',
      );
    }
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'upstream-timeout',
    );
  }

  if (rawNormalized.contains('401') ||
      rawNormalized.contains('403') ||
      rawNormalized.contains('404') ||
      rawNormalized.contains('429') ||
      rawNormalized.contains('502') ||
      rawNormalized.contains('503') ||
      rawNormalized.contains('cloudflare') ||
      rawNormalized.contains('forbidden')) {
    return const ValidationFailureClassification(
      outcome: SourceValidationOutcome.skip,
      category: 'upstream-blocked',
    );
  }

  return const ValidationFailureClassification(
    outcome: SourceValidationOutcome.fail,
    category: 'app-or-parser',
  );
}

bool _sourceMarkedBrokenForStage(BookSource source, String stage) {
  final markers =
      '${source.bookSourceGroup ?? ''}\n${source.bookSourceComment ?? ''}'
          .toLowerCase();
  if (markers.isEmpty) return false;

  if (markers.contains('網站失效') ||
      markers.contains('网站失效') ||
      markers.contains('校驗超時') ||
      markers.contains('校验超时')) {
    return true;
  }

  if (stage.startsWith('search') &&
      (markers.contains('搜尋失效') || markers.contains('搜索失效'))) {
    return true;
  }

  if (stage.startsWith('toc') &&
      (markers.contains('目錄失效') || markers.contains('目录失效'))) {
    return true;
  }

  if (stage.startsWith('content') &&
      (markers.contains('正文失效') || markers.contains('内容失效'))) {
    return true;
  }

  return false;
}

Future<SearchKeywordSeed> pickKeywordSeed(
  BookSourceService service,
  BookSource source, {
  CancelToken? cancelToken,
}) async {
  // Align batch validation with Legado's CheckSourceService:
  // use ruleSearch.checkKeyWord first, otherwise fall back to the global
  // default keyword instead of probing many derived candidates.
  final keyword = resolveValidationKeyword(source);
  final searchBooks = await service.searchBooks(
    source,
    keyword,
    filter: (name, author) => _nameAuthorMatchesKeyword(name, author, keyword),
    shouldBreak: (size) => size >= 1,
    cancelToken: cancelToken,
  );
  return SearchKeywordSeed(keyword: keyword, searchBooks: searchBooks);
}

String resolveValidationKeyword(
  BookSource source, {
  String defaultKeyword = legadoValidationDefaultKeyword,
}) {
  final keyword = source.getCheckKeyword(defaultKeyword).trim();
  return keyword.isEmpty ? defaultKeyword : keyword;
}

Future<String> pickKeyword(
  BookSourceService service,
  BookSource source,
) async => resolveValidationKeyword(source);

Future<SearchKeywordSeed?> _tryKeyword(
  BookSourceService service,
  BookSource source,
  String keyword,
) async {
  try {
    final results = await service.searchBooks(source, keyword);
    if (results.isEmpty) return null;
    return SearchKeywordSeed(keyword: keyword, searchBooks: results);
  } catch (_) {
    return null;
  }
}

Future<SearchKeywordSeed?> findWorkingKeywordCandidate(
  BookSourceService service,
  BookSource source,
  String seed,
) async {
  SearchKeywordSeed? fallbackSeed;
  for (final keyword in buildKeywordCandidates(seed)) {
    final matched = await _tryKeyword(service, source, keyword);
    if (matched == null) continue;
    if (_plainKeywordPattern.hasMatch(keyword)) {
      return matched;
    }
    fallbackSeed ??= matched;
  }
  return fallbackSeed;
}

Future<SearchKeywordSeed?> pickKeywordFromBrowse(
  BookSourceService service,
  BookSource source,
) async {
  final fromExplore = await pickKeywordFromExplore(service, source);
  if (fromExplore != null) {
    return fromExplore;
  }
  return pickKeywordFromHomepage(service, source);
}

Future<SearchKeywordSeed?> pickKeywordFromExplore(
  BookSourceService service,
  BookSource source,
) async {
  final exploreUrl = source.exploreUrl;
  if (exploreUrl == null || exploreUrl.trim().isEmpty) {
    return null;
  }
  try {
    final kinds = await ExploreUrlParser.parseAsync(exploreUrl, source: source);
    for (final kind in kinds) {
      final url = kind.url?.trim() ?? '';
      if (url.isEmpty) {
        continue;
      }
      final books = await service.exploreBooks(source, url, page: 1);
      for (final book in books.take(5)) {
        final name = book.name.trim();
        if (!looksLikeBookName(name)) {
          continue;
        }
        final matched = await findWorkingKeywordCandidate(
          service,
          source,
          name,
        );
        if (matched != null) {
          return matched;
        }
      }
    }
  } catch (_) {}
  return null;
}

Future<SearchKeywordSeed?> pickKeywordFromHomepage(
  BookSourceService service,
  BookSource source,
) async {
  final searchRule = source.ruleSearch;
  if (searchRule?.bookList == null || searchRule!.bookList!.isEmpty) {
    return null;
  }
  final homeUrl = source.bookSourceUrl.split('#').first;
  final analyzeUrl = await AnalyzeUrl.create(homeUrl, source: source);
  final response = await analyzeUrl.getStrResponse();
  final listRule = AnalyzeRule(
    source: source,
  ).setContent(response.body, baseUrl: response.url);
  try {
    final items = listRule.getElements(searchRule.bookList!);
    for (final item in items.take(5)) {
      final itemRule = AnalyzeRule(
        source: source,
      ).setContent(item, baseUrl: response.url);
      try {
        final name = itemRule.getString(searchRule.name ?? '').trim();
        if (!looksLikeBookName(name)) {
          continue;
        }
        final matched = await findWorkingKeywordCandidate(
          service,
          source,
          name,
        );
        if (matched != null) {
          return matched;
        }
      } finally {
        itemRule.dispose();
      }
    }

    final fallbackRule = AnalyzeRule(
      source: source,
    ).setContent(response.body, baseUrl: response.url);
    try {
      final anchorTexts = fallbackRule.getStringList('a@text');
      for (final text in anchorTexts) {
        final name = text.trim();
        if (!looksLikeBookName(name)) {
          continue;
        }
        final matched = await findWorkingKeywordCandidate(
          service,
          source,
          name,
        );
        if (matched != null) {
          return matched;
        }
      }
    } finally {
      fallbackRule.dispose();
    }
  } finally {
    listRule.dispose();
  }
  return null;
}

SearchBook? selectMatchingSearchBook(
  List<SearchBook> searchBooks,
  String? keyword,
) {
  final candidates =
      searchBooks.where((book) => book.bookUrl.trim().isNotEmpty).toList();
  if (candidates.isEmpty) {
    return searchBooks.isEmpty ? null : searchBooks.first;
  }

  final trimmedKeyword = keyword?.trim() ?? '';
  if (trimmedKeyword.isEmpty) {
    return candidates.first;
  }

  for (final book in candidates) {
    if (_searchBookMatchesKeyword(book, trimmedKeyword)) {
      return book;
    }
  }
  return null;
}

Book selectBook(List<SearchBook> searchBooks, {String? keyword}) {
  final selected = selectMatchingSearchBook(searchBooks, keyword);
  if (selected != null) {
    return selected.toBook();
  }
  if (searchBooks.isEmpty) {
    throw StateError('searchBooks is empty');
  }
  return searchBooks.first.toBook();
}

bool looksReadable(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('加載章節失敗')) return false;
  if (trimmed.startsWith('章節內容為空')) return false;
  return trimmed.runes.length >= 20;
}

bool looksLikeLoginRequiredContent(String content) {
  final normalized = content.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('permissionlimit') ||
      normalized.contains('loginrequired') ||
      normalized.contains('登录后阅读') ||
      normalized.contains('登入後閱讀') ||
      normalized.contains('需要你登录后阅读') ||
      normalized.contains('需要你登入後閱讀') ||
      normalized.contains('請先登錄') ||
      normalized.contains('请先登录');
}

bool looksLikeBrokenBookShell(Book book) {
  final html =
      ((book.tocHtml?.isNotEmpty ?? false) ? book.tocHtml : book.infoHtml) ??
      '';
  if (html.isEmpty) return false;

  final hasEmptySectionList = RegExp(
    r'<ul[^>]*class="[^"]*section-list[^"]*"[^>]*>\s*</ul>',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(html);
  final hasEmptyPageSelect = RegExp(
    r'<select[^>]*name="pageselect"[^>]*>\s*</select>',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(html);
  if (!hasEmptySectionList || !hasEmptyPageSelect) {
    return false;
  }

  final latestChapter = (book.latestChapterTitle ?? '').trim();
  final normalizedWordCount = (book.wordCount ?? '').replaceAll(
    RegExp(r'\s+'),
    '',
  );
  final hasMissingWordCount = normalizedWordCount.isEmpty;
  final hasZeroWordCount = RegExp(r'^0+(万)?$').hasMatch(normalizedWordCount);
  final hasPlaceholderLatestChapter =
      latestChapter.contains('1970-01-01') ||
      latestChapter.contains('1970/01/01') ||
      latestChapter.contains('1970年') ||
      latestChapter.contains('{{@@') ||
      latestChapter.contains('property\$=update_time');
  return latestChapter.isEmpty ||
      hasMissingWordCount ||
      hasZeroWordCount ||
      hasPlaceholderLatestChapter;
}

bool looksLikeDownloadOnlySource(
  Book book,
  List<BookChapter> readableChapters,
) {
  if (readableChapters.isEmpty) return false;
  final firstChapter = readableChapters.first;
  final title = firstChapter.title.trim().toLowerCase();
  final urls = <String>[
    book.bookUrl.trim().toLowerCase(),
    book.tocUrl.trim().toLowerCase(),
    firstChapter.url.trim().toLowerCase(),
  ];

  const downloadMarkers = <String>[
    '点击地址栏下载',
    '點擊地址欄下載',
    '点击下载',
    '點擊下載',
    '网盘',
    '網盤',
    'txt下载',
    'txt下載',
    'zip下载',
    'zip下載',
    'epub下载',
    'epub下載',
    'rar下载',
    'rar下載',
    '📥',
  ];
  const downloadUrlMarkers = <String>[
    'downbook.php',
    '/download/',
    'downajax',
    '.zip',
    '.rar',
    '.epub',
    '.txt',
  ];

  return downloadMarkers.any(title.contains) ||
      urls.any(
        (url) => downloadUrlMarkers.any((marker) => url.contains(marker)),
      );
}

List<int> buildContentProbeIndexes(List<BookChapter> chapters, int maxProbe) {
  final preferred = <int>[];
  final fallback = <int>[];

  void addProbe(int index) {
    if (index < 0 || index >= chapters.length) return;
    if (preferred.contains(index) || fallback.contains(index)) return;
    if (isLikelyLockedChapter(chapters[index])) {
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

  return <int>[...preferred, ...fallback];
}

List<int> buildNeighborProbeIndexes(
  List<BookChapter> chapters,
  int anchorIndex,
  int maxProbe,
) {
  final preferred = <int>[];
  final fallback = <int>[];

  void addProbe(int index) {
    if (index < 0 || index >= chapters.length) return;
    if (preferred.contains(index) || fallback.contains(index)) return;
    if (isLikelyLockedChapter(chapters[index])) {
      fallback.add(index);
    } else {
      preferred.add(index);
    }
  }

  final nextEnd = math.min(anchorIndex + 1 + maxProbe, chapters.length);
  for (var i = anchorIndex + 1; i < nextEnd; i++) {
    addProbe(i);
  }

  final prevStart = math.max(anchorIndex - maxProbe, 0);
  for (var i = anchorIndex - 1; i >= prevStart; i--) {
    addProbe(i);
  }

  return <int>[...preferred, ...fallback];
}

bool isLikelyLockedChapter(BookChapter chapter) {
  final title = chapter.title.trim().toUpperCase();
  return (chapter.isVip && !chapter.isPay) ||
      title.contains('🔒') ||
      title.contains('VIP') ||
      title.contains('鎖章') ||
      title.contains('锁章') ||
      title.contains('解鎖') ||
      title.contains('解锁') ||
      title.contains('付費') ||
      title.contains('付费');
}

BookChapter? firstLikelyLockedChapter(List<BookChapter> chapters) {
  for (final chapter in chapters) {
    if (isLikelyLockedChapter(chapter)) {
      return chapter;
    }
  }
  return null;
}

List<String> buildKeywordCandidates(String seed) {
  final candidates = <String>[];
  final trimmedSeed = seed.trim();

  void addCandidate(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    if (keyword.runes.length < 2) return;
    if (candidates.contains(keyword)) return;
    candidates.add(keyword);
  }

  if (_plainKeywordPattern.hasMatch(trimmedSeed)) {
    addCandidate(trimmedSeed);
  }

  final normalized =
      trimmedSeed
          .replaceAll(RegExp(r'[《》【】\[\]（）()<>]'), ' ')
          .replaceAll(RegExp(r'[:：,，.。!！?？/\\|_\-]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  addCandidate(normalized);

  final joined = normalized.replaceAll(' ', '');
  addCandidate(joined);

  final tokenPattern = RegExp(r'[\u4e00-\u9fffA-Za-z0-9]+', unicode: true);
  final tokens =
      tokenPattern
          .allMatches(normalized)
          .map((match) => match.group(0)!)
          .where(looksLikeBookName)
          .toList();
  for (final token in tokens) {
    addCandidate(token);
  }

  for (var len = math.min(joined.runes.length, 6); len >= 2; len--) {
    addCandidate(String.fromCharCodes(joined.runes.take(len)));
  }

  addCandidate(trimmedSeed);

  return candidates;
}

bool looksLikeBookName(String text) {
  final value = text.trim();
  if (value.runes.length < 2 || value.runes.length > 24) {
    return false;
  }
  if (value.contains('登录') ||
      value.contains('注册') ||
      value.contains('首页') ||
      value.contains('上一章') ||
      value.contains('下一章')) {
    return false;
  }
  return RegExp(r'[\u4e00-\u9fffA-Za-z0-9]', unicode: true).hasMatch(value);
}

bool _searchBookMatchesKeyword(SearchBook book, String keyword) {
  return _nameAuthorMatchesKeyword(book.name, book.author ?? '', keyword);
}

bool _nameAuthorMatchesKeyword(String name, String author, String keyword) {
  final haystacks =
      <String>[
        _normalizeKeywordText(name),
        _normalizeKeywordText(author),
      ].where((value) => value.isNotEmpty).toList();
  if (haystacks.isEmpty) return false;

  for (final candidate in _buildKeywordMatchCandidates(keyword)) {
    if (candidate.isEmpty) continue;
    if (haystacks.any((value) => value.contains(candidate))) {
      return true;
    }
  }
  return false;
}

List<String> _buildKeywordMatchCandidates(String keyword) {
  final trimmed = keyword.trim();
  final candidates = <String>[];

  void addCandidate(String value) {
    final normalized = _normalizeKeywordText(value);
    if (normalized.runes.length < 2) return;
    if (candidates.contains(normalized)) return;
    candidates.add(normalized);
  }

  addCandidate(trimmed);

  final cleaned =
      trimmed
          .replaceAll(RegExp(r'[《》【】\[\]（）()<>]'), ' ')
          .replaceAll(RegExp(r'[:：,，.。!！?？/\\|_\-]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  addCandidate(cleaned);

  for (final token in cleaned.split(' ')) {
    addCandidate(token);
  }

  return candidates;
}

String _normalizeKeywordText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[《》【】\[\]（）()<>]'), '')
      .replaceAll(RegExp(r'[:：,，.。!！?？/\\|_\-\s]+'), '');
}

class _PassthroughHttpOverrides extends HttpOverrides {}

final RegExp _plainKeywordPattern = RegExp(
  r'^[\u4e00-\u9fffA-Za-z0-9]{2,24}$',
  unicode: true,
);
