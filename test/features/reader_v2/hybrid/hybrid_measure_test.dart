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

    test('incremental edge admits match a bulk rebuild exactly', () {
      const center = BlockKey(chapterIndex: 2, blockIndex: 3);
      final metrics = <BlockKey, BlockMetrics>{};
      var height = 10.0;
      for (var chapter = 0; chapter < 5; chapter += 1) {
        for (var block = 0; block < 7; block += 1) {
          metrics[BlockKey(chapterIndex: chapter, blockIndex: block)] =
              BlockMetrics(height: height, lineCount: 1);
          height += 3.5;
        }
      }
      final sorted = metrics.keys.toList()..sort();
      final centerPos = sorted.indexOf(center);

      final incremental = DocumentIndex(centerKey: center);
      incremental.admit(center, metrics[center]!);
      // 由 center 向兩側交錯放行（I2 的實際運轉方式）。
      var forward = centerPos + 1;
      var backward = centerPos - 1;
      while (forward < sorted.length || backward >= 0) {
        if (forward < sorted.length) {
          incremental.admit(sorted[forward], metrics[sorted[forward]]!);
          forward += 1;
        }
        if (backward >= 0) {
          incremental.admit(sorted[backward], metrics[sorted[backward]]!);
          backward -= 1;
        }
      }

      final bulk = DocumentIndex(centerKey: center)..admitAll(metrics);
      expect(incremental.admittedCount, bulk.admittedCount);
      expect(incremental.beforeExtent, closeTo(bulk.beforeExtent, 1e-6));
      expect(incremental.afterExtent, closeTo(bulk.afterExtent, 1e-6));
      expect(incremental.keys.toList(), bulk.keys.toList());
      expect(incremental.keys.toList(), sorted);
      for (final key in sorted) {
        expect(incremental.topOf(key), closeTo(bulk.topOf(key)!, 1e-6));
        expect(incremental.bottomOf(key), closeTo(bulk.bottomOf(key)!, 1e-6));
      }
      expect(incremental.backwardEdgeKey, sorted.first);
      expect(incremental.forwardEdgeKey, sorted.last);
      for (var chapter = 0; chapter < 5; chapter += 1) {
        expect(
          incremental.chapterExtent(chapter),
          closeTo(bulk.chapterExtent(chapter), 1e-6),
        );
      }
    });

    test('keysInRange returns exactly the intersecting blocks in order', () {
      const center = BlockKey(chapterIndex: 1, blockIndex: 0);
      final index = DocumentIndex(centerKey: center)..admitAll({
        for (var i = 0; i < 4; i += 1)
          BlockKey(chapterIndex: 0, blockIndex: i): const BlockMetrics(
            height: 25,
            lineCount: 1,
          ),
        for (var i = 0; i < 4; i += 1)
          BlockKey(chapterIndex: 1, blockIndex: i): const BlockMetrics(
            height: 25,
            lineCount: 1,
          ),
      });
      // 文檔佔據 [-100, 100)，每塊 25px。
      List<BlockKey> naive(double top, double bottom) {
        if (bottom <= top) return const <BlockKey>[]; // 空區間 → 空（契約）
        return index.keys.where((key) {
          final blockTop = index.topOf(key)!;
          return blockTop + 25 > top && blockTop < bottom;
        }).toList();
      }

      for (final (top, bottom) in <(double, double)>[
        (-100, 100),
        (-60, 60),
        (-25, 25),
        (-1, 1),
        (0, 50),
        (-50, 0),
        (-200, -99),
        (99, 200),
        (-300, -150),
        (150, 300),
        (10, 10),
      ]) {
        expect(
          index.keysInRange(top, bottom),
          naive(top, bottom),
          reason: 'range [$top, $bottom)',
        );
      }
    });

    test('chapterRange spans both sides when the chapter crosses center', () {
      const center = BlockKey(chapterIndex: 1, blockIndex: 2);
      final index = DocumentIndex(centerKey: center)..admitAll({
        const BlockKey(chapterIndex: 0, blockIndex: 0): const BlockMetrics(
          height: 40,
          lineCount: 1,
        ),
        for (var i = 0; i < 4; i += 1)
          BlockKey(chapterIndex: 1, blockIndex: i): const BlockMetrics(
            height: 30,
            lineCount: 1,
          ),
        const BlockKey(chapterIndex: 2, blockIndex: 0): const BlockMetrics(
          height: 50,
          lineCount: 1,
        ),
      });
      // before: ch0b0(-100..-60) ch1b0(-60..-30) ch1b1(-30..0)
      // after: ch1b2(0..30) ch1b3(30..60) ch2b0(60..110)
      final range = index.chapterRange(1)!;
      expect(range.top, closeTo(-60, 1e-9));
      expect(range.bottom, closeTo(60, 1e-9));
      expect(index.chapterExtent(1), closeTo(120, 1e-9));
      expect(index.chapterRange(0)!.top, closeTo(-100, 1e-9));
      expect(index.chapterRange(0)!.bottom, closeTo(-60, 1e-9));
      expect(index.chapterRange(2)!.top, closeTo(60, 1e-9));
      expect(index.chapterRange(2)!.bottom, closeTo(110, 1e-9));
      expect(index.chapterRange(3), isNull);
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
