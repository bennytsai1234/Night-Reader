import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/async_js_rewriter.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';
import 'package:night_reader/core/engine/js/js_rule_async_wrapper.dart';

import '../../../test_helper.dart';

/// Promise bridge 端到端整合測試
///
/// 驗證 P5 async JS 改造的完整管線：
///   rule JS → AsyncJsRewriter → JsRuleAsyncWrapper → QuickJS eval →
///   __asyncCall → onMessage → Dart async 工作 → resolveJsPending →
///   executePendingJob → await 繼續 → __ruleDone → Dart Completer
///
/// 為避免觸碰 production 的 `java.ajax` → real HttpClient 路徑，
/// 測試直接只執行 [JsExtensions.setupPromiseBridge] 並自己安裝
/// 一個走 `ajax` channel 的 `java` shim，channel 的 Dart handler 完全
/// 由測試案例控制 (回傳 / 延遲 / reject)。
void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('Promise bridge integration', () {
    JavascriptRuntime? runtime;
    JsExtensions? ext;
    Object? runtimeError;

    // 測試可調的 ajax 響應表
    final responses = <String, String>{};
    final delays = <String, Duration>{};
    final rejects = <String, String>{};
    var callCount = 0;
    final callOrder = <String>[];

    setUp(() {
      responses.clear();
      delays.clear();
      rejects.clear();
      callCount = 0;
      callOrder.clear();
      runtimeError = null;
      try {
        runtime = getJavascriptRuntime();
        ext = JsExtensions(runtime!);
        ext!.setupPromiseBridge();

        // 安裝測試用 java shim。
        runtime!.evaluate('''
            var java = {
              ajax: function(u) { return __asyncCall("ajax", u); },
              post: function(u, body, headers) {
                return __asyncCall("ajax", [u, body || "", headers || null]);
              },
              log: function(msg) { return msg; }
            };
          ''');

        // 測試專用 ajax handler — 根據表控制 resolve / reject / delay
        runtime!.onMessage('ajax', (dynamic args) {
          final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
          final url =
              parsed.payload is List
                  ? (parsed.payload as List)[0].toString()
                  : parsed.payload.toString();
          callCount++;
          callOrder.add(url);
          final delay = delays[url] ?? Duration.zero;
          // 用 Future.delayed(Duration.zero) 確保 handler 先 return null
          // 後再進行 resolve，避免 re-entry onMessage
          Future.delayed(delay, () {
            if (rejects.containsKey(url)) {
              ext!.rejectJsPending(parsed.callId, Exception(rejects[url]));
            } else {
              ext!.resolveJsPending(
                parsed.callId,
                responses[url] ?? 'MISS:$url',
              );
            }
          });
          return null;
        });
      } catch (error) {
        runtime = null;
        runtimeError = error;
      }
    });

    tearDown(() {
      runtime?.dispose();
      runtime = null;
      ext = null;
    });

    /// 執行 rule JS 並回傳最終結果 (對標 JsEngine.evaluateAsync)
    Future<dynamic> runRule(String src) async {
      final rewritten = AsyncJsRewriter.rewrite(src);
      final (id, future) = ext!.registerRuleCall();
      final wrapped = JsRuleAsyncWrapper.wrap(rewritten, id);
      final res = runtime!.evaluate(wrapped);
      if (res.isError) {
        ext!.cancelRuleCall(
          id,
          StateError('JS evaluate error: ${res.stringResult}'),
        );
      } else {
        runtime!.executePendingJob();
      }
      return future;
    }

    test('single java.ajax resolves with Dart-provided body', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['http://a'] = 'BODY_A';

      final result = await runRule('java.ajax("http://a")');

      expect(result, 'BODY_A');
      expect(callCount, 1);
    });

    test('sequential chain: two awaited ajax calls preserve order', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['http://a'] = 'A';
      responses['http://b'] = 'B';

      final result = await runRule('''
        var a = java.ajax("http://a");
        var b = java.ajax("http://b");
        a + "|" + b
      ''');

      expect(result, 'A|B');
      expect(callCount, 2);
      expect(callOrder, ['http://a', 'http://b']);
    });

    test('nested: inner result feeds outer URL', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['first'] = 'http://second';
      responses['http://second'] = 'FINAL';

      final result = await runRule('java.ajax(java.ajax("first"))');

      expect(result, 'FINAL');
      expect(callCount, 2);
      expect(callOrder, ['first', 'http://second']);
    });

    test('error propagation: rejected Promise → JS try/catch', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      rejects['http://err'] = 'network boom';

      final result = await runRule('''
        var out;
        try {
          out = "got:" + java.ajax("http://err");
        } catch (e) {
          out = "caught:" + e.message;
        }
        out
      ''');

      expect(result, contains('caught:'));
      expect(result, contains('network boom'));
    });

    test('unhandled rejection surfaces as rule-level error', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      rejects['http://boom'] = 'kaboom';

      await expectLater(
        runRule('java.ajax("http://boom")'),
        throwsA(
          predicate(
            (e) => e.toString().contains('kaboom'),
            'error message contains "kaboom"',
          ),
        ),
      );
    });

    test(
      'out-of-order async resolution still returns correct values',
      () async {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        responses['slow'] = 'SLOW';
        responses['fast'] = 'FAST';
        delays['slow'] = const Duration(milliseconds: 50);
        delays['fast'] = const Duration(milliseconds: 5);

        // 順序 await — slow 先叫但 handler 回應較晚
        final result = await runRule('''
        var s = java.ajax("slow");
        var f = java.ajax("fast");
        s + "+" + f
      ''');

        expect(result, 'SLOW+FAST');
        expect(callCount, 2);
        // JS 依然以程式碼順序叫 handler，即使 Dart 側 resolve 順序相反
        expect(callOrder, ['slow', 'fast']);
      },
    );

    test('pure-sync rule JS still works through async wrapper', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      // 沒有任何 java/cache/* 呼叫，但依然走整個 wrapper 路徑
      final result = await runRule('''
        var x = 3;
        var y = 4;
        x * x + y * y
      ''');

      expect(result, 25);
      expect(callCount, 0);
    });

    test('mixed: sync + async in same rule', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['http://data'] = 'PAYLOAD';

      final result = await runRule('''
        var prefix = "[" + (1 + 2) + "]";
        var body = java.ajax("http://data");
        prefix + body
      ''');

      expect(result, '[3]PAYLOAD');
    });

    test('method chain: (await java.ajax(url)).length works', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['http://len'] = 'hello';

      final result = await runRule('java.ajax("http://len").length');

      expect(result, 5);
    });

    test('cancelRuleCall rejects pending future from Dart side', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      // 取一個 id 但永遠不 sendMessage，手動 cancel
      final (id, future) = ext!.registerRuleCall();
      ext!.cancelRuleCall(id, StateError('manual cancel'));

      await expectLater(
        future,
        throwsA(
          predicate(
            (e) => e.toString().contains('manual cancel'),
            'error contains manual cancel',
          ),
        ),
      );
    });

    test(
      'concurrent rules on same runtime each complete independently',
      () async {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        responses['http://x'] = 'X_VAL';
        responses['http://y'] = 'Y_VAL';
        delays['http://x'] = const Duration(milliseconds: 20);
        delays['http://y'] = const Duration(milliseconds: 5);

        // 在同一個 runtime 上同時 fire 兩個 rule
        final r1 = runRule('java.ajax("http://x")');
        final r2 = runRule('java.ajax("http://y")');
        final results = await Future.wait([r1, r2]);

        expect(results[0], 'X_VAL');
        expect(results[1], 'Y_VAL');
        expect(callCount, 2);
      },
    );

    test('async rewriter correctly injects await for var assignment', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['http://x'] = 'XX';

      // 直接寫 raw JS — 驗證 rewriter 自動加 await 後仍能得到 XX
      // (若 rewriter 漏加 await, 結果會是 "[object Promise]" 之類)
      final result = await runRule('''
        var r = java.ajax("http://x");
        "got=" + r
      ''');

      expect(result, 'got=XX');
    });

    test('final if statement preserves branch completion value', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }

      final result = await runRule('''
        var enabled = true;
        if (enabled) {
          "branch:yes";
        } else {
          "branch:no";
        }
      ''');

      expect(result, 'branch:yes');
    });

    test('final if statement can resolve awaited branch results', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }
      responses['http://branch'] = 'BRANCH_OK';

      final result = await runRule('''
        if (1 < 2) {
          java.ajax("http://branch");
        } else {
          "MISS";
        }
      ''');

      expect(result, 'BRANCH_OK');
    });

    test(
      'realistic regex + try content scripts preserve logged completion',
      () async {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }
        runtime!.evaluate(r'''
          var result = '{"url":"https://api.example.com/content"}';
          var baseUrl = 'https://api.example.com/book/1';
        ''');
        responses['https://api.example.com/content'] =
            '{"content":"chapter body"}';

        final result = await runRule(r'''
        var regex = /\{"url"\s*:\s*"[^"]+"\}/;
        var match = result.match(regex);
        if (match) {
          try {
            var jsonObj = JSON.parse(match[0]);
            var response = java.post(jsonObj.url, '', {});
            if (response) {
              var content = JSON.parse(response)["content"];
              java.log(content);
            } else {
              java.log("EMPTY");
            }
          } catch (e) {
            java.log("ERR:" + e.message);
          }
        } else {
          java.log("MISS");
        }
      ''');

        expect(result, 'chapter body');
      },
    );
  }, skip: quickJsSkip);
}
