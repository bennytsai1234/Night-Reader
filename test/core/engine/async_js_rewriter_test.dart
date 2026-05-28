import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/async_js_rewriter.dart';

void main() {
  group('AsyncJsRewriter.normalizeLegacyTemplateEscapes', () {
    test('drops invalid template literal escapes in legacy regex strings', () {
      const input = r'var pattern = `${callback}\((.*)\)`;';
      const expected = r'var pattern = `${callback}((.*))`;';

      expect(AsyncJsRewriter.normalizeLegacyTemplateEscapes(input), expected);
    });

    test('preserves valid template literal escapes', () {
      const input = r'var msg = `line1\n${value}\${escaped}`;';

      expect(AsyncJsRewriter.normalizeLegacyTemplateEscapes(input), input);
    });
  });

  group('AsyncJsRewriter.rewrite', () {
    test('simple java.ajax call gets wrapped with (await …)', () {
      expect(
        AsyncJsRewriter.rewrite('java.ajax(url)'),
        '(await java.ajax(url))',
      );
    });

    test('assignment preserves LHS', () {
      expect(
        AsyncJsRewriter.rewrite('var r = java.ajax(url);'),
        'var r = (await java.ajax(url));',
      );
    });

    test('method chain .body() stays outside the await wrapper', () {
      expect(
        AsyncJsRewriter.rewrite('java.get(url).body()'),
        '(await java.get(url)).body()',
      );
    });

    test('java.get(scopeKey) without response chain stays sync', () {
      const input = "var intro = java.get('intro');";
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test(
      'java.get(url, headers) remains async even without response chain',
      () {
        expect(
          AsyncJsRewriter.rewrite('java.get(url, headers)'),
          '(await java.get(url, headers))',
        );
      },
    );

    test('nested call argument', () {
      expect(
        AsyncJsRewriter.rewrite('JSON.parse(java.ajax(url))'),
        'JSON.parse((await java.ajax(url)))',
      );
    });

    test('multiple async calls in same source', () {
      expect(
        AsyncJsRewriter.rewrite('java.ajax(a); java.post(b, c);'),
        '(await java.ajax(a)); (await java.post(b, c));',
      );
    });

    test('java.post with object literal argument preserves braces', () {
      const input =
          'java.post(url, body, {"Content-Type": "application/json"})';
      const expected =
          '(await java.post(url, body, {"Content-Type": "application/json"}))';
      expect(AsyncJsRewriter.rewrite(input), expected);
    });

    test('java.post with multiline headers object is awaited', () {
      const input = '''
let response = java.post("https://bcshuku.com/conapi.php", params, {
  "accept": "application/json, text/javascript, */*; q=0.01",
  "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
  "referer": baseUrl
});
if (response && response.body()) {
  JSON.parse(response.body())["content"];
}
''';
      const expected = '''
let response = (await java.post("https://bcshuku.com/conapi.php", params, {
  "accept": "application/json, text/javascript, */*; q=0.01",
  "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
  "referer": baseUrl
}));
if (response && response.body()) {
  JSON.parse(response.body())["content"];
}
''';
      expect(AsyncJsRewriter.rewrite(input), expected);
    });

    test('regex literal before java.post still rewrites correctly', () {
      const input = r'''
var regex = /\{"url"\s*:\s*"[^"]+"\s*,\s*"mobile"\s*:\s*"\d"\s*,\s*"isk"\s*:\s*"\d"\s*,\s*"novel"\s*:\s*"\d+"\s*,\s*"chapter"\s*:\s*"\d+"\}/;
var match = result.match(regex);
if (match) {
  let response = java.post("https://bcshuku.com/conapi.php", params, {
    "accept": "application/json, text/javascript, */*; q=0.01",
    "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
    "referer": baseUrl
  });
  if (response && response.body()) {
    JSON.parse(response.body())["content"];
  }
}
''';
      const expected = r'''
var regex = /\{"url"\s*:\s*"[^"]+"\s*,\s*"mobile"\s*:\s*"\d"\s*,\s*"isk"\s*:\s*"\d"\s*,\s*"novel"\s*:\s*"\d+"\s*,\s*"chapter"\s*:\s*"\d+"\}/;
var match = result.match(regex);
if (match) {
  let response = (await java.post("https://bcshuku.com/conapi.php", params, {
    "accept": "application/json, text/javascript, */*; q=0.01",
    "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
    "referer": baseUrl
  }));
  if (response && response.body()) {
    JSON.parse(response.body())["content"];
  }
}
''';
      expect(AsyncJsRewriter.rewrite(input), expected);
    });

    test(
      'regex literals inside java.ajax arguments keep chained calls intact',
      () {
        const input = r'''
java.ajax(baseUrl.replace('read-', '_getcontent.php?id=').replace('.html','&v=' + result.match(/&v=(.*?)"/)[1])).replaceAll('<style.*style>','').replaceAll('<([^<]*?)class(.*?)</(.*?)>','')
''';
        const expected = r'''
(await java.ajax(baseUrl.replace('read-', '_getcontent.php?id=').replace('.html','&v=' + result.match(/&v=(.*?)"/)[1]))).replaceAll('<style.*style>','').replaceAll('<([^<]*?)class(.*?)</(.*?)>','')
''';
        expect(AsyncJsRewriter.rewrite(input), expected);
      },
    );

    test('sync methods (md5Encode, base64Encode) are left alone', () {
      const input =
          'var h = java.md5Encode(str); var b = java.base64Encode(str);';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('java.get INSIDE single-quoted string literal is untouched', () {
      const input = "var s = 'java.get(url).body() is async';";
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('java.ajax inside double-quoted string literal is untouched', () {
      const input = 'var s = "do not match java.ajax(x) in strings";';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('java.ajax inside line comment is untouched', () {
      const input = '// java.ajax(url)\nvar r = 1;';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('java.ajax inside block comment is untouched', () {
      const input = '/* example: java.ajax(url) */\nvar r = 1;';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('already-awaited call is not double-wrapped', () {
      const input = 'var r = await java.ajax(url);';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('await with extra whitespace is still recognised', () {
      const input = 'var r = await   java.ajax(url);';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('identifier prefix "myjava" is not matched (word boundary)', () {
      const input = 'myjava.ajax(url)';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('case-sensitive: Java.ajax is not matched', () {
      const input = 'Java.ajax(url)';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('method name prefix "java.getSomething" is not matched', () {
      const input = 'java.getSomething(url)';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('java.get property reference without call is not matched', () {
      const input = 'var fn = java.get;';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('java.head delegates through java.get, also gets await', () {
      expect(
        AsyncJsRewriter.rewrite('java.head(url, headers)'),
        '(await java.head(url, headers))',
      );
    });

    test('java.webView async call', () {
      expect(
        AsyncJsRewriter.rewrite('java.webView(html, url, js)'),
        '(await java.webView(html, url, js))',
      );
    });

    test('backtick template literal passes through verbatim', () {
      // 已知限制：template literal 插值內不做掃描
      const input = 'var s = `java.ajax: \${x}`;';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('long realistic rule JS combining sync and async', () {
      const input = '''
        var token = java.md5Encode(key + Date.now());
        var res = java.get(baseUrl + "/api?t=" + token).body();
        var obj = JSON.parse(res);
        "https://cdn.example.com/" + obj.path
      ''';
      const expected = '''
        var token = java.md5Encode(key + Date.now());
        var res = (await java.get(baseUrl + "/api?t=" + token)).body();
        var obj = JSON.parse(res);
        "https://cdn.example.com/" + obj.path
      ''';
      expect(AsyncJsRewriter.rewrite(input), expected);
    });

    test('pure sync source is returned unchanged', () {
      const input = 'var x = 1 + 2; var s = "hi"; // comment';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('unterminated string does not crash', () {
      const input = 'var s = "unterminated';
      expect(() => AsyncJsRewriter.rewrite(input), returnsNormally);
    });

    test('unterminated paren after async call does not crash', () {
      const input = 'java.ajax(url';
      // 無法配對右括號 → 整段視為非匹配，保持原樣
      expect(AsyncJsRewriter.rewrite(input), input);
    });
  });

  group('AsyncJsRewriter multi-owner', () {
    test('cache.get(key) gets wrapped', () {
      expect(
        AsyncJsRewriter.rewrite('var v = cache.get("k")'),
        'var v = (await cache.get("k"))',
      );
    });

    test('cache.getFile(key) gets wrapped', () {
      expect(
        AsyncJsRewriter.rewrite('var v = cache.getFile("k")'),
        'var v = (await cache.getFile("k"))',
      );
    });

    test('source.get(key) gets wrapped', () {
      expect(
        AsyncJsRewriter.rewrite('source.get("login")'),
        '(await source.get("login"))',
      );
    });

    test('source.getLoginInfo() gets wrapped', () {
      expect(
        AsyncJsRewriter.rewrite('source.getLoginInfo()'),
        '(await source.getLoginInfo())',
      );
    });

    test('cookie.get(url) gets wrapped', () {
      expect(
        AsyncJsRewriter.rewrite('cookie.get("https://ex.com")'),
        '(await cookie.get("https://ex.com"))',
      );
    });

    test('cache.put is not wrapped (sync method)', () {
      const input = 'cache.put(key, val, 600);';
      expect(AsyncJsRewriter.rewrite(input), input);
    });

    test('mixed owners and method chains', () {
      const input =
          'var a = java.ajax(u); var b = cache.get(k); var c = source.get("x").toString();';
      const expected =
          'var a = (await java.ajax(u)); var b = (await cache.get(k)); var c = (await source.get("x")).toString();';
      expect(AsyncJsRewriter.rewrite(input), expected);
    });

    test('unknown owner (myCache.get) is not wrapped', () {
      const input = 'myCache.get(key)';
      expect(AsyncJsRewriter.rewrite(input), input);
    });
  });

  group('AsyncJsRewriter.needsAsync', () {
    test('returns false for pure sync JS', () {
      expect(AsyncJsRewriter.needsAsync('var x = 1 + 2;'), isFalse);
    });

    test('returns false when only sync java methods are used', () {
      expect(AsyncJsRewriter.needsAsync('java.md5Encode(str)'), isFalse);
    });

    test('returns true when java.ajax is used', () {
      expect(AsyncJsRewriter.needsAsync('var r = java.ajax(url);'), isTrue);
    });

    test('returns true when java.get chain is used', () {
      expect(AsyncJsRewriter.needsAsync('java.get(url).body()'), isTrue);
    });

    test('returns false when java.get is used as sync scope lookup', () {
      expect(AsyncJsRewriter.needsAsync("java.get('intro')"), isFalse);
    });

    test('returns false when "java.ajax" only appears inside a string', () {
      expect(AsyncJsRewriter.needsAsync('var s = "java.ajax(x)";'), isFalse);
    });

    test('returns false when "java.ajax" only appears inside a comment', () {
      expect(AsyncJsRewriter.needsAsync('// java.ajax(x)'), isFalse);
    });
  });
}
