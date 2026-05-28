/// AlphanumComparator - 字典序與數字混合排序工具 (原 Android utils/AlphanumComparator.kt)
/// 用於章節標題排序 (例如 "第2章" 應排在 "第10章" 之前)
class AlphanumComparator {
  AlphanumComparator._();

  static int compare(String s1, String s2) {
    var thisMarker = 0;
    var thatMarker = 0;
    final s1Length = s1.length;
    final s2Length = s2.length;

    while (thisMarker < s1Length && thatMarker < s2Length) {
      final thisChunk = _getChunk(s1, s1Length, thisMarker);
      thisMarker += thisChunk.length;

      final thatChunk = _getChunk(s2, s2Length, thatMarker);
      thatMarker += thatChunk.length;

      int result;
      if (_isDigit(thisChunk[0]) && _isDigit(thatChunk[0])) {
        // 如果兩塊都是數字，先比長度，再逐位比
        final thisChunkLength = thisChunk.length;
        result = thisChunkLength - thatChunk.length;
        if (result == 0) {
          for (var i = 0; i < thisChunkLength; i++) {
            result = thisChunk.codeUnitAt(i) - thatChunk.codeUnitAt(i);
            if (result != 0) return result;
          }
        }
      } else {
        result = thisChunk.compareTo(thatChunk);
      }

      if (result != 0) return result;
    }

    return s1Length - s2Length;
  }

  static String _getChunk(String string, int length, int marker) {
    var current = marker;
    final chunk = StringBuffer();
    var c = string[current];
    chunk.write(c);
    current++;
    if (_isDigit(c)) {
      while (current < length) {
        c = string[current];
        if (!_isDigit(c)) break;
        chunk.write(c);
        current++;
      }
    } else {
      while (current < length) {
        c = string[current];
        if (_isDigit(c)) break;
        chunk.write(c);
        current++;
      }
    }
    return chunk.toString();
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }
}
