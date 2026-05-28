/// AsyncJsRewriter
///
/// 在書源 rule JS 原始碼中的 **已知 async 物件方法呼叫** 前方注入 `await` 並括住，
/// 讓被包在 `async function` 內的 rule JS 能正確等待 Promise 解析。
///
/// 例：
///   `var r = java.ajax(url);`
///     → `var r = (await java.ajax(url));`
///   `java.get(url).body()`
///     → `(await java.get(url)).body()`
///   `var v = cache.get(key);`
///     → `var v = (await cache.get(key));`
///
/// 設計重點：
///   * 輕量字串感知 lexer — 正確處理單/雙引號、block/line 註解、template literal
///   * 白名單驅動 — 支援多個 owner（java / cache / cookie / source），
///     每個 owner 有自己的 async method 集合
///   * 採用「整個 call expression 以 `(await …)` 包起來」策略，method chain
///     (`.body()`, `.statusCode()`) 仍能正常銜接在外層
///   * 避免二次包裹：若偵測到前方已有 `await `（word boundary 檢查），則跳過
///
/// 已知限制（刻意不處理）：
///   1. Template literal 的 `${ … }` 插值內部不會被掃描
///   2. 動態分派如 `var fn = java.ajax; fn(url)` 無法偵測
///   3. 動態方法名如 `java['aj' + 'ax'](url)` 無法偵測
///
/// 對書源實務而言這三種寫法幾乎不出現，權衡後不做處理。
library;

class AsyncJsRewriter {
  AsyncJsRewriter._();

  /// 需要注入 `await` 的 owner.method 白名單
  ///
  /// 必須與 `JsJavaObject.injectJavaObjectJs()` 中定義為 Promise-returning
  /// 的方法集合保持一致。key 是 JS 端的 owner 變數名，value 是該 owner
  /// 上所有 async 方法的集合。
  static const Map<String, Set<String>> asyncMethodsByOwner = {
    'java': {
      'ajax',
      'ajaxAll',
      'cacheFile',
      'connect',
      'get',
      'getCookie',
      'importScript',
      'post',
      'head',
      'webView',
      'webViewGetOverrideUrl',
      'webViewGetSource',
      'startBrowserAwait',
      'getVerificationCode',
      'downloadFile',
      'readFile',
      'readTxtFile',
      'getZipByteArrayContent',
      'unArchiveFile',
      'getTxtInFolder',
    },
    'cache': {'get', 'getFile'},
    'cookie': {'get', 'getCookie', 'all'},
    'source': {'get', 'getVariable', 'getLoginInfo', 'getLoginInfoMap'},
  };

  /// 快速偵測：source 是否包含任何 async `java.*` 呼叫
  ///
  /// 用於 fast path 判斷——若回傳 false，呼叫端可跳過 rewrite 並直接走同步 evalJS。
  /// 會正確忽略字串字面量與註解中的假匹配。
  static bool needsAsync(String source) {
    return _scan(source, rewrite: false).hasAsync;
  }

  /// 對 source 執行 rewrite，回傳注入 await 後的新原始碼
  ///
  /// 若 source 不含任何 async 呼叫，回傳值等於原字串（非 referential equality）。
  static String rewrite(String source) {
    return _scan(source, rewrite: true).result;
  }

  /// Normalize legacy template-literal escapes that Rhino-tolerant book source
  /// rules sometimes emit, such as `` `${callback}\((.*)\)` ``.
  ///
  /// QuickJS treats unknown escapes inside untagged template literals as syntax
  /// errors, while legacy Rhino-style rules often use forms like `\(` as if
  /// they were plain `(` when composing regex source strings. For compatibility
  /// we drop the invalid backslash and keep the following character.
  static String normalizeLegacyTemplateEscapes(String source) {
    if (!source.contains('`') || !source.contains(r'\')) {
      return _normalizeLegacyArrowDestructuring(source);
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
    return _normalizeLegacyArrowDestructuring(sb.toString());
  }

  static String _normalizeLegacyArrowDestructuring(String source) {
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

  // ─── internal ────────────────────────────────────────────────────────

  static _ScanResult _scan(String source, {required bool rewrite}) {
    final sb = rewrite ? StringBuffer() : null;
    final n = source.length;
    var i = 0;
    var hasAsync = false;

    while (i < n) {
      final c = source.codeUnitAt(i);

      // 註解
      if (c == _slash && i + 1 < n) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          // line comment
          final end = source.indexOf('\n', i);
          final stop = end == -1 ? n : end;
          if (rewrite) sb!.write(source.substring(i, stop));
          i = stop;
          continue;
        }
        if (next == _star) {
          // block comment
          final end = source.indexOf('*/', i + 2);
          final stop = end == -1 ? n : end + 2;
          if (rewrite) sb!.write(source.substring(i, stop));
          i = stop;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          final endIdx = _skipRegexLiteral(source, i);
          if (rewrite) sb!.write(source.substring(i, endIdx));
          i = endIdx;
          continue;
        }
      }

      // 字串字面量（含 template literal）
      if (c == _dquote || c == _squote || c == _backtick) {
        final endIdx = _skipString(source, i, c);
        if (rewrite) sb!.write(source.substring(i, endIdx));
        i = endIdx;
        continue;
      }

      // 嘗試 <owner>.<asyncMethod>( 匹配
      if (_isIdentStartChar(c) && _isIdentifierStart(source, i)) {
        final asyncCall = _tryMatchAsyncCall(source, i);
        if (asyncCall != null) {
          hasAsync = true;
          if (!rewrite) {
            return const _ScanResult(result: '', hasAsync: true);
          }
          final rewrittenCall = _rewriteAsyncCall(
            source,
            startIdx: i,
            match: asyncCall,
          );
          final awaited = _sbPrecededByAwait(sb!);
          if (awaited) {
            sb.write(rewrittenCall);
          } else {
            sb.write('(await ');
            sb.write(rewrittenCall);
            sb.write(')');
          }
          i = asyncCall.endIndex;
          continue;
        }
      }

      if (rewrite) sb!.writeCharCode(c);
      i++;
    }

    return _ScanResult(
      result: rewrite ? sb!.toString() : '',
      hasAsync: hasAsync,
    );
  }

  /// 從 [startIdx] (指向引號) 跳過整個字串字面量，回傳結束後下一個 index
  ///
  /// 支援 backslash escape；對 template literal 的 `${...}` 以巢狀大括號計數跳過。
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

  /// 跳過 `${...}` 插值內容（含巢狀大括號、字串、註解），回傳結束後 index
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

  /// 嘗試從 [startIdx] 開始匹配 `<owner>.<asyncMethod>(...)`
  ///
  /// 成功回傳整個 call expression 結束後下一個 index；失敗回傳 null。
  static _AsyncCallMatch? _tryMatchAsyncCall(String source, int startIdx) {
    final n = source.length;
    // 讀 owner identifier
    var i = startIdx;
    while (i < n && _isIdentChar(source.codeUnitAt(i))) {
      i++;
    }
    if (i == startIdx) return null;
    final owner = source.substring(startIdx, i);
    final methodSet = asyncMethodsByOwner[owner];
    if (methodSet == null) return null;

    // 必須接 '.'
    if (i >= n || source.codeUnitAt(i) != _dot) return null;
    i++;

    // 讀 method identifier
    final methodStart = i;
    while (i < n && _isIdentChar(source.codeUnitAt(i))) {
      i++;
    }
    if (i == methodStart) return null;
    final method = source.substring(methodStart, i);
    if (!methodSet.contains(method)) return null;

    // 跳過空白
    while (i < n && _isWhitespace(source.codeUnitAt(i))) {
      i++;
    }
    if (i >= n || source.codeUnitAt(i) != _lparen) return null;
    final openParenIdx = i;

    // 括號配對 — 找出對應的 ')' 位置
    final closeIdx = _matchParen(source, i);
    if (closeIdx == null) return null;

    if (owner == 'java' && method == 'get') {
      final argCount = _countTopLevelArgs(source, i, closeIdx);
      final chainedResponse = _looksLikeJavaGetResponseChain(
        source,
        closeIdx + 1,
      );
      if (argCount <= 1 && !chainedResponse) {
        return null;
      }
    }

    return _AsyncCallMatch(
      openParenIndex: openParenIdx,
      closeParenIndex: closeIdx,
      endIndex: closeIdx + 1,
    );
  }

  static String _rewriteAsyncCall(
    String source, {
    required int startIdx,
    required _AsyncCallMatch match,
  }) {
    final beforeArgs = source.substring(startIdx, match.openParenIndex + 1);
    final rawArgs = source.substring(
      match.openParenIndex + 1,
      match.closeParenIndex,
    );
    final rewrittenArgs =
        rawArgs.isEmpty ? rawArgs : _scan(rawArgs, rewrite: true).result;
    return '$beforeArgs$rewrittenArgs)';
  }

  static bool _isIdentStartChar(int cu) {
    return (cu >= _charUpperA && cu <= _charUpperZ) ||
        (cu >= _charLowerA && cu <= _charLowerZ) ||
        cu == _underscore ||
        cu == _dollar;
  }

  /// 從左括號位置配對右括號（考慮字串/註解/巢狀括號）
  static int? _matchParen(String source, int openIdx) {
    final n = source.length;
    var depth = 1;
    var i = openIdx + 1;
    while (i < n) {
      final c = source.codeUnitAt(i);
      if (c == _lparen) {
        depth++;
        i++;
        continue;
      }
      if (c == _rparen) {
        depth--;
        if (depth == 0) return i;
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
    return null;
  }

  static int _countTopLevelArgs(String source, int openIdx, int closeIdx) {
    var count = 0;
    var hasToken = false;
    var depthParen = 0;
    var depthBracket = 0;
    var depthBrace = 0;
    var i = openIdx + 1;

    while (i < closeIdx) {
      final c = source.codeUnitAt(i);
      if (c == _dquote || c == _squote || c == _backtick) {
        hasToken = true;
        i = _skipString(source, i, c);
        continue;
      }
      if (c == _slash && i + 1 < closeIdx) {
        final next = source.codeUnitAt(i + 1);
        if (next == _slash) {
          final end = source.indexOf('\n', i);
          i = end == -1 || end > closeIdx ? closeIdx : end;
          continue;
        }
        if (next == _star) {
          final end = source.indexOf('*/', i + 2);
          i = end == -1 || end + 2 > closeIdx ? closeIdx : end + 2;
          continue;
        }
        if (_isRegexLiteralStart(source, i)) {
          i = _skipRegexLiteral(source, i);
          continue;
        }
      }
      if (!_isWhitespace(c)) {
        hasToken = true;
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
      } else if (c == _comma &&
          depthParen == 0 &&
          depthBracket == 0 &&
          depthBrace == 0) {
        count++;
      }
      i++;
    }

    if (!hasToken) return 0;
    return count + 1;
  }

  static bool _looksLikeJavaGetResponseChain(String source, int startIdx) {
    final n = source.length;
    var i = startIdx;
    while (i < n && _isWhitespace(source.codeUnitAt(i))) {
      i++;
    }
    if (i >= n || source.codeUnitAt(i) != _dot) return false;
    i++;
    final methodStart = i;
    while (i < n && _isIdentChar(source.codeUnitAt(i))) {
      i++;
    }
    if (i == methodStart) return false;
    final member = source.substring(methodStart, i);
    return _javaGetResponseMembers.contains(member);
  }

  /// [idx] 處的字元能否作為新 identifier 的起始（即前一個字元不是 identifier 字元）
  static bool _isIdentifierStart(String source, int idx) {
    if (idx == 0) return true;
    final prev = source.codeUnitAt(idx - 1);
    return !_isIdentChar(prev);
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

  /// 檢查已寫入 sb 的尾端是否以 `await ` 結尾（word boundary）
  ///
  /// 效能備註：每次呼叫會 toString 一次 sb。對典型 rule JS（<2KB）影響可忽略。
  static bool _sbPrecededByAwait(StringBuffer sb) {
    final buf = sb.toString();
    var j = buf.length - 1;
    while (j >= 0 && _isWhitespace(buf.codeUnitAt(j))) {
      j--;
    }
    if (j < 4) return false;
    if (buf.substring(j - 4, j + 1) != 'await') return false;
    if (j - 5 < 0) return true;
    return !_isIdentChar(buf.codeUnitAt(j - 5));
  }

  static bool _isIdentChar(int cu) {
    return (cu >= _char0 && cu <= _char9) ||
        (cu >= _charUpperA && cu <= _charUpperZ) ||
        (cu >= _charLowerA && cu <= _charLowerZ) ||
        cu == _underscore ||
        cu == _dollar;
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
  static const int _rparen = 0x29;
  static const int _lbracket = 0x5B;
  static const int _rbracket = 0x5D;
  static const int _comma = 0x2C;
  static const int _dot = 0x2E;
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
  static const int _underscore = 0x5F;
  static const int _char0 = 0x30;
  static const int _char9 = 0x39;
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

  static const Set<String> _javaGetResponseMembers = {
    'body',
    'url',
    'statusCode',
    'headers',
  };
}

class _ScanResult {
  const _ScanResult({required this.result, required this.hasAsync});
  final String result;
  final bool hasAsync;
}

class _AsyncCallMatch {
  const _AsyncCallMatch({
    required this.openParenIndex,
    required this.closeParenIndex,
    required this.endIndex,
  });

  final int openParenIndex;
  final int closeParenIndex;
  final int endIndex;
}
