import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/encode/charsets.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

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
}
