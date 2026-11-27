import 'package:night_reader/core/network/page_digest.dart';

// 網站檢查（`judgeSite`）認首頁是不是防護頁、是不是只有一段轉址程式時用
// 的判斷。AI 修書源讀到的網頁不貼這些標記：頁面是限流、防護還是轉址，交給
// AI 讀了自己判斷（使用者 2026-11-13：要讀頁面才知道的是判斷題，交給 AI）。

/// 要瀏覽器算題目、人工勾選或答題才放行的防護頁。Cloudflare 的五秒盾夜讀
/// 會在背景的瀏覽器裡過（ADR 0033），過不了才會還是這一頁。防搜刮的算術
/// 驗證頁（「防搜刮安全验证」，1659 位元組）只看短的頁面：正常頁面裡剛好有
/// 「安全验证」這類字樣不算。
bool isProtectionPage(String body) {
  if (_challenge.hasMatch(body)) return true;
  return _shortVerification.hasMatch(body) &&
      digestPage(body).length < _shortPageLength;
}

/// 一定是防護頁的字樣：Anubis、Cloudflare 的檢查頁。
final RegExp _challenge = RegExp(
  r'anubis|making sure you(?:&#39;|’|'
  ')re not a bot|正在确认你是不是机器人|'
  r'<title>\s*just a moment|cf-chl-|challenge-platform',
  caseSensitive: false,
);

/// 只有在短的頁面才算防護頁的字樣。
final RegExp _shortVerification = RegExp(
  r'防搜刮|防采集|防採集|安全验证|安全驗證|人机验证|人機驗證|'
  r'请完成验证|請完成驗證|访问验证|訪問驗證',
);

/// 精簡後短於這個字數才算「沒有內容」：防護頁與轉址頁都只有幾行字。
const int _shortPageLength = 1000;

/// 頁面用程式或 `<meta refresh>` 轉去的網址（照頁面上寫的，可能是相對路徑）；
/// 頁面有內容（精簡後 [_shortPageLength] 字以上）或沒有轉址時是 null。
///
/// 程式只認一定會自動跑的：`<script>` 最外層的那一行。寫在函式、區塊、
/// 按鈕的 `onclick`、註解與字串裡的不算——網站檢查會照轉去的網址抓（帶
/// 書源的 Cookie），跟到登出按鈕的網址會把讀者登出。
String? scriptRedirectOf(String body) {
  if (!body.trimLeft().startsWith('<')) return null;
  final page = _scanPage(body);
  final found =
      page.redirect ?? _metaRefresh.firstMatch(page.visible)?.group(1);
  if (found == null) return null;
  final target = found.trim();
  if (target.isEmpty || target.startsWith('#')) return null;
  if (digestPage(body).length >= _shortPageLength) return null;
  return target;
}

/// 整頁由左往右掃一趟：`<script>` 外遇到 `<!--` 整段略過（沒閉合就到檔尾），
/// 遇到 `<script …>` 抽出裡面的程式找最外層轉址（[_topLevelCode]）；回傳的
/// [visible] 是拿掉註解與 `<script>` 區塊後剩下的文字，給 `<meta refresh>`
/// 比對。
({String visible, String? redirect}) _scanPage(String body) {
  final visible = StringBuffer();
  String? redirect;
  var i = 0;
  while (i < body.length) {
    if (body.startsWith('<!--', i)) {
      final end = body.indexOf('-->', i + 4);
      i = end < 0 ? body.length : end + 3;
      continue;
    }
    final open = _scriptTagEnd(body, i);
    if (open == _noTagEnd) {
      // `<script` 後面整頁都沒有 `>`：後面的 `<script` 也都沒有，剩下的
      // 照一般文字，不再一個個往後找。
      visible.write(body.substring(i));
      break;
    }
    if (open >= 0) {
      final close = _indexOfIgnoreCase(body, '</script', open + 1);
      final codeEnd = close < 0 ? body.length : close;
      redirect ??= _topLevelRedirect(body.substring(open + 1, codeEnd));
      if (close < 0) {
        i = body.length;
      } else {
        final tagEnd = body.indexOf('>', close);
        i = tagEnd < 0 ? body.length : tagEnd + 1;
      }
      continue;
    }
    visible.write(body[i]);
    i++;
  }
  return (visible: visible.toString(), redirect: redirect);
}

/// [_scriptTagEnd] 找到 `<script` 但後面整頁都沒有 `>`。
const int _noTagEnd = -2;

/// [i] 是 `<script` 開頭時，傳回這個標籤的 `>` 在哪；不是時是 -1，後面
/// 沒有 `>` 時是 [_noTagEnd]。
int _scriptTagEnd(String body, int i) {
  const name = '<script';
  if (i + name.length > body.length) return -1;
  if (body.substring(i, i + name.length).toLowerCase() != name) return -1;
  final after = i + name.length;
  if (after < body.length && _isWordChar(body[after])) return -1;
  final end = body.indexOf('>', after);
  return end < 0 ? _noTagEnd : end;
}

/// [text] 從 [from] 開始第一次出現 [pattern] 的位置，不分大小寫。
int _indexOfIgnoreCase(String text, String pattern, int from) {
  final last = text.length - pattern.length;
  for (var i = from; i <= last; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (text[i + j].toLowerCase() != pattern[j].toLowerCase()) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

/// [code] 裡最外層的 [_locationAssign] 轉去的網址。
String? _topLevelRedirect(String code) {
  final top = _topLevelCode(code);
  for (final assign in _locationAssign.allMatches(code)) {
    if (top[assign.start]) return assign.group(1) ?? assign.group(2);
  }
  return null;
}

/// [code] 每個位置是不是最外層的程式：不在 `{}` 裡（函式、區塊），也不在
/// 字串、正規表示式與註解（含舊式的 `<!--` 那一行）裡，也不是 `if`、`for`、
/// `while`、`else` 或 `=>` 後面沒加大括號的那一句。
List<bool> _topLevelCode(String code) {
  final top = List<bool>.filled(code.length, false);
  final nested = List<bool>.filled(code.length, false);
  var depth = 0;
  String? quote;
  var lineComment = false;
  var blockComment = false;
  var regex = false;
  var regexClass = false;
  // 上一個有意義的字元：斜線前面是運算子、括號或開頭時是正規表示式。
  String? prev;
  for (var i = 0; i < code.length; i++) {
    final c = code[i];
    final next = i + 1 < code.length ? code[i + 1] : '';
    if (lineComment) {
      if (c == '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (c == '*' && next == '/') {
        blockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
        prev = c;
      }
      continue;
    }
    if (regex) {
      if (c == '\\') {
        i++;
      } else if (regexClass) {
        if (c == ']') regexClass = false;
      } else if (c == '[') {
        regexClass = true;
      } else if (c == '/') {
        regex = false;
        prev = c;
      }
      continue;
    }
    if (c == '/' && next == '/') {
      lineComment = true;
    } else if (c == '/' && next == '*') {
      blockComment = true;
    } else if (c == '<' && code.startsWith('<!--', i)) {
      lineComment = true;
    } else if (c == '/' && (prev == null || _beforeRegex.contains(prev))) {
      regex = true;
    } else if (c == '"' || c == "'" || c == '`') {
      quote = c;
    } else if (c == '{') {
      depth++;
      prev = c;
    } else if (c == '}') {
      if (depth > 0) depth--;
      prev = c;
    } else {
      final atTop = depth == 0;
      top[i] = atTop;
      if (c.trim().isNotEmpty) prev = c;
      if (!atTop) continue;
      if (c == '=' && next == '>') {
        final body = _skipSpace(code, i + 2);
        if (body < code.length && code[body] != '{') {
          _markNested(nested, body, _statementEnd(code, body));
        }
      } else if (_isWordStart(c) &&
          (i == 0 || (!_isWordChar(code[i - 1]) && code[i - 1] != '.'))) {
        final word = _wordAt(code, i);
        final after = i + word.length;
        if (after < code.length && _isWordChar(code[after])) continue;
        if (word == 'if' || word == 'for' || word == 'while') {
          _markControlBody(code, nested, after);
        } else if (word == 'else') {
          final body = _skipSpace(code, after);
          if (body < code.length &&
              code[body] != '{' &&
              !_keywordAt(code, body, 'if')) {
            _markNested(nested, body, _statementEnd(code, body));
          }
        }
      }
    }
  }
  for (var i = 0; i < top.length; i++) {
    if (nested[i]) top[i] = false;
  }
  return top;
}

/// 控制關鍵字後面的那一句：沒有 `{` 時整句不算最外層。
void _markControlBody(String code, List<bool> nested, int afterWord) {
  final paren = _skipSpace(code, afterWord);
  if (paren >= code.length || code[paren] != '(') return;
  final end = _afterBalanced(code, paren);
  if (end >= code.length) return;
  final body = _skipSpace(code, end);
  if (body < code.length && code[body] != '{') {
    _markNested(nested, body, _statementEnd(code, body));
  }
}

void _markNested(List<bool> nested, int from, int to) {
  for (var i = from; i < to && i < nested.length; i++) {
    nested[i] = true;
  }
}

/// 從 [start] 開始的那一句到哪裡結束（不含）：一句到 `;`，沒有分號時到行
/// 尾；`if` 後面接的 `else` 也算同一句。
int _statementEnd(String code, int start) {
  var i = _skipSpace(code, start);
  if (i >= code.length) return code.length;
  if (code[i] == '{') return _afterBalanced(code, i);
  if (_keywordAt(code, i, 'if')) {
    final paren = _skipSpace(code, i + 2);
    if (paren < code.length && code[paren] == '(') {
      var end = _statementEnd(code, _afterBalanced(code, paren));
      final after = _skipSpace(code, end);
      if (_keywordAt(code, after, 'else')) {
        end = _statementEnd(code, after + 4);
      }
      return end;
    }
  }
  if (_keywordAt(code, i, 'for')) {
    final paren = _skipSpace(code, i + 3);
    if (paren < code.length && code[paren] == '(') {
      return _statementEnd(code, _afterBalanced(code, paren));
    }
  }
  if (_keywordAt(code, i, 'while')) {
    final paren = _skipSpace(code, i + 5);
    if (paren < code.length && code[paren] == '(') {
      return _statementEnd(code, _afterBalanced(code, paren));
    }
  }
  return _simpleStatementEnd(code, i);
}

/// 不算控制結構的一般陳述句：到 `;`，沒有分號時到括號外的行尾。
int _simpleStatementEnd(String code, int start) {
  var paren = 0;
  var brace = 0;
  var bracket = 0;
  String? quote;
  var lineComment = false;
  var blockComment = false;
  var regex = false;
  var regexClass = false;
  String? prev;
  var i = start;
  bool atDepth0() => paren == 0 && brace == 0 && bracket == 0;
  while (i < code.length) {
    final c = code[i];
    final next = i + 1 < code.length ? code[i + 1] : '';
    if (lineComment) {
      if (c == '\n') {
        if (atDepth0()) return i + 1;
        lineComment = false;
      }
      i++;
      continue;
    }
    if (blockComment) {
      if (c == '*' && next == '/') {
        blockComment = false;
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (c == '\\') {
        i += 2;
      } else {
        if (c == quote) quote = null;
        i++;
      }
      continue;
    }
    if (regex) {
      if (c == '\\') {
        i += 2;
      } else {
        if (regexClass) {
          if (c == ']') regexClass = false;
        } else if (c == '[') {
          regexClass = true;
        } else if (c == '/') {
          regex = false;
          prev = c;
        }
        i++;
      }
      continue;
    }
    if (c == '\n' && atDepth0()) return i + 1;
    if (c == ';' && atDepth0()) return i + 1;
    if (c == '/' && next == '/') {
      lineComment = true;
      i += 2;
      continue;
    }
    if (c == '/' && next == '*') {
      blockComment = true;
      i += 2;
      continue;
    }
    if (c == '<' && code.startsWith('<!--', i)) {
      lineComment = true;
      i += 4;
      continue;
    }
    if (c == '/' && (prev == null || _beforeRegex.contains(prev))) {
      regex = true;
      i++;
      continue;
    }
    switch (c) {
      case '"' || "'" || '`':
        quote = c;
      case '(':
        paren++;
      case ')':
        if (paren > 0) paren--;
      case '{':
        brace++;
      case '}':
        if (brace > 0) brace--;
      case '[':
        bracket++;
      case ']':
        if (bracket > 0) bracket--;
    }
    if (c.trim().isNotEmpty) prev = c;
    i++;
  }
  return code.length;
}

/// [open] 是 `(`、`{` 或 `[`，傳回配對的那個字元後面的位置；沒有配對時是
/// [code] 的長度。
int _afterBalanced(String code, int open) {
  final opener = code[open];
  final closer = switch (opener) {
    '(' => ')',
    '{' => '}',
    '[' => ']',
    _ => '',
  };
  if (closer.isEmpty) return open + 1;
  var depth = 0;
  String? quote;
  var lineComment = false;
  var blockComment = false;
  var regex = false;
  var regexClass = false;
  String? prev;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    final next = i + 1 < code.length ? code[i + 1] : '';
    if (lineComment) {
      if (c == '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (c == '*' && next == '/') {
        blockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
        prev = c;
      }
      continue;
    }
    if (regex) {
      if (c == '\\') {
        i++;
      } else if (regexClass) {
        if (c == ']') regexClass = false;
      } else if (c == '[') {
        regexClass = true;
      } else if (c == '/') {
        regex = false;
        prev = c;
      }
      continue;
    }
    if (c == '/' && next == '/') {
      lineComment = true;
    } else if (c == '/' && next == '*') {
      blockComment = true;
    } else if (c == '<' && code.startsWith('<!--', i)) {
      lineComment = true;
    } else if (c == '/' && (prev == null || _beforeRegex.contains(prev))) {
      regex = true;
    } else if (c == '"' || c == "'" || c == '`') {
      quote = c;
    } else if (c == opener) {
      depth++;
      prev = c;
    } else if (c == closer) {
      if (--depth == 0) return i + 1;
      prev = c;
    } else if (c.trim().isNotEmpty) {
      prev = c;
    }
  }
  return code.length;
}

int _skipSpace(String code, int i) {
  while (i < code.length && code[i].trim().isEmpty) {
    i++;
  }
  return i;
}

String _wordAt(String code, int start) {
  var end = start;
  while (end < code.length && _isWordChar(code[end])) {
    end++;
  }
  return code.substring(start, end);
}

bool _keywordAt(String code, int i, String word) {
  if (i < 0 || i + word.length > code.length) return false;
  if (code.substring(i, i + word.length) != word) return false;
  if (i > 0 && (_isWordChar(code[i - 1]) || code[i - 1] == '.')) return false;
  final end = i + word.length;
  return end >= code.length || !_isWordChar(code[end]);
}

bool _isWordStart(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
}

bool _isWordChar(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      code == 0x5f ||
      code == 0x24;
}

/// 斜線前面是這些字元時是正規表示式，不是除號。
const String _beforeRegex = '(,=:[!&|?{};+-*%<>~^';

/// `location.href = "…"`、`window.location = '…'`、`location.replace("…")`
/// 這類。
final RegExp _locationAssign = RegExp(
  r'''location(?:\.href)?\s*=\s*["']([^"']+)["']|'''
  r'''location\.(?:replace|assign)\(\s*["']([^"']+)["']''',
);

/// `<meta http-equiv="refresh" content="0;url=…">`。
final RegExp _metaRefresh = RegExp(
  r'''<meta[^>]+http-equiv=["']?refresh["']?[^>]*content=["']?\s*\d+\s*;\s*url=([^"'>\s]+)''',
  caseSensitive: false,
);
