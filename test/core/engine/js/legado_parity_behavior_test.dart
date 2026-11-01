import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// 規則 JS 的方法照 Legado 的結果：期望值是 Legado（Java）跑同一段會得到的。
void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  late JavascriptRuntime runtime;
  String eval(String js) => runtime.evaluate(js).stringResult;

  setUp(() {
    if (skip != null) return;
    runtime = getJavascriptRuntime();
    JsExtensions(runtime).inject();
  });
  tearDown(() {
    if (skip == null) runtime.dispose();
  });

  test('encodeURI follows Java URLEncoder', () {
    expect(
      eval(r'''java.encodeURI("a b!'()~*-_.中")'''),
      'a+b%21%27%28%29%7E*-_.%E4%B8%AD',
    );
    expect(eval('java.encodeURI("中文", "gbk")'), '%D6%D0%CE%C4');
  }, skip: skip);

  test('base64 takes Android flags and a charset', () {
    expect(eval('java.base64Encode("hello")'), 'aGVsbG8=');
    // DEFAULT（0）：每 76 字換行、最後也換行。
    expect(eval('java.base64Encode("hello", 0)'), 'aGVsbG8=\n');
    // URL_SAFE | NO_WRAP | NO_PADDING
    expect(eval('java.base64Encode("???", 11)'), 'Pz8_');
    expect(eval('java.base64Decode("1tDOxA==", "gbk")'), '中文');
    expect(eval('java.base64Decode("Pz8_")'), '???');
    expect(eval('java.base64Decode("Pz8_", 8)'), '???');
    expect(eval('String(java.base64DecodeToByteArray(""))'), 'null');
  }, skip: skip);

  test('cookie converts between text and a map', () {
    expect(
      eval('JSON.stringify(cookie.cookieToMap("a=1; b=; c=x=y;d"))'),
      '{"a":"1","c":"x=y"}',
    );
    expect(eval('cookie.mapToCookie({a: "1", b: "2"})'), 'a=1; b=2');
    expect(eval('String(cookie.mapToCookie({}))'), 'null');
  }, skip: skip);

  test('cache keeps values in memory', () {
    eval('cache.putMemory("token", {id: 3})');
    expect(eval('JSON.stringify(cache.getFromMemory("token"))'), '{"id":3}');
    eval('cache.deleteMemory("token")');
    expect(eval('String(cache.getFromMemory("token"))'), 'null');
  }, skip: skip);

  test('htmlFormat keeps images, toURL splits a URL', () {
    expect(
      eval(r'java.htmlFormat("<p>a</p><img data-src=\"x.png\"><br>b")'),
      '　　a\n　　<img src="x.png">\n　　b',
    );
    expect(
      eval(r'''
        var u = java.toURL("https://a.com:8080/p/q?x=%E4%B8%AD&y=1");
        [u.host, u.origin, u.pathname, u.searchParams.x, u.searchParams.y].join("|")
      '''),
      'a.com|https://a.com:8080|/p/q|中|1',
    );
    expect(
      eval('java.toURL("../c?k=v", "https://a.com/x/y/z").pathname'),
      '/x/c',
    );
  }, skip: skip);

  test('source.login runs the login program in the login URL', () {
    expect(
      eval(r'''
        source.loginUrl = "@js:function login() { globalThis.loggedIn = 'yes'; }";
        source.login();
        [source.getLoginJs().indexOf("function login") === 0, globalThis.loggedIn].join("|")
      '''),
      'true|yes',
    );
  }, skip: skip);

  test('java.get responses also read like Jsoup Connection.Response', () {
    expect(
      eval(r'''
        var r = buildHttpResponse({
          body: '<p class="t">內文</p>', url: 'https://a.test/x', code: 302, message: 'Found',
          headers: { 'Location': ['https://b.test/y'], 'Set-Cookie': ['a=1; Path=/', 'b=2'],
                     'Content-Type': ['text/html; charset=gbk'] }
        });
        [r.headers('Location')[0], r.hasHeader('set-cookie'), r.cookie('a'), r.cookies().b,
         r.statusCode(), r.statusMessage(), r.charset(), r.parse().select('p.t').text(),
         typeof r.headers().get].join('|')
      '''),
      'https://b.test/y|true|1|2|302|Found|gbk|內文|function',
    );
  }, skip: skip);

  group('Java classes book sources use', () {
    test('Thread, System, StringBuilder', () {
      expect(
        eval(r'''
          // 測試跑在畫面那條 isolate：停不得，丟錯誤（ADR 0034）。
          var refused;
          try { Packages.java.lang.Thread.sleep(1); } catch (e) { refused = 'refused'; }
          var a = [1, 2, 3], b = [0, 0, 0, 0];
          Packages.java.lang.System.arraycopy(a, 0, b, 1, 3);
          var sb = new Packages.java.lang.StringBuilder("x").append(1).append("y");
          [refused, b.join(""), sb.toString(), sb.length(),
           typeof Packages.java.lang.System.currentTimeMillis()].join("|")
        '''),
        'refused|0123|x1y|3|number',
      );
    }, skip: skip);

    test('HashMap and ArrayList read like Java and reach Dart as JSON', () {
      expect(
        eval(r'''
          var m = new Packages.java.util.HashMap();
          m.put("name", "一"); m.put("url", "/1");
          var list = new Packages.java.util.ArrayList();
          list.add(m);
          [list.size(), list.get(0).get("name"), m.containsKey("url"),
           String(m.get("none")), JSON.stringify(m), m.keySet().join(",")].join("|")
        '''),
        '1|一|true|null|{"name":"一","url":"/1"}|name,url',
      );
      final rule = AnalyzeRule(
        source: BookSource(bookSourceUrl: 'https://a.test'),
      );
      addTearDown(rule.dispose);
      expect(
        rule.evalJS(r'''
          var list = new Packages.java.util.ArrayList();
          var m = new Packages.java.util.HashMap();
          m.put("name", "一");
          list.add(m);
          list
        ''', null),
        [
          {'name': '一'},
        ],
      );
    }, skip: skip);

    test('MessageDigest, ByteBuffer, byte streams', () {
      expect(
        eval(r'''
          var md = Packages.java.security.MessageDigest.getInstance("MD5");
          var d = md.digest(new Packages.java.lang.String("abc").getBytes("UTF-8"));
          var hex = d.map(function(b) { return ((b & 0xFF) + 0x100).toString(16).substring(1); }).join("");
          var bb = Packages.java.nio.ByteBuffer.allocate(4); bb.putInt(258);
          var out = new Packages.java.io.ByteArrayOutputStream();
          out.write(65); out.write([66, 67]);
          var input = new Packages.java.io.ByteArrayInputStream([7, 8]);
          [hex, bb.array().join(","), out.toByteArray().join(","), out.toString(),
           input.read(), input.read(), input.read()].join("|")
        '''),
        '900150983cd24fb0d6963f7d28e17f72|0,0,1,2|65,66,67|ABC|7|8|-1',
      );
    }, skip: skip);

    test('android.util.Base64 and JavaImporter', () {
      expect(
        eval(r'''
          var bytes = java.strToBytes("hello?>", "UTF-8");
          var a = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP | android.util.Base64.URL_SAFE);
          var back = java.bytesToStr(Packages.android.util.Base64.decode(a, 8), "UTF-8");
          var imported = new JavaImporter(Packages.android.util.Base64, Packages.java.net.URL);
          var b;
          with (imported) { b = Base64.encodeToString(bytes, 0); }
          [a, back, JSON.stringify(b)].join("|")
        '''),
        'aGVsbG8_Pg==|hello?>|"aGVsbG8/Pg==\\n"',
      );
    }, skip: skip);

    test('JsonPath, URL, URLEncoder, URLDecoder, SimpleDateFormat', () {
      expect(
        eval(r'''
          var json = '{"a":{"b":[1,2,3],"c":"x"}}';
          var u = new Packages.java.net.URL("https://a.com:8080/p?q=1#r");
          var when = new Packages.java.util.Date(new Date(2024, 0, 2, 3, 4, 5).getTime());
          [JSON.stringify(com.jayway.jsonpath.JsonPath.read(json, "$.a.b[0:2]")),
           com.jayway.jsonpath.JsonPath.read(json, "$.a.c"),
           u.getHost(), u.getPort(), u.getPath(), u.getQuery(), u.getRef(),
           Packages.java.net.URLEncoder.encode("a b中", "UTF-8"),
           Packages.java.net.URLDecoder.decode("a+b%E4%B8%AD", "UTF-8"),
           new Packages.java.text.SimpleDateFormat("yyyyMMdd HH:mm:ss").format(when)].join("|")
        '''),
        '[1,2]|x|a.com|8080|/p|q=1|r|a+b%E4%B8%AD|a b中|20240102 03:04:05',
      );
    }, skip: skip);

    test('Mac and SecureRandom', () {
      expect(
        eval(r'''
          var key = java.strToBytes("key", "UTF-8");
          var mac = Packages.javax.crypto.Mac.getInstance("HmacSHA256");
          mac.init(new Packages.javax.crypto.spec.SecretKeySpec(key, "HmacSHA256"));
          var out = mac.doFinal(java.strToBytes("The quick brown fox jumps over the lazy dog", "UTF-8"));
          var hex = out.map(function(b) { return ((b & 0xFF) + 0x100).toString(16).substring(1); }).join("");
          var random = new Packages.java.security.SecureRandom();
          var buf = [0, 0, 0];
          random.nextBytes(buf);
          [hex, random.generateSeed(5).length, buf.length].join("|")
        '''),
        'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8|5|3',
      );
    }, skip: skip);

    test('InflaterInputStream reads zlib data', () {
      // zlib.encode(utf8.encode('hello'))
      expect(
        eval(r'''
          var input = new Packages.java.io.ByteArrayInputStream(
            [120, 156, 203, 72, 205, 201, 201, 7, 0, 6, 44, 2, 21]);
          var stream = new Packages.java.util.zip.InflaterInputStream(input, new Packages.java.util.zip.Inflater());
          var buf = [0, 0, 0, 0, 0, 0, 0, 0], out = new Packages.java.io.ByteArrayOutputStream(), n;
          while ((n = stream.read(buf)) > 0) out.write(buf, 0, n);
          out.toString("UTF-8")
        '''),
        'hello',
      );
    }, skip: skip);
  });

  group('the same results as Java for edge cases', () {
    test('digest and HMAC updates, Hutool', () {
      expect(
        eval(r'''
          function hex(b) { return b.map(function(x) { return ((x & 0xFF) + 0x100).toString(16).substring(1); }).join(''); }
          var md = Packages.java.security.MessageDigest.getInstance('MD5');
          md.update(97);
          var one = hex(md.digest());
          var mac = Packages.javax.crypto.Mac.getInstance('HmacSHA256');
          mac.init(new Packages.javax.crypto.spec.SecretKeySpec(java.strToBytes('key', 'UTF-8'), 'HmacSHA256'));
          mac.update([65, 66, 67], 1, 1);
          var sliced = hex(mac.doFinal());
          mac.update(66);
          var single = hex(mac.doFinal());
          [one, sliced === single, cn.hutool.crypto.digest.DigestUtil.md5Hex('a')].join('|')
        '''),
        '0cc175b9c0f1b6a831c399e269772661|true|0cc175b9c0f1b6a831c399e269772661',
      );
    }, skip: skip);

    test('URL encoding and Base64 charsets', () {
      expect(
        eval(r'''
          var bad;
          try { java.base64Decode('QQ==', 'NOT-A-CHARSET'); } catch (e) { bad = 'error'; }
          [java.encodeURI('A B中', 'UTF-16'),
           java.base64Decode(java.base64Encode(java.strToBytes('中', 'UTF-16LE')), 'UTF-16LE'),
           bad, String(java.base64Decode(null)),
           android.util.Base64.encodeToString([65, 66, 67], 1, 1, 2),
           Packages.java.util.Base64.getDecoder().decode([81, 81, 61, 61]).join(',')].join('|')
        '''),
        'A+B%FE%FF%4E%2D|中|error|null|Qg==|65',
      );
    }, skip: skip);

    test('maps, sets, arrays', () {
      expect(
        eval(r'''
          var m = new Packages.java.util.HashMap();
          m.put(1, 'n'); m.put('1', 's'); m.put('__proto__', 123);
          var t = new Packages.java.util.TreeMap(); t.put('b', 2); t.put('a', 1);
          var set = new Packages.java.util.HashSet([10, 20]);
          var removed = set.remove(10);
          var a = [1, 2, 3, 4];
          Packages.java.lang.System.arraycopy(a, 0, a, 1, 3);
          var h = new Packages.java.util.HashMap(); h.put('a', '1');
          cache.putMemory('obj', h);
          [m.size(), m.get(1), m.get('1'), m.get('__proto__'), t.keySet().join(','),
           removed, set.join(','), a.join(','), cookie.cookieToMap('a=1').get('a'),
           cookie.mapToCookie(h), cache.getFromMemory('obj') === h,
           java.toURL('https://a.test/?x=%D6%D0&y=1').searchParams.get('y'),
           new Packages.java.util.ArrayList().addAll([])].join('|')
        '''),
        '3|n|s|123|a,b|true|20|1,1,2,3|1|a=1|true|1|false',
      );
    }, skip: skip);

    test('streams, buffers, StringBuilder', () {
      expect(
        eval(r'''
          var input = new Packages.java.io.ByteArrayInputStream([-1, 65, 66, 67], 2, 1);
          var first = new Packages.java.io.ByteArrayInputStream([-1]).read();
          var zlib = [120, 156, 203, 72, 205, 201, 201, 7, 0, 6, 44, 2, 21];
          var inflated = new Packages.java.util.zip.InflaterInputStream(
            new Packages.java.io.ByteArrayInputStream(zlib)).read();
          var inflater = new Packages.java.util.zip.Inflater();
          inflater.setInput(zlib);
          var out = [0, 0, 0, 0, 0];
          var n = inflater.inflate(out);
          var bb = Packages.java.nio.ByteBuffer.allocate(4); bb.putInt(0, 258);
          var overflow;
          try { Packages.java.nio.ByteBuffer.allocate(1).putInt(258); } catch (e) { overflow = 'overflow'; }
          var sb = new Packages.java.lang.StringBuilder('😀a').reverse();
          var grow = new Packages.java.lang.StringBuilder('a'); grow.setLength(3);
          [first, input.read(), input.read(), inflated, n, inflater.finished(),
           bb.array().join(','), bb.position(), overflow, sb.toString(), grow.length()].join('|')
        '''),
        '255|66|-1|104|5|true|0,0,1,2|0|overflow|a😀|3',
      );
    }, skip: skip);

    test('dates, URLs, decoder errors', () {
      expect(
        eval(r'''
          var f = new Packages.java.text.SimpleDateFormat('yyyy-MM-dd Z E EEEE a MMM');
          f.setTimeZone(Packages.java.util.TimeZone.getTimeZone('GMT+8'));
          var parsed = new Packages.java.text.SimpleDateFormat('yyyyMMddHHmm');
          parsed.setTimeZone(Packages.java.util.TimeZone.getTimeZone('UTC'));
          var u = new Packages.java.net.URL('https://user@a.test:81/p?q=%D6%D0#r');
          var bad;
          try { Packages.java.net.URLDecoder.decode('a%ZZ', 'UTF-8'); } catch (e) { bad = 'error'; }
          var h = okhttp3.HttpUrl.parse('https://a.test/?x=1&x=2');
          [f.format(new Packages.java.util.Date(0)), parsed.parse('197001020304').getTime(),
           u.getQuery(), u.getAuthority(), String(okhttp3.HttpUrl.parse('not a url')),
           h.queryParameter('x'), bad].join('|')
        '''),
        '1970-01-01 +0800 週四 星期四 上午 1月|97440000|q=%D6%D0|user@a.test:81|null|1|error',
      );
    }, skip: skip);

    test('cache numbers follow Kotlin', () {
      expect(
        eval(r'''
          cache.put('big', '2147483648'); cache.put('hex', '0x10'); cache.put('f', '16777217');
          cache.put('d', '1.5e2'); cache.put('i', '-12');
          [String(cache.getInt('big')), cache.getLong('big'), String(cache.getDouble('hex')),
           cache.getFloat('f'), cache.getDouble('d'), cache.getInt('i')].join('|')
        '''),
        'null|2147483648|null|16777216|150|-12',
      );
    }, skip: skip);

    test('Jsoup Elements, StrResponse, priorResponse', () {
      expect(
        eval(r'''
          var doc = org.jsoup.Jsoup.parse('<p>a</p><p>b</p>');
          var list = new org.jsoup.select.Elements();
          list.add(doc.select('p').get(1));
          var r = new Packages.io.legado.app.help.http.StrResponse('https://a.test/', '內文');
          var hop = buildHttpResponse({ url: 'https://b.test/', requestUrl: 'https://a.test/',
            redirects: ['https://b.test/'], code: 200, headers: {} }).raw().priorResponse();
          [list.size(), list.text(), r.body(), r.url(), hop.request().url(), hop.header('Location')].join('|')
        '''),
        '1|b|內文|https://a.test/|https://a.test/|https://b.test/',
      );
    }, skip: skip);
  });

  test('rule scope: setters, evalJS, source scope, bindings reset', () {
    final rule = AnalyzeRule(
      source: BookSource(bookSourceUrl: 'https://src.test'),
    )..setContent('<i>x</i><i>x</i>', baseUrl: 'https://page.test/c/1');
    addTearDown(rule.dispose);
    expect(
      rule.evalJS(r'''
        [java.setBaseUrl('https://page.test/c/2') === java,
         String(java.setRedirectUrl('data:text/plain,x')),
         java.evalJS('result + 1', 2),
         source.evalJS('baseUrl'),
         typeof source.encodeURI,
         java.getStringList('tag.i@text').join(',')].join('|')
      ''', null),
      'true|https://page.test/c/1|3|https://src.test|function|x,x',
    );
    // 規則把 cookie 拿去存別的值，下一條規則照樣拿到 Legado 的 cookie。
    rule.evalJS('cookie = "被改掉"; 1', null);
    expect(rule.evalJS('typeof cookie.getKey', null), 'function');
  }, skip: skip);

  test('getString parses the content it is given', () {
    final rule = AnalyzeRule(
      source: BookSource(bookSourceUrl: 'https://a.test'),
    )..setContent('<p><b>目前</b></p>', baseUrl: 'https://a.test/');
    addTearDown(rule.dispose);
    expect(
      rule.evalJS(r'''
        [java.getString("tag.b@text"),
         java.getString("tag.b@text", "<p><b>給的</b></p>"),
         java.getStringList("tag.i@text", "<i>一</i><i>二</i>").join("/")].join("|")
      ''', null),
      '目前|給的|一/二',
    );
  }, skip: skip);
}
