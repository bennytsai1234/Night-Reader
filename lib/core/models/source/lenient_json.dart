/// 照 Gson 寬鬆模式（Legado 讀書源欄位用的）讀 JSON：欄位名可以不加引號、
/// 字串可以用單引號、可以有 `//`、`/* */`、`#` 註解，陣列與物件結尾可以多
/// 一個逗號，不加引號的值照字串讀。書源作者常照 JS 的寫法填，Legado 照收，
/// 夜讀也要照收。讀不懂時丟出 [FormatException]。
Object? decodeLenientJson(String source) {
  final reader = _LenientReader(source);
  final value = reader.readValue();
  reader.skipSpace();
  if (!reader.atEnd) reader.fail('多出無法解讀的內容');
  return value;
}

final class _LenientReader {
  _LenientReader(this.text);

  final String text;
  int index = 0;

  bool get atEnd => index >= text.length;

  Never fail(String reason) =>
      throw FormatException('JSON 格式錯誤：$reason', text, index);

  void skipSpace() {
    while (!atEnd) {
      final c = text[index];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '﻿') {
        index++;
      } else if (c == '#') {
        _skipLine();
      } else if (c == '/' && index + 1 < text.length) {
        final next = text[index + 1];
        if (next == '/') {
          _skipLine();
        } else if (next == '*') {
          final end = text.indexOf('*/', index + 2);
          if (end < 0) fail('註解沒有結尾');
          index = end + 2;
        } else {
          return;
        }
      } else {
        return;
      }
    }
  }

  void _skipLine() {
    while (!atEnd && text[index] != '\n') {
      index++;
    }
  }

  Object? readValue() {
    skipSpace();
    if (atEnd) fail('內容提早結束');
    final c = text[index];
    if (c == '{') return _readObject();
    if (c == '[') return _readArray();
    if (c == '"' || c == "'") return _readQuoted();
    return _literal(_readUnquoted());
  }

  Map<String, Object?> _readObject() {
    index++; // {
    final map = <String, Object?>{};
    while (true) {
      skipSpace();
      if (atEnd) fail('物件沒有結尾');
      if (text[index] == '}') {
        index++;
        return map;
      }
      final key = switch (text[index]) {
        '"' || "'" => _readQuoted(),
        _ => _readUnquoted(),
      };
      if (key.isEmpty) fail('缺少欄位名稱');
      skipSpace();
      if (atEnd) fail('物件沒有結尾');
      // Gson 也收 `=` 與 `=>`。
      if (text[index] == ':') {
        index++;
      } else if (text[index] == '=') {
        index++;
        if (!atEnd && text[index] == '>') index++;
      } else {
        fail('欄位「$key」後面缺少冒號');
      }
      map[key] = readValue();
      skipSpace();
      if (atEnd) fail('物件沒有結尾');
      final sep = text[index];
      if (sep == ',' || sep == ';') {
        index++;
      } else if (sep != '}') {
        fail('欄位之間缺少逗號');
      }
    }
  }

  List<Object?> _readArray() {
    index++; // [
    final list = <Object?>[];
    while (true) {
      skipSpace();
      if (atEnd) fail('陣列沒有結尾');
      if (text[index] == ']') {
        index++;
        return list;
      }
      list.add(readValue());
      skipSpace();
      if (atEnd) fail('陣列沒有結尾');
      final sep = text[index];
      if (sep == ',' || sep == ';') {
        index++;
      } else if (sep != ']') {
        fail('項目之間缺少逗號');
      }
    }
  }

  String _readQuoted() {
    final quote = text[index++];
    final out = StringBuffer();
    while (true) {
      if (atEnd) fail('字串沒有結尾');
      final c = text[index++];
      if (c == quote) return out.toString();
      if (c != r'\') {
        out.write(c);
        continue;
      }
      if (atEnd) fail('字串沒有結尾');
      final e = text[index++];
      switch (e) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case 'b':
          out.write('\b');
        case 'f':
          out.write('\f');
        case 'u':
          if (index + 4 > text.length) fail('\\u 後面不足四碼');
          final code = int.tryParse(
            text.substring(index, index + 4),
            radix: 16,
          );
          if (code == null) fail('\\u 後面不是十六進位');
          out.writeCharCode(code);
          index += 4;
        case '\n':
          // 行尾的反斜線：接續下一行。
          break;
        default:
          out.write(e);
      }
    }
  }

  /// 不加引號的欄位名或值，讀到分隔符號為止。
  String _readUnquoted() {
    final start = index;
    while (!atEnd) {
      final c = text[index];
      if (' \t\n\r,:;={}[]#/\\\'"'.contains(c)) break;
      index++;
    }
    return text.substring(start, index);
  }

  Object? _literal(String raw) {
    if (raw.isEmpty) fail('缺少值');
    switch (raw) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    return num.tryParse(raw) ?? raw;
  }
}
