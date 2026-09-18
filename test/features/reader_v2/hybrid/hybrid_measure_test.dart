import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

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
      final index =
          DocumentIndex(
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
      final index = DocumentIndex(centerKey: center)
        ..admitAll({
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
      final index = DocumentIndex(centerKey: center)
        ..admitAll({
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

    test('invalidateChapter drops only that chapter\'s admitted keys and bumps resetGeneration', () {
      final index =
          DocumentIndex(
            centerKey: const BlockKey(chapterIndex: 1, blockIndex: 0),
          )..admitAll({
            const BlockKey(chapterIndex: 0, blockIndex: 0): const BlockMetrics(
              height: 40,
              lineCount: 1,
            ),
            const BlockKey(chapterIndex: 0, blockIndex: 1): const BlockMetrics(
              height: 30,
              lineCount: 1,
            ),
            const BlockKey(chapterIndex: 1, blockIndex: 0): const BlockMetrics(
              height: 80,
              lineCount: 2,
            ),
            const BlockKey(chapterIndex: 2, blockIndex: 0): const BlockMetrics(
              height: 50,
              lineCount: 1,
            ),
          });
      final generationBefore = index.resetGeneration;

      final changed = index.invalidateChapter(0);

      expect(changed, isTrue);
      expect(
        index.metricsFor(const BlockKey(chapterIndex: 0, blockIndex: 0)),
        isNull,
      );
      expect(
        index.metricsFor(const BlockKey(chapterIndex: 0, blockIndex: 1)),
        isNull,
      );
      expect(
        index.metricsFor(const BlockKey(chapterIndex: 1, blockIndex: 0)),
        isNotNull,
        reason: '未被 invalidate 的章節不得受影響',
      );
      expect(
        index.metricsFor(const BlockKey(chapterIndex: 2, blockIndex: 0)),
        isNotNull,
      );
      expect(index.beforeExtent, 0);
      expect(index.chapterExtent(0), 0);
      expect(
        index.resetGeneration,
        generationBefore + 1,
        reason: 'index→key 映射位移，sliver 需要以 resetGeneration 強制整批重建',
      );

      // 沒有殘留 key 時應是 no-op，不做多餘的 rebuild／revision bump。
      expect(index.invalidateChapter(0), isFalse);
      expect(index.resetGeneration, generationBefore + 1);
    });

    test('章節 evicted 後以不同 segmentation 重新 admit：不殘留舊切法的高度', () {
      const center = BlockKey(chapterIndex: 5, blockIndex: 0);
      final index = DocumentIndex(centerKey: center);
      // 舊 segmentation：chapter 4 被切成 5 塊，總高 100。
      index.admitAll({
        for (var i = 0; i < 5; i += 1)
          BlockKey(chapterIndex: 4, blockIndex: i): const BlockMetrics(
            height: 20,
            lineCount: 1,
          ),
        center: const BlockMetrics(height: 60, lineCount: 2),
      });
      expect(index.chapterExtent(4), 100);

      // 章節 4 evicted／invalidated：DocumentIndex 端必須整批丟棄，否則
      // 新 segmentation 缺席的舊 blockIndex 會一直錯誤貢獻文檔幾何。
      expect(index.invalidateChapter(4), isTrue);
      expect(index.chapterExtent(4), 0);

      // 重新載入後 maxBlockChars 變大，chapter 4 只剩 2 塊。
      index.admitAll({
        for (var i = 0; i < 2; i += 1)
          BlockKey(chapterIndex: 4, blockIndex: i): const BlockMetrics(
            height: 45,
            lineCount: 3,
          ),
      });

      // 只有新 segmentation 的高度；舊切法遺留的 blockIndex 2..4 不殘留。
      expect(index.chapterExtent(4), 90);
      expect(
        index.metricsFor(const BlockKey(chapterIndex: 4, blockIndex: 2)),
        isNull,
      );
      expect(
        index.metricsFor(const BlockKey(chapterIndex: 4, blockIndex: 4)),
        isNull,
      );
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
      final admission = AdmissionController(documentIndex: index)
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
        final admission = AdmissionController(documentIndex: index)
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
      final admission = AdmissionController(documentIndex: index)
        ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
        ..registerChapter(_chapterBlocks(0, 3))
        ..offer(_ready(0, 1))
        ..activateViewport(visibleTop: 0, visibleBottom: 100, cacheExtent: 50);
      addTearDown(admission.dispose);

      admission.offer(_ready(0, 0));

      expect(index.admittedCount, 2);
      expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 1)), 0);
      expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 0)), -100);
    });

    test(
      'admits a ready edge immediately even when it intersects the viewport',
      () {
        final index = DocumentIndex(
          centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
        );
        final admission = AdmissionController(documentIndex: index)
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
        expect(index.admittedCount, 2);

        admission.updateViewport(
          visibleTop: 0,
          visibleBottom: 100,
          cacheExtent: 50,
        );
        expect(index.admittedCount, 2);
      },
    );

    test('invalidateChapter（連同 DocumentIndex）讓舊 segmentation 重新載入後'
        '不與新高度混疊——重現章節 evicted／invalidated 後 maxBlockChars '
        '改變的實際路徑', () {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
      );
      final admission = AdmissionController(documentIndex: index)
        ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
        ..registerChapter(_chapterBlocks(0, 3)); // 舊 segmentation：3 塊
      addTearDown(admission.dispose);

      admission
        ..offer(_ready(0, 0))
        ..offer(_ready(0, 1))
        ..offer(_ready(0, 2));
      expect(index.admittedCount, 3);
      expect(index.chapterExtent(0), 300); // _ready 固定 height: 100

      // 章節 evicted／invalidated：與 HybridReaderScreen._onChapterEvent
      // 同款兩步——DocumentIndex 丟棄已放行座標，AdmissionController 丟棄
      // 記住的舊章節形狀與尚未 admit 的殘留 pending。
      final indexChanged = index.invalidateChapter(0);
      admission.invalidateChapter(0);
      expect(indexChanged, isTrue);
      expect(index.admittedCount, 0);

      // 重新載入：maxBlockChars 變大，chapter 0 只剩 1 塊。
      admission.registerChapter(_chapterBlocks(0, 1));
      admission.offer(
        BlockReady(
          key: const BlockKey(chapterIndex: 0, blockIndex: 0),
          epoch: LayoutEpoch.initial,
          metrics: const BlockMetrics(height: 42, lineCount: 5),
        ),
      );

      // 只有新 segmentation 的高度，沒有舊切法遺留的 blockIndex 1/2。
      expect(index.admittedCount, 1);
      expect(index.chapterExtent(0), 42);
    });
  });

  group('MetricsDiskCache', () {
    test('identical content with different block boundaries cannot share disk metrics', () async {
      final temp = await Directory.systemTemp.createTemp(
        'reader_segmentation_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final cache = MetricsDiskCache(baseDirectory: temp);
      final text = ChapterText(
        id: 0,
        title: '',
        paragraphs: const ['abcdefgh'],
        displayText: 'abcdefgh',
        contentHash: 'same-content',
      );
      const preprocessor = TextPreprocessor(useIsolate: false);
      final small = await preprocessor.process(text, maxBlockChars: 2);
      final large = await preprocessor.process(text, maxBlockChars: 4);
      final repeated = await preprocessor.process(text, maxBlockChars: 2);
      expect(small.contentHash, large.contentHash);
      expect(small.layoutIdentity, isNot(large.layoutIdentity));
      expect(small.layoutIdentity, repeated.layoutIdentity);
      final metrics = {
        small.blocks.first.key: const BlockMetrics(height: 40, lineCount: 2),
      };
      final fingerprint = _fingerprint(width: 360);
      await cache.write(
        bookUrl: 'book://segmentation',
        fingerprint: fingerprint,
        metrics: metrics,
        chapterLayoutIdentities: {0: small.layoutIdentity},
      );
      expect(
        await cache.read(
          bookUrl: 'book://segmentation',
          fingerprint: fingerprint,
          chapterLayoutIdentities: {0: repeated.layoutIdentity},
        ),
        metrics,
      );
      expect(
        await cache.read(
          bookUrl: 'book://segmentation',
          fingerprint: fingerprint,
          chapterLayoutIdentities: {0: large.layoutIdentity},
        ),
        isEmpty,
      );
    });

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
          chapterLayoutIdentities: const <int, String>{2: 'content-v1'},
        ),
        1,
      );

      final restored = await cache.read(
        bookUrl: 'book://1',
        fingerprint: fp,
        chapterLayoutIdentities: const <int, String>{2: 'content-v1'},
      );
      expect(restored, metrics);
      expect(
        await cache.read(
          bookUrl: 'book://1',
          fingerprint: fp,
          chapterLayoutIdentities: const <int, String>{2: 'content-v2'},
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
