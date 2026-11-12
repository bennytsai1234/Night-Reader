import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/page_notes.dart';

/// 防搜刮的算術驗證頁（2026-11-12 話本小說的搜尋，1659 位元組）的樣子。
const _mathCheck =
    '<html><head><title>安全验证</title></head><body>'
    '<h3>防搜刮安全验证</h3><div class="q">请计算 3 + 4 = ?</div>'
    '<form method="post"><input name="answer"><button>提交</button></form>'
    '<script>document.cookie="search_pass=0"</script></body></html>';

void main() {
  test('the anti-scraping arithmetic check and browser checks are '
      'protection pages', () {
    expect(isProtectionPage(_mathCheck), isTrue);
    expect(isProtectionPage('<title>Just a moment...</title>'), isTrue);
    expect(pageNoteOf(_mathCheck), contains('網站防護頁'));
  });

  test('a long page that happens to mention a security check is content', () {
    final article =
        '<html><body><div class="txt">'
        '${'第一章 他在安全验证的窗口前停了很久。' * 80}</div></body></html>';
    expect(isProtectionPage(article), isFalse);
    expect(pageNoteOf(article), isNull);
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
        '<html><head><meta http-equiv="refresh" '
            'content="0; url=https://new.example/home"></head></html>',
        'https://new.example/home',
      ),
    ]) {
      expect(scriptRedirectOf(body), target, reason: body);
      expect(pageNoteOf(body), '這頁用程式轉到 $target');
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
