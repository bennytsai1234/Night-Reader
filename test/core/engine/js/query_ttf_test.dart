import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/query_ttf.dart';

// ─── 輔助：建立只含 cmap (Format 0) 的最小 TTF binary ─────────────────────────
//
// Layout（共 302 bytes）：
//  [0..11]   TTF header         (12 bytes)
//  [12..27]  cmap dir entry     (16 bytes)
//  [28..39]  cmap table header + 1 subtable record (12 bytes)
//  [40..301] Format 0 subtable  (262 bytes = 6 header + 256 glyph IDs)
Uint8List _buildFormat0Ttf(Map<int, int> unicodeToGlyphId) {
  const cmapOffset = 28;
  const subtableRelOffset = 12;
  const format0DataSize = 262; // 6 + 256
  const cmapLength = subtableRelOffset + format0DataSize;
  const totalSize = cmapOffset + cmapLength;

  final buf = ByteData(totalSize);

  // TTF header
  buf.setUint32(0, 0x00010000); // sfntVersion (TrueType)
  buf.setUint16(4, 1); // numTables = 1
  buf.setUint16(6, 16); // searchRange
  buf.setUint16(8, 0); // entrySelector
  buf.setUint16(10, 0); // rangeShift

  // cmap directory entry
  for (var i = 0; i < 4; i++) {
    buf.setUint8(12 + i, 'cmap'.codeUnitAt(i));
  }
  buf.setUint32(16, 0); // checkSum (ignored in our parser)
  buf.setUint32(20, cmapOffset); // offset to cmap table
  buf.setUint32(24, cmapLength); // length

  // cmap table header at offset 28
  buf.setUint16(28, 0); // version = 0
  buf.setUint16(30, 1); // numTables = 1 (one subtable)

  // Subtable record (platformID=1 Macintosh, compatible with Format 0)
  buf.setUint16(32, 1); // platformID
  buf.setUint16(34, 0); // encodingID
  buf.setUint32(36, subtableRelOffset); // offset within cmap

  // Format 0 subtable at offset 40 (28+12)
  const f0 = cmapOffset + subtableRelOffset;
  buf.setUint16(f0 + 0, 0); // format = 0
  buf.setUint16(f0 + 2, format0DataSize); // length = 262
  buf.setUint16(f0 + 4, 0); // language = 0

  // Fill glyph ID array (256 bytes starting at f0+6)
  final bytes = buf.buffer.asUint8List();
  for (final entry in unicodeToGlyphId.entries) {
    if (entry.key < 256 && entry.value > 0) {
      bytes[f0 + 6 + entry.key] = entry.value;
    }
  }

  return bytes;
}

// 測試用輔助子類別，讓我們能直接操作 QueryTTFBase 的 extension 方法
class _BaseUnderTest extends QueryTTFBase {}

void main() {
  group('QueryTTF Tests', () {
    // ─── 錯誤處理 ─────────────────────────────────────────────────────────────
    group('錯誤處理', () {
      test('空 buffer 拋出 RangeError', () {
        expect(() => QueryTTF(Uint8List(0)), throwsRangeError);
      });

      test('只有 header（0 個 table）可正常解析、不含任何 directory', () {
        final bytes = Uint8List.fromList([
          0, 1, 0, 0, // sfntVersion
          0, 0, // numTables = 0
          0, 0, // searchRange
          0, 0, // entrySelector
          0, 0, // rangeShift
        ]);
        final q = QueryTTF(bytes);
        expect(q.directorys, isEmpty);
        expect(q.unicodeToGlyph, isEmpty);
      });
    });

    // ─── isBlankUnicode ────────────────────────────────────────────────────────
    group('isBlankUnicode()', () {
      test('辨識所有規定的空白 codepoint', () {
        const blanks = {
          0x0009: 'Tab',
          0x0020: 'Space',
          0x00A0: 'Non-breaking space',
          0x2002: 'En space',
          0x2003: 'Em space',
          0x2007: 'Figure space',
          0x200A: 'Hair space',
          0x200B: 'Zero-width space',
          0x200C: 'Zero-width non-joiner',
          0x200D: 'Zero-width joiner',
          0x202F: 'Narrow no-break space',
          0x205F: 'Medium mathematical space',
        };
        for (final entry in blanks.entries) {
          expect(
            QueryTTF.isBlank(entry.key),
            isTrue,
            reason:
                'U+${entry.key.toRadixString(16).toUpperCase().padLeft(4, "0")} (${entry.value}) 應視為空白',
          );
        }
      });

      test('非空白字元回傳 false', () {
        const nonBlanks = {
          0x0041: 'A',
          0x4E2D: '中',
          0x0021: '!',
          0x000A: 'LF (newline)',
          0x000D: 'CR',
          0x0030: '0',
        };
        for (final entry in nonBlanks.entries) {
          expect(
            QueryTTF.isBlank(entry.key),
            isFalse,
            reason:
                'U+${entry.key.toRadixString(16).toUpperCase().padLeft(4, "0")} (${entry.value}) 不應視為空白',
          );
        }
      });

      test('QueryTTFBase 實例方法 isBlankUnicode 與靜態方法結果一致', () {
        final base = _BaseUnderTest();
        expect(base.isBlankUnicode(0x0020), isTrue);
        expect(base.isBlankUnicode(0x0041), isFalse);
      });
    });

    // ─── Format 0 cmap 解析 ───────────────────────────────────────────────────
    group('Format 0 cmap 解析', () {
      test('正確建立 unicode → glyph ID 對應', () {
        final buf = _buildFormat0Ttf({
          0x41: 1, // 'A' → glyph 1
          0x42: 2, // 'B' → glyph 2
          0x61: 3, // 'a' → glyph 3
        });

        final base = _BaseUnderTest();
        base.directorys['cmap'] =
            DirectoryEntry()
              ..tableTag = 'cmap'
              ..offset = 28
              ..length = 274;
        base.readCmapTable(buf);

        expect(
          base.unicodeToGlyphId[0x41],
          equals(1),
          reason: "'A' 應對應 glyph 1",
        );
        expect(
          base.unicodeToGlyphId[0x42],
          equals(2),
          reason: "'B' 應對應 glyph 2",
        );
        expect(
          base.unicodeToGlyphId[0x61],
          equals(3),
          reason: "'a' 應對應 glyph 3",
        );
        expect(base.unicodeToGlyphId[0x43], isNull, reason: "'C' 未設定，不應有對應");
      });

      test('glyph ID 為 0 的 entry 不加入對應表（表示未定義字型）', () {
        final buf = _buildFormat0Ttf({0x41: 1}); // 其餘 255 個 entry 皆為 0

        final base = _BaseUnderTest();
        base.directorys['cmap'] =
            DirectoryEntry()
              ..tableTag = 'cmap'
              ..offset = 28
              ..length = 274;
        base.readCmapTable(buf);

        expect(base.unicodeToGlyphId.containsKey(0x41), isTrue);
        expect(base.unicodeToGlyphId.containsKey(0x42), isFalse);
        expect(base.unicodeToGlyphId.length, equals(1));
      });

      test('cmap table 不存在時不拋出錯誤', () {
        final buf = _buildFormat0Ttf({0x41: 1});
        final base = _BaseUnderTest();
        // directorys 空，代表沒有 cmap table
        expect(() => base.readCmapTable(buf), returnsNormally);
        expect(base.unicodeToGlyphId, isEmpty);
      });
    });

    // ─── getGlyfById ──────────────────────────────────────────────────────────
    group('getGlyfById()', () {
      test('index 超出陣列長度時回傳 null', () {
        final base = _BaseUnderTest();
        base.glyfArray = [null, null];
        expect(base.getGlyfById(5), isNull);
        expect(base.getGlyfById(2), isNull);
      });

      test('glyfArray 中對應位置為 null 時回傳 null', () {
        final base = _BaseUnderTest();
        base.glyfArray = [null, null, null];
        expect(base.getGlyfById(1), isNull);
      });

      test('簡單字型（numberOfContours > 0）回傳 "x,y|x,y" 格式坐標字串', () {
        final base = _BaseUnderTest();
        final glyph = GlyfLayout();
        glyph.numberOfContours = 1;
        glyph.glyphSimple = GlyphTableBySimple();
        glyph.glyphSimple!.xCoordinates = [10, 20, 30];
        glyph.glyphSimple!.yCoordinates = [40, 50, 60];
        base.glyfArray = [null, glyph]; // glyph 放在 index 1

        expect(base.getGlyfById(1), equals('10,40|20,50|30,60'));
      });

      test('numberOfContours == 0（沒有輪廓）的字型回傳 null', () {
        final base = _BaseUnderTest();
        final glyph = GlyfLayout();
        glyph.numberOfContours = 0;
        // numberOfContours == 0 表示沒有可用字型，getGlyfById 應跳過
        base.glyfArray = [glyph];
        expect(base.getGlyfById(0), isNull);
      });
    });

    // ─── 查詢輔助 ──────────────────────────────────────────────────────────────
    group('查詢輔助方法', () {
      test('getGlyfIdByUnicode: 未對應的 unicode 回傳 0', () {
        final base = _BaseUnderTest();
        expect(base.getGlyfIdByUnicode(0x1234), equals(0));
      });

      test('getGlyfByUnicode: 未對應的 unicode 回傳 null', () {
        final base = _BaseUnderTest();
        expect(base.getGlyfByUnicode(0x1234), isNull);
      });

      test('getUnicodeByGlyf: 未對應的 glyph 字串回傳 0', () {
        final base = _BaseUnderTest();
        expect(base.getUnicodeByGlyf('nonexistent'), equals(0));
        expect(base.getUnicodeByGlyf(null), equals(0));
      });
    });
  });
}
