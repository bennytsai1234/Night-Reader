import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/encode/charsets.dart';
import 'package:night_reader/core/utils/big5.dart';
import 'package:night_reader/core/utils/encoding_detect.dart';

void main() {
  // 2026-11-14 86读书：GBK 的正文頁裡有一個孤立的位元組（0xD0），整頁被改用
  // UTF-8 解成亂碼。Legado 用 String(bytes, charset)，只把那一個字換成替代
  // 字元。
  final bytes = Uint8List.fromList([
    ...gbk.encode('第一章 学'),
    0xD0,
    ...gbk.encode('</p><p>后面的正文'),
  ]);

  test('a stray byte in a GBK page only spoils that one character', () {
    final text = EncodingDetect.decodeWithCharset(bytes, 'gb2312');
    expect(text, '第一章 学\uFFFD</p><p>后面的正文');
  });

  test('rule JS decodes GBK bytes the same way', () {
    final text = Charsets.decode(bytes, 'gbk');
    expect(text, '第一章 学\uFFFD</p><p>后面的正文');
  });

  // 網站標著 charset=big5（台灣、香港的舊網站）：照 Big5 解，同 Legado 的
  // String(bytes, "big5")；孤立的位元組只換掉它自己。
  test('a Big5 page decodes as Big5', () {
    final big5 = [0xA9, 0x5D, 0xC5, 0xAA, 0xAE, 0xD1]; // 夜讀書
    expect(EncodingDetect.decodeWithCharset(big5, 'Big5'), '夜讀書');
    expect(EncodingDetect.decodeWithCharset(big5, 'big5-hkscs'), '夜讀書');
    expect(
      EncodingDetect.decodeWithCharset([0xA9, 0x3C, 0x70, 0x3E], 'big5'),
      '\uFFFD<p>',
    );
    expect(EncodingDetect.encodeWithCharset('夜讀書', 'Big5'), big5);
    expect(Charsets.decode(big5, 'big5'), '夜讀書');
    expect(Charsets.encode('夜讀書a', 'BIG5'), [...big5, 0x61]);
    expect(Charsets.supports('big5'), isTrue);
    // 「十」「卅」在 Big5 有兩個位置，Java 編成 A451、A4CA。
    expect(Charsets.encode('十卅', 'big5'), [0xA4, 0x51, 0xA4, 0xCA]);
  });

  group('沒標字元集時照 Legado 的偵測（ICU 的 GB18030、Big5、UTF-16 辨識器）', () {
    const traditional =
        '第一章　開始\n　　他說：「我們走吧。」她點了點頭，沒有說話。天色已經暗了'
        '下來，街上的人也越來越少。這是一個很長的故事，從前有一個人，他每天都在想'
        '自己為什麼會在這裡。\n';
    const simplified =
        '第一章　开始\n　　他说：“我们走吧。”她点了点头，没有说话。天色已经暗了'
        '下来，街上的人也越来越少。这是一个很长的故事，从前有一个人，他每天都在想'
        '自己为什么会在这里。\n';

    test('Big5 的 TXT 認成 Big5，不是 GBK', () {
      expect(EncodingDetect.getEncode(Big5.encode(traditional * 20)), 'Big5');
    });

    test('GBK 的 TXT 照舊認成 GBK', () {
      expect(
        EncodingDetect.getEncode(
          Uint8List.fromList(gbk.encode(simplified * 20)),
        ),
        'GBK',
      );
    });

    test('10 個字以內分不出 GBK 與 Big5，照改之前當 GBK', () {
      expect(
        EncodingDetect.getEncode(Uint8List.fromList(gbk.encode('你好世界'))),
        'GBK',
      );
      expect(
        EncodingDetect.getEncode(
          Uint8List.fromList(gbk.encode('<html><body>你好世界</body></html>')),
        ),
        'GBK',
      );
    });

    test('沒有 BOM 的 UTF-16LE', () {
      final units = 'Chapter 1\nHe said: let us go.\n'.codeUnits;
      final bytes = Uint8List(units.length * 2);
      for (var i = 0; i < units.length; i++) {
        bytes[i * 2] = units[i] & 0xff;
        bytes[i * 2 + 1] = units[i] >> 8;
      }
      expect(EncodingDetect.getEncode(bytes), 'UTF-16LE');
    });

    test('UTF-8 照舊', () {
      expect(
        EncodingDetect.getEncode(Uint8List.fromList(utf8.encode(traditional))),
        'UTF-8',
      );
    });
  });

  // 網站明寫 GB18030 時，GBK 沒有的字（emoji、擴充區漢字、¥ 這類）是四位元組
  // （WHATWG gb18030；位元組照 Python 的 gb18030 編碼器算）。
  group('GB18030', () {
    const text = '中a€😀𠀀¥é　';
    const bytes = [
      0xD6, 0xD0, 0x61, 0xA2, 0xE3, 0x94, 0x39, 0xFC, 0x36, //
      0x95, 0x32, 0x82, 0x36, 0x81, 0x30, 0x84, 0x36, 0xA8, 0xA6, 0xA1, 0xA1,
    ];

    test('四位元組的字解得出來', () {
      expect(EncodingDetect.decodeWithCharset(bytes, 'GB18030'), text);
      expect(EncodingDetect.decodeWithCharset(bytes, 'gb18030'), text);
    });

    test('編得出四位元組，和解碼互為反向', () {
      expect(EncodingDetect.encodeWithCharset(text, 'GB18030'), bytes);
    });

    test('只有雙位元組時和 GBK 一樣，壞掉的位元組照樣只換一個替代字元', () {
      expect(
        EncodingDetect.decodeWithCharset([
          0xD6,
          0xD0,
          0xD0,
          0x3C,
          0x61,
        ], 'GB18030'),
        EncodingDetect.decodeWithCharset([0xD6, 0xD0, 0xD0, 0x3C, 0x61], 'GBK'),
      );
    });
  });
}
