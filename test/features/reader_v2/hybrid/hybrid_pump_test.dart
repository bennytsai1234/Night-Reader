import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParagraphCache', () {
    test('keeps pinned paragraphs past capacity until unpinned', () {
      final cache = ParagraphCache(capacity: 1);
      const epoch = LayoutEpoch.initial;
      const key0 = BlockKey(chapterIndex: 0, blockIndex: 0);
      const key1 = BlockKey(chapterIndex: 0, blockIndex: 1);
      const key2 = BlockKey(chapterIndex: 0, blockIndex: 2);

      cache
        ..put(key0, epoch, _paragraph('a'))
        ..pinRange(const BlockRange(first: key0, last: key0))
        ..put(key1, epoch, _paragraph('b'));

      expect(cache.contains(key0, epoch), isTrue);
      expect(cache.contains(key1, epoch), isFalse);

      cache
        ..unpinAll()
        ..put(key2, epoch, _paragraph('c'));

      expect(cache.contains(key0, epoch), isFalse);
      cache.dispose();
    });

    test('put 一次性消費 put-waiter，remove 後不再回呼', () {
      final cache = ParagraphCache();
      const epoch = LayoutEpoch.initial;
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      var calls = 0;
      void waiter() => calls += 1;

      cache
        ..addPutWaiter(key, epoch, waiter)
        ..put(key, epoch, _paragraph('a'));
      expect(calls, 1);

      // 一次性：put 已消費註冊，再 put 不重複回呼。
      cache.put(key, epoch, _paragraph('b'));
      expect(calls, 1);

      // remove 後 put 不回呼。
      cache
        ..addPutWaiter(key, epoch, waiter)
        ..removePutWaiter(key, epoch, waiter)
        ..put(key, epoch, _paragraph('c'));
      expect(calls, 1);
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
    test('asserts instead of laying out while dragging', () async {
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

      expect(pump.pumpPending, throwsA(isA<AssertionError>()));
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
      final baselineParagraph =
          baselineCache.acquire(key, LayoutEpoch.initial)!;
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
