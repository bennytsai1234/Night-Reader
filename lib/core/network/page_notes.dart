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
  final found =
      _topLevelRedirect(body) ?? _metaRefresh.firstMatch(body)?.group(1);
  if (found == null) return null;
  final target = found.trim();
  if (target.isEmpty || target.startsWith('#')) return null;
  if (digestPage(body).length >= _shortPageLength) return null;
  return target;
}

/// 頁面裡 `<script>` 最外層的 [_locationAssign] 轉去的網址。
String? _topLevelRedirect(String body) {
  for (final script in _inlineScript.allMatches(body)) {
    final code = script.group(1)!;
    final top = _topLevelCode(code);
    for (final assign in _locationAssign.allMatches(code)) {
      if (top[assign.start]) return assign.group(1) ?? assign.group(2);
    }
  }
  return null;
}

/// `<script>` 裡的程式（HTML 標籤不分大小寫）。
final RegExp _inlineScript = RegExp(
  r'<script\b[^>]*>([\s\S]*?)</script\s*>',
  caseSensitive: false,
);

/// [code] 每個位置是不是最外層的程式：不在 `{}` 裡（函式、區塊），也不在
/// 字串、正規表示式與註解（含舊式的 `<!--` 那一行）裡。
List<bool> _topLevelCode(String code) {
  final top = List<bool>.filled(code.length, false);
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
      top[i] = depth == 0;
      if (c.trim().isNotEmpty) prev = c;
    }
  }
  return top;
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
