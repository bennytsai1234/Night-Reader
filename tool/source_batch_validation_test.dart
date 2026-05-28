import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/services/book_source_service.dart';

import 'source_validation_support.dart';

void main() {
  final service = BookSourceService();
  final start = int.tryParse(Platform.environment['SOURCE_START'] ?? '') ?? 0;
  final limit = int.tryParse(Platform.environment['SOURCE_LIMIT'] ?? '') ?? 10;
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
          result = await validateSourceFlow(
            service,
            source,
            index: start + i + 1,
            cancelToken: cancelToken,
          ).timeout(
            Duration(seconds: perSourceTimeoutSeconds),
            onTimeout: () {
              cancelToken.cancel('source validation timeout');
              throw TimeoutException(
                'source validation timeout',
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
        print('[batch] ${result.toSummaryLine()}');
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    results = orderedResults.whereType<SourceValidationResult>().toList(
      growable: false,
    );
  });

  test(
    'audit configured imported sources',
    () {
      expect(results, hasLength(limit));

      final typedResults = results.cast<SourceValidationResult>();
      final passed = typedResults.where((it) => it.passed).length;
      final skipped = typedResults.where((it) => it.skipped).length;
      final failed = typedResults.length - passed - skipped;
      final categories = <String, int>{};
      for (final result in typedResults) {
        final category = result.category;
        if (category == null || category.isEmpty) continue;
        categories.update(category, (value) => value + 1, ifAbsent: () => 1);
      }
      // ignore: avoid_print
      print(
        '[batch] summary: range=${start + 1}-${start + limit} '
        'pass=$passed skip=$skipped fail=$failed '
        'categories=$categories',
      );
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}

int _clampConcurrency(int requested, int itemCount) {
  if (itemCount <= 0) return 1;
  return requested.clamp(1, itemCount).toInt();
}
