import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/storage/reader_layout_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/chapter_plan_disk_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/metrics_disk_cache.dart';

StyleFingerprint _style(double fontSize) => StyleFingerprint(
  contentWidth: 288,
  fontSize: fontSize,
  lineHeight: 1.5,
  letterSpacing: 0,
  paragraphSpacing: 1,
  textIndent: 2,
  bold: false,
  textScaleFactor: 1,
  fontFamilySignature: 'system',
  platformFontSignature: 'test',
);

final _text = ChapterText(
  id: 0,
  title: '第一章',
  paragraphs: const ['正文'],
  displayText: '第一章\n\n正文',
  contentHash: 'content-0',
);

final _blocks = ChapterBlocks(
  chapterIndex: 0,
  title: _text.title,
  displayText: _text.displayText,
  contentHash: _text.contentHash,
  blocks: const [
    ChapterBlock(
      key: BlockKey(chapterIndex: 0, blockIndex: 0),
      text: '第一章',
      charRange: HybridTextRange(0, 3),
      sourceParagraphIndex: -1,
      isTitle: true,
    ),
    ChapterBlock(
      key: BlockKey(chapterIndex: 0, blockIndex: 1),
      text: '正文',
      charRange: HybridTextRange(5, 7),
      sourceParagraphIndex: 0,
    ),
  ],
);

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('reader_layout_cache_');
  });

  tearDown(() => base.delete(recursive: true));

  Future<void> writeBoth(
    String bookUrl,
    StyleFingerprint style,
    String build,
  ) => Future.wait([
    MetricsDiskCache(baseDirectory: base).write(
      bookUrl: bookUrl,
      fingerprint: style,
      metrics: {
        const BlockKey(chapterIndex: 0, blockIndex: 0): BlockMetrics(
          height: 30,
          lineCount: 1,
        ),
      },
    ),
    ChapterPlanDiskCache(
      baseDirectory: base,
      buildSignature: build,
    ).write(bookUrl: bookUrl, fingerprint: style, blocks: _blocks),
  ]);

  Future<bool> hasPlan(
    String bookUrl,
    StyleFingerprint style,
    String build,
  ) async =>
      await ChapterPlanDiskCache(
        baseDirectory: base,
        buildSignature: build,
      ).read(bookUrl: bookUrl, fingerprint: style, text: _text) !=
      null;

  Future<bool> hasMetrics(String bookUrl, StyleFingerprint style) async =>
      (await MetricsDiskCache(
        baseDirectory: base,
      ).read(bookUrl: bookUrl, fingerprint: style)).isNotEmpty;

  test('deleting a book removes its layout caches only', () async {
    await writeBoth('book://a', _style(18), '1.0.0+1');
    await writeBoth('book://b', _style(18), '1.0.0+1');

    await ReaderLayoutCache.deleteBook('book://a', base: base);

    expect(await hasMetrics('book://a', _style(18)), isFalse);
    expect(await hasPlan('book://a', _style(18), '1.0.0+1'), isFalse);
    expect(await hasMetrics('book://b', _style(18)), isTrue);
    expect(await hasPlan('book://b', _style(18), '1.0.0+1'), isTrue);
  });

  test(
    'the startup sweep keeps only known books and the current build',
    () async {
      await writeBoth('book://kept', _style(18), '1.0.0+1');
      await writeBoth('book://gone', _style(18), '1.0.0+1');
      await writeBoth('book://kept', _style(18), '1.0.0+2');

      await ReaderLayoutCache.retainOnly(
        bookUrls: const ['book://kept'],
        build: '1.0.0+2',
        base: base,
      );

      expect(await hasMetrics('book://kept', _style(18)), isTrue);
      expect(await hasPlan('book://kept', _style(18), '1.0.0+2'), isTrue);
      expect(await hasPlan('book://kept', _style(18), '1.0.0+1'), isFalse);
      expect(await hasMetrics('book://gone', _style(18)), isFalse);
    },
  );

  test('each book keeps the two most recently written styles', () async {
    for (final size in [16.0, 18.0, 20.0]) {
      await writeBoth('book://a', _style(size), '1.0.0+1');
      // 檔案系統的修改時間解析度有限，隔開才分得出先後。
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(await hasMetrics('book://a', _style(16)), isFalse);
    expect(await hasPlan('book://a', _style(16), '1.0.0+1'), isFalse);
    for (final size in [18.0, 20.0]) {
      expect(await hasMetrics('book://a', _style(size)), isTrue);
      expect(await hasPlan('book://a', _style(size), '1.0.0+1'), isTrue);
    }
  });
}
