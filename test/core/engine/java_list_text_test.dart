import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 規則 JS 拿到的清單是 Java 的 List（Legado 的 `result`、`java.getStringList`、
/// `new ArrayList()`、Jsoup 的 `eachText()`），轉成文字是 `[a, b]`、空的是
/// `[]`；不是 JS 陣列的 `a,b` 與空字串。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(String html) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://m.test'))
          .setContent(html, baseUrl: 'https://m.test/book/a.html');

  // 書源的目錄下一頁：先取「尾页」連結裡的總頁數，再組出第 2 頁到最後一頁。
  const nextTocUrl =
      'text.尾页@href##.*\\_(\\d+)\\.html##\$1\n'
      '@js:\n'
      'res = JSON.parse(result)\n'
      'list = [];\n'
      'for (var i = 2; i <= res; i++) {\n'
      '\tlist.push(baseUrl.replace(/\\.html/,"_" + i + ".html"));\n'
      '}\n'
      'list;';

  test('目錄只有一頁、沒有尾頁連結時沒有下一頁，不是解析失敗', () {
    expect(rule('<p>x</p>').getStringList(nextTocUrl, isUrl: true), isEmpty);
    expect(
      rule('<a href="/book/a_3.html">尾页</a>')
          .getStringList(nextTocUrl, isUrl: true),
      ['https://m.test/book/a_2.html', 'https://m.test/book/a_3.html'],
    );
  });

  test('上一段交來的清單轉成文字照 Java', () {
    const html = '<a href="/x">a</a><a href="/y">b</a>';
    expect(rule(html).getStringList('a@href\n@js:String(result)'), [
      '[/x, /y]',
    ]);
    expect(rule(html).getStringList('p@text\n@js:"" + result'), ['[]']);
    // 方法不是可列舉的鍵：for-in 只走過每一項。
    expect(
      rule(html).getStringList(
        'a@href\n@js:var keys = []; for (var k in result) keys.push(k); keys.join()',
      ),
      ['0,1'],
    );
  });

  test('規則 JS 自己拿到或建立的清單轉成文字照 Java', () {
    const html = '<p>甲</p><p>乙</p>';
    String js(String code) => rule(html).getString('@js:$code');
    expect(js('String(java.getStringList("p@text"))'), '[甲, 乙]');
    expect(
      js(
        'var l = new Packages.java.util.ArrayList(); l.add("a"); l.add(1); String(l)',
      ),
      '[a, 1]',
    );
    expect(js('String(new Packages.java.util.HashSet())'), '[]');
    expect(
      js(
        'String(org.jsoup.Jsoup.parse("<b>一</b><b>二</b>").select("b").eachText())',
      ),
      '[一, 二]',
    );
    expect(
      js(
        'String(org.jsoup.Jsoup.parse("<p x=1 y=2>a</p>").select("p").first().attributes().asList())',
      ),
      '[x="1", y="2"]',
    );
  });

  test('Jsoup 請求的集合轉成文字照 Java', () {
    String js(String code) => rule('<p>x</p>').getString(
      '@js:var r = org.jsoup.Jsoup.connect("https://unused.test").request(); $code',
    );
    expect(
      js(
        '[r.cookies().keySet(), r.cookies().values(), r.headers("missing"), r.data()].map(String).join("|")',
      ),
      '[]|[]|[]|[]',
    );
    expect(
      js(
        'r.header("X", "a"); r.cookie("c", "1"); '
        '[r.cookies().keySet(), r.headers("X"), r.multiHeaders().get("X"), r.cookies().values()].map(String).join("|")',
      ),
      '[c]|[a]|[a]|[1]',
    );
  });

  test('上一段規則 JS 交回的陣列還是 JS 陣列，轉成文字照 JS', () {
    List<String> run(String rules) => rule('<p>x</p>').getStringList(rules);
    expect(run('<js>["a","b"]</js><js>String(result)</js>'), ['a,b']);
    expect(run('<js>[]</js><js>"X" + result + "Y"</js>'), ['XY']);
    expect(run('<js>["https://unused.test/a"]</js><js>"" + result</js>'), [
      'https://unused.test/a',
    ]);
  });

  test('Java List 的 get 超出範圍照 Java 丟出例外', () {
    String js(String code) => rule('<p>甲</p><p>乙</p>').getString('@js:$code');
    expect(
      js(
        'var l = java.getStringList("p@text"); '
        'var out = []; [-1, 2].forEach(function(i) { '
        'try { l.get(i); out.push("no"); } catch (e) { out.push(/IndexOutOfBounds/.test(String(e))); } '
        '}); out.join() + "|" + l.get(1)',
      ),
      'true,true|乙',
    );
  });
}
