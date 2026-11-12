import 'package:night_reader/core/network/page_digest.dart';

/// 網站回的這一頁不是內容、而是擋在內容前面的東西時，給人與 AI 看的一句
/// 說明；正常的頁面是 null。請求紀錄（`RequestLog`）在每個回應後面接上它，
/// 網站檢查（`judgeSite`）也照它判斷，兩邊認的是同一套。
///
/// 認三種：
/// - **網站限流**（[rateLimitOf]）：狀態碼 429，或短短一頁只跳出「搜索间隔:
///   30 秒」這類提示就返回。
/// - **網站防護頁**（[isProtectionPage]）：要瀏覽器算題目、勾選或答算術題
///   才放行的頁面。
/// - **用程式轉址的頁面**（[scriptRedirectOf]）：短短一頁，有一段改
///   `location` 的程式或 `<meta http-equiv="refresh">`，瀏覽器打開就轉走。
///   精簡網頁會拿掉 `<head>` 與程式，不寫出來的話看精簡後的頁面只看到一片
///   空白或幾個字。
String? pageNoteOf(String body, {int? status}) {
  if (rateLimitOf(body, status: status) case final limit?) {
    return '網站限流：$limit';
  }
  if (isProtectionPage(body)) return '看起來是網站防護頁，要先通過驗證才給內容';
  final target = scriptRedirectOf(body);
  if (target != null) return '這頁用程式轉到 $target';
  return null;
}

/// 網站限流時它說的話：狀態碼 429，或短短一頁只用程式跳出「搜索间隔: 30 秒」
/// 「操作太频繁」這類提示。2026-11-13 蜘蛛小說網的搜尋每 30 秒只能一次、連續
/// 觸發會拉長，回的是 `<script>alert("搜索间隔: 30 秒");history.go(-1)</script>`；
/// 不寫出來，AI 要花好幾輪寫空轉等待的程式才確認。不是限流是 null。
String? rateLimitOf(String body, {int? status}) {
  if (digestPage(body).length < _shortPageLength) {
    for (final match in _alert.allMatches(body)) {
      final text = match.group(1)!.trim();
      if (_tooOften.hasMatch(text)) return '「$text」';
    }
  }
  if (status == 429) return '狀態碼 429（要求太多次）';
  return null;
}

/// `alert("…")` 跳出的那句話。
final RegExp _alert = RegExp(r'''alert\(\s*["']([^"']{1,200})["']''');

/// 要隔一段時間再來的說法。
final RegExp _tooOften = RegExp(
  r'间隔|間隔|频繁|頻繁|太快|过快|過快|稍后再|稍後再|秒后再|秒後再|'
  r'too many requests|rate limit|try again later',
  caseSensitive: false,
);

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
String? scriptRedirectOf(String body) {
  if (!body.trimLeft().startsWith('<')) return null;
  final assign = _locationAssign.firstMatch(body);
  final found = assign != null
      ? assign.group(1) ?? assign.group(2)
      : _metaRefresh.firstMatch(body)?.group(1);
  if (found == null) return null;
  final target = found.trim();
  if (target.isEmpty || target.startsWith('#')) return null;
  if (digestPage(body).length >= _shortPageLength) return null;
  return target;
}

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
