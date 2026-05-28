import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/engine/explore_url_parser.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/models/source/explore_kind.dart';
import 'package:reader/core/services/book_source_service.dart';

import 'source_validation_support.dart';
import '../test/test_helper.dart';

void main() {
  final service = BookSourceService();
  final start = int.tryParse(Platform.environment['SOURCE_START'] ?? '') ?? 0;
  final limit = int.tryParse(Platform.environment['SOURCE_LIMIT'] ?? '') ?? 30;
  final perSourceTimeoutSeconds =
      int.tryParse(Platform.environment['SOURCE_TIMEOUT_SECONDS'] ?? '') ?? 20;
  final sourceConcurrency =
      int.tryParse(Platform.environment['SOURCE_CONCURRENCY'] ?? '') ?? 6;
  late final List<SourceValidationResult> results;

  setUpAll(() async {
    await initSourceValidationEnvironment();
    final fetched = await fetchSources(limit: start + limit);
    final sources = fetched.skip(start).take(limit).toList();
    final orderedResults = List<SourceValidationResult?>.filled(
      sources.length,
      null,
    );
    var nextIndex = 0;
    final workerCount = _clampConcurrency(sourceConcurrency, sources.length);

    Future<void> worker() async {
      while (true) {
        final i = nextIndex;
        if (i >= sources.length) break;
        nextIndex = i + 1;

        final source = sources[i];
        late final SourceValidationResult result;
        final cancelToken = CancelToken();
        try {
          result = await validateExploreFlow(
            service,
            source,
            index: start + i + 1,
            cancelToken: cancelToken,
          ).timeout(
            Duration(seconds: perSourceTimeoutSeconds),
            onTimeout: () {
              cancelToken.cancel('explore validation timeout');
              throw TimeoutException(
                'explore validation timeout',
                Duration(seconds: perSourceTimeoutSeconds),
              );
            },
          );
        } catch (error) {
          final classification = classifyValidationFailure(
            error,
            source: source,
            stage: 'timeout',
          );
          result = SourceValidationResult(
            index: start + i + 1,
            sourceName: source.bookSourceName,
            outcome: classification.outcome,
            stage: 'timeout',
            duration: Duration(seconds: perSourceTimeoutSeconds),
            failure: compactError(error),
            category: classification.category,
          );
        }
        orderedResults[i] = result;
        // ignore: avoid_print
        print('[explore-batch] ${result.toSummaryLine()}');
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    results = orderedResults.whereType<SourceValidationResult>().toList(
      growable: false,
    );
  });

  test(
    'audit configured imported explore sources',
    () {
      expect(results, hasLength(limit));

      final passed = results.where((it) => it.passed).length;
      final skipped = results.where((it) => it.skipped).length;
      final failed = results.length - passed - skipped;
      final categories = <String, int>{};
      for (final result in results) {
        final category = result.category;
        if (category == null || category.isEmpty) continue;
        categories.update(category, (value) => value + 1, ifAbsent: () => 1);
      }
      // ignore: avoid_print
      print(
        '[explore-batch] summary: range=${start + 1}-${start + limit} '
        'pass=$passed skip=$skipped fail=$failed categories=$categories',
      );
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<SourceValidationResult> validateExploreFlow(
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

  if (!source.enabledExplore || !source.hasExploreUrl) {
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: SourceValidationOutcome.skip,
      stage: 'source-filter',
      duration: Duration.zero,
      failure: '書源未啟用發現或缺少發現規則',
      category: 'explore-disabled',
    );
  }

  if (_requiresJsExplore(source) && quickJsUnavailableReason() != null) {
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: SourceValidationOutcome.skip,
      stage: 'source-filter',
      duration: Duration.zero,
      failure: quickJsUnavailableReason(),
      category: 'env-js-runtime',
    );
  }

  if (_exploreMarkedBroken(source)) {
    return SourceValidationResult(
      index: index,
      sourceName: source.bookSourceName,
      outcome: SourceValidationOutcome.skip,
      stage: 'source-filter',
      duration: Duration.zero,
      failure: '書源已標記發現失效或校驗超時',
      category: 'source-marked-broken',
    );
  }

  final stopwatch = Stopwatch()..start();
  var stage = 'explore:kinds';
  ExploreKind? selectedKind;

  try {
    final kinds = await ExploreUrlParser.parseAsync(
      source.exploreUrl,
      source: source,
    );
    final candidates =
        kinds.where((kind) {
          final title = kind.title.trim();
          final url = kind.url?.trim() ?? '';
          return title.isNotEmpty &&
              !title.startsWith('ERROR:') &&
              url.isNotEmpty;
        }).toList();
    if (candidates.isEmpty) {
      throw StateError('發現分類為空或規則解析失敗');
    }

    stage = 'explore:books';
    for (final kind in candidates.take(3)) {
      final books = await service.exploreBooks(
        source,
        kind.url!,
        page: 1,
        cancelToken: cancelToken,
      );
      if (books.isNotEmpty) {
        final firstBook = books.first;
        if (_looksLikeJsRuntimePlaceholder(firstBook)) {
          return SourceValidationResult(
            index: index,
            sourceName: source.bookSourceName,
            outcome: SourceValidationOutcome.skip,
            stage: stage,
            duration: stopwatch.elapsed,
            bookName: firstBook.name,
            bookUrl: firstBook.bookUrl,
            firstChapterTitle: kind.title,
            failure: '書籍欄位受 JS runtime 缺失污染',
            category: 'env-js-runtime',
          );
        }
        selectedKind = kind;
        stopwatch.stop();
        return SourceValidationResult(
          index: index,
          sourceName: source.bookSourceName,
          outcome: SourceValidationOutcome.pass,
          stage: stage,
          duration: stopwatch.elapsed,
          bookName: books.first.name,
          bookUrl: books.first.bookUrl,
          firstChapterTitle: kind.title,
        );
      }
      selectedKind = kind;
    }
    throw StateError('發現分類打開後沒有書籍');
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
      firstChapterTitle: selectedKind?.title,
      failure: compactError(error),
      category: classification.category,
    );
  }
}

int _clampConcurrency(int requested, int itemCount) {
  if (itemCount <= 0) return 1;
  return requested.clamp(1, itemCount).toInt();
}

bool _exploreMarkedBroken(BookSource source) {
  final markers =
      '${source.bookSourceGroup ?? ''}\n${source.bookSourceComment ?? ''}'
          .toLowerCase();
  if (markers.isEmpty) return false;
  return markers.contains('發現失效') ||
      markers.contains('发现失效') ||
      markers.contains('校驗超時') ||
      markers.contains('校验超时');
}

bool _requiresJsExplore(BookSource source) {
  final exploreUrl = source.exploreUrl?.trimLeft() ?? '';
  return exploreUrl.startsWith('@js:') || exploreUrl.startsWith('<js>');
}

bool _looksLikeJsRuntimePlaceholder(SearchBook book) {
  bool containsPlaceholder(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return false;
    final normalized = text.toLowerCase();
    return normalized.contains('js_error: library not available') ||
        normalized.contains('libquickjs_c_bridge_plugin.so');
  }

  return containsPlaceholder(book.name) ||
      containsPlaceholder(book.author) ||
      containsPlaceholder(book.bookUrl);
}
