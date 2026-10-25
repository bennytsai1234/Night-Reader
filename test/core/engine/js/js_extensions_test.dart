import 'dart:convert';
import 'dart:io' show Directory, File, gzip;

import 'package:archive/archive.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/async_js_rewriter.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';
import 'package:night_reader/core/engine/js/js_rule_async_wrapper.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_validation_context.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../test_helper.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider({required this.temporaryPath, required this.documentsPath});

  final String temporaryPath;
  final String documentsPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('JsExtensions bridge completeness', () {
    JavascriptRuntime? runtime;
    Object? runtimeError;

    setUp(() {
      runtimeError = null;
      try {
        runtime = getJavascriptRuntime();
      } catch (error) {
        runtime = null;
        runtimeError = error;
      }
    });

    tearDown(() {
      runtime?.dispose();
    });

    test('legacy crypto helpers and javax.crypto.Cipher match Legado', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      JsExtensions(runtime!).inject();
      String eval(String code) {
        final result = runtime!.evaluate(code);
        expect(result.isError, isFalse, reason: result.stringResult);
        return result.stringResult;
      }

      // 對照答案由 Python cryptography（OpenSSL）算出。
      const cbc =
          'nRmiA4tZ9RKopqLxKpPmO18Bciqi8K22kaHQ23wdE9KeHjBn8HnHegQ5vh6k7lT4';
      const plain = '夜讀 Night Reader 第一章：山雨欲來';
      expect(
        eval(
          "java.aesEncodeToBase64String('$plain', '0123456789abcdef', "
          "'AES/CBC/PKCS5Padding', 'fedcba9876543210')",
        ),
        cbc,
      );
      expect(
        eval(
          "java.aesBase64DecodeToString('$cbc', '0123456789abcdef', "
          "'AES/CBC/PKCS5Padding', 'fedcba9876543210')",
        ),
        plain,
      );
      // Legado 的 aesEncodeToString 其實是解密。
      expect(
        eval(
          "java.aesEncodeToString('$cbc', '0123456789abcdef', "
          "'AES/CBC/PKCS5Padding', 'fedcba9876543210')",
        ),
        plain,
      );
      expect(
        eval(
          "java.tripleDESEncodeBase64Str('$plain', 'OW84U8Eerdb99rtsTXWSILDO', "
          "'CBC', 'PKCS5Padding', 'SK8bncVu')",
        ),
        'AWZH676WJU1IwCwkL1g3Lngc/0+N94zXR9LT2zIDrLv+I3lqvuaWfbwYsT8kIj36',
      );
      expect(
        eval(
          "String(java.HMacBase64('$plain', 'HmacSHA1', '0123456789abcdef'))",
        ),
        'RcIthmJ4naPxIEkdIjawBlLrfws=',
      );

      // 豆瓣閱讀的正文解密：金鑰是 cookie 的 SHA-256（十六進位轉成位元組），
      // IV 從密文尾巴切出來，對位元組陣列解密。
      expect(
        eval('''
          (function() {
            var t = '9TERedZ1x3kgj4SvkOcZ2TVt964UiyNqg/fpvE3c7cIxBXJ/jy6NBFXoUpbySOhPMDEyMzQ1Njc4OWFiY2RlZlRUVFRUVFRUVFRUVFQ=';
            var decodedBytes = java.base64DecodeToByteArray(t);
            var ivStart = decodedBytes.length - 16 - 13;
            var cipher = java.createSymmetricCrypto('AES/CBC/PKCS5Padding',
              java.hexDecodeToByteArray(java.digestHex('bid=abc123', 'SHA-256')),
              decodedBytes.slice(ivStart, ivStart + 16));
            var text = cipher.decryptStr(decodedBytes.slice(0, ivStart));
            return JSON.parse(text).posts[0].contents;
          })()
        '''),
        '第一章 正文',
      );

      // 愛麗絲書屋的寫法：RSA 私鑰（PKCS#8 位元組）解出 AES 金鑰。金鑰與
      // 密文、簽章由 Python cryptography 產生。
      const rsaPrivate =
          'MIICeAIBADANBgkqhkiG9w0BAQEFAASCAmIwggJeAgEAAoGBALZIWkQpX1LDg3r+NkruJ+nAEDMS2lpzVL6wazQlHwpjhVwFsJR4WyFlAXV69KjmMvICn47hRqB9HiiW7+bmVe0qFFYqOaOEKYn9t5GZKAsNVo39KXrezIHI6Zq19e8EhObuy2+3iYdIxZ6fN4ZUsH8qTBfOXK5quCzzhAdim1IBAgMBAAECgYBp9vGSgkKJyGKckz9Ym83UEvTX2/PXdQgkukX30ESVM3mJHz2hcb34UdFhTBMCRKAFFAVReCAol9N6YRQhNHFqLEMMxMGqfNlyYaFGbSPgloasGj+m85mffBAhZz49gwRuzbj0IPP3r89DR7K424MnKFt+snWSWZ4J+fkUAc8byQJBANwJvzoGBq/jyqaPEaNXRPPXVuSzxcHP2DoEfgCmuijAQpafDmvQRYbMzwNV43kY8C23DUIHgeywrb/aLxWhZ0cCQQDUEvEWrLQMYX2hPIYLmR/o7uqKaTN8RAsMB0A35hhD5OImQy/lAi+oJi/u8q/B9rc9ZOwizsPBBSy2ho3ekTB3AkEAyRyvh10Sp5jQFEQXnu+YujZL2WTmjyplO0H32KiK5cw0EG74Q1ps8bQoUagi7P/6Jg51M7Cg87DYXc4R0vde6QJBAMweuywO6HFuOIRDg+WP6bXCl77HCQYXW+ak5/ulnT9kAwO+8U9j7kjTEJnVvrNbav1NsTbDeojDGUlJcy2A43sCQQCEZjJ25tbBDS0KUFfU0plI5Fnbj03KTWC7Kfsvt4gutIERe3x4kVC5nehEOz0yP7KwlrOJcpYDA9bxKdHdcmgr';
      const rsaPublic =
          'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC2SFpEKV9Sw4N6/jZK7ifpwBAzEtpac1S+sGs0JR8KY4VcBbCUeFshZQF1evSo5jLyAp+O4UagfR4olu/m5lXtKhRWKjmjhCmJ/beRmSgLDVaN/Sl63syByOmatfXvBITm7stvt4mHSMWenzeGVLB/KkwXzlyuargs84QHYptSAQIDAQAB';
      expect(
        eval('''
          (function() {
            var rsa = java.createAsymmetricCrypto('RSA/ECB/PKCS1Padding');
            rsa.setPrivateKey(java.base64DecodeToByteArray('$rsaPrivate'));
            return rsa.decryptStr('r4oIz6Snp1U4MUcQdWvmJhOl9/cMaU1dT2WnHC89/cDfDawRpxunS3k2tPXEuYzt7v8KtQ75V17Odr9QM8n818/u+U+RAlEhhl8g8CLh/1urQiO60IiJ+1GaOWwSLhgPdFmcRi0eyHPUIP59yMCASgU66JoPZ/WcAbmCMNQOCDg=', false);
          })()
        '''),
        'QUVTLWtleS1iYXNlNjQtMTIzNDU2Nzg5MA==',
      );
      expect(
        eval('''
          (function() {
            var rsa = java.createAsymmetricCrypto('RSA/ECB/PKCS1Padding')
              .setPublicKey(java.base64DecodeToByteArray('$rsaPublic'))
              .setPrivateKey(java.base64DecodeToByteArray('$rsaPrivate'));
            var long = new Array(30).join('夜讀長資料要分塊加密。');
            return rsa.decryptStr(rsa.encryptBase64(long), false) === long;
          })()
        '''),
        'true',
      );
      expect(
        eval(
          "java.createSign('SHA256withRSA')"
          ".setPrivateKey(java.base64DecodeToByteArray('$rsaPrivate'))"
          ".signHex('第一章')",
        ),
        '4197120d3ac569e2446800172658efb2813df8fcd2b7edc67b33d046e644ef49'
        'f1b9589b6ceb66be653509d164a969bf8900fe8e2bb38f4e1141b3f4c2edbf0a'
        '5e1604bb50898100b3c16c00480c4a5221fa51aa9c3d738bddff95d85b2ca867'
        '703a771ac22a7902fd790810e701ae3eedeae7f925dd229441621823880d3104',
      );

      // 零點文學的寫法：Cipher 加密後交給 Base64.getEncoder()。
      expect(
        eval('''
          (function() {
            var Cipher = Packages.javax.crypto.Cipher;
            var JString = Packages.java.lang.String;
            var key = new Packages.javax.crypto.spec.SecretKeySpec(
              new JString('0123456789abcdef').getBytes('UTF-8'), 'AES');
            var iv = new Packages.javax.crypto.spec.IvParameterSpec(
              new JString('fedcba9876543210').getBytes('UTF-8'));
            var cipher = Cipher.getInstance('AES/CBC/PKCS5Padding');
            cipher.init(Cipher.ENCRYPT_MODE, key, iv);
            var bytes = cipher.doFinal(new JString('$plain').getBytes('UTF-8'));
            var encoded = java.base64Encode(bytes);
            cipher.init(Cipher.DECRYPT_MODE, key, iv);
            var back = cipher.doFinal(java.base64DecodeToByteArray(encoded));
            return encoded + '|' + String(new JString(back));
          })()
        '''),
        '$cbc|$plain',
      );
    }, skip: quickJsSkip);

    test('java bridge exposes missing helper methods', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      expect(
        runtime!.evaluate('typeof java.base64Decode').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.md5Encode16').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.hexEncodeToString').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.hexDecodeToString').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.randomUUID').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.timeFormat').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.timeFormatUTC').stringResult,
        'function',
      );
      expect(runtime!.evaluate('typeof java.HMacHex').stringResult, 'function');
      expect(
        runtime!.evaluate('typeof java.desEncodeToBase64String').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.toNumChapter').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.cacheFile').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.importScript').stringResult,
        'function',
      );
      expect(runtime!.evaluate('typeof java.head').stringResult, 'function');
      expect(
        runtime!.evaluate('typeof java.webViewGetSource').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.webViewGetOverrideUrl').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof java.encodeURI').stringResult,
        'function',
      );
    });

    test('java.log returns the original value like Legado', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        var logged = java.log("bridge-value");
        logged;
      ''');

      expect(result.stringResult, 'bridge-value');
    });

    test('string match with string regex patterns behaves like legacy sources expect', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        var input = 'd918eac({"id":"164"})';
        var matched = input.match('918eac\\((.*)\\)');
        matched ? matched[1] : '';
      ''');

      expect(result.stringResult, '{"id":"164"}');
    });

    test('cookie and cache bridges are exposed', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      expect(runtime!.evaluate('typeof cookie.set').stringResult, 'function');
      expect(
        runtime!.evaluate('typeof cookie.remove').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof cookie.getCookie').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof cookie.setCookie').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof cookie.removeCookie').stringResult,
        'function',
      );
      expect(runtime!.evaluate('typeof cache.get').stringResult, 'function');
      expect(
        runtime!.evaluate('typeof cache.getFile').stringResult,
        'function',
      );
      expect(runtime!.evaluate('typeof cache.put').stringResult, 'function');
      expect(
        runtime!.evaluate('typeof cache.putFile').stringResult,
        'function',
      );
    });

    test('cache.getFile returns null on cache miss like Legado', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final rewritten = AsyncJsRewriter.rewrite(r'''
        var cached = cache.getFile("missing-key");
        cached == null ? "null" : String(cached);
      ''');
      final (callId, future) = ext.registerRuleCall();
      final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

      final evalResult = runtime!.evaluate(wrapped);
      expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
      runtime!.executePendingJob();

      final resolved = await future;
      expect(resolved, 'null');
    });

    test('java.readTxtFile honors UTF-16LE charset', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final file = File(
        '${Directory.systemTemp.path}/night_reader_js_utf16_${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      final bytes = <int>[0xFF, 0xFE];
      for (final codeUnit in '夜讀文字'.codeUnits) {
        bytes
          ..add(codeUnit & 0xFF)
          ..add(codeUnit >> 8);
      }
      await file.writeAsBytes(bytes, flush: true);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final ext = JsExtensions(runtime!);
      ext.inject();
      final rewritten = AsyncJsRewriter.rewrite(
        'java.readTxtFile(${jsonEncode(file.path)}, "UTF-16LE")',
      );
      final (callId, future) = ext.registerRuleCall();
      final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

      final evalResult = runtime!.evaluate(wrapped);
      expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
      runtime!.executePendingJob();

      expect(await future, '夜讀文字');
    });

    test('java.unArchiveFile keeps entries inside its output folder', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final root = await Directory.systemTemp.createTemp(
        'night_reader_js_archive_',
      );
      final documents = await Directory(p.join(root.path, 'documents'))
          .create();
      final temporary = await Directory(p.join(root.path, 'temporary'))
          .create();
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(
        temporaryPath: temporary.path,
        documentsPath: documents.path,
      );
      addTearDown(() async {
        PathProviderPlatform.instance = previousPathProvider;
        if (await root.exists()) await root.delete(recursive: true);
      });

      final archive = Archive()
        ..addFile(ArchiveFile.string('safe.txt', 'safe'))
        ..addFile(ArchiveFile.string('../../escape.txt', 'escape'));
      final zipBytes = ZipEncoder().encode(archive);
      await File(p.join(documents.path, 'archive.zip'))
          .writeAsBytes(zipBytes, flush: true);

      final ext = JsExtensions(runtime!);
      ext.inject();
      final rewritten = AsyncJsRewriter.rewrite(
        'java.unArchiveFile("archive.zip")',
      );
      final (callId, future) = ext.registerRuleCall();
      final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

      final evalResult = runtime!.evaluate(wrapped);
      expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
      runtime!.executePendingJob();

      final relativeOutputPath = (await future).toString();
      expect(
        await File(p.join(temporary.path, relativeOutputPath, 'safe.txt'))
            .readAsString(),
        'safe',
      );
      expect(
        await File(p.join(temporary.path, 'escape.txt')).exists(),
        isFalse,
      );
    });

    test('source bridge is exposed when source exists', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(
        runtime!,
        source: BookSource(
          bookSourceUrl: 'https://example.com',
          bookSourceName: 'Example',
        ),
      );
      ext.inject();

      expect(
        runtime!.evaluate('typeof source.getLoginInfo').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof source.getKey').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof source.getVariable').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof source.setVariable').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof source.getHeaderMap').stringResult,
        'function',
      );
      expect(
        runtime!.evaluate('typeof source.putLoginInfo').stringResult,
        'function',
      );
      expect(runtime!.evaluate('typeof source.put').stringResult, 'function');
      expect(runtime!.evaluate('typeof source.get').stringResult, 'function');
    });

    test('non-interactive validation rejects interactive JS calls', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(
        runtime!,
        source: BookSource(
          bookSourceUrl: 'https://example.com',
          bookSourceName: 'Example',
        ),
      );
      ext.inject();

      Future<dynamic> runRule(String source) {
        return SourceValidationContext.runNonInteractive(() async {
          final rewritten = AsyncJsRewriter.rewrite(source);
          final (callId, future) = ext.registerRuleCall();
          final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);
          final evalResult = runtime!.evaluate(wrapped);
          expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
          runtime!.executePendingJob();
          return future;
        });
      }

      await expectLater(
        runRule('java.startBrowserAwait("https://example.com/captcha", "驗證")'),
        throwsA(
          predicate((Object error) => error.toString().contains('不支援互動驗證')),
        ),
      );
      await expectLater(
        runRule('java.getVerificationCode("https://example.com/code.png")'),
        throwsA(
          predicate((Object error) => error.toString().contains('不支援互動驗證')),
        ),
      );
      // 不需要互動的網頁渲染（java.webView）在校驗裡照常執行（ADR 0033）。
    });

    test('Jsoup shim supports importClass and select text helpers', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<div class="introduce">简介</div><div class="text-row">标签1</div><div class="text-row">标签2</div>');
        doc.select('.introduce').text() + '|' + doc.select('.text-row:eq(0)').text();
      ''');

      expect(result.stringResult, '简介|标签1');
    });

    test('Jsoup shim supports select().first().attr()', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<div><a href="/chapter/1">第一章</a><a href="/chapter/2">第二章</a></div>');
        doc.select('a').first().attr('href');
      ''');

      expect(result.stringResult, '/chapter/1');
    });

    test('Jsoup selection shim supports nested select()', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var form = Jsoup.parse('<div><form action="/search"><input name="_token" value="abc"></form></div>').select('form');
        form.select('[name=_token]').attr('value');
      ''');

      expect(result.stringResult, 'abc');
    });

    test('java HMacHex and desEncodeToBase64String are exposed', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final hmac = runtime!.evaluate(r'''
        java.HMacHex("hello", "HmacMD5", "key").toString();
      ''');
      final des = runtime!.evaluate(r'''
        java.desEncodeToBase64String(
          "hello",
          "12345678",
          "DES/ECB/PKCS5Padding",
          ""
        ).toString();
      ''');

      expect(hmac.stringResult, '04130747afca4d79e32e87cf2104f087');
      expect(des.stringResult, 'uhbGoCVxJa8=');
    });

    test('java encodeURI uses component-style escaping', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        java.encodeURI("a+b/c?d=e&f=中");
      ''');

      expect(result.stringResult, 'a%2Bb%2Fc%3Fd%3De%26f%3D%E4%B8%AD');
    });

    test('java.randomUUID returns a uuid-like token', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        java.randomUUID().toString();
      ''');

      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(result.stringResult),
        isTrue,
      );
    });

    test('Jsoup shim supports selectFirst().attributes()', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<li data-order="7"><a href="/chapter/1" data-real="第一章">第一章</a></li>');
        var attrs = Array.from(doc.selectFirst('a').attributes());
        attrs.join('|');
      ''');

      expect(result.stringResult, contains('href="/chapter/1"'));
      expect(result.stringResult, contains('data-real="第一章"'));
    });

    test('Jsoup shim exposes selection.size() and eachText()', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<div><h1>标题</h1><strong>作者</strong><strong>分类</strong></div>');
        var texts = doc.select('h1,strong').eachText();
        doc.select('strong').size() + '|' + texts.size() + '|' + texts.get(1);
      ''');

      expect(result.stringResult, '2|3|作者');
    });

    test('Jsoup shim supports data() and remove() mutations', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<style>.hide:nth-last-child(2){display:none}</style><div class="hide">X</div><div class="show">Y</div>');
        var selector = String(doc.select("style").first().data()).replace(/{display:none}/g, ",").slice(0, -1);
        doc.select(selector).remove();
        doc.html();
      ''');

      expect(result.stringResult.contains('>X<'), isFalse);
      expect(result.stringResult.contains('>Y<'), isTrue);
    });

    test(
      'Jsoup shim normalizes regex selectors used by detail cleanup rules',
      () {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        final ext = JsExtensions(runtime!);
        ext.inject();

        final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<html><head><meta property="keep" content="1"><script>bad()</script></head><body><footer>F</footer><div class="footbar">X</div><a href="/cat"><span>分类</span></a><input value="1"><article>正文</article></body></html>');
        doc.select('script,noscript,style,head>:not(meta,title),footer,[class~=^foot],[id~=^foot],a:has(>:last-child:matchesOwn(^分类$)),[value]').remove();
        doc.html();
      ''');

        expect(result.stringResult.contains('<meta property="keep"'), isTrue);
        expect(result.stringResult.contains('<script>'), isFalse);
        expect(result.stringResult.contains('<footer>'), isFalse);
        expect(result.stringResult.contains('class="footbar"'), isFalse);
        expect(result.stringResult.contains('href="/cat"'), isFalse);
        expect(result.stringResult.contains('<input value="1">'), isFalse);
        expect(result.stringResult.contains('<article>正文</article>'), isTrue);
      },
    );

    test('Jsoup shim preserves middle nodes for nth-child removals', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        importClass(org.jsoup.Jsoup);
        var doc = Jsoup.parse('<style>.list>li:nth-child(1){display:none}.list>li:nth-last-child(1){display:none}</style><ul class="list"><li>A</li><li>B</li><li>C</li></ul>');
        var selector = String(doc.select("style").first().data()).replace(/{display:none}/g, ",").slice(0, -1);
        doc.select(selector).remove();
        doc.html();
      ''');

      expect(result.stringResult.contains('>A<'), isFalse);
      expect(result.stringResult.contains('>B<'), isTrue);
      expect(result.stringResult.contains('>C<'), isFalse);
    });

    test('JavaImporter shim supports Base64 and GZIP decode loops', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();
      final payload = base64Encode(gzip.encode(utf8.encode('解压成功')));

      final result = runtime!.evaluate('''
        var payload = "$payload";
        var javaImport = new JavaImporter();
        javaImport.importPackage(
          Packages.java.lang,
          Packages.java.io,
          Packages.java.util,
          Packages.java.util.zip
        );
        with(javaImport) {
          function decode(content) {
            var decoded = Base64.getDecoder().decode(String(content));
            var output = new ByteArrayOutputStream();
            var input = new ByteArrayInputStream(decoded);
            var gzipInput = new GZIPInputStream(input);
            var buffer = String(" ").getBytes();
            while (true) {
              var read = gzipInput.read(buffer);
              if (read > 0) {
                output.write(buffer, 0, read);
              } else {
                return output.toString();
              }
            }
          }
          decode(payload);
        }
      ''');

      expect(result.stringResult, '解压成功');
    });

    test('Java String getBytes returns a writable buffer', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        var javaImport = new JavaImporter();
        javaImport.importPackage(Packages.java.lang);
        with(javaImport) {
          String(" ").getBytes().length;
        }
      ''');

      expect(result.stringResult, '1');
    });

    test(
      'java.gzipToString accepts byte arrays from base64DecodeToByteArray',
      () {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        final ext = JsExtensions(runtime!);
        ext.inject();
        final payload = base64Encode(gzip.encode(utf8.encode('解压成功')));

        final result = runtime!.evaluate('''
        var payload = "$payload";
        java.gzipToString(java.base64DecodeToByteArray(payload), "UTF-8");
      ''');

        expect(result.stringResult, '解压成功');
      },
    );

    test('java.base64Encode supports byte arrays', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        var javaImport = new JavaImporter();
        javaImport.importPackage(Packages.java.lang);
        with(javaImport) {
          java.base64Encode(String("hello").getBytes());
        }
      ''');

      expect(result.stringResult, 'aGVsbG8=');
    });

    test('String.replaceAll follows Legado Java regex semantics', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        var javaImport = new JavaImporter();
        javaImport.importPackage(Packages.java.lang);
        with(javaImport) {
          "abc123".replaceAll("[a-z]+", "") + "|" +
          String("第12章").replaceAll("\\d+", "#");
        }
      ''');

      expect(result.stringResult, '123|第#章');
    });

    test('global unpack helper decodes packed source tokens', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        unpack('0("1 2");', 3, 3, ['alert', 'hello', 'world']);
      ''');

      expect(result.stringResult, 'alert("hello world");');
    });

    test(
      'java.aesBase64DecodeToString helper matches symmetric crypto output',
      () {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        final ext = JsExtensions(runtime!);
        ext.inject();

        final result = runtime!.evaluate(r'''
        var key = "1234567890123456";
        var iv = "6543210987654321";
        var crypto = java.createSymmetricCrypto("AES/CBC/PKCS5Padding", key, iv);
        var encoded = crypto.encryptBase64("hello");
        var decoded = java.aesBase64DecodeToString(
          encoded,
          key,
          "AES/CBC/PKCS5Padding",
          iv
        );
        encoded + "|" + decoded;
      ''');

        expect(result.stringResult, 'WcQYnUww0VTFgh1HE4gepg==|hello');
      },
    );

    test('JavaImporter shim supports javax crypto, Arrays.copyOfRange, and digestHex', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        var javaImport = new JavaImporter();
        javaImport.importPackage(
          Packages.java.lang,
          Packages.java.util,
          Packages.javax.crypto.spec,
          Packages.javax.crypto
        );
        with(javaImport) {
          var keyBytes = String("1234567890123456").getBytes();
          var ivBytes = String("6543210987654321").getBytes();
          var prefix = String(Arrays.copyOfRange(keyBytes, 0, 3)).toString();
          var parsed = Integer.parseInt("ff", 16);
          var digest = java.digestHex("hello", "sha-256");

          var encrypted = java.base64DecodeToByteArray(
            java.createSymmetricCrypto("AES/CBC/PKCS5Padding", "1234567890123456", "6543210987654321")
              .encryptBase64("hello")
          );
          var decryptCipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
          decryptCipher.init(2, SecretKeySpec(keyBytes, "AES"), IvParameterSpec(ivBytes));
          var plain = String(decryptCipher.doFinal(encrypted)).toString();

          prefix + "|" + parsed + "|" + digest.length() + "|" + plain;
        }
      ''');

      expect(result.stringResult, '123|255|64|hello');
    });

    test(
      'Cipher.doFinal decrypts large byte arrays without corrupting payloads',
      () {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        final ext = JsExtensions(runtime!);
        ext.inject();

        final result = runtime!.evaluate(r'''
        var javaImport = new JavaImporter();
        javaImport.importPackage(
          Packages.java.lang,
          Packages.java.util,
          Packages.javax.crypto.spec,
          Packages.javax.crypto
        );
        with(javaImport) {
          var prefix = '{"book":[';
          var suffix = '],"ok":true}';
          var filler = "章节内容".repeat(20000);
          var plainText = prefix + JSON.stringify({ title: "深空彼岸", body: filler }) + suffix;
          var keyBytes = String("12345678901234561234567890123456").getBytes();
          var ivBytes = String("6543210987654321").getBytes();

          var encrypted = java.base64DecodeToByteArray(
            java.createSymmetricCrypto(
              "AES/CBC/PKCS5Padding",
              keyBytes,
              ivBytes
            ).encryptBase64(plainText)
          );

          var decryptCipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
          decryptCipher.init(2, SecretKeySpec(keyBytes, "AES"), IvParameterSpec(ivBytes));
          var decoded = String(decryptCipher.doFinal(encrypted)).toString();

          decoded.length + "|" + decoded.substring(0, 8) + "|" + decoded.substring(decoded.length - 11);
        }
      ''');

        final parts = result.stringResult.split('|');
        expect(parts.length, 3);
        expect(int.tryParse(parts[0]), isNotNull);
        expect(parts[1], '{"book":');
        expect(parts[2], ',"ok":true}');
      },
    );

    test('Cipher.doFinal matches createSymmetricCrypto for signed byte key material', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        function intToByte(i) {
          var b = i & 0xFF;
          if (b >= 128) {
            return -1 * (128 - (b % 128));
          }
          return b;
        }

        var javaImport = new JavaImporter();
        javaImport.importPackage(
          Packages.java.lang,
          Packages.java.util,
          Packages.javax.crypto.spec,
          Packages.javax.crypto
        );
        with(javaImport) {
          var prefix = "T2CP9CY7FAQIBEZW";
          var suffix = "PE3PHV5A4NVHZ73W";
          var sha = java.digestHex(prefix, "sha-256").toString();
          var md5 = java.md5Encode(suffix).toString();
          var keyBytes = [];
          for (var i = 0; i < sha.length; i += 2) {
            keyBytes.push(intToByte(Integer.parseInt(sha.substring(i, i + 2), 16)));
          }
          var suffixBytes = String(suffix).getBytes();
          var md5Bytes = String(md5).getBytes();
          var ivBytes = [];
          for (var j = 0; j < 16; j++) {
            ivBytes[j] = (md5Bytes[j] ^ suffixBytes[j]) ^ (-1);
          }

          var plain = '{"book":[{"title":"深空彼岸"}],"ok":true}';
          var encrypted = java.base64DecodeToByteArray(
            java.createSymmetricCrypto("AES/CBC/PKCS5Padding", keyBytes, ivBytes)
              .encryptBase64(plain)
          );

          var decryptCipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
          decryptCipher.init(2, SecretKeySpec(keyBytes, "AES"), IvParameterSpec(ivBytes));
          String(decryptCipher.doFinal(encrypted)).toString();
        }
      ''');

      expect(result.stringResult, '{"book":[{"title":"深空彼岸"}],"ok":true}');
    });

    test('java.toNumChapter matches Legado chapter numbering helper', () {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();

      final result = runtime!.evaluate(r'''
        java.toNumChapter("第十二章 归来");
      ''');

      expect(result.stringResult, '第12章 归来');
    });

    test(
      'async java.ajax results support chained Java-style replaceAll rules',
      () async {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        final ext = JsExtensions(runtime!);
        ext.inject();
        runtime!.evaluate(
          'java.ajax = function() { '
          '  return Promise.resolve(\'<style>gone</style><p>正文</p>\'); '
          '}; '
          'var baseUrl = "https://fqbook.cc/read-61918.html"; '
          'var result = \'<script>var url="_getcontent.php?id=61918&v=test-token"</script>\';',
        );

        final rewritten = AsyncJsRewriter.rewrite(r'''
java.ajax(baseUrl.replace('read-', '_getcontent.php?id=').replace('.html','&v=' + result.match(/&v=(.*?)"/)[1])).replaceAll('<style.*style>','').replaceAll('<([^<]*?)class(.*?)</(.*?)>','')
''');
        final (callId, future) = ext.registerRuleCall();
        final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

        final evalResult = runtime!.evaluate(wrapped);
        expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
        runtime!.executePendingJob();

        final resolved = await future;
        expect(resolved, '<p>正文</p>');
      },
    );

    test('java.connect wraps responses with raw request url parity', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      final ext = JsExtensions(runtime!);
      ext.inject();
      runtime!.evaluate(r'''
        __asyncCall = function(channel, payload) {
          if (channel !== 'connect') {
            return Promise.reject(new Error('unexpected channel: ' + channel));
          }
          return Promise.resolve({
            body: 'OK',
            url: 'https://canonical.example/e/search/result/index.php?searchid=42',
            requestUrl: 'http://m.666biquge.com',
            code: 200,
            message: 'OK',
            headers: {},
            redirects: ['https://canonical.example/e/search/result/index.php?searchid=42']
          });
        };
      ''');

      final rewritten = AsyncJsRewriter.rewrite(r'''
        var res = java.connect("http://m.666biquge.com");
        [
          res.raw().request().url(),
          res.url(),
          String(res.code()),
          String(res.statusCode()),
          String(res.isSuccessful())
        ].join("|")
      ''');
      final (callId, future) = ext.registerRuleCall();
      final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

      final evalResult = runtime!.evaluate(wrapped);
      expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
      runtime!.executePendingJob();

      final resolved = await future;
      expect(
        resolved,
        'https://canonical.example/e/search/result/index.php?searchid=42|'
        'https://canonical.example/e/search/result/index.php?searchid=42|'
        '200|200|true',
      );
    });

    test(
      'java.connect normalizes bare-origin raw request urls with slash',
      () async {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        final ext = JsExtensions(runtime!);
        ext.inject();
        runtime!.evaluate(r'''
        __asyncCall = function(channel, payload) {
          if (channel !== 'connect') {
            return Promise.reject(new Error('unexpected channel: ' + channel));
          }
          return Promise.resolve({
            body: '',
            url: 'http://m.666biquge.com',
            requestUrl: 'http://m.666biquge.com',
            code: 200,
            message: 'OK',
            headers: {},
            redirects: []
          });
        };
      ''');

        final rewritten = AsyncJsRewriter.rewrite(r'''
        java.connect("http://m.666biquge.com").raw().request().url() + "modules/article/waps.php"
      ''');
        final (callId, future) = ext.registerRuleCall();
        final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

        final evalResult = runtime!.evaluate(wrapped);
        expect(evalResult.isError, isFalse, reason: evalResult.stringResult);
        runtime!.executePendingJob();

        final resolved = await future;
        expect(resolved, 'http://m.666biquge.com/modules/article/waps.php');
      },
    );
  }, skip: quickJsSkip);
}
