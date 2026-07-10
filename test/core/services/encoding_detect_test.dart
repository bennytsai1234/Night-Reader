import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

Uint8List _utf16Bytes(String text, Endian endian, {bool includeBom = true}) {
  final prefix = switch (endian) {
    Endian.little => <int>[0xFF, 0xFE],
    Endian.big => <int>[0xFE, 0xFF],
    _ => throw ArgumentError.value(endian),
  };
  final data = ByteData(text.codeUnits.length * 2);
  for (var index = 0; index < text.codeUnits.length; index += 1) {
    data.setUint16(index * 2, text.codeUnits[index], endian);
  }
  return Uint8List.fromList(<int>[
    if (includeBom) ...prefix,
    ...data.buffer.asUint8List(),
  ]);
}

void main() {
  test('解碼 UTF-16LE BOM 文字', () {
    final bytes = _utf16Bytes('第一章\n內容甲', Endian.little);

    expect(EncodingDetect.getEncode(bytes), 'UTF-16LE');
    expect(EncodingDetect.decode(bytes), '第一章\n內容甲');
  });

  test('解碼 UTF-16BE BOM 文字', () {
    final bytes = _utf16Bytes('第二章\n內容乙', Endian.big);

    expect(EncodingDetect.getEncode(bytes), 'UTF-16BE');
    expect(EncodingDetect.decode(bytes), '第二章\n內容乙');
  });

  test('依已知 charset 解碼不含 BOM 的 UTF-16 章節切片', () {
    final bytes = _utf16Bytes('章節切片', Endian.little, includeBom: false);

    expect(EncodingDetect.decodeWithCharset(bytes, 'UTF-16LE'), '章節切片');
  });
}
