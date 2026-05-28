import 'dart:typed_data';
import 'ttf/buffer_reader.dart';
import 'ttf/ttf_tables.dart';
import 'ttf/query_ttf_base.dart';
import 'ttf/query_ttf_logic.dart';

export 'ttf/ttf_tables.dart';
export 'ttf/query_ttf_base.dart';
export 'ttf/query_ttf_logic.dart';

/// QueryTTF - TTF 字體解析器 (重構後)
class QueryTTF extends QueryTTFBase {
  QueryTTF(Uint8List buffer) {
    final reader = BufferReader(buffer);
    reader.readUInt32(); // sfntVersion
    final numTables = reader.readUInt16();
    reader.readUInt16(); // searchRange
    reader.readUInt16(); // entrySelector
    reader.readUInt16(); // rangeShift

    for (var i = 0; i < numTables; ++i) {
      final d = DirectoryEntry();
      final tagBytes = reader.readByteArray(4);
      d.tableTag = String.fromCharCodes(tagBytes);
      reader.readUInt32(); // checkSum
      d.offset = reader.readUInt32();
      d.length = reader.readUInt32();
      directorys[d.tableTag] = d;
    }

    readHeadTable(buffer);
    readMaxpTable(buffer);
    readLocaTable(buffer);
    readCmapTable(buffer);
    readGlyfTable(buffer);

    for (var entry in unicodeToGlyphId.entries) {
      final u = entry.key;
      final gId = entry.value;
      if (gId >= glyfArray.length) continue;
      final glyfString = getGlyfById(gId);
      if (glyfString != null) {
        unicodeToGlyph[u] = glyfString;
        glyphToUnicode[glyfString] = u;
      }
    }
  }

  // 靜態輔助方法 (保持相容性)
  static bool isBlank(int unicode) {
    return _BlankChecker().isBlankUnicode(unicode);
  }
}

class _BlankChecker extends QueryTTFBase {}
