import 'dart:convert' show LineSplitter;

/// 將 rule JS 原始碼包成 async IIFE，並透過 `__ruleDone` sentinel 把結果
/// 回送給 Dart 側 [JsExtensionsBase] 中的 pending Completer。
///
/// 典型 rule JS 是「最後一行表達式即為回傳值」的 Rhino/QuickJS 語意：
///
/// ```
/// var url = baseUrl + "/api";
/// java.ajax(url)
/// ```
///
/// 我們透過 [injectFinalReturn] 在最後一個 top-level statement 前補上 `return`，
/// 再包進 async IIFE 以便內部可以對 rewriter 產生的 `(await ...)` 正確等待。
///
/// 失敗處理：任何 JS 端例外都透過 sentinel 第 3 欄 (errMsg) 回傳，Dart 端
/// Completer 會 completeError。
class JsRuleAsyncWrapper {
  JsRuleAsyncWrapper._();

  /// 包裝已經經過 AsyncJsRewriter 處理的 JS 原始碼為 async IIFE。
  ///
  /// [callId] 對應 [JsExtensionsBase.registerRuleCall] 配到的 id。
  static String wrap(String rewrittenSource, int callId) {
    final body = injectFinalReturn(rewrittenSource);
    return '''
(async function() {
  try {
    var __lrRuleRes = await (async function() {
${_indent(body, '      ')}
    })();
    var __lrNormalizedRuleRes =
      typeof __lrNormalizeRuleResult === 'function'
        ? __lrNormalizeRuleResult(__lrRuleRes)
        : __lrRuleRes;
    sendMessage('__ruleDone', JSON.stringify([$callId, __lrNormalizedRuleRes === undefined ? null : __lrNormalizedRuleRes, null]));
  } catch (__lrErr) {
    var __lrMsg = (__lrErr && __lrErr.message) ? String(__lrErr.message) : String(__lrErr);
    sendMessage('__ruleDone', JSON.stringify([$callId, null, __lrMsg]));
  }
})();
''';
  }

  /// 對 JS source 注入 `return`，使最後一個 top-level statement 的結果被回傳。
  ///
  /// 若最後一個 statement 已經以 `return` / `throw` 開頭，或是以變數宣告、
  /// 控制流 keyword 開頭，則不做修改（它們不會產生表達式結果）。
  ///
  /// 對包含在字串字面量、註解、巢狀括號內部的 `;` / `}` 不會誤判為 statement
  /// 邊界。
  static String injectFinalReturn(String code) {
    final stmtStart = _findLastTopLevelStatementStart(code);
    // 取得從 stmtStart 到結尾的「尾段」，扣除尾端空白
    var end = code.length;
    while (end > stmtStart && _isWhitespace(code.codeUnitAt(end - 1))) {
      end--;
    }
    // 若尾端是 `;`，一併 trim（避免 `return <expr>;;` 但也防止空統計）
    var trailingSemi = false;
    if (end > stmtStart && code.codeUnitAt(end - 1) == _semi) {
      end--;
      trailingSemi = true;
      while (end > stmtStart && _isWhitespace(code.codeUnitAt(end - 1))) {
        end--;
      }
    }
    if (end == stmtStart) return code; // 空 tail，不注入

    // tail 起始：跳過 leading whitespace
    var tailStart = stmtStart;
    while (tailStart < end && _isWhitespace(code.codeUnitAt(tailStart))) {
      tailStart++;
    }
    if (tailStart == end) return code;

    final tail = code.substring(tailStart, end);
    final transformedTail = _injectReturnIntoStatement(tail);
    if (transformedTail == null) return code;

    final head = code.substring(0, tailStart);
    final rest = code.substring(end);
    if (transformedTail == tail && !trailingSemi) {
      return '$head$transformedTail$rest';
    }
    return '$head$transformedTail$rest';
  }

  /// 尋找最後一個 top-level statement 起點的位置。
  ///
  /// 規則：從左到右掃描，追蹤括號/大括號/方括號深度並跳過字串與註解。
  /// 每次在 depth == 0 遇到 `;` 或 `}` 就把「下一個 index」當作候選 statement
  /// 起點。回傳最後一個候選；若從未遇到則回傳 0（整段就是一個 statement）。
  static int _findLastTopLevelStatementStart(String code) {
    var n = code.length;
    while (n > 0 && _isWhitespace(code.codeUnitAt(n - 1))) {
      n--;
    }
    while (n > 0 && code.codeUnitAt(n - 1) == _semi) {
      n--;
      while (n > 0 && _isWhitespace(code.codeUnitAt(n - 1))) {
        n--;
      }
    }
    var lastStart = 0;
    var i = 0;
    while (i < n) {
      i = _skipTrivia(code, i, limit: n);
      if (i >= n) break;
      lastStart = i;
      final end = _findStatementEnd(code, i);
      if (end == -1 || end <= i) {
        return lastStart;
      }
      i = end;
    }
    return lastStart;
  }

  static int _skipTrivia(String source, int start, {int? limit}) {
    final max = limit ?? source.length;
    var i = start;
    while (i < max) {
      final c = source.codeUnitAt(i);
      if (_isWhitespace(c)) {
        i++;
        continue;
      }
      if (c == _slash && i + 1 < max) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          i = end == -1 || end > max ? max : end + 1;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          i = end == -1 || end + 2 > max ? max : end + 2;
          continue;
        }
      }
      break;
    }
    return i;
  }

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
        // 跳過 ${...} 插值
        var depth = 1;
        i += 2;
        while (i < n && depth > 0) {
          final cc = source.codeUnitAt(i);
          if (cc == _lbrace) {
            depth++;
          } else if (cc == _rbrace) {
            depth--;
          } else if (cc == _dquote || cc == _squote || cc == _backtick) {
            i = _skipString(source, i, cc);
            continue;
          }
          i++;
        }
        continue;
      }
      i++;
    }
    return n;
  }

  /// 檢查 [tail] 開頭是否為一個不會產生表達式值的 keyword (var/let/const/
  /// if/for/while/do/switch/try/function/class/return/throw/break/continue/
  /// debugger/{/}) — 若是，表示 tail 不適合包 `return`。
  ///
  /// 特別地，`return` / `throw` 已經會把值/例外往外傳播，也不應重複包。
  static String? _injectReturnIntoStatement(String tail) {
    if (tail.isEmpty) return null;
    final c0 = tail.codeUnitAt(0);
    if (c0 == _lbrace) {
      return _injectReturnIntoBlock(tail);
    }
    if (c0 == _rbrace) return null;

    var i = 0;
    while (i < tail.length && _isIdentChar(tail.codeUnitAt(i))) {
      i++;
    }
    if (i == 0) return 'return $tail;';
    final word = tail.substring(0, i);
    switch (word) {
      case 'if':
        return _injectReturnIntoIf(tail);
      case 'try':
        return _injectReturnIntoTry(tail);
      case 'return':
      case 'throw':
        return tail;
      default:
        if (_stmtKeywords.contains(word)) return null;
        return 'return $tail;';
    }
  }

  static String? _injectReturnIntoBlock(String block) {
    final end = _findMatchingDelimiter(block, 0, _lbrace, _rbrace);
    if (end == -1) return null;
    if (_skipWhitespaceIndex(block, end + 1) != block.length) {
      return null;
    }
    final inner = block.substring(1, end);
    final injected = injectFinalReturn(inner);
    return '{${injected.isEmpty ? inner : injected}}';
  }

  static String? _injectReturnIntoIf(String stmt) {
    var index = _skipWhitespaceIndex(stmt, 2);
    if (index >= stmt.length || stmt.codeUnitAt(index) != _lparen) return null;
    final condEnd = _findMatchingDelimiter(stmt, index, _lparen, _rparen);
    if (condEnd == -1) return null;

    final consequentStart = _skipWhitespaceIndex(stmt, condEnd + 1);
    if (consequentStart >= stmt.length) return null;
    final consequentEnd = _findStatementEnd(stmt, consequentStart);
    if (consequentEnd == -1) return null;

    final consequent = stmt.substring(consequentStart, consequentEnd);
    final transformedConsequent = _injectReturnIntoStatement(consequent);
    if (transformedConsequent == null) return null;

    final out =
        StringBuffer()
          ..write(stmt.substring(0, consequentStart))
          ..write(transformedConsequent);

    var cursor = _skipWhitespaceIndex(stmt, consequentEnd);
    if (_startsWithKeyword(stmt, cursor, 'else')) {
      final alternateStart = _skipWhitespaceIndex(stmt, cursor + 4);
      if (alternateStart >= stmt.length) return null;
      final alternateEnd = _findStatementEnd(stmt, alternateStart);
      if (alternateEnd == -1) return null;
      final alternate = stmt.substring(alternateStart, alternateEnd);
      final transformedAlternate = _injectReturnIntoStatement(alternate);
      if (transformedAlternate == null) return null;
      out
        ..write(stmt.substring(consequentEnd, alternateStart))
        ..write(transformedAlternate)
        ..write(stmt.substring(alternateEnd));
      return out.toString();
    }

    out.write(' else { return null; }');
    out.write(stmt.substring(consequentEnd));
    return out.toString();
  }

  static String? _injectReturnIntoTry(String stmt) {
    var index = _skipWhitespaceIndex(stmt, 3);
    if (index >= stmt.length || stmt.codeUnitAt(index) != _lbrace) return null;
    final tryBlockEnd = _findMatchingDelimiter(stmt, index, _lbrace, _rbrace);
    if (tryBlockEnd == -1) return null;

    final transformedTryBlock = _injectReturnIntoBlock(
      stmt.substring(index, tryBlockEnd + 1),
    );
    if (transformedTryBlock == null) return null;

    final out =
        StringBuffer()
          ..write(stmt.substring(0, index))
          ..write(transformedTryBlock);

    var cursor = tryBlockEnd + 1;
    var sawCatch = false;
    while (true) {
      final keywordStart = _skipWhitespaceIndex(stmt, cursor);
      if (_startsWithKeyword(stmt, keywordStart, 'catch')) {
        sawCatch = true;
        var catchParamStart = _skipWhitespaceIndex(stmt, keywordStart + 5);
        if (catchParamStart >= stmt.length ||
            stmt.codeUnitAt(catchParamStart) != _lparen) {
          return null;
        }
        final catchParamEnd = _findMatchingDelimiter(
          stmt,
          catchParamStart,
          _lparen,
          _rparen,
        );
        if (catchParamEnd == -1) return null;
        final catchBlockStart = _skipWhitespaceIndex(stmt, catchParamEnd + 1);
        if (catchBlockStart >= stmt.length ||
            stmt.codeUnitAt(catchBlockStart) != _lbrace) {
          return null;
        }
        final catchBlockEnd = _findMatchingDelimiter(
          stmt,
          catchBlockStart,
          _lbrace,
          _rbrace,
        );
        if (catchBlockEnd == -1) return null;
        final transformedCatchBlock = _injectReturnIntoBlock(
          stmt.substring(catchBlockStart, catchBlockEnd + 1),
        );
        if (transformedCatchBlock == null) return null;
        out
          ..write(stmt.substring(cursor, catchBlockStart))
          ..write(transformedCatchBlock);
        cursor = catchBlockEnd + 1;
        continue;
      }
      if (_startsWithKeyword(stmt, keywordStart, 'finally')) {
        final finallyBlockStart = _skipWhitespaceIndex(stmt, keywordStart + 7);
        if (finallyBlockStart >= stmt.length ||
            stmt.codeUnitAt(finallyBlockStart) != _lbrace) {
          return null;
        }
        final finallyBlockEnd = _findMatchingDelimiter(
          stmt,
          finallyBlockStart,
          _lbrace,
          _rbrace,
        );
        if (finallyBlockEnd == -1) return null;
        out.write(stmt.substring(cursor, finallyBlockEnd + 1));
        cursor = finallyBlockEnd + 1;
      }
      break;
    }

    if (!sawCatch) return null;
    out.write(stmt.substring(cursor));
    return out.toString();
  }

  static int _findStatementEnd(String source, int start) {
    if (start >= source.length) return -1;
    final first = source.codeUnitAt(start);
    if (first == _lbrace) {
      final end = _findMatchingDelimiter(source, start, _lbrace, _rbrace);
      return end == -1 ? -1 : end + 1;
    }
    if (_startsWithKeyword(source, start, 'if')) {
      return _findIfEnd(source, start);
    }
    if (_startsWithKeyword(source, start, 'try')) {
      return _findTryEnd(source, start);
    }
    var depthParen = 0;
    var depthBracket = 0;
    var depthBrace = 0;
    var i = start;
    while (i < source.length) {
      final c = source.codeUnitAt(i);
      if (c == _slash && i + 1 < source.length) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          i = end == -1 ? source.length : end;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          i = end == -1 ? source.length : end + 2;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          i = _skipRegexLiteral(source, i);
          continue;
        }
      }
      if (c == _dquote || c == _squote || c == _backtick) {
        i = _skipString(source, i, c);
        continue;
      }
      if (c == _lparen) {
        depthParen++;
      } else if (c == _rparen) {
        depthParen--;
      } else if (c == _lbracket) {
        depthBracket++;
      } else if (c == _rbracket) {
        depthBracket--;
      } else if (c == _lbrace) {
        depthBrace++;
      } else if (c == _rbrace) {
        depthBrace--;
      } else if (c == _semi &&
          depthParen == 0 &&
          depthBracket == 0 &&
          depthBrace == 0) {
        return i + 1;
      } else if ((c == 0x0A || c == 0x0D) &&
          depthParen == 0 &&
          depthBracket == 0 &&
          depthBrace == 0 &&
          _isImplicitStatementBoundary(source, start, i)) {
        return i + 1;
      }
      i++;
    }
    return source.length;
  }

  static bool _isImplicitStatementBoundary(
    String source,
    int start,
    int newlineIdx,
  ) {
    var prev = newlineIdx - 1;
    while (prev >= start && _isWhitespace(source.codeUnitAt(prev))) {
      prev--;
    }
    if (prev < start) return false;
    final prevChar = source.codeUnitAt(prev);
    if (_continuationTrailingChars.contains(prevChar)) {
      return false;
    }

    var next = newlineIdx + 1;
    while (next < source.length && _isWhitespace(source.codeUnitAt(next))) {
      next++;
    }
    if (next >= source.length) return true;
    final nextChar = source.codeUnitAt(next);
    if (_continuationLeadingChars.contains(nextChar)) {
      return false;
    }
    return true;
  }

  static int _findIfEnd(String source, int start) {
    var index = _skipWhitespaceIndex(source, start + 2);
    if (index >= source.length || source.codeUnitAt(index) != _lparen) {
      return -1;
    }
    final condEnd = _findMatchingDelimiter(source, index, _lparen, _rparen);
    if (condEnd == -1) return -1;
    final consequentStart = _skipWhitespaceIndex(source, condEnd + 1);
    final consequentEnd = _findStatementEnd(source, consequentStart);
    if (consequentEnd == -1) return -1;
    final maybeElse = _skipWhitespaceIndex(source, consequentEnd);
    if (_startsWithKeyword(source, maybeElse, 'else')) {
      final alternateStart = _skipWhitespaceIndex(source, maybeElse + 4);
      final alternateEnd = _findStatementEnd(source, alternateStart);
      return alternateEnd;
    }
    return consequentEnd;
  }

  static int _findTryEnd(String source, int start) {
    var index = _skipWhitespaceIndex(source, start + 3);
    if (index >= source.length || source.codeUnitAt(index) != _lbrace) {
      return -1;
    }
    var cursor = _findMatchingDelimiter(source, index, _lbrace, _rbrace);
    if (cursor == -1) return -1;
    cursor++;
    var sawCatch = false;
    while (true) {
      final keywordStart = _skipWhitespaceIndex(source, cursor);
      if (_startsWithKeyword(source, keywordStart, 'catch')) {
        sawCatch = true;
        var catchParamStart = _skipWhitespaceIndex(source, keywordStart + 5);
        if (catchParamStart >= source.length ||
            source.codeUnitAt(catchParamStart) != _lparen) {
          return -1;
        }
        final catchParamEnd = _findMatchingDelimiter(
          source,
          catchParamStart,
          _lparen,
          _rparen,
        );
        if (catchParamEnd == -1) return -1;
        final catchBlockStart = _skipWhitespaceIndex(source, catchParamEnd + 1);
        if (catchBlockStart >= source.length ||
            source.codeUnitAt(catchBlockStart) != _lbrace) {
          return -1;
        }
        final catchBlockEnd = _findMatchingDelimiter(
          source,
          catchBlockStart,
          _lbrace,
          _rbrace,
        );
        if (catchBlockEnd == -1) return -1;
        cursor = catchBlockEnd + 1;
        continue;
      }
      if (_startsWithKeyword(source, keywordStart, 'finally')) {
        final finallyBlockStart = _skipWhitespaceIndex(
          source,
          keywordStart + 7,
        );
        if (finallyBlockStart >= source.length ||
            source.codeUnitAt(finallyBlockStart) != _lbrace) {
          return -1;
        }
        final finallyBlockEnd = _findMatchingDelimiter(
          source,
          finallyBlockStart,
          _lbrace,
          _rbrace,
        );
        return finallyBlockEnd == -1 ? -1 : finallyBlockEnd + 1;
      }
      break;
    }
    return sawCatch ? cursor : -1;
  }

  static int _findMatchingDelimiter(
    String source,
    int start,
    int open,
    int close,
  ) {
    var depth = 0;
    var i = start;
    while (i < source.length) {
      final c = source.codeUnitAt(i);
      if (c == _slash && i + 1 < source.length) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          i = end == -1 ? source.length : end;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          i = end == -1 ? source.length : end + 2;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          i = _skipRegexLiteral(source, i);
          continue;
        }
      }
      if (c == _dquote || c == _squote || c == _backtick) {
        i = _skipString(source, i, c);
        continue;
      }
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }

  static int _skipWhitespaceIndex(String source, int start) {
    var index = start;
    while (index < source.length && _isWhitespace(source.codeUnitAt(index))) {
      index++;
    }
    return index;
  }

  static bool _startsWithKeyword(String source, int start, String keyword) {
    if (start < 0 || start + keyword.length > source.length) return false;
    if (source.substring(start, start + keyword.length) != keyword) {
      return false;
    }
    final before = start == 0 ? null : source.codeUnitAt(start - 1);
    final afterIndex = start + keyword.length;
    final after =
        afterIndex < source.length ? source.codeUnitAt(afterIndex) : null;
    final beforeOk = before == null || !_isIdentChar(before);
    final afterOk = after == null || !_isIdentChar(after);
    return beforeOk && afterOk;
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
        prev == _semi ||
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
          if ((flag >= 0x61 && flag <= 0x7A) ||
              (flag >= 0x41 && flag <= 0x5A)) {
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

  static String _indent(String code, String prefix) {
    final lines = const LineSplitter().convert(code);
    return lines.map((l) => l.isEmpty ? l : '$prefix$l').join('\n');
  }

  static bool _isWhitespace(int cu) =>
      cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

  static bool _isIdentChar(int cu) {
    return (cu >= 0x30 && cu <= 0x39) ||
        (cu >= 0x41 && cu <= 0x5A) ||
        (cu >= 0x61 && cu <= 0x7A) ||
        cu == 0x5F ||
        cu == 0x24;
  }

  static const Set<String> _stmtKeywords = {
    'var',
    'let',
    'const',
    'if',
    'else',
    'for',
    'while',
    'do',
    'switch',
    'case',
    'default',
    'try',
    'catch',
    'finally',
    'function',
    'class',
    'return',
    'throw',
    'break',
    'continue',
    'debugger',
    'import',
    'export',
  };

  // char codes
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
  static const int _rparen = 0x29;
  static const int _lbracket = 0x5B;
  static const int _rbracket = 0x5D;
  static const int _comma = 0x2C;
  static const int _equal = 0x3D;
  static const int _colon = 0x3A;
  static const int _semi = 0x3B;
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
  static const int _dot = 0x2E;

  static const Set<int> _continuationTrailingChars = {
    _dot,
    _equal,
    _plus,
    _minus,
    _star,
    _slash,
    _percent,
    _ampersand,
    _pipe,
    _caret,
    _bang,
    _question,
    _colon,
    _comma,
    _lparen,
    _lbracket,
    _lbrace,
  };

  static const Set<int> _continuationLeadingChars = {
    _dot,
    _equal,
    _plus,
    _minus,
    _star,
    _slash,
    _percent,
    _ampersand,
    _pipe,
    _caret,
    _bang,
    _question,
    _colon,
    _comma,
    _rparen,
    _rbracket,
    _rbrace,
  };
}
