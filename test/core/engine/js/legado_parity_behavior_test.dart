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
          Packages.java.lang.Thread.sleep(1);
          Packages.java.util.concurrent.locks.LockSupport.parkNanos(this, 1000);
          var a = [1, 2, 3], b = [0, 0, 0, 0];
          Packages.java.lang.System.arraycopy(a, 0, b, 1, 3);
          var sb = new Packages.java.lang.StringBuilder("x").append(1).append("y");
          [b.join(""), sb.toString(), sb.length(),
           typeof Packages.java.lang.System.currentTimeMillis()].join("|")
        '''),
        '0123|x1y|3|number',
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
