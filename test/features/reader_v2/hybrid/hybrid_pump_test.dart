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
  });
}

ui.Paragraph _paragraph(String text) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
  )..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 100));
}

StyleFingerprint _fingerprint() {
  return const StyleFingerprint(
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
  );
}
