import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/illustration/illustration_images.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

const _mark = ReaderV2IllustrationMarkers.placeholder;

ReaderV2IllustrationSlot _slot(String src) =>
    (src: src, path: '/images/$src', pixelWidth: 300, pixelHeight: 200);

void main() {
  group('插圖標記', () {
    test('標記換成記號，網址依序留下', () {
      final extracted = ReaderV2IllustrationMarkers.extract(
        '前文<img src="https://a.test/1.jpg">後文\n'
        '<img src="https://a.test/2.png,{\'headers\':{}}">',
      );
      expect(extracted.text, '前文$_mark後文\n$_mark');
      expect(extracted.sources, [
        'https://a.test/1.jpg',
        "https://a.test/2.png,{'headers':{}}",
      ]);
    });

    test('拿掉標記只留字', () {
      expect(ReaderV2IllustrationMarkers.strip('一<img src="x.jpg">二'), '一二');
      expect(ReaderV2IllustrationMarkers.strip('沒有圖'), '沒有圖');
    });

    test('同一個網址同一個檔名', () {
      expect(
        ReaderV2IllustrationMarkers.fileNameFor('https://a.test/1.jpg'),
        ReaderV2IllustrationMarkers.fileNameFor('https://a.test/1.jpg'),
      );
      expect(
        ReaderV2IllustrationMarkers.fileNameFor('https://a.test/1.jpg'),
        isNot(ReaderV2IllustrationMarkers.fileNameFor('https://a.test/2.jpg')),
      );
    });
  });

  group('圖檔寬高', () {
    test('PNG', () {
      final bytes = Uint8List(24)
        ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..setAll(16, [0, 0, 0x04, 0xB0, 0, 0, 0x06, 0x40]);
      expect(ReaderV2ImageSize.ofBytes(bytes), (width: 1200, height: 1600));
    });

    test('JPEG 跳過前面的區段找到尺寸', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0，長度 4
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0，精度 8
        0x02, 0x58, // 高 600
        0x03, 0x20, // 寬 800
        0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]);
      expect(ReaderV2ImageSize.ofBytes(bytes), (width: 800, height: 600));
    });

    test('GIF', () {
      final bytes = Uint8List.fromList([
        ...'GIF89a'.codeUnits,
        0x2C, 0x01, // 寬 300
        0xC8, 0x00, // 高 200
      ]);
      expect(ReaderV2ImageSize.ofBytes(bytes), (width: 300, height: 200));
    });

    test('不是圖或檔案不在時是 null', () {
      expect(ReaderV2ImageSize.ofBytes(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
        ReaderV2ImageSize.ofFile(
          '${Directory.systemTemp.path}/night-reader-missing-image',
        ),
        isNull,
      );
    });
  });

  group('正文裡的插圖位置', () {
    test('沒有插圖時正文與雜湊和以前一樣', () {
      final plain = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '甲\n乙',
      );
      final marked = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '甲\n$_mark\n乙',
      );
      expect(marked.displayText, plain.displayText);
      expect(marked.contentHash, plain.contentHash);
      expect(marked.illustrations, isEmpty);
    });

    test('只有插圖的行不成段，圖在下一段前面；段中的圖記在字的位置', () {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '甲甲\n$_mark\n乙$_mark乙\n丙$_mark\n$_mark',
        illustrationSlots: [_slot('1'), _slot('2'), _slot('3'), _slot('4')],
      );
      expect(content.paragraphs, ['甲甲', '乙乙', '丙']);
      expect(content.displayText, '第一章\n\n甲甲\n\n乙乙\n\n丙');
      final text = content.displayText;
      expect(
        [for (final i in content.illustrations) i.offset],
        [
          text.indexOf('乙乙'), // 段前
          text.indexOf('乙乙') + 1, // 段中
          text.indexOf('丙') + 1, // 段尾
          text.length, // 章末
        ],
      );
      expect(content.illustrations.map((i) => i.src), ['1', '2', '3', '4']);
    });

    test('關掉顯示插圖時字一模一樣，只是沒有插圖', () {
      final on = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '',
        rawText: '甲\n$_mark\n乙',
        illustrationSlots: [_slot('1')],
      );
      final off = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '',
        rawText: '甲\n$_mark\n乙',
      );
      expect(on.displayText, off.displayText);
      expect(on.illustrations, hasLength(1));
      expect(off.illustrations, isEmpty);
      expect(on.contentHash, isNot(off.contentHash));
    });

    test('讀不到的圖不顯示，其他照常', () {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '',
        rawText: '$_mark甲\n$_mark乙',
        illustrationSlots: [null, _slot('2')],
      );
      expect(content.illustrations.map((i) => i.src), ['2']);
    });
  });

  group('切塊', () {
    Future<ChapterBlocks> blocksOf(ReaderV2Content content) {
      return const TextPreprocessor(useIsolate: false).process(
        ChapterText(
          id: 0,
          title: content.title,
          paragraphs: content.paragraphs,
          displayText: content.displayText,
          contentHash: content.contentHash,
          illustrations: content.illustrations,
        ),
      );
    }

    test('段前、段中、段尾、章末的插圖各自一塊，段中的圖把段落切開', () async {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章',
        rawText: '甲甲\n$_mark\n乙$_mark乙\n丙$_mark\n$_mark',
        illustrationSlots: [_slot('1'), _slot('2'), _slot('3'), _slot('4')],
      );
      final blocks = (await blocksOf(content)).blocks;
      String describe(ChapterBlock block) => block.isIllustration
          ? '圖${block.illustration!.src}'
          : '${block.text}${block.isContinuation ? '(續${block.layoutBreakBefore ? '，換行' : ''})' : ''}';
      expect(blocks.map(describe), [
        '第一章',
        '甲甲',
        '圖1',
        '乙',
        '圖2',
        '乙(續，換行)',
        '丙',
        '圖3',
        '圖4',
      ]);
      expect(
        [for (final b in blocks) b.blockIndex],
        [for (var i = 0; i < blocks.length; i += 1) i],
      );
    });

    test('位置一律落在字上，不落在插圖', () async {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '',
        rawText: '甲\n$_mark\n乙\n$_mark',
        illustrationSlots: [_slot('1'), _slot('2')],
      );
      final blocks = await blocksOf(content);
      final atSecond = blocks.blockForCharOffset(
        content.displayText.indexOf('乙'),
      );
      expect(atSecond.isIllustration, isFalse);
      expect(atSecond.text, '乙');
      final atEnd = blocks.blockForCharOffset(content.displayText.length);
      expect(atEnd.isIllustration, isFalse);
    });
  });

  group('插圖大小', () {
    ReaderV2Illustration illustration(int width, int height) =>
        ReaderV2Illustration(
          offset: 0,
          src: 's',
          path: 'p',
          pixelWidth: width,
          pixelHeight: height,
        );

    test('照原尺寸、不放大，置中', () {
      final box = IllustrationBox.layout(
        illustration(300, 60),
        contentWidth: 369,
        maxHeight: 800,
        devicePixelRatio: 3,
        gap: 10,
      );
      expect(box.rect, const Rect.fromLTWH(134.5, 10, 100, 20));
      expect(box.blockHeight, 40);
      expect(box.decodeWidth, 300);
    });

    test('比欄寬就縮到欄寬，比正文區高就縮到正文區高', () {
      final wide = IllustrationBox.layout(
        illustration(1600, 900),
        contentWidth: 320,
        maxHeight: 800,
        devicePixelRatio: 2,
        gap: 0,
      );
      expect(wide.rect.width, 320);
      expect(wide.rect.height, 180);
      final tall = IllustrationBox.layout(
        illustration(700, 2400),
        contentWidth: 369,
        maxHeight: 600,
        devicePixelRatio: 3,
        gap: 0,
      );
      expect(tall.rect.height, 600);
      expect(tall.rect.width, closeTo(175, 0.01));
    });
  });
}
