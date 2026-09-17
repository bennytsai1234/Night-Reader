import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/metrics_disk_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

void main() {
  final fingerprint = StyleFingerprint(
    viewportWidth: 240,
    viewportHeight: 320,
    contentWidth: 216,
    contentHeight: 296,
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 0.8,
    paddingTop: 12,
    paddingBottom: 12,
    paddingLeft: 12,
    paddingRight: 12,
    textIndent: 0,
    bold: false,
    justify: true,
    textScaleFactor: 1,
    fontFamilySignature: 'system',
    platformFontSignature: 'test',
  );
  const key = BlockKey(chapterIndex: 0, blockIndex: 0);
  final oldNamespace = MeasurementNamespace(
    epoch: LayoutEpoch(7),
    fingerprint: fingerprint,
  );
  final newNamespace = MeasurementNamespace(
    epoch: LayoutEpoch(8),
    fingerprint: fingerprint,
  );

  test('MeasurementStore namespace freshness rejects the old epoch', () {
    final store = MeasurementStore();
    store.put(oldNamespace, key, const BlockMetrics(height: 10, lineCount: 1));

    expect(store.get(oldNamespace, key), isNotNull);
    expect(store.get(newNamespace, key), isNull);

    store.put(newNamespace, key, const BlockMetrics(height: 12, lineCount: 1));
    expect(store.get(newNamespace, key)?.height, 12);
    store.invalidateNamespace(oldNamespace);
    expect(store.get(oldNamespace, key), isNull);
  });

  test('ParagraphCache namespace freshness does not reuse old Paragraph', () {
    final cache = ParagraphCache();
    final oldParagraph = _paragraph('騄');
    final newParagraph = _paragraph('𫘧');
    addTearDown(() {
      cache.dispose();
    });

    cache.put(key, oldNamespace.epoch, oldParagraph);
    expect(cache.acquire(key, newNamespace.epoch), isNull);

    cache.put(key, newNamespace.epoch, newParagraph);
    expect(cache.acquire(key, newNamespace.epoch), same(newParagraph));
    expect(cache.acquire(key, oldNamespace.epoch), same(oldParagraph));
  });

  test(
    'MetricsDiskCache content hash freshness rejects the old hash',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'night_reader_conversion_metrics_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final cache = MetricsDiskCache(baseDirectory: temp);
      final metrics = <BlockKey, BlockMetrics>{
        key: const BlockMetrics(height: 42, lineCount: 3),
      };

      expect(
        await cache.write(
          bookUrl: 'book://conversion',
          fingerprint: fingerprint,
          metrics: metrics,
          chapterLayoutIdentities: const <int, String>{
            0: 'content-hash-before',
          },
        ),
        1,
      );
      expect(
        await cache.read(
          bookUrl: 'book://conversion',
          fingerprint: fingerprint,
          chapterLayoutIdentities: const <int, String>{
            0: 'content-hash-before',
          },
        ),
        metrics,
      );
      expect(
        await cache.read(
          bookUrl: 'book://conversion',
          fingerprint: fingerprint,
          chapterLayoutIdentities: const <int, String>{0: 'content-hash-after'},
        ),
        isEmpty,
      );
    },
  );
}

ui.Paragraph _paragraph(String text) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle())..addText(text);
  final paragraph = builder.build();
  paragraph.layout(const ui.ParagraphConstraints(width: 240));
  return paragraph;
}
