import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/rule_data_interface.dart';
import 'package:night_reader/core/services/cookie_store.dart';

import '../../test_helper.dart';

class MockRuleData extends RuleDataInterface {
  @override
  final Map<String, String> variableMap = {};

  @override
  String getVariable(String key) => variableMap[key] ?? '';

  @override
  void putVariable(String key, String? value) {
    if (value == null) {
      variableMap.remove(key);
    } else {
      variableMap[key] = value;
    }
  }
}

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('AnalyzeRule Tests', () {
    const htmlStr = '''
    <html>
      <body>
        <div class="title">Test Title</div>
        <div class="content">Test Content</div>
        <a class="link" href="/book/1">Book 1</a>
        <div class="links">
          <a href="/chapter/1">Chapter 1</a>
          <a href="/chapter/2">Chapter 2</a>
        </div>
      </body>
    </html>
    ''';

    const jsonStr = '''
    {
      "title": "JSON Title",
      "content": "JSON Content"
    }
    ''';

    test('Routing to CSS parser', () {
      final analyzer = AnalyzeRule().setContent(htmlStr);
      expect(analyzer.getString('.title@text'), 'Test Title');
    });

    test(
      'Default CSS string mode joins multiple matches while isUrl keeps first match',
      () async {
        final analyzer = AnalyzeRule().setContent('''
          <div id="article">
            <p>第一段</p>
            <p>第二段</p>
          </div>
          <div class="links">
            <a href="/chapter/1">第一章</a>
            <a href="/chapter/2">第二章</a>
          </div>
          ''', baseUrl: 'https://example.com/book/1');

        expect(analyzer.getString('#article@p@textNodes'), '第一段\n第二段');
        expect(
          await analyzer.getStringAsync('#article@p@textNodes'),
          '第一段\n第二段',
        );
        expect(
          analyzer.getString('.links@tag.a@href', isUrl: true),
          'https://example.com/chapter/1',
        );
      },
    );

    test('Routing to JsonPath parser', () {
      final analyzer = AnalyzeRule().setContent(jsonStr);
      expect(analyzer.getString(r'$.title'), 'JSON Title');
    });

    test(
      'Default mode falls back to bare JSON field paths and wildcard lists',
      () {
        final analyzer = AnalyzeRule().setContent({
          'title': 'Bare Title',
          'meta': {'author': 'Bare Author'},
        });
        final listAnalyzer = AnalyzeRule().setContent([
          {'name': 'Book A'},
          {'name': 'Book B'},
        ]);

        expect(analyzer.getString('title'), 'Bare Title');
        expect(analyzer.getString('meta.author'), 'Bare Author');
        expect(
          analyzer.getString('title&&meta.author'),
          'Bare Title\nBare Author',
        );
        expect(listAnalyzer.getElements('*'), hasLength(2));
      },
    );

    test(
      'getElementAsync preserves raw JSON object results for init-style rules',
      () async {
        final analyzer = AnalyzeRule().setContent({
          'body': {
            'bookinfo': {'book': 86730, 'v_book': '示例書名'},
          },
        });

        final result = await analyzer.getElementAsync(r'$.body.bookinfo');

        expect(result, isA<Map>());
        expect((result as Map)['book'], 86730);
        expect(result['v_book'], '示例書名');
      },
    );

    test('Routing to XPath parser', () {
      final analyzer = AnalyzeRule().setContent(htmlStr);
      expect(analyzer.getString('//div[@class="title"]/text()'), 'Test Title');
    });

    test('Prefix override @Json:', () {
      // Force JSON mode even if content looks like HTML (though this content IS JSON)
      final analyzer = AnalyzeRule().setContent(jsonStr);
      expect(analyzer.getString(r'@Json:$.title'), 'JSON Title');
    });

    test('Prefix override is case-insensitive and supports @css:', () {
      final htmlAnalyzer = AnalyzeRule().setContent(htmlStr);
      expect(htmlAnalyzer.getString('@css:.title@text'), 'Test Title');
      expect(
        htmlAnalyzer.getString('@XPath://div[@class="title"]/text()'),
        'Test Title',
      );

      final jsonAnalyzer = AnalyzeRule().setContent(jsonStr);
      expect(jsonAnalyzer.getString(r'@json:$.title'), 'JSON Title');
    });

    test('@@ forces default mode', () {
      final analyzer = AnalyzeRule().setContent(htmlStr);
      expect(analyzer.getString('@@.title@text'), 'Test Title');
    });

    test('Regex replacement ##', () {
      final analyzer = AnalyzeRule().setContent(htmlStr);
      // Replace Title with Header
      expect(analyzer.getString('.title@text##Title##Header'), 'Test Header');
    });

    test('Regex replacement ### only replaces first match', () {
      final analyzer = AnalyzeRule().setContent(
        '<div class="title">Title Title</div>',
      );
      expect(
        analyzer.getString('.title@text##Title##Header###'),
        'Header Title',
      );
    });

    test('Variables @get and put', () {
      final mockData = MockRuleData();
      final analyzer = AnalyzeRule(ruleData: mockData).setContent(htmlStr);

      analyzer.put('myVar', 'Hello');
      expect(analyzer.getString('@get:{myVar}'), 'Hello');

      // Test embedded in rule
      expect(analyzer.getString('Prefix: @get:{myVar}'), 'Prefix: Hello');
    });

    test('transient variables work without ruleData or source storage', () {
      final analyzer = AnalyzeRule().setContent(htmlStr);

      analyzer.put('tempVar', 'Hello');

      expect(analyzer.get('tempVar'), 'Hello');
      expect(analyzer.getString('@get:{tempVar}'), 'Hello');
    });

    test(
      'java.put values survive across analyze rules for the same source',
      () {
        final source = BookSource(
          bookSourceUrl: 'https://example.com/source',
          bookSourceName: 'Shared Scope Source',
        );

        final writer = AnalyzeRule(source: source).setContent(htmlStr);
        final reader = AnalyzeRule(source: source).setContent(htmlStr);

        expect(
          writer.evalJS(
            'java.put("headers", "{\\"headers\\":{\\"X-Test\\":\\"1\\"}}")',
            null,
          ),
          isNotNull,
        );
        expect(
          reader.evalJS('java.get("headers")', null),
          '{"headers":{"X-Test":"1"}}',
        );
      },
      skip: quickJsSkip,
    );

    test(
      'java.getElements exposes parsed element lists to rule js',
      () {
        final analyzer = AnalyzeRule().setContent(htmlStr);

        expect(
          analyzer.evalJS('java.getElements(".links@tag.a").join("|")', null),
          '<a href="/chapter/1">Chapter 1</a>|<a href="/chapter/2">Chapter 2</a>',
        );
      },
      skip: quickJsSkip,
    );

    test('@put runs before rule evaluation in getString', () {
      final analyzer = AnalyzeRule(
        ruleData: MockRuleData(),
      ).setContent(htmlStr);
      final value = analyzer.getString(
        '@put:{"myVar":"@css:.title@text"}Prefix: @get:{myVar}',
      );

      expect(value, 'Prefix: Test Title');
      expect(analyzer.get('myVar'), 'Test Title');
    });

    test('Rule-like content in {{}} is resolved as rule instead of JS', () {
      final analyzer = AnalyzeRule().setContent(jsonStr);
      expect(analyzer.getString(r'{{$.title}}'), 'JSON Title');
    });

    test('isUrl=true resolves relative url to absolute url', () {
      final analyzer = AnalyzeRule().setContent(
        htmlStr,
        baseUrl: 'https://example.com/search?q=test',
      );

      expect(
        analyzer.getString('.link@href', isUrl: true),
        'https://example.com/book/1',
      );
    });

    test('isUrl=true prefers redirectUrl over baseUrl', () {
      final analyzer =
          AnalyzeRule()
            ..setContent(htmlStr, baseUrl: 'https://example.com/search?q=test')
            ..setRedirectUrl('https://cdn.example.net/results/list.html');

      expect(
        analyzer.getString('.link@href', isUrl: true),
        'https://cdn.example.net/book/1',
      );
    });

    test(
      'isUrl=true preserves analyzeUrl option suffix for js-generated relative urls',
      () async {
        final analyzer = AnalyzeRule().setContent(
          htmlStr,
          baseUrl: 'https://api-bc.wtzw.com/api/v5/search/words',
        );

        final result = await analyzer.getStringAsync(
          '''@js:"/api/v4/book/detail?id=1,{\\"headers\\":{\\"X-Test\\":\\"1\\"}}"''',
          isUrl: true,
        );

        expect(
          result,
          'https://api-bc.wtzw.com/api/v4/book/detail?id=1,{"headers":{"X-Test":"1"}}',
        );
      },
      skip: quickJsSkip,
    );

    test(
      'dynamic map-backed url strings return assembled values instead of xpath parsing',
      () async {
        final analyzer = AnalyzeRule().setContent({'bookId': '47749'});

        expect(
          analyzer.getString(r'/books?bookId={$.bookId}'),
          '/books?bookId=47749',
        );
        expect(
          await analyzer.getStringAsync(r'/books?bookId={$.bookId}'),
          '/books?bookId=47749',
        );
      },
    );

    test(
      'dynamic map-backed js rules still execute instead of returning raw code',
      () async {
        final analyzer = AnalyzeRule().setContent({'id': '47749'});

        expect(
          analyzer.getString(r'@js:"/books?bookId={{$.id}}"'),
          '/books?bookId=47749',
        );
        expect(
          await analyzer.getStringAsync(r'@js:"/books?bookId={{$.id}}"'),
          '/books?bookId=47749',
        );
      },
      skip: quickJsSkip,
    );

    test(
      'isUrl=true treats analyzeUrl-style literal paths as urls instead of xpath',
      () async {
        final analyzer = AnalyzeRule().setContent(
          '<html></html>',
          baseUrl: 'https://ixdzs8.com/read/17047/',
        );

        final result = await analyzer.getStringAsync(
          r'''/novel/clist/,{"body":"bid={{baseUrl.match(/(\d+).$/)[1]}}","method":"POST"}''',
          isUrl: true,
        );

        expect(
          result,
          'https://ixdzs8.com/novel/clist/,{"body":"bid=17047","method":"POST"}',
        );
      },
      skip: quickJsSkip,
    );

    test(
      'getStringListAsync with url regex extraction returns captured urls only',
      () async {
        final analyzer = AnalyzeRule().setContent('''
<script src="http://m.bqgcn.com/bqgcn/mobile/js/jquery.min.js"></script>
<script>var next = "http://m.bqgcn.com/21_21466/15743972.html?page=_2";</script>
<script src="http://m.bqgcn.com/bqgcn/mobile/js/wap.js"></script>
''', baseUrl: 'http://m.bqgcn.com/21_21466/15743972.html');

        final result = await analyzer.getStringListAsync(
          r'script@html##(http[^"]+page[^"]+)##$1###',
          isUrl: true,
        );

        expect(result, ['http://m.bqgcn.com/21_21466/15743972.html?page=_2']);
      },
    );

    test('isUrl=true returns the first css match instead of joined values', () {
      final analyzer = AnalyzeRule().setContent(
        htmlStr,
        baseUrl: 'https://example.com/search?q=test',
      );

      expect(
        analyzer.getString('.links@tag.a@href', isUrl: true),
        'https://example.com/chapter/1',
      );
    });

    test('getStringList with isUrl=true resolves relative urls', () {
      final analyzer = AnalyzeRule().setContent(
        htmlStr,
        baseUrl: 'https://example.com/search?q=test',
      );

      expect(analyzer.getStringList('.links@tag.a@href', isUrl: true), [
        'https://example.com/chapter/1',
        'https://example.com/chapter/2',
      ]);
    });

    test(
      'getStringAsync with isUrl=true resolves relative url to absolute url',
      () async {
        final analyzer = AnalyzeRule().setContent(
          htmlStr,
          baseUrl: 'https://example.com/search?q=test',
        );

        expect(
          await analyzer.getStringAsync('.link@href', isUrl: true),
          'https://example.com/book/1',
        );
      },
    );

    test(
      'getStringAsync with isUrl=true prefers redirectUrl over baseUrl',
      () async {
        final analyzer =
            AnalyzeRule()
              ..setContent(
                htmlStr,
                baseUrl: 'https://example.com/search?q=test',
              )
              ..setRedirectUrl('https://cdn.example.net/results/list.html');

        expect(
          await analyzer.getStringAsync('.link@href', isUrl: true),
          'https://cdn.example.net/book/1',
        );
      },
    );

    test(
      'getStringAsync expands async importScript fragments in browser mode',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'analyze_rule_import_script_test_',
        );
        final scriptFile = File('${tempDir.path}/helper.js');
        await scriptFile.writeAsString(r'''
!function(root, factory) {
  if (typeof exports === "object" && typeof module !== "undefined") {
    module.exports = factory(require("./core.min"));
  } else if (typeof define === "function" && define.amd) {
    define([], factory);
  } else {
    root.Helper = factory();
  }
}(this, function() {
  return {
    value: function(v) {
      return v + "!";
    }
  };
});
''');

        try {
          final analyzer = AnalyzeRule().setContent(htmlStr);
          final value = await analyzer.getStringAsync(
            '@js:{{java.importScript("${scriptFile.path}")}}\nHelper.value("ok")',
          );

          expect(value, 'ok!');
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
      skip: quickJsSkip,
    );

    test(
      'getStringListAsync resolves async dynamic rules before css parsing',
      () async {
        await CookieStore().setCookie('https://example.com', 'selector=.links');
        try {
          final analyzer = AnalyzeRule().setContent(
            htmlStr,
            baseUrl: 'https://example.com/search?q=test',
          );

          expect(
            await analyzer.getStringListAsync(
              '{{java.getCookie("https://example.com", "selector")}}@tag.a@href',
              isUrl: true,
            ),
            ['https://example.com/chapter/1', 'https://example.com/chapter/2'],
          );
        } finally {
          await CookieStore().removeCookie('https://example.com');
        }
      },
      skip: quickJsSkip,
    );

    test('leading standalone comment lines are ignored before json rules', () {
      final analyzer = AnalyzeRule().setContent({'isvip': true});

      expect(analyzer.getString('// 删掉这行字，vip章节会显示🔓\n\$.isvip'), 'true');
    });

    test(
      'leading standalone comment lines are ignored before json rules asynchronously',
      () async {
        final analyzer = AnalyzeRule().setContent({'isvip': true});

        expect(
          await analyzer.getStringAsync('// 删掉这行字，vip章节会显示🔓\n\$.isvip'),
          'true',
        );
      },
    );
  });
}
