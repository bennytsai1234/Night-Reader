import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/metrics_disk_cache.dart';

void main() {
  group('DocumentIndex', () {
    test('maps offsets to exact admitted block extents across center', () {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 1, blockIndex: 0),
      )..admitAll({
        const BlockKey(chapterIndex: 0, blockIndex: 0): const BlockMetrics(
          height: 100,
          lineCount: 3,
        ),
        const BlockKey(chapterIndex: 0, blockIndex: 1): const BlockMetrics(
          height: 50,
          lineCount: 2,
        ),
        const BlockKey(chapterIndex: 1, blockIndex: 0): const BlockMetrics(
          height: 80,
          lineCount: 2,
        ),
        const BlockKey(chapterIndex: 1, blockIndex: 1): const BlockMetrics(
          height: 60,
          lineCount: 2,
        ),
      });

      expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 1)), -50);
      expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 0)), -150);
      expect(index.blockAtOffset(-1)?.blockIndex, 1);
      expect(index.blockAtOffset(-50)?.blockIndex, 1);
      expect(index.blockAtOffset(-51)?.blockIndex, 0);
      expect(
        index.blockAtOffset(0),
        const BlockKey(chapterIndex: 1, blockIndex: 0),
      );
      expect(
        index.blockAtOffset(80),
        const BlockKey(chapterIndex: 1, blockIndex: 1),
      );
      expect(index.chapterExtent(0), 150);
    });
  });

  group('MeasurementStore', () {
    test('invalidates only the changed chapter for content updates', () {
      final store = MeasurementStore();
      final ns = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(width: 320),
      );
      final key0 = const BlockKey(chapterIndex: 0, blockIndex: 0);
      final key1 = const BlockKey(chapterIndex: 1, blockIndex: 0);
      store
        ..put(ns, key0, const BlockMetrics(height: 10, lineCount: 1))
        ..put(ns, key1, const BlockMetrics(height: 20, lineCount: 1))
        ..invalidateFor(
          cause: MetricsInvalidationCause.content,
          chapterIndex: 0,
        );

      expect(store.get(ns, key0), isNull);
      expect(store.get(ns, key1), isNotNull);
    });
  });

  group('MetricsDiskCache', () {
    test('round-trips versioned binary metrics', () async {
      final temp = await Directory.systemTemp.createTemp(
        'night_reader_metrics_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final cache = MetricsDiskCache(baseDirectory: temp);
      final fp = _fingerprint(width: 360);
      final metrics = <BlockKey, BlockMetrics>{
        const BlockKey(chapterIndex: 2, blockIndex: 1): const BlockMetrics(
          height: 42.5,
          lineCount: 3,
        ),
      };

      expect(
        await cache.write(
          bookUrl: 'book://1',
          fingerprint: fp,
          metrics: metrics,
        ),
        1,
      );

      final restored = await cache.read(bookUrl: 'book://1', fingerprint: fp);
      expect(restored, metrics);
    });
  });
}

StyleFingerprint _fingerprint({required double width}) {
  return StyleFingerprint(
    viewportWidth: width,
    viewportHeight: 640,
    contentWidth: width - 32,
    contentHeight: 600,
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1,
    paddingTop: 8,
    paddingBottom: 8,
    paddingLeft: 16,
    paddingRight: 16,
    textIndent: 2,
    bold: false,
    justify: true,
    textScaleFactor: 1,
    fontFamilySignature: 'system',
    platformFontSignature: 'test',
  );
}
