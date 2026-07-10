import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/metrics_disk_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/admission_controller.dart';

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

  group('AdmissionController', () {
    test('holds out-of-order ready blocks until both sides are contiguous', () {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 1),
      );
      final admission =
          AdmissionController(documentIndex: index)
            ..reset(epoch: LayoutEpoch.initial, chapterCount: 2)
            ..registerChapter(_chapterBlocks(0, 3))
            ..registerChapter(_chapterBlocks(1, 1));
      addTearDown(admission.dispose);

      admission.offer(_ready(1, 0));
      expect(index.admittedCount, 0);

      admission.offer(_ready(0, 1));
      expect(index.keys, <BlockKey>[
        const BlockKey(chapterIndex: 0, blockIndex: 1),
      ]);

      admission.offer(_ready(0, 2));
      expect(index.keys, <BlockKey>[
        const BlockKey(chapterIndex: 0, blockIndex: 1),
        const BlockKey(chapterIndex: 0, blockIndex: 2),
        const BlockKey(chapterIndex: 1, blockIndex: 0),
      ]);

      admission.offer(_ready(0, 0));
      expect(index.admittedCount, 4);
    });

    test(
      'admits a late exact edge block without moving existing coordinates',
      () {
        final index = DocumentIndex(
          centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
        );
        final admission =
            AdmissionController(documentIndex: index)
              ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
              ..registerChapter(_chapterBlocks(0, 2))
              ..offer(_ready(0, 0))
              ..activateViewport(
                visibleTop: 0,
                visibleBottom: 100,
                cacheExtent: 50,
              );
        addTearDown(admission.dispose);

        final originalTop = index.topOf(
          const BlockKey(chapterIndex: 0, blockIndex: 0),
        );
        admission.offer(_ready(0, 1));

        expect(index.admittedCount, 2);
        expect(
          index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 0)),
          originalTop,
        );
        expect(
          index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 1)),
          100,
        );
      },
    );

    test('admits a late exact backward edge without moving the center', () {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 1),
      );
      final admission =
          AdmissionController(documentIndex: index)
            ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
            ..registerChapter(_chapterBlocks(0, 3))
            ..offer(_ready(0, 1))
            ..activateViewport(
              visibleTop: 0,
              visibleBottom: 100,
              cacheExtent: 50,
            );
      addTearDown(admission.dispose);

      admission.offer(_ready(0, 0));

      expect(index.admittedCount, 2);
      expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 1)), 0);
      expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 0)), -100);
    });

    test(
      'keeps a late edge pending until it is outside the visible viewport',
      () {
        final index = DocumentIndex(
          centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
        );
        final admission =
            AdmissionController(documentIndex: index)
              ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
              ..registerChapter(_chapterBlocks(0, 2))
              ..offer(_ready(0, 0))
              ..activateViewport(
                visibleTop: 0,
                visibleBottom: 120,
                cacheExtent: 50,
              );
        addTearDown(admission.dispose);

        admission.offer(_ready(0, 1));
        expect(index.admittedCount, 1);

        admission.updateViewport(
          visibleTop: 0,
          visibleBottom: 100,
          cacheExtent: 50,
        );
        expect(index.admittedCount, 2);
      },
    );
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
          chapterContentHashes: const <int, String>{2: 'content-v1'},
        ),
        1,
      );

      final restored = await cache.read(
        bookUrl: 'book://1',
        fingerprint: fp,
        chapterContentHashes: const <int, String>{2: 'content-v1'},
      );
      expect(restored, metrics);
      expect(
        await cache.read(
          bookUrl: 'book://1',
          fingerprint: fp,
          chapterContentHashes: const <int, String>{2: 'content-v2'},
        ),
        isEmpty,
      );
    });
  });
}

ChapterBlocks _chapterBlocks(int chapterIndex, int count) {
  return ChapterBlocks(
    chapterIndex: chapterIndex,
    title: '',
    displayText: 'x' * count,
    contentHash: 'hash-$chapterIndex',
    blocks: List<ChapterBlock>.generate(
      count,
      (index) => ChapterBlock(
        key: BlockKey(chapterIndex: chapterIndex, blockIndex: index),
        text: 'x',
        charRange: HybridTextRange(index, index + 1),
        sourceParagraphIndex: index,
      ),
    ),
  );
}

BlockReady _ready(int chapterIndex, int blockIndex) {
  return BlockReady(
    key: BlockKey(chapterIndex: chapterIndex, blockIndex: blockIndex),
    epoch: LayoutEpoch.initial,
    metrics: const BlockMetrics(height: 100, lineCount: 1),
  );
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
