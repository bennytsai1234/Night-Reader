import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// 規則 JS 裡文字與位元組互轉（`java.strToBytes`、`bytesToStr`、加解密的
/// 字元集參數），照 Java 的 `String.getBytes(charset)`、`new String(bytes,
/// charset)`：沒寫是 UTF-8；解不出的位元組換成替代字元，不丟錯誤。不認得
/// 的字元集直接說，不默默改用 UTF-8。
abstract final class Charsets {
  static Uint8List encode(String text, [String? charset]) =>
      switch (_name(charset)) {
        'UTF-8' => Uint8List.fromList(utf8.encode(text)),
        'GBK' => Uint8List.fromList(gbk.encode(text)),
        'UTF-16LE' => _utf16(text, littleEndian: true, bom: false),
        'UTF-16BE' => _utf16(text, littleEndian: false, bom: false),
        // Java 的 UTF-16 編碼時加上大端序的 BOM。
        'UTF-16' => _utf16(text, littleEndian: false, bom: true),
        'ISO-8859-1' => Uint8List.fromList([
          for (final unit in text.codeUnits) unit > 0xFF ? 0x3F : unit,
        ]),
        'US-ASCII' => Uint8List.fromList([
          for (final unit in text.codeUnits) unit > 0x7F ? 0x3F : unit,
        ]),
        final other => throw UnsupportedError('不支援的字元集：$other'),
      };

  static String decode(List<int> bytes, [String? charset]) =>
      switch (_name(charset)) {
        'UTF-8' => utf8.decode(bytes, allowMalformed: true),
        'GBK' => gbk.decode(bytes),
        'UTF-16LE' => _fromUtf16(bytes, littleEndian: true),
        'UTF-16BE' => _fromUtf16(bytes, littleEndian: false),
        'UTF-16' => _fromUtf16WithBom(bytes),
        'ISO-8859-1' => String.fromCharCodes(bytes),
        'US-ASCII' => String.fromCharCodes([
          for (final b in bytes) b > 0x7F ? 0xFFFD : b,
        ]),
        final other => throw UnsupportedError('不支援的字元集：$other'),
      };

  static String _name(String? charset) {
    final name = (charset ?? '').trim().toUpperCase().replaceAll('_', '-');
    return switch (name) {
      '' || 'UTF-8' || 'UTF8' => 'UTF-8',
      'GBK' || 'GB2312' || 'GB18030' || 'CP936' => 'GBK',
      'UTF-16LE' || 'UTF16LE' || 'UNICODELITTLEUNMARKED' => 'UTF-16LE',
      'UTF-16BE' || 'UTF16BE' || 'UNICODEBIGUNMARKED' => 'UTF-16BE',
      'UTF-16' || 'UTF16' || 'UNICODE' => 'UTF-16',
      'ISO-8859-1' || 'ISO8859-1' || 'LATIN1' || 'ISO-LATIN-1' => 'ISO-8859-1',
      'US-ASCII' || 'ASCII' => 'US-ASCII',
      _ => name,
    };
  }

  static Uint8List _utf16(
    String text, {
    required bool littleEndian,
    required bool bom,
  }) {
    final units = [if (bom) 0xFEFF, ...text.codeUnits];
    final data = ByteData(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      data.setUint16(
        i * 2,
        units[i],
        littleEndian ? Endian.little : Endian.big,
      );
    }
    return data.buffer.asUint8List();
  }

  static String _fromUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    if (bytes.length.isOdd) units.add(0xFFFD);
    return String.fromCharCodes(units);
  }

  /// 沒有 BOM 時照 Java 當成大端序。
  static String _fromUtf16WithBom(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _fromUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _fromUtf16(bytes.sublist(2), littleEndian: false);
    }
    return _fromUtf16(bytes, littleEndian: false);
  }
}
