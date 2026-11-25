import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 規則 JS 裡的 Java 物件照 Legado（Rhino 與 `JsExtensions`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  final skip = quickJsUnavailableReason();

  String run(String js) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://site.test'))
          .setContent('<p>x</p>', baseUrl: 'https://site.test/')
          .getString('@js:$js', unescape: false);

  test('importPackage(java.lang) 不蓋掉 JS 的 String', () {
    expect(
      run(
        'importPackage(Packages.java.lang); var r = "正文"; '
        'String(r) + String.fromCharCode(20013)',
      ),
      '正文中',
    );
  }, skip: skip);

  test('new java.lang.String(位元組, 編碼) 照給的編碼解', () {
    expect(
      run(
        "String(new Packages.java.lang.String("
        "java.strToBytes('中文', 'UTF-16LE'), 'UTF-16LE'))",
      ),
      '中文',
    );
    expect(
      run(
        "String(new Packages.java.lang.String(java.strToBytes('中文', 'GBK'), 'GBK'))",
      ),
      '中文',
    );
    expect(
      run("String(new Packages.java.lang.String(java.strToBytes('中文')))"),
      '中文',
    );
  }, skip: skip);

  test('queryTTF 交回的字型查得到輪廓與字碼', () {
    final font = base64Encode(
      File('test/fixtures/fonts/mixed_width_test.ttf').readAsBytesSync(),
    );
    expect(
      run('''
        var f = java.queryTTF("$font");
        var code = 0x41;
        var glyf = f.getGlyfByUnicode(code);
        [glyf != null, f.getGlyfByUnicode(f.getUnicodeByGlyf(glyf)) == glyf,
          f.getGlyfIdByUnicode(code) > 0,
          f.getGlyfById(f.getGlyfIdByUnicode(code)) == glyf,
          f.isBlankUnicode(0x20)].join(",")
      '''),
      'true,true,true,true,true',
    );
  }, skip: skip);

  test('setContent 交 Jsoup 的網頁，後面的規則照它解析', () {
    expect(
      run(
        "java.setContent(org.jsoup.Jsoup.parse('<p>第一章</p>')); "
        "java.getString('@css:p@text')",
      ),
      '第一章',
    );
    expect(
      run(
        "java.setContent(org.jsoup.Jsoup.parse('<div><p>第二章</p></div>').selectFirst('div')); "
        "java.getString('@css:p@text')",
      ),
      '第二章',
    );
    expect(
      run("java.setContent('{\"a\":\"甲\"}'); java.getString('\$.a')"),
      '甲',
    );
  }, skip: skip);

  group('Jsoup', () {
    test('文字節點的 outerHtml 把字面的標記寫回實體', () {
      expect(
        run(
          "org.jsoup.Jsoup.parse('<p>&lt;b&gt;第一章&lt;/b&gt; &amp;</p>')"
          ".selectFirst('p').childNode(0).outerHtml()",
        ),
        '&lt;b&gt;第一章&lt;/b&gt; &amp;',
      );
      expect(
        run(
          "String(org.jsoup.Jsoup.parse('<p>a&lt;b</p>').selectFirst('p').childNode(0))",
        ),
        'a&lt;b',
      );
      expect(
        run(
          "org.jsoup.Jsoup.parse('<script>if(a<b){}</script>')"
          ".selectFirst('script').childNode(0).outerHtml()",
        ),
        'if(a<b){}',
      );
    }, skip: skip);

    test('正文規則逐個取文字節點組回正文，網站寫出的標記照樣看得到', () async {
      final source = BookSource.fromJson({
        'bookSourceName': '字面標記',
        'bookSourceUrl': 'https://site.test',
        'ruleContent': {
          'content': "@js:org.jsoup.Jsoup.parse(result).selectFirst('p').childNode(0).outerHtml()",
        },
      });
      final parsed = await ContentParser.parse(
        source: source,
        body: '<p>&lt;b&gt;第一章&lt;/b&gt;</p>',
        baseUrl: 'https://site.test/1',
      );
      expect(parsed.content, contains('<b>第一章</b>'));
    }, skip: skip);

    test('location() 是解析時給的頁面網址，不是 <base href>', () {
      expect(
        run(
          "var d = org.jsoup.Jsoup.parse('<base href=\"https://cdn.test/assets/\"><a href=\"x\">a</a>',"
          " 'https://site.test/chapter/1');"
          "d.location() + '|' + d.baseUri() + '|' + d.selectFirst('a').attr('abs:href')",
        ),
        'https://site.test/chapter/1|https://cdn.test/assets/|https://cdn.test/assets/x',
      );
    }, skip: skip);

    test('空的文件 body()、head() 會補上，可以接著寫內容', () {
      expect(
        run(
          "var d = new org.jsoup.nodes.Document('https://site.test/');"
          "d.body().append('<p>正文</p>'); d.head().append('<title>t</title>');"
          "d.body().text() + '|' + d.title() + '|' + d.location()",
        ),
        '正文|t|https://site.test/',
      );
    }, skip: skip);
  });
}
