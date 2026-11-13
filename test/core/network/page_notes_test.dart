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

  test('a page that only pops up "wait between searches", or a 429, is the '
      'site limiting requests', () {
    // 2026-11-13 蜘蛛小說網的搜尋（59 字）。
    const interval =
        '<script>alert("搜索间隔: 30 秒");window.history.go(-1);</script>';
    expect(pageNoteOf(interval), '網站限流：「搜索间隔: 30 秒」');
    expect(pageNoteOf('<p>busy</p>', status: 429), contains('網站限流'));
    expect(
      pageNoteOf('<script>alert("请输入关键字");history.go(-1)</script>'),
      isNull,
      reason: '別的提示不是限流',
    );
  });

  test('a search error written in the page, not popped up, is the site '
      'limiting requests too', () {
    // 2026-11-13 肉肉屋（整頁 9282 位元組）與神话之后的搜尋。
    final jieqi =
        '<html><body><div class="nav">${'首页 书库 排行 ' * 60}</div>'
        '<div class="err">出现错误！ 错误原因：对不起，两次搜索的间隔时间不得少于 5 秒'
        ' 请 返 回 并修正</div></body></html>';
    expect(
      pageNoteOf(jieqi),
      allOf(startsWith('網站限流：'), contains('两次搜索的间隔时间不得少于 5 秒')),
    );
    expect(
      rateLimitOf('<p>系统限制的搜索时间间隔为 30 秒,请稍后再搜索</p>'),
      '「系统限制的搜索时间间隔为 30 秒,请稍后再搜索」',
    );
    expect(
      pageNoteOf('<p>他屏住呼吸，間隔三秒才敢再看一眼。</p>'),
      isNull,
      reason: '故事裡的間隔不是限流',
    );
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
