import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/page_notes.dart';

/// 防搜刮的算術驗證頁（2026-11-12 話本小說的搜尋，1659 位元組）的樣子。
const _mathCheck =
    '<html><head><title>安全验证</title></head><body>'
    '<h3>防搜刮安全验证</h3><div class="q">请计算 3 + 4 = ?</div>'
    '<form method="post"><input name="answer"><button>提交</button></form>'
    '<script>document.cookie="search_pass=0"</script></body></html>';

/// 網站檢查認首頁用的兩個判斷（`judgeSite`）。
void main() {
  test('the anti-scraping arithmetic check and browser checks are '
      'protection pages', () {
    expect(isProtectionPage(_mathCheck), isTrue);
    expect(isProtectionPage('<title>Just a moment...</title>'), isTrue);
  });

  test('a long page that happens to mention a security check is content', () {
    final article =
        '<html><body><div class="txt">'
        '${'第一章 他在安全验证的窗口前停了很久。' * 80}</div></body></html>';
    expect(isProtectionPage(article), isFalse);
  });

  test('a short page that sends the browser elsewhere by script '
      'says where it goes', () {
    for (final (body, target) in [
      (
        '<html><head><script>window.location.href="/lander?d=x"</script>'
            '</head><body></body></html>',
        '/lander?d=x',
      ),
      (
        "<script>location.replace('https://new.example/')</script>",
        'https://new.example/',
      ),
      (
        "<SCRIPT>function go(){} // 舊的\nlocation.href='/new/';</SCRIPT>",
        '/new/',
      ),
      // 正規表示式裡的引號、斜線不是字串與註解。
      (
        "<script>var a = s.replace(/'/g, '').replace(/\"/g, '');"
            "location.href='/new/';</script>",
        '/new/',
      ),
      (
        "<script>if (/^https?:\\/\\//.test(u)) {} location.href='/new/';"
            '</script>',
        '/new/',
      ),
      // 舊式的 `<!--` 只遮掉那一行。
      ("<script><!--\nlocation.href='/new/';\n//--></script>", '/new/'),
      (
        '<html><head><meta http-equiv="refresh" '
            'content="0; url=https://new.example/home"></head></html>',
        'https://new.example/home',
      ),
    ]) {
      expect(scriptRedirectOf(body), target, reason: body);
    }
  });

  // 只跟著一定會自動發生的轉址：網站檢查會照轉去的網址抓（帶書源的
  // Cookie），跟到登出按鈕的網址會把讀者登出。
  test('an address in a function, a click handler, a comment or a string '
      'is not a redirect', () {
    for (final body in [
      '<button onclick="logout()">登出</button>'
          "<script>function logout(){location.href='/logout';}</script>",
      '<button onclick="location.href=\'/logout\'">登出</button>',
      "<script>// location.href='/old'\n</script>",
      "<script>/* location.replace('/old') */</script>",
      '<script>var tip = "location.href=\'/old\'";</script>',
      "<script>if (a) { location.href='/m/'; }</script>",
    ]) {
      expect(scriptRedirectOf(body), isNull, reason: body);
    }
  });

  test('a page with content keeps its script redirects to itself', () {
    final page =
        '<html><body><script>if (x) location.href="/m/"</script>'
        '<div class="list">${'<a href="/b/1">一本書的書名</a>' * 100}</div>'
        '</body></html>';
    expect(scriptRedirectOf(page), isNull);
  });
}
