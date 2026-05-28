import 'dart:convert';
import 'dart:typed_data';

/// TtfParser - TTF 字体二進位解析器 (原 Android QueryTTF.java)
/// 用於還原防盜字體中的亂碼字符
class TtfParser {
  final Uint8List _buffer;
  int _pos = 0;

  final Map<int, String> unicodeToGlyph = {};
  final Map<String, int> glyphToUnicode = {};
  final Map<String, int> _tableDirectories = {};

  TtfParser(this._buffer) {
    _parse();
  }

  void _parse() {
    // 1. 讀取文件頭 (Header)
    _pos = 0;
    _readUInt32(); // sfntVersion
    int numTables = _readUInt16();
    _readUInt16(); // searchRange
    _readUInt16(); // entrySelector
    _readUInt16(); // rangeShift

    // 2. 讀取表目錄 (Directory)
    for (int i = 0; i < numTables; i++) {
      String tag = String.fromCharCodes(_readBytes(4));
      _readUInt32(); // checkSum
      int offset = _readUInt32();
      _readUInt32(); // length
      _tableDirectories[tag] = offset;
    }

    // 3. 獲取核心表偏移量
    int? cmapOffset = _tableDirectories['cmap'];
    int? headOffset = _tableDirectories['head'];
    int? locaOffset = _tableDirectories['loca'];
    int? glyfOffset = _tableDirectories['glyf'];
    int? maxpOffset = _tableDirectories['maxp'];

    if (cmapOffset == null ||
        headOffset == null ||
        locaOffset == null ||
        glyfOffset == null ||
        maxpOffset == null) {
      return;
    }

    // 4. 解析 maxp 獲取字形數量
    _pos = maxpOffset + 4;
    int numGlyphs = _readUInt16();

    // 5. 解析 head 獲取 loca 格式 (Short/Long)
    _pos = headOffset + 50;
    int indexToLocFormat = _readInt16();

    // 6. 解析 loca 獲取 glyf 偏移數組
    List<int> loca = [];
    _pos = locaOffset;
    if (indexToLocFormat == 0) {
      for (int i = 0; i <= numGlyphs; i++) {
        loca.add(_readUInt16() * 2);
      }
    } else {
      for (int i = 0; i <= numGlyphs; i++) {
        loca.add(_readUInt32());
      }
    }

    // 7. 解析 cmap 建立 Unicode -> GlyphID 映射
    Map<int, int> unicodeToGlyphId = {};
    _pos = cmapOffset + 2;
    int cmapNumTables = _readUInt16();
    int? encodingOffset;
    for (int i = 0; i < cmapNumTables; i++) {
      int platformID = _readUInt16();
      int encodingID = _readUInt16();
      int offset = _readUInt32();
      if ((platformID == 3 && encodingID == 1) || (platformID == 0)) {
        encodingOffset = cmapOffset + offset;
        break;
      }
    }

    if (encodingOffset != null) {
      _pos = encodingOffset;
      int format = _readUInt16();
      if (format == 4) {
        _readUInt16(); // length
        _readUInt16(); // language
        int segCountX2 = _readUInt16();
        int segCount = segCountX2 ~/ 2;
        _pos += 6; // skip searchRange, entrySelector, rangeShift

        List<int> endCodes = [];
        for (int i = 0; i < segCount; i++) {
          endCodes.add(_readUInt16());
        }
        _readUInt16(); // reservedPad
        List<int> startCodes = [];
        for (int i = 0; i < segCount; i++) {
          startCodes.add(_readUInt16());
        }
        List<int> idDeltas = [];
        for (int i = 0; i < segCount; i++) {
          idDeltas.add(_readInt16());
        }
        int idRangeOffsetStart = _pos;
        List<int> idRangeOffsets = [];
        for (int i = 0; i < segCount; i++) {
          idRangeOffsets.add(_readUInt16());
        }

        for (int i = 0; i < segCount; i++) {
          for (
            int charCode = startCodes[i];
            charCode <= endCodes[i];
            charCode++
          ) {
            if (charCode == 0xFFFF) continue;
            int glyphId;
            if (idRangeOffsets[i] == 0) {
              glyphId = (charCode + idDeltas[i]) & 0xFFFF;
            } else {
              int offset =
                  idRangeOffsetStart +
                  i * 2 +
                  idRangeOffsets[i] +
                  (charCode - startCodes[i]) * 2;
              _pos = offset;
              glyphId = _readUInt16();
              if (glyphId != 0) glyphId = (glyphId + idDeltas[i]) & 0xFFFF;
            }
            if (glyphId != 0) unicodeToGlyphId[charCode] = glyphId;
          }
        }
      }
    }

    // 8. 建立字形特徵字符串並完成映射 (簡化版特徵：使用字形數據偏移與長度作為特徵)
    // 注意：真正的 QueryTTF 使用輪廓點特徵，這裡先對位基礎還原邏輯
    for (var entry in unicodeToGlyphId.entries) {
      int unicode = entry.key;
      int gid = entry.value;
      if (gid < loca.length - 1) {
        int start = loca[gid];
        int end = loca[gid + 1];
        if (start < end) {
          // 讀取字形輪廓數據的一部分作為特徵字串
          int len = (end - start).clamp(0, 100);
          _pos = glyfOffset + start;
          String feature = base64Encode(_readBytes(len));
          unicodeToGlyph[unicode] = feature;
          glyphToUnicode[feature] = unicode;
        }
      }
    }
  }

  // --- 二進位讀取工具 ---
  int _readUInt32() {
    int val = _buffer.buffer.asByteData().getUint32(_pos, Endian.big);
    _pos += 4;
    return val;
  }

  int _readUInt16() {
    int val = _buffer.buffer.asByteData().getUint16(_pos, Endian.big);
    _pos += 2;
    return val;
  }

  int _readInt16() {
    int val = _buffer.buffer.asByteData().getInt16(_pos, Endian.big);
    _pos += 2;
    return val;
  }

  Uint8List _readBytes(int len) {
    var res = _buffer.sublist(_pos, _pos + len);
    _pos += len;
    return res;
  }
}
