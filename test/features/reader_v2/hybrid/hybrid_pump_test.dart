import 'package:night_reader/features/reader_v2/hybrid/view/admission_controller.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/metrics_disk_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/budget_governor.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_cost_model.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParagraphCache', () {
    test('live consumer survives LRU eviction until its lease is released', () {
      final cache = ParagraphCache(capacity: 1);
      const epoch = LayoutEpoch.initial;
      const first = BlockKey(chapterIndex: 0, blockIndex: 0);
      const second = BlockKey(chapterIndex: 0, blockIndex: 1);
      final live = cache.retain(first, epoch);
      final paragraph = _paragraph('first');
      cache.put(first, epoch, paragraph);
      cache.put(second, epoch, _paragraph('second'));
      expect(cache.length, 1);
      expect(live.entry!.paragraph, same(paragraph));
      expect(live.entry!.paragraph.height, greaterThan(0));
      expect(cache.contains(first, epoch), isTrue);
      live.release();
      expect(cache.contains(first, epoch), isFalse);
      cache.dispose();
    });

    test(
      'leases acquired before a group is built survive capacity enforcement',
      () {
        final cache = ParagraphCache(capacity: 1);
        const epoch = LayoutEpoch.initial;
        const first = BlockKey(chapterIndex: 0, blockIndex: 0);
        const second = BlockKey(chapterIndex: 0, blockIndex: 1);
        final a = cache.retain(first, epoch);
        final b = cache.retain(second, epoch);
        cache.putGroup([first, second], [0, 20], epoch, _paragraph('group'));
        expect(cache.length, 1);
        expect(a.entry!.paragraph, same(b.entry!.paragraph));
        expect(b.entry!.localTop, 20);
        cache.dispose();
        expect(a.entry!.paragraph.height, greaterThan(0));
        a.release();
        expect(b.entry!.paragraph.height, greaterThan(0));
        b.release();
      },
    );

    test(
      'a consumer observes every replacement and stops observing on release',
      () {
        final cache = ParagraphCache();
        const key = BlockKey(chapterIndex: 0, blockIndex: 0);
        var calls = 0;
        final lease = cache.retain(
          key,
          LayoutEpoch.initial,
          onChanged: () => calls++,
        );
        cache.put(key, LayoutEpoch.initial, _paragraph('a'));
        cache.put(key, LayoutEpoch.initial, _paragraph('b'));
        expect(calls, 2);
        lease.release();
        cache.put(key, LayoutEpoch.initial, _paragraph('c'));
        expect(calls, 2);
        cache.dispose();
      },
    );

    test('tracks baked color for the paint fast path', () {
      final cache = ParagraphCache();
      const epoch = LayoutEpoch.initial;
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      const black = ui.Color(0xFF000000);
      const sepia = ui.Color(0xFF5B4636);

      cache.put(key, epoch, _paragraph('a'), bakedColor: black);
      expect(cache.containsFresh(key, epoch, black), isTrue);
      expect(cache.containsFresh(key, epoch, sepia), isFalse);
      expect(cache.acquireEntry(key, epoch)?.bakedColor, black);

      // 換色重建後條目被替換、烘色更新。
      cache.put(key, epoch, _paragraph('a'), bakedColor: sepia);
      expect(cache.containsFresh(key, epoch, sepia), isTrue);
      expect(cache.acquireEntry(key, epoch)?.bakedColor, sepia);
      cache.dispose();
    });
  });

  group('LayoutPump', () {
    testWidgets(
      'pending group identity is deduplicated but a completed group can repaint',
      (tester) async {
        final cache = ParagraphCache();
        final namespace = MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: _fingerprint(),
        );
        final pump = LayoutPump(
          paragraphCache: cache,
          measurementStore: MeasurementStore(),
          namespace: namespace,
        );
        addTearDown(() {
          pump.dispose();
          cache.dispose();
        });
        const key = BlockKey(chapterIndex: 0, blockIndex: 0);
        LayoutTask task(ui.Color color) => LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: 'abcd',
            charRange: HybridTextRange(0, 4),
            sourceParagraphIndex: 0,
          ),
          epoch: namespace.epoch,
          fingerprint: namespace.fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: 18,
            lineHeight: 1.5,
            letterSpacing: 0,
          ),
          contentWidth: 240,
          textColor: color,
        );
        const black = ui.Color(0xFF000000);
        const green = ui.Color(0xFF244739);
        pump
          ..submit(task(black))
          ..submit(task(green));
        expect(pump.queueDepth, 1);
        expect(await pump.pumpPending(), 1);
        expect(cache.containsFresh(key, namespace.epoch, green), true);
        pump.submit(task(black));
        await tester.pump(const Duration(milliseconds: 16));
        expect(pump.queueDepth, 0);
        expect(cache.containsFresh(key, namespace.epoch, black), true);
        pump.submit(task(green));
        pump.invalidateChapter(0);
        expect(pump.queueDepth, 0);
      },
    );

    test('dragging keeps bounded valid work runnable', () async {
      final cache = ParagraphCache();
      final store = MeasurementStore();
      final ns = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: ns,
      )..onScrollStateChanged(PumpState.dragging);
      final task = _ownedTask(0, ns);
      pump.submit(task);
      expect(await pump.pumpPending(), 1);
      expect(store.get(ns, task.block.key), isNotNull);
      pump.dispose();
      cache.dispose();
    });

    test('builds paragraph, stores metrics, and emits BlockReady', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
      );
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      final ready = expectLater(
        pump.completed,
        emits(isA<BlockReady>().having((event) => event.key, 'key', key)),
      );

      pump.submit(
        LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: '這是一段測試文字。',
            charRange: HybridTextRange(0, 8),
            sourceParagraphIndex: 0,
          ),
          epoch: LayoutEpoch.initial,
          fingerprint: namespace.fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: 18,
            lineHeight: 1.5,
            letterSpacing: 0,
            textAlign: ui.TextAlign.justify,
          ),
          contentWidth: 240,
          textColor: const ui.Color(0xFFEEEEEE),
        ),
      );

      expect(await pump.pumpPending(), 1);
      await ready;
      expect(store.get(namespace, key), isNotNull);
      expect(cache.contains(key, LayoutEpoch.initial), isTrue);
      expect(
        cache.containsFresh(
          key,
          LayoutEpoch.initial,
          const ui.Color(0xFFEEEEEE),
        ),
        isTrue,
        reason: 'pump 必須把 LayoutTask.textColor 烘進快取條目',
      );
      final metrics = store.get(namespace, key)!;
      expect(metrics.lineCount, greaterThan(0));
      pump.dispose();
      cache.dispose();
    });

    test('B2 末行字距補償增加末行寬度但不超過內容寬', () async {
      final b2Store = MeasurementStore();
      final b2Cache = ParagraphCache();
      final b2Fingerprint = _fingerprint(lastLineSpacingCompensation: true);
      final baselineStore = MeasurementStore();
      final baselineCache = ParagraphCache();
      final baselineFingerprint = _fingerprint();
      final b2Pump = LayoutPump(
        paragraphCache: b2Cache,
        measurementStore: b2Store,
        namespace: MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: b2Fingerprint,
        ),
      );
      final baselinePump = LayoutPump(
        paragraphCache: baselineCache,
        measurementStore: baselineStore,
        namespace: MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: baselineFingerprint,
        ),
      );
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      LayoutTask taskFor(StyleFingerprint fingerprint) {
        return LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: '這是一段足夠長的中文測試文字，用來確保排版會產生上方滿行與最後短行。',
            charRange: HybridTextRange(0, 33),
            sourceParagraphIndex: 0,
          ),
          epoch: LayoutEpoch.initial,
          fingerprint: fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: 18,
            lineHeight: 1.5,
            letterSpacing: 0,
            textAlign: ui.TextAlign.justify,
          ),
          contentWidth: 150,
        );
      }

      b2Pump.submit(taskFor(b2Fingerprint));
      baselinePump.submit(taskFor(baselineFingerprint));

      expect(await b2Pump.pumpPending(), 1);
      expect(await baselinePump.pumpPending(), 1);
      final paragraph = b2Cache.acquire(key, LayoutEpoch.initial)!;
      final baselineParagraph = baselineCache.acquire(
        key,
        LayoutEpoch.initial,
      )!;
      final lines = paragraph.computeLineMetrics();
      final baselineLines = baselineParagraph.computeLineMetrics();
      expect(lines.length, greaterThan(1));
      expect(lines.last.width, greaterThan(0));
      expect(lines.last.width, greaterThan(baselineLines.last.width));
      expect(lines.last.width, lessThanOrEqualTo(150.01));

      b2Pump.dispose();
      b2Cache.dispose();
      baselinePump.dispose();
      baselineCache.dispose();
    });

    test('B2 末行補償：近滿末行不得把末字擠到下一行', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final fingerprint = _fingerprint(lastLineSpacingCompensation: true);
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: fingerprint,
        ),
      );
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      const fontSize = 20.0;
      // 27 個無標點字元 + 寬 9 字 + 1px 殘餘 → 9/9/9 三行；末行 headroom
      // 僅 1px。補償上限若誤用間隙數（8）作分母，總增量 9×0.125 會超寬
      // 而把末字擠成第四行孤行。
      final text = '夜' * 27;
      pump.submit(
        LayoutTask(
          block: ChapterBlock(
            key: key,
            text: text,
            charRange: const HybridTextRange(0, 27),
            sourceParagraphIndex: 0,
          ),
          epoch: LayoutEpoch.initial,
          fingerprint: fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: fontSize,
            lineHeight: 1.5,
            letterSpacing: 0,
            textAlign: ui.TextAlign.justify,
          ),
          contentWidth: fontSize * 9 + 1,
        ),
      );

      expect(await pump.pumpPending(), 1);
      final paragraph = cache.acquire(key, LayoutEpoch.initial)!;
      final lines = paragraph.computeLineMetrics();
      expect(lines.length, 3, reason: '補償不得改變斷行（末字回捲即為 off-by-one）');
      expect(
        lines.last.width,
        lessThanOrEqualTo(fontSize * 9 + 1 + 0.01),
        reason: '末行寬不得超出內容寬',
      );
      pump.dispose();
      cache.dispose();
    });

    test('B2 條件式 Pass 2：必為單行的 block 不進兩段式路徑', () {
      final fingerprint = _fingerprint(lastLineSpacingCompensation: true);
      LayoutTask taskFor(String text, {double contentWidth = 240}) {
        return LayoutTask(
          block: ChapterBlock(
            key: const BlockKey(chapterIndex: 0, blockIndex: 0),
            text: text,
            charRange: HybridTextRange(0, text.length),
            sourceParagraphIndex: 0,
          ),
          epoch: LayoutEpoch.initial,
          fingerprint: fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: 20,
            lineHeight: 1.5,
            letterSpacing: 0,
            textAlign: ui.TextAlign.justify,
          ),
          contentWidth: contentWidth,
          indentChars: 2,
        );
      }

      final costModel = LayoutCostModel();
      // 縮排 2 + 6 字 = 8 units ≤ 12 units 寬 → 必為單行，單次 layout。
      final short = taskFor('「好。」他說', contentWidth: 240);
      expect(LayoutCostModel.mayCompensateLastLine(short), isFalse);
      expect(costModel.layoutPassesFor(short), 1.0);
      // 縮排 2 + 16 字 = 18 units > 12 units 寬 → 可能 soft-wrap，兩段式。
      final long = taskFor('衝在最前面的妖怪頭顱便滾落在地。', contentWidth: 240);
      expect(LayoutCostModel.mayCompensateLastLine(long), isTrue);
      expect(costModel.layoutPassesFor(long), 2.0);
      // B2 關閉時一律單次。
      expect(
        costModel.layoutPassesFor(
          LayoutTask(
            block: long.block,
            epoch: LayoutEpoch.initial,
            fingerprint: _fingerprint(),
            textStyle: long.textStyle,
            contentWidth: 240,
            indentChars: 2,
          ),
        ),
        1.0,
      );
    });

    test('B2 開啟時末行 getBoxesForRange 幾何與畫面一致（TTS 高亮契約）', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final fingerprint = _fingerprint(lastLineSpacingCompensation: true);
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: fingerprint,
        ),
      );
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      const fontSize = 20.0;
      const indentChars = 2;
      const text = '衝在最前面的妖怪頭顱便滾落在地面上。';
      // 縮排 2 + 18 字 = 20 units；寬 16.4 units → 首行 soft-wrap、
      // 末行 4 字有大量 headroom，B2 補償必然生效（受 cap 限制）。
      const contentWidth = fontSize * 16.4;
      pump.submit(
        LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: text,
            charRange: HybridTextRange(0, 18),
            sourceParagraphIndex: 0,
          ),
          epoch: LayoutEpoch.initial,
          fingerprint: fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: fontSize,
            lineHeight: 1.5,
            letterSpacing: 0,
            textAlign: ui.TextAlign.justify,
          ),
          contentWidth: contentWidth,
          indentChars: indentChars,
        ),
      );

      expect(await pump.pumpPending(), 1);
      final paragraph = cache.acquire(key, LayoutEpoch.initial)!;
      final lines = paragraph.computeLineMetrics();
      expect(lines.length, 2);
      expect(
        lines.last.width,
        greaterThan(fontSize * 4),
        reason: 'B2 須實際生效（末行寬 > 自然寬）',
      );

      // TTS 高亮以 displayText offset + 縮排位移換 boxes；B2 的
      // letterSpacing span 不得讓 boxes 與實繪 glyph 幾何脫鉤：
      // 末行各字 box 必須連續相接（無累積漂移）、落在第二行、
      // 總覆蓋範圍與 LineMetrics 寬一致。實測 SkParagraph 把
      // letterSpacing 前後各半分攤在字形兩側，行首容許半個 spacing
      // 的起始偏移（≤ cap 2.0）。
      final lastLineStart = indentChars + 14; // 首行 14 字 + 縮排
      double? expectedLeft;
      var firstLeft = 0.0;
      for (var offset = lastLineStart; offset < indentChars + 18; offset += 1) {
        final box = paragraph.getBoxesForRange(offset, offset + 1).single;
        if (expectedLeft == null) {
          firstLeft = box.left;
          expect(
            firstLeft,
            inInclusiveRange(0.0, LayoutPump.lastLineLetterSpacingCap),
          );
        } else {
          expect(
            box.left,
            closeTo(expectedLeft, 0.01),
            reason: '末行 box 必須連續相接',
          );
        }
        expect(box.top, greaterThan(lines.first.height - 0.01));
        expectedLeft = box.right;
      }
      expect(
        expectedLeft!,
        closeTo(lines.last.width, LayoutPump.lastLineLetterSpacingCap),
        reason: '末行 boxes 覆蓋範圍不得偏離 LineMetrics 寬',
      );
      pump.dispose();
      cache.dispose();
    });

    test('justify 下段首縮排以 placeholder 保留原寬，字距不吸收縮排寬度', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
      );
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      const fontSize = 20.0;
      // 16 字正文 + 縮排 2 = 18 units；寬 16.4 units 讓首行 soft-wrap 且
      // 留 0.4 字寬殘餘空隙給 justify 分配。
      const contentWidth = fontSize * 16.4;
      pump.submit(
        LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: '衝在最前面的妖怪頭顱便滾落在地。',
            charRange: HybridTextRange(0, 16),
            sourceParagraphIndex: 0,
          ),
          epoch: LayoutEpoch.initial,
          fingerprint: namespace.fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: fontSize,
            lineHeight: 1.5,
            letterSpacing: 0,
            textAlign: ui.TextAlign.justify,
          ),
          contentWidth: contentWidth,
          indentChars: 2,
        ),
      );

      expect(await pump.pumpPending(), 1);
      final paragraph = cache.acquire(key, LayoutEpoch.initial)!;
      final lines = paragraph.computeLineMetrics();
      expect(lines.length, 2, reason: '斷行位置須與 U+3000 前綴時相同');

      // 縮排 placeholder 不能被 justify 折疊成 0 寬。
      final placeholders = paragraph.getBoxesForPlaceholders();
      expect(placeholders.length, 2);
      expect(placeholders[0].left, 0);
      expect(placeholders[0].right, closeTo(fontSize, 0.01));
      expect(placeholders[1].right, closeTo(fontSize * 2, 0.01));

      // 首個正文字元緊接縮排之後，且字寬只吸收真正殘餘空隙
      // （縮排寬度被平攤時每字會膨脹到 ~23.4px）。
      final firstGlyph = paragraph.getBoxesForRange(2, 3).single;
      expect(firstGlyph.left, closeTo(fontSize * 2, 0.01));
      expect(firstGlyph.right - firstGlyph.left, lessThan(fontSize + 1.5));
      pump.dispose();
      cache.dispose();
    });
  });

  group('LayoutPump demand ownership', () {
    test(
      'transferring demand cancels old work before layout and permits re-entry',
      () async {
        final cache = ParagraphCache();
        final store = MeasurementStore();
        final ns = MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: _fingerprint(),
        );
        final pump = LayoutPump(
          paragraphCache: cache,
          measurementStore: store,
          namespace: ns,
        );
        addTearDown(() {
          pump.dispose();
          cache.dispose();
        });
        pump.setDemandRange(8, 12);
        final task = _ownedTask(10, ns);
        pump.submit(task);
        pump.setDemandRange(198, 202);
        expect(pump.queueDepth, 0);
        expect(pump.discardedWorkCount, 1);
        expect(await pump.pumpPending(), 0);
        expect(store.get(ns, task.block.key), isNull);
        pump.setDemandRange(8, 12);
        pump.submit(task);
        expect(await pump.pumpPending(), 1);
        expect(store.get(ns, task.block.key), isNotNull);
      },
    );

    test('overlapping demand preserves useful queued work', () async {
      final cache = ParagraphCache();
      final store = MeasurementStore();
      final ns = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: ns,
      );
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });
      pump.setDemandRange(8, 12);
      pump.submit(_ownedTask(12, ns));
      pump.setDemandRange(9, 13);
      expect(await pump.pumpPending(), 1);
      expect(pump.discardedWorkCount, 0);
    });

    test('foreign namespace is rejected at the owning pump', () async {
      final cache = ParagraphCache();
      final store = MeasurementStore();
      final ns = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: ns,
      );
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });
      pump.submit(
        _ownedTask(
          0,
          MeasurementNamespace(
            epoch: LayoutEpoch.initial,
            fingerprint: _fingerprint(lastLineSpacingCompensation: true),
          ),
        ),
      );
      expect(pump.queueDepth, 0);
      expect(await pump.pumpPending(), 0);
    });

    test('demand transfer during dragging does not perform layout', () {
      final cache = ParagraphCache();
      final store = MeasurementStore();
      final ns = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: ns,
      )..onScrollStateChanged(PumpState.dragging);
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });
      pump.submit(_ownedTask(0, ns));
      pump.setDemandRange(10, 12);
      expect(pump.queueDepth, 0);
      expect(pump.discardedWorkCount, 1);
      expect(store.snapshot(ns), isEmpty);
    });

    testWidgets(
      'current demand promotes reusable chapter planning without restart',
      (tester) async {
        final cache = ParagraphCache();
        final store = MeasurementStore();
        final ns = MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: _fingerprint(),
        );
        final pump = LayoutPump(
          paragraphCache: cache,
          measurementStore: store,
          namespace: ns,
          governor: BudgetGovernor(
            ballisticSliceBudget: const Duration(microseconds: 1),
          ),
        )..onScrollStateChanged(PumpState.dragging);
        addTearDown(() {
          pump.dispose();
          cache.dispose();
        });
        pump.setDemandRange(0, 1);

        ChapterBlocks source(int chapter) => ChapterBlocks(
          chapterIndex: chapter,
          title: 'Chapter $chapter',
          displayText: 'abc',
          contentHash: 'source-$chapter',
          blocks: [
            ChapterBlock(
              key: BlockKey(chapterIndex: chapter, blockIndex: 0),
              text: 'abc',
              charRange: const HybridTextRange(0, 3),
              sourceParagraphIndex: 0,
            ),
          ],
        );

        Future<ChapterBlocks?> plan(
          int chapter,
          LayoutTaskPriority priority,
        ) => pump.planChapterVisualLines(
          source(chapter),
          maxBlockChars: 40,
          bodyStyle: const HybridBlockTextStyle(
            fontSize: 18,
            lineHeight: 1.5,
            letterSpacing: 0,
          ),
          titleStyle: const HybridBlockTextStyle(
            fontSize: 22,
            lineHeight: 1.5,
            letterSpacing: 0,
            bold: true,
          ),
          contentWidth: 1000,
          cellWidth: null,
          textIndent: 0,
          priority: priority,
        );

        final firstPrefetch = plan(0, LayoutTaskPriority.prefetch);
        final promoted = plan(1, LayoutTaskPriority.prefetch);
        final samePromoted = plan(1, LayoutTaskPriority.anchor);
        expect(identical(promoted, samePromoted), isTrue);
        expect(pump.queueDepth, 2);

        // A 1us dragging budget admits one ChapterWork step per frame.
        // Manual pumping consumes this frame's credit; the next real frame
        // must continue the promoted work instead of returning to the older
        // prefetch task.
        expect(await pump.pumpPending(), 0);
        await tester.pump(const Duration(milliseconds: 16));
        final promotedBlocks = await promoted;
        expect(promotedBlocks, isNotNull);
        expect(promotedBlocks!.chapterIndex, 1);

        pump.invalidateChapter(0);
        expect(await firstPrefetch, isNull);
      },
    );

    testWidgets('repeated awaits cannot mint a second frame budget', (
      tester,
    ) async {
      final cache = ParagraphCache();
      final store = MeasurementStore();
      final ns = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: ns,
        governor: BudgetGovernor(
          ballisticSliceBudget: const Duration(microseconds: 1),
        ),
      )..onScrollStateChanged(PumpState.dragging);
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });
      pump.submit(_ownedTask(0, ns));
      pump.submit(_ownedTask(1, ns));
      expect(await pump.pumpPending(), 1);
      expect(await pump.pumpPending(), 0);
      expect(await pump.pumpPending(), 0);
      expect(store.snapshot(ns).length, 1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(store.snapshot(ns).length, 2);
    });

    testWidgets(
      'queued visual probes share demand cancellation with drawable work',
      (tester) async {
        final cache = ParagraphCache();
        final store = MeasurementStore();
        final ns = MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: _fingerprint(),
        );
        final pump = LayoutPump(
          paragraphCache: cache,
          measurementStore: store,
          namespace: ns,
        );
        addTearDown(() {
          pump.dispose();
          cache.dispose();
        });
        pump.setDemandRange(0, 2);
        final source = ChapterBlocks(
          chapterIndex: 0,
          title: 'Chapter',
          displayText: 'A long paragraph ' * 100,
          contentHash: 'source',
          blocks: [
            ChapterBlock(
              key: const BlockKey(chapterIndex: 0, blockIndex: 0),
              text: 'A long paragraph ' * 100,
              charRange: HybridTextRange(0, ('A long paragraph ' * 100).length),
              sourceParagraphIndex: 0,
            ),
          ],
        );
        final preparation = pump.planChapterVisualLines(
          source,
          maxBlockChars: 40,
          bodyStyle: const HybridBlockTextStyle(
            fontSize: 18,
            lineHeight: 1.5,
            letterSpacing: 0,
          ),
          titleStyle: const HybridBlockTextStyle(
            fontSize: 22,
            lineHeight: 1.5,
            letterSpacing: 0,
            bold: true,
          ),
          contentWidth: 200,
          cellWidth: null,
          textIndent: 0,
        );
        pump.submit(_ownedTask(1, ns));
        expect(pump.queueDepth, 2);
        pump.setDemandRange(10, 12);
        expect(await preparation, isNull);
        expect(pump.queueDepth, 0);
        expect(pump.discardedWorkCount, 2);
        await tester.pump(const Duration(milliseconds: 16));
        expect(store.snapshot(ns), isEmpty);
      },
    );
  });


  TestWidgetsFlutterBinding.ensureInitialized();
    // 4 個句子（各 14 個 CJK 字 + 句號）+ 1 個含 surrogate pair 的片段
    // （不以句號結尾之外的標點）+ 4 個句子。刻意選一個會讓 Skia 換行落在
    // 「非句界」字元上的內容寬度，確保測試涵蓋句中切、代理對旁切、
    // 跨段落中段等情境，而不是只切在天然斷句處。
    const sentenceBody = '夜讀好書真愉快今晚月色真美麗啊'; // 14 CJK chars
    String _paragraphText() {
      final buffer = StringBuffer();
      for (var i = 0; i < 4; i += 1) {
        buffer.write(sentenceBody);
        buffer.write('。');
      }
      buffer.write('驚喜😀連連。'); // 60..67：含 surrogate pair 的片段
      for (var i = 0; i < 4; i += 1) {
        buffer.write(sentenceBody);
        buffer.write('。');
      }
      return buffer.toString();
    }
  
    final paragraphText = _paragraphText();
  
    const fontSize = 20.0;
    const contentWidth = fontSize * 6.3; // 非整數行寬比例，避免巧合對齊句界
    const trailingSpacing = 3.0;
    const textStyle = HybridBlockTextStyle(
      fontSize: fontSize,
      lineHeight: 1.5,
      letterSpacing: 0,
      textAlign: ui.TextAlign.start,
    );
  
    StyleFingerprint fingerprint() => StyleFingerprint(
      viewportWidth: 320,
      viewportHeight: 640,
      contentWidth: contentWidth,
      contentHeight: 600,
      fontSize: fontSize,
      lineHeight: 1.5,
      letterSpacing: 0,
      paragraphSpacing: 1,
      paddingTop: 8,
      paddingBottom: 8,
      paddingLeft: 16,
      paddingRight: 16,
      textIndent: 0,
      bold: false,
      justify: false,
      textScaleFactor: 1,
      fontFamilySignature: 'system',
      platformFontSignature: 'test',
    );
  
    /// 依 [cutPoints]（段落內部切點，須為合法 UTF-16 邊界）手動切出一組
    /// ChapterBlock；不經 TextPreprocessor，讓測試能精準控制切點落於句中／
    /// 行中／代理對旁，不受 `_splitParagraph` 內部啟發式牽動。
    List<ChapterBlock> manualSplit(List<int> cutPoints) {
      final offsets = <int>[0, ...cutPoints, paragraphText.length];
      return <ChapterBlock>[
        for (var i = 0; i < offsets.length - 1; i += 1)
          ChapterBlock(
            key: BlockKey(chapterIndex: 0, blockIndex: i),
            text: paragraphText.substring(offsets[i], offsets[i + 1]),
            charRange: HybridTextRange(offsets[i], offsets[i + 1]),
            sourceParagraphIndex: 0,
            isContinuation: i > 0,
          ),
      ];
    }
  
    LayoutTask taskFor(List<ChapterBlock> group, StyleFingerprint fp) {
      return LayoutTask(
        block: group.first,
        continuationBlocks: group.skip(1).toList(growable: false),
        epoch: LayoutEpoch.initial,
        fingerprint: fp,
        textStyle: textStyle,
        contentWidth: contentWidth,
        trailingSpacing: trailingSpacing,
      );
    }
  
    double? lineTopForOffset(ui.Paragraph paragraph, int offset, int length) {
      if (length <= 0) return 0.0;
      final safe = offset.clamp(0, length).toInt();
      final start = safe >= length ? length - 1 : safe;
      final boxes = paragraph.getBoxesForRange(start, start + 1);
      if (boxes.isEmpty) return null;
      return boxes.first.top;
    }
  
    /// 黑箱重現 HybridReaderScreen._visualPositionForChar 的世界座標換算：
    /// 只用 ParagraphCache／MeasurementStore 的公開介面，找出 [chapterOffset]
    /// 視覺上真正落在 group 哪個 block 的 Y 窗、以及該窗內的 local top，
    /// 再累加前面 block 的高度得到世界座標。
    double worldYForOffset({
      required List<ChapterBlock> group,
      required ParagraphCache cache,
      required MeasurementStore store,
      required MeasurementNamespace namespace,
      required int chapterOffset,
    }) {
      final head = group.first;
      final headEntry = cache.acquireEntry(head.key, LayoutEpoch.initial)!;
      final paragraph = headEntry.paragraph;
      final totalLength = group.fold<int>(0, (sum, b) => sum + b.text.length);
      final localOffset = chapterOffset - head.charRange.start;
      final paragraphY =
          lineTopForOffset(paragraph, localOffset, totalLength) ?? 0.0;
  
      var owningIndex = 0;
      var owningLocalTop = headEntry.localTop;
      for (var i = 0; i < group.length; i += 1) {
        final entry = cache.acquireEntry(group[i].key, LayoutEpoch.initial)!;
        if (entry.localTop <= paragraphY + 0.001) {
          owningIndex = i;
          owningLocalTop = entry.localTop;
        } else {
          break;
        }
      }
      var worldTop = 0.0;
      for (var i = 0; i < owningIndex; i += 1) {
        worldTop += store.get(namespace, group[i].key)!.height;
      }
      return worldTop + (paragraphY - owningLocalTop);
    }
  
    ({
      ui.Paragraph paragraph,
      ParagraphCache cache,
      MeasurementStore store,
      MeasurementNamespace namespace,
    })
    runSegmentation(List<ChapterBlock> group) {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final fp = fingerprint();
      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: fp,
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
      );
      pump.submit(taskFor(group, fp));
      // 整個 group 必須在同一次 pumpPending 完成（連續排版是一次 layout()）。
      expect(pump.pumpPending(), completion(1));
      final paragraph = cache.acquireEntry(group.first.key, LayoutEpoch.initial)!
          .paragraph;
      pump.dispose();
      return (
        paragraph: paragraph,
        cache: cache,
        store: store,
        namespace: namespace,
      );
    }
  
    test('段落文字 fixture 涵蓋句中切、行中切與 surrogate pair 邊界', () {
      // 66/67 是 😀 的高/低代理；68 緊接在代理對之後，是合法但非句界的切點。
      expect(
        paragraphText.codeUnitAt(66),
        inInclusiveRange(0xD800, 0xDBFF),
        reason: 'fixture 需要在 66 起有一個 surrogate pair',
      );
      expect(paragraphText.codeUnitAt(67), inInclusiveRange(0xDC00, 0xDFFF));
      expect(paragraphText[68 - 1], isNot('。'));
    });
  
    group('連續段落排版：block 切法不得產生額外硬換行', () {
      late ui.Paragraph reference;
      late List<double> referenceLineTops;
  
      setUpAll(() {
        final result = runSegmentation(manualSplit(const <int>[]));
        reference = result.paragraph;
        referenceLineTops = [
          for (final line in reference.computeLineMetrics())
            line.baseline - line.ascent,
        ];
      });
  
      test('測試內容寬度確實讓至少一個切點落在行中（非行首）', () {
        // 取這條測試會用到的其中一個切點（68，緊接 surrogate pair 之後）
        // 驗證它落在某一行的內部，而不是巧合對在行首——否則後面的比較就
        // 測不到「行中切」這個情境。
        var offset = 0;
        var foundMidLine = false;
        for (var i = 0; i < referenceLineTops.length; i += 1) {
          final line = reference.getLineBoundary(
            ui.TextPosition(offset: offset),
          );
          if (68 > line.start && 68 < line.end) foundMidLine = true;
          offset = line.end;
          if (offset >= paragraphText.length) break;
        }
        expect(
          foundMidLine,
          isTrue,
          reason: '切點 68 應落在某一行中間，才能驗證人工邊界不產生硬換行',
        );
      });
  
      final segmentations = <String, List<int>>{
        '句界對齊切法（4 塊）': const <int>[32, 71, 103],
        '句中＋代理對旁混合切法（3 塊）': const <int>[55, 68],
        '細切法（6 塊，含多個非句界切點）': const <int>[20, 42, 68, 95, 115],
      };
  
      for (final entry in segmentations.entries) {
        test('${entry.key}：斷行、總高度與逐行 UTF-16 range 與連續排版完全一致', () {
          final group = manualSplit(entry.value);
          final result = runSegmentation(group);
  
          // 斷行數與逐行 UTF-16 range 必須逐一相同：human-invisible 的
          // block 邊界不能讓 Skia 多斷或少斷一行。
          expect(
            result.paragraph.numberOfLines,
            reference.numberOfLines,
            reason: '${entry.key}：line count 必須與連續排版一致',
          );
          var refOffset = 0;
          var segOffset = 0;
          for (var i = 0; i < reference.numberOfLines; i += 1) {
            final refLine = reference.getLineBoundary(
              ui.TextPosition(offset: refOffset),
            );
            final segLine = result.paragraph.getLineBoundary(
              ui.TextPosition(offset: segOffset),
            );
            expect(
              segLine.start,
              refLine.start,
              reason: '${entry.key}：第 $i 行起點必須相同',
            );
            expect(
              segLine.end,
              refLine.end,
              reason: '${entry.key}：第 $i 行終點必須相同',
            );
            refOffset = refLine.end;
            segOffset = segLine.end;
          }
  
          // 總高度：group 內每塊 BlockMetrics.height 加總，必須等於連續排版
          // 的 paragraph.height + trailingSpacing（人工邊界不得新增／遺漏
          // 高度；只有 group 真正最後一塊計入 trailingSpacing）。
          var totalHeight = 0.0;
          var totalLineCount = 0;
          for (var i = 0; i < group.length; i += 1) {
            final metrics = result.store.get(result.namespace, group[i].key)!;
            totalHeight += metrics.height;
            totalLineCount += metrics.lineCount;
            if (i < group.length - 1) {
              // 效能切點之間恆為 0 間距——不是語意段落邊界。
              expect(
                result.store.get(result.namespace, group[i + 1].key) != null,
                isTrue,
              );
            }
          }
          expect(
            totalHeight,
            closeTo(reference.height + trailingSpacing, 0.01),
            reason: '${entry.key}：總高度必須等於連續排版 + trailingSpacing',
          );
          expect(
            totalLineCount,
            reference.numberOfLines,
            reason: '${entry.key}：各切塊 lineCount 加總必須等於連續排版行數',
          );
  
          // charOffset → 世界座標：涵蓋段落中段、每個人工切點前後、句中切點
          // 與 surrogate pair 緊鄰處，逐一與連續排版比較。
          // 排除落在 low surrogate 上的探測點——查詢單一 code unit 的
          // getBoxesForRange 在那裡沒有意義（不是合法的字元起點）。
          bool isLowSurrogateStart(int offset) {
            if (offset < 0 || offset >= paragraphText.length) return false;
            final unit = paragraphText.codeUnitAt(offset);
            return unit >= 0xDC00 && unit <= 0xDFFF;
          }
  
          final probeOffsets = <int>{
            10,
            65,
            68,
            75,
            paragraphText.length - 5,
            for (final cut in entry.value) ...[
              (cut - 1).clamp(0, paragraphText.length - 1),
              cut.clamp(0, paragraphText.length - 1),
            ],
          }..removeWhere(isLowSurrogateStart);
          for (final offset in probeOffsets) {
            final refY = lineTopForOffset(reference, offset, paragraphText.length)!;
            final segY = worldYForOffset(
              group: group,
              cache: result.cache,
              store: result.store,
              namespace: result.namespace,
              chapterOffset: offset,
            );
            expect(
              segY,
              closeTo(refY, 0.01),
              reason: '${entry.key}：charOffset=$offset 的世界 Y 必須與連續排版一致',
            );
          }
  
          result.cache.dispose();
        });
      }
  
      test(
        '同一行落兩個切點：中間切塊 own height 合法為 0，不得頂到整像素造成總高度偏移',
        () {
          // 找一條至少有 3 個字元、且不是最後一行的行，把兩個切點都放進同一
          // 行——這是唯一會讓中間切塊的「own height」真正為 0 的情境（見
          // layout_pump.dart _groupSplitYs／_metricsFromSplitYs：兩個切點的
          // line-top 相同時，中間切塊的視窗寬度就是 0）。
          ui.TextRange? targetLine;
          var offset = 0;
          while (offset < paragraphText.length) {
            final boundary = reference.getLineBoundary(
              ui.TextPosition(offset: offset),
            );
            if (boundary.end - boundary.start >= 3 &&
                boundary.end < paragraphText.length) {
              targetLine = boundary;
              break;
            }
            offset = boundary.end;
          }
          expect(
            targetLine,
            isNotNull,
            reason: 'fixture 需要至少一行有 3+ 字元且非最後一行',
          );
          final line = targetLine!;
          final cut1 = line.start + 1;
          final cut2 = line.start + 2;
  
          final group = manualSplit(<int>[cut1, cut2]);
          final result = runSegmentation(group);
  
          // 中間切塊（block 1）own height 必須合法為極小正值（BlockMetrics
          // 要求 height > 0），不得像過去的 bug 那樣被頂成一整個 pixel。
          final midMetrics = result.store.get(result.namespace, group[1].key)!;
          expect(midMetrics.height, greaterThan(0));
          expect(
            midMetrics.height,
            lessThan(0.01),
            reason: '同一行多切點的中間切塊視覺上不佔任何高度，不得累積人工像素',
          );
          expect(midMetrics.lineCount, 0);
  
          // 總高度仍必須等於連續排版 + trailingSpacing——不因中間切塊的極小
          // floor 值而系統性偏移；容差遠低於既有測試的 0.01，確保沒有整像素
          // 被誤加進去。
          var totalHeight = 0.0;
          for (final block in group) {
            totalHeight += result.store.get(result.namespace, block.key)!.height;
          }
          expect(
            totalHeight,
            closeTo(reference.height + trailingSpacing, 0.001),
          );
  
          // 切點之後的世界座標仍須與連續排版一致，不因中間切塊的極小 floor
          // 累積偏移量。
          final probeOffset = (line.end + 2).clamp(0, paragraphText.length - 1);
          final refY = lineTopForOffset(reference, probeOffset, paragraphText.length)!;
          final segY = worldYForOffset(
            group: group,
            cache: result.cache,
            store: result.store,
            namespace: result.namespace,
            chapterOffset: probeOffset,
          );
          expect(segY, closeTo(refY, 0.01));
  
          result.cache.dispose();
        },
      );
    });


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
            ..offer(_ready(0, 0));
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
          ..offer(_ready(0, 1));
        addTearDown(admission.dispose);
  
        admission.offer(_ready(0, 0));
  
        expect(index.admittedCount, 2);
        expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 1)), 0);
        expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 0)), -100);
      });
  
      test(
        'a ready contiguous edge is usable even inside the visible viewport',
        () {
          final index = DocumentIndex(
            centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
          );
          final admission = AdmissionController(documentIndex: index)
            ..reset(epoch: LayoutEpoch.initial, chapterCount: 1)
            ..registerChapter(_chapterBlocks(0, 2))
            ..offer(_ready(0, 0));
          addTearDown(admission.dispose);
  
          admission.offer(_ready(0, 1));
          expect(index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 0)), 0);
          expect(
            index.topOf(const BlockKey(chapterIndex: 0, blockIndex: 1)),
            100,
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
  
  
    test('DocumentIndex 隨機交錯放行下與樸素模型全等', () {
        final random = Random(20260710);
        for (var round = 0; round < 30; round += 1) {
          final chapterCount = 1 + random.nextInt(6);
          final blocksPerChapter = List<int>.generate(
            chapterCount,
            (_) => 1 + random.nextInt(9),
          );
          final allKeys = <BlockKey>[
            for (var c = 0; c < chapterCount; c += 1)
              for (var b = 0; b < blocksPerChapter[c]; b += 1)
                BlockKey(chapterIndex: c, blockIndex: b),
          ];
          final heights = <BlockKey, double>{
            for (final key in allKeys) key: 5.0 + random.nextDouble() * 200.0,
          };
          final centerPos = random.nextInt(allKeys.length);
          final center = allKeys[centerPos];
          final index = DocumentIndex(centerKey: center);
    
          // 由 center 向兩側隨機交錯放行（模擬 admission 的實際順序）。
          var forward = centerPos;
          var backward = centerPos - 1;
          final admitted = <BlockKey>[];
          while (forward < allKeys.length || backward >= 0) {
            final goForward =
                backward < 0 ||
                (forward < allKeys.length && random.nextBool());
            if (goForward) {
              index.admit(
                allKeys[forward],
                BlockMetrics(height: heights[allKeys[forward]]!, lineCount: 1),
              );
              admitted.add(allKeys[forward]);
              forward += 1;
            } else {
              index.admit(
                allKeys[backward],
                BlockMetrics(height: heights[allKeys[backward]]!, lineCount: 1),
              );
              admitted.add(allKeys[backward]);
              backward -= 1;
            }
    
            // 每次放行後即時對照——增量結構任何一步走樣都會在此暴露。
            final sorted = admitted.toList()..sort();
            // 樸素座標：center 的 top 恆為 0，向兩側累加高度。
            // center 可能尚未放行（backward 先行），以「小於 center 的鍵數」定位。
            final tops = <BlockKey, double>{};
            final centerSortedPos = sorted.where((k) => k < center).length;
            var cursor = 0.0;
            for (var i = centerSortedPos; i < sorted.length; i += 1) {
              tops[sorted[i]] = cursor;
              cursor += heights[sorted[i]]!;
            }
            final afterTotal = cursor;
            cursor = 0.0;
            for (var i = centerSortedPos - 1; i >= 0; i -= 1) {
              cursor -= heights[sorted[i]]!;
              tops[sorted[i]] = cursor;
            }
            final beforeTotal = -cursor;
    
            expect(index.keys.toList(), sorted);
            expect(index.beforeExtent, closeTo(beforeTotal, 1e-6));
            expect(index.afterExtent, closeTo(afterTotal, 1e-6));
            expect(index.backwardEdgeKey, centerSortedPos == 0 ? null : sorted.first);
            expect(
              index.forwardEdgeKey,
              centerSortedPos == sorted.length ? null : sorted.last,
            );
            for (final key in sorted) {
              expect(index.topOf(key), closeTo(tops[key]!, 1e-6), reason: '$key');
              expect(
                index.bottomOf(key),
                closeTo(tops[key]! + heights[key]!, 1e-6),
              );
            }
    
            // blockAtOffset：對每個 block 的內部點與邊界點抽查。
            for (var probe = 0; probe < 8; probe += 1) {
              final offset =
                  -beforeTotal - 10 +
                  random.nextDouble() * (beforeTotal + afterTotal + 20);
              BlockKey? expected;
              for (final key in sorted) {
                final top = tops[key]!;
                if (offset >= top && offset < top + heights[key]!) {
                  expected = key;
                  break;
                }
              }
              expect(
                index.blockAtOffset(offset),
                expected,
                reason: 'offset=$offset round=$round n=${sorted.length}',
              );
            }
    
            // keysInRange 對照。
            for (var probe = 0; probe < 4; probe += 1) {
              final a =
                  -beforeTotal - 20 +
                  random.nextDouble() * (beforeTotal + afterTotal + 40);
              final b = a + random.nextDouble() * 300;
              final expected = sorted.where((key) {
                final top = tops[key]!;
                return top + heights[key]! > a && top < b;
              }).toList();
              expect(index.keysInRange(a, b), expected, reason: '[$a, $b)');
            }
          }
    
          // sliver 幾何查詢：對照框架 RenderSliverFixedExtentBoxAdaptor 在
          // itemExtentBuilder 模式下的線性演算法（RenderHybridBlockSliver 以
          // Fenwick 取代之，語意必須逐點一致）。Fenwick 與逐項累加的浮點求和
          // 順序不同（誤差 ~1e-13），index 探測避開精確邊界（±1e-6 nudge，
          // 高度 ≥5.0 不會因此跨界），offset 比較用 closeTo。
          {
            final sorted = admitted.toList()..sort();
            final centerSortedPos = sorted.where((k) => k < center).length;
            final beforeList =
                sorted.sublist(0, centerSortedPos).reversed.toList(growable: false);
            final afterList = sorted.sublist(centerSortedPos);
            for (final (beforeCenter, list) in <(bool, List<BlockKey>)>[
              (true, beforeList),
              (false, afterList),
            ]) {
              double naiveOffset(int count) {
                var sum = 0.0;
                for (var i = 0; i < count && i < list.length; i += 1) {
                  sum += heights[list[i]]!;
                }
                return sum;
              }
    
              // 框架 _getChildIndexForScrollOffset 的忠實複刻。
              int naiveIndex(double scrollOffset) {
                if (scrollOffset == 0.0) return 0;
                var position = 0.0;
                var i = 0;
                while (position < scrollOffset) {
                  if (i > list.length - 1) break;
                  position += heights[list[i]]!;
                  i += 1;
                }
                return i - 1;
              }
    
              final side = beforeCenter ? 'before' : 'after';
              final total = naiveOffset(list.length);
              expect(
                index.sliverScrollExtent(beforeCenter: beforeCenter),
                closeTo(total, 1e-6),
                reason: '$side extent',
              );
              for (var i = 0; i <= list.length + 2; i += 1) {
                expect(
                  index.sliverLayoutOffset(beforeCenter: beforeCenter, index: i),
                  closeTo(naiveOffset(i), 1e-6),
                  reason: '$side layoutOffset($i)',
                );
              }
              final probes = <double>[
                0.0,
                total + 25.0,
                for (var i = 0; i < list.length; i += 1) ...<double>[
                  // 框架不會傳負 scrollOffset，邊界前緣只在 i>0 時探測。
                  if (i > 0) naiveOffset(i) - 1e-6, // 邊界前緣（屬前一子項）
                  naiveOffset(i) + 1e-6, // 邊界後緣（屬本子項）
                  naiveOffset(i) + heights[list[i]]! * 0.5, // 內部點
                ],
              ];
              for (final offset in probes) {
                expect(
                  index.sliverIndexForScrollOffset(
                    beforeCenter: beforeCenter,
                    scrollOffset: offset,
                  ),
                  naiveIndex(offset),
                  reason: '$side indexFor($offset) n=${list.length}',
                );
              }
            }
          }
    
          // 全部放行後的章節範圍對照。
          for (var c = 0; c < chapterCount; c += 1) {
            final chapterKeys =
                allKeys.where((key) => key.chapterIndex == c).toList();
            final sorted = admitted.toList()..sort();
            final tops = <BlockKey, double>{};
            final centerSortedPos = sorted.where((k) => k < center).length;
            var cursor = 0.0;
            for (var i = centerSortedPos; i < sorted.length; i += 1) {
              tops[sorted[i]] = cursor;
              cursor += heights[sorted[i]]!;
            }
            cursor = 0.0;
            for (var i = centerSortedPos - 1; i >= 0; i -= 1) {
              cursor -= heights[sorted[i]]!;
              tops[sorted[i]] = cursor;
            }
            final expectedTop = tops[chapterKeys.first]!;
            final expectedBottom =
                tops[chapterKeys.last]! + heights[chapterKeys.last]!;
            final range = index.chapterRange(c)!;
            expect(range.top, closeTo(expectedTop, 1e-6), reason: 'chapter $c');
            expect(range.bottom, closeTo(expectedBottom, 1e-6));
            expect(
              index.chapterExtent(c),
              closeTo(expectedBottom - expectedTop, 1e-6),
            );
          }
        }
      });
}

ui.Paragraph _paragraph(String text) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
  )..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 100));
}

StyleFingerprint _fingerprint({
  double width = 320,
  bool lastLineSpacingCompensation = false,
}) {
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
    lastLineSpacingCompensation: lastLineSpacingCompensation,
  );
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

LayoutTask _ownedTask(int chapter, MeasurementNamespace ns) {
  const text = 'A measured paragraph.';
  return LayoutTask(
    block: ChapterBlock(
      key: BlockKey(chapterIndex: chapter, blockIndex: 0),
      text: text,
      charRange: const HybridTextRange(0, text.length),
      sourceParagraphIndex: 0,
    ),
    epoch: ns.epoch,
    fingerprint: ns.fingerprint,
    textStyle: const HybridBlockTextStyle(
      fontSize: 18,
      lineHeight: 1.5,
      letterSpacing: 0,
    ),
    contentWidth: 288,
  );
}
