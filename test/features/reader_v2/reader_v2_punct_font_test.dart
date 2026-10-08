import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 內建標點字型 NightReaderPunct 的契約：字形置於臺灣排版的位置，
/// 且與系統 Noto Sans CJK 混排時不改變字寬與行高。
void main() {
  const punctuation = '，。、；：！？';
  const opening = '「『';
  const closing = '」』';

  test('pubspec registers both weights under the reader family name', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: $kReaderV2PunctFontFamily'));
    for (final weight in ['Regular', 'Bold']) {
      expect(
        pubspec,
        contains('assets/fonts/$kReaderV2PunctFontFamily-$weight.ttf'),
      );
    }
  });

  for (final weight in ['Regular', 'Bold']) {
    group(weight, () {
      final font = _TrueTypeFont(
        File('assets/fonts/$kReaderV2PunctFontFamily-$weight.ttf')
            .readAsBytesSync(),
      );

      test('family name matches the reader text style', () {
        expect(font.familyName, kReaderV2PunctFontFamily);
      });

      test('covers only the reader punctuation set', () {
        expect(
          font.codePoints,
          (punctuation + opening + closing).runes.toSet(),
        );
      });

      test('keeps the cell width and vertical metrics of Noto Sans CJK', () {
        expect(font.unitsPerEm, 1000);
        expect(font.ascender, 1160);
        expect(font.descender, -288);
        for (final rune in font.codePoints) {
          expect(font.advance(rune), 1000, reason: String.fromCharCode(rune));
        }
      });

      test('sentence punctuation is centred in the cell', () {
        for (final rune in punctuation.runes) {
          final box = font.bounds(rune);
          expect(
            (box.xMin + box.xMax) / 2,
            closeTo(500, 60),
            reason: String.fromCharCode(rune),
          );
        }
      });

      // Noto 的表意字框中心是 (500, 380)；教育部位置以直筆外緣貼中線，
      // 上引號在右上、下引號在左下，各約半格高。
      test('opening brackets fill the upper-right quarter', () {
        for (final rune in opening.runes) {
          final box = font.bounds(rune);
          expect(box.xMin, 500, reason: String.fromCharCode(rune));
          expect(box.yMin, greaterThanOrEqualTo(350));
          expect(box.yMax - box.yMin, lessThanOrEqualTo(470));
        }
      });

      test('closing brackets fill the lower-left quarter', () {
        for (final rune in closing.runes) {
          final box = font.bounds(rune);
          expect(box.xMax, 500, reason: String.fromCharCode(rune));
          expect(box.yMax, lessThanOrEqualTo(410));
          expect(box.yMax - box.yMin, lessThanOrEqualTo(470));
        }
      });
    });
  }
}

typedef _Box = ({int xMin, int yMin, int xMax, int yMax});

/// 只讀取契約需要的 TrueType 表：head、hhea、hmtx、loca、glyf、cmap、name。
final class _TrueTypeFont {
  _TrueTypeFont(Uint8List bytes) : _data = ByteData.sublistView(bytes) {
    final tableCount = _data.getUint16(4);
    for (var i = 0; i < tableCount; i += 1) {
      final record = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      _tables[tag] = _data.getUint32(record + 8);
    }
    final cmap = _tables['cmap']!;
    for (var i = 0; i < _data.getUint16(cmap + 2); i += 1) {
      final record = cmap + 4 + i * 8;
      final platform = _data.getUint16(record);
      final encoding = _data.getUint16(record + 2);
      if (platform == 3 && encoding == 1) {
        _readFormat4(cmap + _data.getUint32(record + 4));
      }
    }
  }

  final ByteData _data;
  final Map<String, int> _tables = <String, int>{};
  final Map<int, int> _glyphByCodePoint = <int, int>{};

  Set<int> get codePoints => _glyphByCodePoint.keys.toSet();
  int get unitsPerEm => _data.getUint16(_tables['head']! + 18);
  int get ascender => _data.getInt16(_tables['hhea']! + 4);
  int get descender => _data.getInt16(_tables['hhea']! + 6);

  String get familyName {
    final name = _tables['name']!;
    final strings = name + _data.getUint16(name + 4);
    for (var i = 0; i < _data.getUint16(name + 2); i += 1) {
      final record = name + 6 + i * 12;
      if (_data.getUint16(record) != 3 || _data.getUint16(record + 6) != 1) {
        continue;
      }
      final length = _data.getUint16(record + 8);
      final offset = strings + _data.getUint16(record + 10);
      return String.fromCharCodes([
        for (var j = 0; j < length; j += 2) _data.getUint16(offset + j),
      ]);
    }
    throw StateError('Font has no Windows family name.');
  }

  int advance(int codePoint) {
    final glyph = _glyphByCodePoint[codePoint]!;
    final metricsCount = _data.getUint16(_tables['hhea']! + 34);
    final index = glyph < metricsCount ? glyph : metricsCount - 1;
    return _data.getUint16(_tables['hmtx']! + index * 4);
  }

  _Box bounds(int codePoint) {
    final glyph = _glyphByCodePoint[codePoint]!;
    final loca = _tables['loca']!;
    final longOffsets = _data.getInt16(_tables['head']! + 50) == 1;
    final offset = longOffsets
        ? _data.getUint32(loca + glyph * 4)
        : _data.getUint16(loca + glyph * 2) * 2;
    final header = _tables['glyf']! + offset;
    return (
      xMin: _data.getInt16(header + 2),
      yMin: _data.getInt16(header + 4),
      xMax: _data.getInt16(header + 6),
      yMax: _data.getInt16(header + 8),
    );
  }

  void _readFormat4(int table) {
    if (_data.getUint16(table) != 4) return;
    final segments = _data.getUint16(table + 6) ~/ 2;
    final ends = table + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final rangeOffsets = deltas + segments * 2;
    for (var i = 0; i < segments; i += 1) {
      final start = _data.getUint16(starts + i * 2);
      final end = _data.getUint16(ends + i * 2);
      final delta = _data.getInt16(deltas + i * 2);
      final rangeOffset = _data.getUint16(rangeOffsets + i * 2);
      for (var codePoint = start; codePoint <= end; codePoint += 1) {
        if (codePoint == 0xFFFF) continue;
        var glyph = codePoint;
        if (rangeOffset != 0) {
          final address =
              rangeOffsets + i * 2 + rangeOffset + (codePoint - start) * 2;
          glyph = _data.getUint16(address);
          if (glyph == 0) continue;
        }
        _glyphByCodePoint[codePoint] = (glyph + delta) & 0xFFFF;
      }
    }
  }
}
