import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/book_source_service.dart';

import 'source_validation_support.dart';

void main() {
  final service = BookSourceService();
  late final List<BookSource> firstThreeSources;

  setUpAll(() async {
    await initSourceValidationEnvironment();
    firstThreeSources = await fetchSources(limit: 3);
  });

  group('Live source validation', () {
    for (var i = 0; i < 3; i++) {
      test(
        'source ${i + 1}: ${i == 0
            ? 'BB成人小说'
            : i == 1
            ? '爱丽丝书屋'
            : '随心看吧'}',
        () async {
          final source = firstThreeSources[i];
          final result = await validateSourceFlow(
            service,
            source,
            index: i + 1,
          );
          expect(result.passed, isTrue, reason: result.toSummaryLine());

          // ignore: avoid_print
          print(
            '[live] ${result.sourceName} '
            'keyword="${result.keyword}" '
            'book="${result.bookName}" '
            'chapters=${result.chapterCount} '
            'first="${result.firstChapterTitle}"',
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  });
}
