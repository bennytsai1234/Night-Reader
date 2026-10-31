import 'dart:math' as math;

/// 舊書源規則 JS 裡 Rhino 吃得下、QuickJS 當成語法錯誤的寫法，執行前改成
/// 等價的寫法。
abstract final class LegacyJsSyntax {
  /// 改寫兩種寫法，都只改程式碼本身，不動字串、註解與正規表示式的內容：
  ///
  /// - template literal 裡不認得的跳脫（例如 `` `${callback}\((.*)\)` ``，
  ///   組正規表示式時把 `\(` 當成 `(`）：拿掉多的反斜線。
  /// - 箭頭函式的陣列解構參數沒加括號（`[a, b] => …`）：補上括號。
  static String normalize(String source) {
    final escaped = source.contains('`') && source.contains(r'\')
        ? _normalizeTemplateEscapes(source)
        : source;
    return _normalizeArrowDestructuring(escaped);
  }

  static final RegExp _arrowAfterToken = RegExp(
    r'([,(=])\s*(\[[^\[\]\n]+\])\s*=>',
  );
  static final RegExp _arrowAtStart = RegExp(r'^(\s*)(\[[^\[\]\n]+\])\s*=>');

  /// 在遮住字面量的文字上找位置，再在原文的參數前後補括號，其餘照原樣：
  /// 遮住的字長度不變、不含 `[`、`]`、換行與 `,(=`，字串裡的
  /// `=[a,b] =>` 比對不到。
  static String _normalizeArrowDestructuring(String source) {
    final masked = _masked(source);
    final matches = [
      ..._arrowAtStart.allMatches(masked),
      ..._arrowAfterToken.allMatches(masked),
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (matches.isEmpty) return source;
    final sb = StringBuffer();
    var copied = 0;
    for (final match in matches) {
      if (match.start < copied) continue;
      final params = match.start + match.group(0)!.indexOf(match.group(2)!);
      final paramsEnd = params + match.group(2)!.length;
      sb
        ..write(source.substring(copied, params))
        ..write('(')
        ..write(source.substring(params, paramsEnd))
        ..write(')');
      copied = paramsEnd;
    }
    sb.write(source.substring(copied));
    return sb.toString();
  }

  /// 程式碼照原樣，字串、註解、正規表示式與模板文字的內容換成 `x`（引號、
  /// 斜線與反引號留著）。
  static String _masked(String source) {
    final sb = StringBuffer();
    for (final span in _scan(source)) {
      final text = source.substring(span.start, span.end);
      sb.write(span.kind == _SpanKind.code ? text : 'x' * text.length);
    }
    return sb.toString();
  }

  /// 模板文字裡不認得的跳脫拿掉反斜線，其餘照原樣。
  static String _normalizeTemplateEscapes(String source) {
    final sb = StringBuffer();
    for (final span in _scan(source)) {
      if (span.kind != _SpanKind.templateText) {
        sb.write(source.substring(span.start, span.end));
        continue;
      }
      var i = span.start;
      while (i < span.end) {
        final c = source.codeUnitAt(i);
        if (c == _backslash && i + 1 < span.end) {
          final next = source.codeUnitAt(i + 1);
          if (_isValidTemplateEscapeStart(next)) {
            sb.write(source.substring(i, i + 2));
          } else {
            sb.writeCharCode(next);
          }
          i += 2;
          continue;
        }
        sb.writeCharCode(c);
        i++;
      }
    }
    return sb.toString();
  }

  /// 把 [source] 從頭到尾切成連續的區段。
  static List<_Span> _scan(String source) {
    final scanner = _Scanner(source);
    scanner.scanCode(0, insideInterpolation: false);
    return scanner.spans;
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
}

enum _SpanKind {
  /// 程式碼，含模板裡 `${…}` 的內容。
  code,

  /// 字串、註解、正規表示式，與模板的反引號。
  literal,

  /// 模板的文字部分（反引號之間、`${…}` 以外）。
  templateText,
}

final class _Span {
  _Span(this.kind, this.start, this.end);

  final _SpanKind kind;
  final int start;
  int end;
}

final class _Scanner {
  _Scanner(this.source);

  final String source;
  final List<_Span> spans = [];

  int get _n => source.length;

  void _add(_SpanKind kind, int start, int end) {
    if (end <= start) return;
    final last = spans.isEmpty ? null : spans.last;
    if (last != null && last.kind == kind && last.end == start) {
      last.end = end;
    } else {
      spans.add(_Span(kind, start, end));
    }
  }

  /// 從 [start] 掃程式碼。在 `${…}` 裡時掃到對應的 `}`（不含）為止，回傳它
  /// 的位置；否則掃到結尾。
  ///
  /// `/` 是除號還是正規表示式的開頭，看前一個語法單元：值（識別字、數字、
  /// 字面量、`)`、`]`、後置的 `++`／`--`）後面是除號；運算子、開括號、
  /// `return`、`typeof` 這類接運算式的關鍵字與開頭是正規表示式。
  int scanCode(int start, {required bool insideInterpolation}) {
    var depth = 0;
    var i = start;
    var regexAllowed = true;
    while (i < _n) {
      final c = source.codeUnitAt(i);
      if (_isWhitespace(c) || _isLineTerminator(c)) {
        _add(_SpanKind.code, i, i + 1);
        i++;
        continue;
      }
      if (_isWordChar(c)) {
        final end = _wordEnd(i);
        final word = source.substring(i, end);
        _add(_SpanKind.code, i, end);
        regexAllowed = _expressionKeywords.contains(word);
        i = end;
        continue;
      }
      if (c == _slash && i + 1 < _n) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          i = _literal(i, _lineEnd(i));
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          i = _literal(i, end == -1 ? _n : end + 2);
          continue;
        }
      }
      if (c == _slash && regexAllowed) {
        i = _literal(i, _skipRegexLiteral(i));
        regexAllowed = false;
        continue;
      }
      if (c == _dquote || c == _squote) {
        i = _literal(i, _skipString(i, c));
        regexAllowed = false;
        continue;
      }
      if (c == _backtick) {
        i = _scanTemplate(i);
        regexAllowed = false;
        continue;
      }
      if (c == _lbrace) {
        depth++;
      } else if (c == _rbrace) {
        if (insideInterpolation && depth == 0) return i;
        depth--;
      }
      if ((c == _plus || c == _minus) &&
          i + 1 < _n &&
          source.codeUnitAt(i + 1) == c) {
        // 後置的 `++`／`--` 接在值後面；前置的後面接的是值，不會是 `/`。
        _add(_SpanKind.code, i, i + 2);
        regexAllowed = false;
        i += 2;
        continue;
      }
      _add(_SpanKind.code, i, i + 1);
      regexAllowed = c != _rparen && c != _rbracket;
      i++;
    }
    return _n;
  }

  /// 後面接運算式的關鍵字：之後的 `/` 是正規表示式的開頭。
  static const Set<String> _expressionKeywords = {
    'return',
    'typeof',
    'instanceof',
    'in',
    'of',
    'new',
    'delete',
    'void',
    'throw',
    'case',
    'do',
    'else',
    'yield',
    'await',
  };

  static bool _isWordChar(int c) =>
      (c >= _charLowerA && c <= _charLowerZ) ||
      (c >= _charUpperA && c <= _charUpperZ) ||
      (c >= _char0 && c <= _char9) ||
      c == _underscore ||
      c == _dollar ||
      c >= 0x80 && !_isLineTerminator(c);

  int _wordEnd(int start) {
    var i = start;
    while (i < _n && _isWordChar(source.codeUnitAt(i))) {
      i++;
    }
    // 小數點與指數接在數字裡（`1.5`、`1e3`），不另算一個語法單元。
    if (i < _n &&
        source.codeUnitAt(i) == _dot &&
        source.codeUnitAt(start) >= _char0 &&
        source.codeUnitAt(start) <= _char9) {
      return _wordEnd(i + 1);
    }
    return i;
  }

  /// 從 [start] 起第一個換行的位置（JavaScript 的四種換行），沒有時是結尾。
  int _lineEnd(int start) {
    var i = start;
    while (i < _n && !_isLineTerminator(source.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  /// 反斜線跳脫佔幾個字元：反斜線接 CRLF 是一組續行。
  int _escapeLength(int backslashIdx) {
    if (backslashIdx + 2 < _n &&
        source.codeUnitAt(backslashIdx + 1) == _cr &&
        source.codeUnitAt(backslashIdx + 2) == _lf) {
      return 3;
    }
    return 2;
  }

  int _literal(int start, int end) {
    _add(_SpanKind.literal, start, end);
    return end;
  }

  /// [start] 指向開頭的反引號，回傳結尾反引號之後的位置。
  int _scanTemplate(int start) {
    _add(_SpanKind.literal, start, start + 1);
    var i = start + 1;
    while (i < _n) {
      final c = source.codeUnitAt(i);
      if (c == _backslash) {
        final end = math.min(i + _escapeLength(i), _n);
        _add(_SpanKind.templateText, i, end);
        i = end;
        continue;
      }
      if (c == _backtick) {
        _add(_SpanKind.literal, i, i + 1);
        return i + 1;
      }
      if (c == _dollar && i + 1 < _n && source.codeUnitAt(i + 1) == _lbrace) {
        _add(_SpanKind.code, i, i + 2);
        final close = scanCode(i + 2, insideInterpolation: true);
        if (close >= _n) return _n;
        _add(_SpanKind.code, close, close + 1);
        i = close + 1;
        continue;
      }
      _add(_SpanKind.templateText, i, i + 1);
      i++;
    }
    return _n;
  }

  /// 從 [startIdx]（指向引號）跳過整個字串，回傳結束後下一個位置。沒跳脫的
  /// 換行代表字串沒寫完（JavaScript 不允許），停在換行前。
  int _skipString(int startIdx, int quote) {
    var i = startIdx + 1;
    while (i < _n) {
      final c = source.codeUnitAt(i);
      if (c == _backslash) {
        i += _escapeLength(i);
        continue;
      }
      if (c == quote) return i + 1;
      if (_isLineTerminator(c)) return i;
      i++;
    }
    return _n;
  }

  int _skipRegexLiteral(int startIdx) {
    var i = startIdx + 1;
    var inCharClass = false;
    while (i < _n) {
      final c = source.codeUnitAt(i);
      if (c == _backslash) {
        i += 2;
        continue;
      }
      if (_isLineTerminator(c)) return i;
      if (c == _lbracket) {
        inCharClass = true;
      } else if (c == _rbracket && inCharClass) {
        inCharClass = false;
      } else if (c == _slash && !inCharClass) {
        i++;
        while (i < _n) {
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
    return _n;
  }

  static bool _isWhitespace(int cu) =>
      cu == _space ||
      cu == _tab ||
      cu == 0x0B ||
      cu == 0x0C ||
      cu == 0xA0 ||
      cu == 0xFEFF;
}

/// JavaScript 的四種換行：LF、CR、U+2028、U+2029。
bool _isLineTerminator(int cu) =>
    cu == _lf || cu == _cr || cu == 0x2028 || cu == 0x2029;

// ─── char code constants ─────────────────────────────────────────────
const int _slash = 0x2F;
const int _star = 0x2A;
const int _backslash = 0x5C;
const int _dquote = 0x22;
const int _squote = 0x27;
const int _backtick = 0x60;
const int _dollar = 0x24;
const int _lbrace = 0x7B;
const int _rbrace = 0x7D;
const int _rparen = 0x29;
const int _lbracket = 0x5B;
const int _rbracket = 0x5D;
const int _plus = 0x2B;
const int _minus = 0x2D;
const int _dot = 0x2E;
const int _underscore = 0x5F;
const int _space = 0x20;
const int _tab = 0x09;
const int _lf = 0x0A;
const int _cr = 0x0D;
const int _char0 = 0x30;
const int _char9 = 0x39;
const int _charUpperA = 0x41;
const int _charUpperU = 0x55;
const int _charUpperX = 0x58;
const int _charUpperZ = 0x5A;
const int _charLowerA = 0x61;
const int _charLowerB = 0x62;
const int _charLowerF = 0x66;
const int _charLowerN = 0x6E;
const int _charLowerR = 0x72;
const int _charLowerT = 0x74;
const int _charLowerU = 0x75;
const int _charLowerV = 0x76;
const int _charLowerX = 0x78;
const int _charLowerZ = 0x7A;
