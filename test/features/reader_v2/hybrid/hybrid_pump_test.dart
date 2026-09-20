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

    test(
      'B2 intermediate paragraph is disposed after the replacement pass',
      () async {
        var disposedIntermediateParagraphs = 0;
        final previousObserver =
            LayoutPump.debugOnIntermediateParagraphDisposed;
        LayoutPump.debugOnIntermediateParagraphDisposed = () {
          disposedIntermediateParagraphs += 1;
        };
        addTearDown(() {
          LayoutPump.debugOnIntermediateParagraphDisposed = previousObserver;
        });

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
        addTearDown(() {
          pump.dispose();
          cache.dispose();
        });

        const key = BlockKey(chapterIndex: 0, blockIndex: 0);
        pump.submit(
          LayoutTask(
            block: const ChapterBlock(
              key: key,
              text: '衝在最前面的妖怪頭顱便滾落在地面上。',
              charRange: HybridTextRange(0, 18),
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
            contentWidth: 20 * 16.4,
            indentChars: 2,
          ),
        );

        expect(await pump.pumpPending(), 1);
        expect(disposedIntermediateParagraphs, 1);
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

        // A 1us dragging budget admits one ChapterWork step per manual slice.
        // The promoted chapter must receive both slices and complete before
        // the older prefetch task gets a turn.
        expect(await pump.pumpPending(), 0);
        expect(await pump.pumpPending(), 1);
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
}

ui.Paragraph _paragraph(String text) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
  )..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 100));
}

StyleFingerprint _fingerprint({bool lastLineSpacingCompensation = false}) {
  return StyleFingerprint(
    viewportWidth: 320,
    viewportHeight: 640,
    contentWidth: 288,
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
