/// 舊書源規則 JS 裡 Rhino 吃得下、QuickJS 當成語法錯誤的寫法，執行前改成
/// 等價的寫法。
abstract final class LegacyJsSyntax {
  /// 改寫兩種寫法：
  ///
  /// - template literal 裡不認得的跳脫（例如 `` `${callback}\((.*)\)` ``，
  ///   組正規表示式時把 `\(` 當成 `(`）：拿掉多的反斜線。
  /// - 箭頭函式的陣列解構參數沒加括號（`[a, b] => …`）：補上括號。
  static String normalize(String source) {
    if (!source.contains('`') || !source.contains(r'\')) {
      return _normalizeArrowDestructuring(source);
    }

    final sb = StringBuffer();
    final n = source.length;
    var i = 0;
    while (i < n) {
      final c = source.codeUnitAt(i);
      if (c == _slash && i + 1 < n) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          final stop = end == -1 ? n : end;
          sb.write(source.substring(i, stop));
          i = stop;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          final stop = end == -1 ? n : end + 2;
          sb.write(source.substring(i, stop));
          i = stop;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          final endIdx = _skipRegexLiteral(source, i);
          sb.write(source.substring(i, endIdx));
          i = endIdx;
          continue;
        }
      }
      if (c == _dquote || c == _squote) {
        final endIdx = _skipString(source, i, c);
        sb.write(source.substring(i, endIdx));
        i = endIdx;
        continue;
      }
      if (c == _backtick) {
        i = _appendNormalizedTemplateLiteral(source, i, sb);
        continue;
      }
      sb.writeCharCode(c);
      i++;
    }
    return _normalizeArrowDestructuring(sb.toString());
  }

  static String _normalizeArrowDestructuring(String source) {
    var normalized = source.replaceAllMapped(
      RegExp(r'([,(=])\s*(\[[^\[\]\n]+\])\s*=>'),
      (match) => '${match.group(1)}(${match.group(2)}) =>',
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'^(\s*)(\[[^\[\]\n]+\])\s*=>'),
      (match) => '${match.group(1)}(${match.group(2)}) =>',
    );
    return normalized;
  }

  /// 從 [startIdx]（指向引號）跳過整個字串字面量，回傳結束後下一個 index。
  /// 支援 backslash escape；template literal 的 `${...}` 以巢狀大括號計數
  /// 跳過。
  static int _skipString(String source, int startIdx, int quote) {
    final n = source.length;
    var i = startIdx + 1;
    while (i < n) {
      final c = source.codeUnitAt(i);
      if (c == _backslash) {
        i += 2;
        continue;
      }
      if (c == quote) return i + 1;
      if (quote == _backtick &&
          c == _dollar &&
          i + 1 < n &&
          source.codeUnitAt(i + 1) == _lbrace) {
        i = _skipTemplateInterp(source, i + 2);
        continue;
      }
      i++;
    }
    return n;
  }

  /// 跳過 `${...}` 插值內容（含巢狀大括號、字串、註解），回傳結束後 index。
  static int _skipTemplateInterp(String source, int startIdx) {
    final n = source.length;
    var depth = 1;
    var i = startIdx;
    while (i < n && depth > 0) {
      final c = source.codeUnitAt(i);
      if (c == _lbrace) {
        depth++;
        i++;
        continue;
      }
      if (c == _rbrace) {
        depth--;
        i++;
        continue;
      }
      if (c == _dquote || c == _squote || c == _backtick) {
        i = _skipString(source, i, c);
        continue;
      }
      if (c == _slash && i + 1 < n) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          i = end == -1 ? n : end;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          i = end == -1 ? n : end + 2;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          i = _skipRegexLiteral(source, i);
          continue;
        }
      }
      i++;
    }
    return i;
  }

  static bool _isRegexLiteralStart(String source, int slashIdx) {
    var i = slashIdx - 1;
    while (i >= 0 && _isWhitespace(source.codeUnitAt(i))) {
      i--;
    }
    if (i < 0) return true;
    final prev = source.codeUnitAt(i);
    return prev == _lparen ||
        prev == _lbrace ||
        prev == _lbracket ||
        prev == _equal ||
        prev == _colon ||
        prev == _comma ||
        prev == _semicolon ||
        prev == _bang ||
        prev == _question ||
        prev == _plus ||
        prev == _minus ||
        prev == _star ||
        prev == _percent ||
        prev == _ampersand ||
        prev == _pipe ||
        prev == _caret ||
        prev == _tilde ||
        prev == _lt ||
        prev == _gt;
  }

  static int _skipRegexLiteral(String source, int startIdx) {
    final n = source.length;
    var i = startIdx + 1;
    var inCharClass = false;
    while (i < n) {
      final c = source.codeUnitAt(i);
      if (c == _backslash) {
        i += 2;
        continue;
      }
      if (c == _lbracket) {
        inCharClass = true;
        i++;
        continue;
      }
      if (c == _rbracket && inCharClass) {
        inCharClass = false;
        i++;
        continue;
      }
      if (c == _slash && !inCharClass) {
        i++;
        while (i < n) {
          final flag = source.codeUnitAt(i);
          if ((flag >= _charLowerA && flag <= _charLowerZ) ||
              (flag >= _charUpperA && flag <= _charUpperZ)) {
            i++;
            continue;
          }
          break;
        }
        return i;
      }
      i++;
    }
    return n;
  }

  static bool _isWhitespace(int cu) {
    return cu == _space || cu == _tab || cu == _lf || cu == _cr;
  }

  static int _appendNormalizedTemplateLiteral(
    String source,
    int startIdx,
    StringBuffer sb,
  ) {
    final n = source.length;
    var i = startIdx;
    sb.writeCharCode(_backtick);
    i++;
    while (i < n) {
      final c = source.codeUnitAt(i);
      if (c == _backslash) {
        if (i + 1 >= n) {
          sb.writeCharCode(_backslash);
          return n;
        }
        final next = source.codeUnitAt(i + 1);
        if (_isValidTemplateEscapeStart(next)) {
          sb.write(source.substring(i, i + 2));
        } else {
          sb.writeCharCode(next);
        }
        i += 2;
        continue;
      }
      if (c == _dollar && i + 1 < n && source.codeUnitAt(i + 1) == _lbrace) {
        sb.write(r'${');
        i = _appendTemplateInterpolation(source, i + 2, sb);
        continue;
      }
      sb.writeCharCode(c);
      i++;
      if (c == _backtick) {
        return i;
      }
    }
    return n;
  }

  static int _appendTemplateInterpolation(
    String source,
    int startIdx,
    StringBuffer sb,
  ) {
    final n = source.length;
    var depth = 1;
    var i = startIdx;
    while (i < n && depth > 0) {
      final c = source.codeUnitAt(i);
      if (c == _slash && i + 1 < n) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          final stop = end == -1 ? n : end;
          sb.write(source.substring(i, stop));
          i = stop;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          final stop = end == -1 ? n : end + 2;
          sb.write(source.substring(i, stop));
          i = stop;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          final endIdx = _skipRegexLiteral(source, i);
          sb.write(source.substring(i, endIdx));
          i = endIdx;
          continue;
        }
      }
      if (c == _dquote || c == _squote) {
        final endIdx = _skipString(source, i, c);
        sb.write(source.substring(i, endIdx));
        i = endIdx;
        continue;
      }
      if (c == _backtick) {
        i = _appendNormalizedTemplateLiteral(source, i, sb);
        continue;
      }
      sb.writeCharCode(c);
      if (c == _lbrace) {
        depth++;
      } else if (c == _rbrace) {
        depth--;
      }
      i++;
    }
    return i;
  }

  static bool _isValidTemplateEscapeStart(int cu) {
    return cu == _backslash ||
        cu == _backtick ||
        cu == _dollar ||
        cu == _dquote ||
        cu == _squote ||
        cu == _char0 ||
        cu == _charLowerB ||
        cu == _charLowerF ||
        cu == _charLowerN ||
        cu == _charLowerR ||
        cu == _charLowerT ||
        cu == _charLowerV ||
        cu == _charLowerX ||
        cu == _charLowerU ||
        cu == _charUpperX ||
        cu == _charUpperU ||
        cu == _lf ||
        cu == _cr;
  }

  // ─── char code constants ─────────────────────────────────────────────
  static const int _slash = 0x2F;
  static const int _star = 0x2A;
  static const int _backslash = 0x5C;
  static const int _dquote = 0x22;
  static const int _squote = 0x27;
  static const int _backtick = 0x60;
  static const int _dollar = 0x24;
  static const int _lbrace = 0x7B;
  static const int _rbrace = 0x7D;
  static const int _lparen = 0x28;
  static const int _lbracket = 0x5B;
  static const int _rbracket = 0x5D;
  static const int _comma = 0x2C;
  static const int _equal = 0x3D;
  static const int _colon = 0x3A;
  static const int _semicolon = 0x3B;
  static const int _bang = 0x21;
  static const int _question = 0x3F;
  static const int _plus = 0x2B;
  static const int _minus = 0x2D;
  static const int _percent = 0x25;
  static const int _ampersand = 0x26;
  static const int _pipe = 0x7C;
  static const int _caret = 0x5E;
  static const int _tilde = 0x7E;
  static const int _lt = 0x3C;
  static const int _gt = 0x3E;
  static const int _space = 0x20;
  static const int _tab = 0x09;
  static const int _lf = 0x0A;
  static const int _cr = 0x0D;
  static const int _char0 = 0x30;
  static const int _charUpperA = 0x41;
  static const int _charUpperU = 0x55;
  static const int _charUpperX = 0x58;
  static const int _charUpperZ = 0x5A;
  static const int _charLowerA = 0x61;
  static const int _charLowerB = 0x62;
  static const int _charLowerF = 0x66;
  static const int _charLowerN = 0x6E;
  static const int _charLowerR = 0x72;
  static const int _charLowerT = 0x74;
  static const int _charLowerU = 0x75;
  static const int _charLowerV = 0x76;
  static const int _charLowerX = 0x78;
  static const int _charLowerZ = 0x7A;
}
