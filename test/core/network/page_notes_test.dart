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

  // 註解裡的程式與轉址都不會執行；網站檢查跟過去會把讀者帶到登出之類的網址。
  test('a redirect written in an HTML comment is not a redirect', () {
    for (final body in [
      '<html><body><!-- <script>location.href="/logout"</script> -->'
          '</body></html>',
      '<html><body><!-- <meta http-equiv="refresh" '
          'content="0; url=/logout"> --></body></html>',
    ]) {
      expect(scriptRedirectOf(body), isNull, reason: body);
    }
  });

  // 沒有大括號的 if／else／for／while 只跑條件成立的那一句，不是一定會跑的
  // 最外層轉址。
  test(
    'a redirect in a control statement without braces is not a redirect',
    () {
      for (final body in [
        "<script>if (a) location.href='/m/';</script>",
        "<script>if (a) location.href='/m/'; else location.href='/logout';"
            '</script>',
        "<script>for (var i = 0; i < 1; i++) location.href='/m/';</script>",
        "<script>while (a) location.href='/m/';</script>",
        "<script>if (a) if (b) location.href='/m/';</script>",
        "<script>if (a) {} else if (b) location.href='/m/';</script>",
        // 條件裡的巢狀括號、字串、正則與註解要配對。
        "<script>if (f(')') && /x/.test(a)) location.href='/m/';</script>",
        "<script>if (a /* ) */) location.href='/m/';</script>",
      ]) {
        expect(scriptRedirectOf(body), isNull, reason: body);
      }
    },
  );

  test('a redirect in an arrow callback without braces is not a redirect', () {
    for (final body in [
      "<script>btn.onclick = () => location.href='/logout';</script>",
      "<script>btn.onclick = () =>\n location.href='/logout';</script>",
    ]) {
      expect(scriptRedirectOf(body), isNull, reason: body);
    }
  });

  test('a meta refresh written in a script string is not a redirect', () {
    final body =
        '<script>var html = \'<meta http-equiv="refresh" '
        'content="0; url=/logout">\';</script>';
    expect(scriptRedirectOf(body), isNull);
  });

  test('a top-level redirect after those is still a redirect', () {
    const body =
        "<script>btn.onclick = () => location.href='/logout';\n"
        "if (a) location.href='/m/';\n"
        "location.href='/new/';</script>";
    expect(scriptRedirectOf(body), '/new/');
    const afterComment =
        '<html><body><!-- <meta http-equiv="refresh" '
        'content="0; url=/old"> -->'
        '<meta http-equiv="refresh" content="0; url=/new/"></body></html>';
    expect(scriptRedirectOf(afterComment), '/new/');
  });

  test('a page full of unclosed <script is scanned once', () {
    final body = '<html>${'<script' * 40000}';
    final watch = Stopwatch()..start();
    expect(scriptRedirectOf(body), isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('a page with content keeps its script redirects to itself', () {
    final page =
        '<html><body><script>if (x) location.href="/m/"</script>'
        '<div class="list">${'<a href="/b/1">一本書的書名</a>' * 100}</div>'
        '</body></html>';
    expect(scriptRedirectOf(page), isNull);
  });
}
