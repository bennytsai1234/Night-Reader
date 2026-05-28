import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_engine.dart';

import '../../../test_helper.dart';

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('JsEngine', () {
    test('evaluateAsync handles sync-only helper calls', () async {
      final engine = JsEngine();

      final digest = await engine.evaluateAsync(r'''
java.HMacHex("hello", "HmacSHA256", "key").toString()
''');
      final encrypted = await engine.evaluateAsync(r'''
java.desEncodeToBase64String("hello", "12345678", "DES/ECB/PKCS5Padding", "").toString()
''');

      expect(digest, isA<String>());
      expect((digest as String), isNotEmpty);
      expect(encrypted, isA<String>());
      expect((encrypted as String), isNotEmpty);
    }, skip: quickJsSkip);

    test('evaluateAsync handles sync-only scope writes', () async {
      final engine = JsEngine();

      final random = await engine.evaluateAsync(r'''
java.randomUUID().toString().replace("-", "").toLowerCase()
''');
      final putOnly = await engine.evaluateAsync(r'''
java.put("tmpToken","abc")
''');
      final getOnly = await engine.evaluateAsync(r'''
java.get("tmpToken")
''');
      final computedPutGet = await engine.evaluateAsync(r'''
java.put("tmpToken", java.randomUUID().toString().replace("-", "").toLowerCase());
java.get("tmpToken")
''');
      final result = await engine.evaluateAsync(r'''
tmpToken=java.randomUUID().toString().replace("-", "").toLowerCase();
java.put("tmpToken",tmpToken);
java.get("tmpToken")
''');

      expect(random, isA<String>());
      expect((random as String), isNotEmpty);
      expect(putOnly, 'abc');
      expect(getOnly, 'abc');
      expect(computedPutGet, isA<String>());
      expect((computedPutGet as String), isNotEmpty);
      expect(result, isA<String>());
      expect((result as String), isNotEmpty);
    }, skip: quickJsSkip);

    test(
      'evaluateAsync falls back to sync execution for sync-only url scripts',
      () async {
        final engine = JsEngine();

        final result = await engine.evaluateAsync(r'''
time=1;
tmpToken=java.randomUUID().toString().replace("-", "").toLowerCase();
java.put("tmpToken",tmpToken);
option={"method":"POST","body":"keyword=我的"};
"/goway/search?_p="+java.encodeURI(java.desEncodeToBase64String("hello","12345678","DES/ECB/PKCS5Padding",""))+","+JSON.stringify(option)
''');

        expect(result, startsWith('/goway/search?_p='));
        expect(result, contains(',{"method":"POST","body":"keyword=我的"}'));
      },
      skip: quickJsSkip,
    );
  });
}
