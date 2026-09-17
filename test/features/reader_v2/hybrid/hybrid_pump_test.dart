import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_cost_model.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParagraphCache', () {
    test('keeps laid-out paragraphs available for the layout epoch', () {
      final cache = ParagraphCache();
      const epoch = LayoutEpoch.initial;
      const key0 = BlockKey(chapterIndex: 0, blockIndex: 0);
      const key1 = BlockKey(chapterIndex: 0, blockIndex: 1);
      const key2 = BlockKey(chapterIndex: 0, blockIndex: 2);

      cache
        ..put(key0, epoch, _paragraph('a'))
        ..put(key1, epoch, _paragraph('b'))
        ..put(key2, epoch, _paragraph('c'));

      expect(cache.contains(key0, epoch), isTrue);
      expect(cache.contains(key1, epoch), isTrue);
      expect(cache.contains(key2, epoch), isTrue);
      cache.dispose();
    });

    test('semantic invalidation removes only the invalidated chapter', () {
      final cache = ParagraphCache();
      const epoch = LayoutEpoch.initial;
      const chapter0 = BlockKey(chapterIndex: 0, blockIndex: 0);
      const chapter1 = BlockKey(chapterIndex: 1, blockIndex: 0);

      cache
        ..put(chapter0, epoch, _paragraph('a'))
        ..put(chapter1, epoch, _paragraph('b'))
        ..invalidateChapter(0);

      expect(cache.contains(chapter0, epoch), isFalse);
      expect(cache.contains(chapter1, epoch), isTrue);
      cache.dispose();
    });

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
    test('pending group identity is deduplicated but a completed group can repaint', () async {
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
      expect(await pump.pumpPending(), 1);
      expect(cache.containsFresh(key, namespace.epoch, black), true);
      pump.submit(task(green));
      pump.invalidateChapter(0);
      expect(pump.queueDepth, 0);
    });

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

    test('continues laying out while dragging', () async {
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
      )..onScrollStateChanged(PumpState.dragging);
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      pump.submit(
        LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: 'drag layout',
            charRange: HybridTextRange(0, 11),
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
        ),
      );

      expect(await pump.pumpPending(), 1);
      expect(store.get(namespace, key), isNotNull);
      expect(cache.contains(key, namespace.epoch), isTrue);
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
      LayoutPumpTaskStats? taskStats;
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
        onTaskCompleted: (stats) => taskStats = stats,
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
      expect(taskStats, isNotNull);
      expect(taskStats!.charCount, greaterThan(0));
      expect(taskStats!.groupBlockCount, 1);
      expect(taskStats!.predicted, greaterThan(Duration.zero));
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

  group('LayoutPump 需求失效', () {
    LayoutTask task(int chapterIndex, StyleFingerprint fingerprint) {
      return LayoutTask(
        block: ChapterBlock(
          key: BlockKey(chapterIndex: chapterIndex, blockIndex: 0),
          text: '這是一段測試文字。',
          charRange: const HybridTextRange(0, 9),
          sourceParagraphIndex: 0,
        ),
        continuationBlocks: <ChapterBlock>[
          ChapterBlock(
            key: BlockKey(chapterIndex: chapterIndex, blockIndex: 1),
            text: '這是續塊。',
            charRange: const HybridTextRange(9, 14),
            sourceParagraphIndex: 0,
          ),
        ],
        epoch: LayoutEpoch.initial,
        fingerprint: fingerprint,
        textStyle: const HybridBlockTextStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          textAlign: ui.TextAlign.start,
        ),
        contentWidth: 240,
      );
    }

    test('中心移開後，舊中心的 task 在排版前被丟棄', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      // 模擬 HybridReaderScreen 的需求視窗：半徑 2，中心可移動。
      var center = 10;
      final discarded = <BlockKey>[];
      final completedKeys = <BlockKey>[];
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
        isTaskStillDesired: (task) =>
            (task.block.key.chapterIndex - center).abs() <= 2,
        onTaskDiscarded: (task) => discarded.addAll(<BlockKey>[
          for (final block in task.groupBlocks) block.key,
        ]),
      );
      final sub = pump.completed.listen(
        (event) => completedKeys.add(event.key),
      );
      addTearDown(() async {
        await sub.cancel();
        pump.dispose();
        cache.dispose();
      });

      pump
        ..submit(task(10, namespace.fingerprint))
        ..submit(task(11, namespace.fingerprint));
      expect(pump.queueDepth, 2);

      // 跳章：新中心 200。兩個 task 都已不在需求視窗內。
      center = 200;

      expect(await pump.pumpPending(), 0, reason: '已失效的 task 不得被排版');
      expect(pump.queueDepth, 0, reason: 'queueDepth 必須反映當前需求');
      expect(completedKeys, isEmpty);
      expect(
        store.get(namespace, const BlockKey(chapterIndex: 10, blockIndex: 0)),
        isNull,
      );
      expect(
        cache.contains(
          const BlockKey(chapterIndex: 10, blockIndex: 0),
          LayoutEpoch.initial,
        ),
        isFalse,
      );
      // 丟棄必須回報整個 group，呼叫端才能完整撤銷「已投放」記錄。
      expect(discarded, <BlockKey>[
        const BlockKey(chapterIndex: 10, blockIndex: 0),
        const BlockKey(chapterIndex: 10, blockIndex: 1),
        const BlockKey(chapterIndex: 11, blockIndex: 0),
        const BlockKey(chapterIndex: 11, blockIndex: 1),
      ]);
    });

    test('仍在需求視窗內的 task 不受影響', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      var center = 10;
      final discarded = <BlockKey>[];
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
        isTaskStillDesired: (task) =>
            (task.block.key.chapterIndex - center).abs() <= 2,
        onTaskDiscarded: (task) => discarded.addAll(<BlockKey>[
          for (final block in task.groupBlocks) block.key,
        ]),
      );
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });

      // 中心從 10 走到 11：chapter 12 由 delta +2 變成 +1，仍在視窗內；
      // 投放端與 drain 端用同一個半徑，不得來回震盪。
      pump.submit(task(12, namespace.fingerprint));
      center = 11;

      expect(await pump.pumpPending(), 1);
      expect(discarded, isEmpty);
      expect(
        store.get(namespace, const BlockKey(chapterIndex: 12, blockIndex: 0)),
        isNotNull,
      );
    });

    test('fingerprint 改變的 task 同樣失效', () async {
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
        isTaskStillDesired: (task) =>
            task.fingerprint == namespace.fingerprint &&
            task.block.key.chapterIndex == 0,
      );
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });

      pump.submit(task(0, _fingerprint(lastLineSpacingCompensation: true)));
      expect(await pump.pumpPending(), 0);
      expect(pump.queueDepth, 0);
    });

    test('purgeUndesiredTasks 在 dragging 期間可安全呼叫（I4）', () {
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
        isTaskStillDesired: (task) => false,
      )..onScrollStateChanged(PumpState.dragging);
      addTearDown(() {
        pump.dispose();
        cache.dispose();
      });

      pump.submit(task(0, namespace.fingerprint));
      // 純記帳，不做排版，因此不觸發 I4 assert。
      expect(pump.purgeUndesiredTasks(), 1);
      expect(pump.queueDepth, 0);
    });
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
