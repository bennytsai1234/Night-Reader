import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';

import '../js_extensions.dart';
import 'js_blocking_tasks.dart';

/// 網址裡的 JS 與登入檢查（`loginCheckJs`）裡的 `java` 是那個請求，同
/// Legado 的 AnalyzeUrl：多了 `url`、`ruleUrl`、`headerMap`、`type`、
/// `serverID` 與 `initUrl()`、`getStrResponse()` 這些。其他規則裡沒有。
///
/// 規則 JS 改了 `java.url` 或 `java.headerMap` 之後抓，照改過的送出。
extension JsUrlExtensions on JsExtensions {
  void injectUrlExtensions() {
    onBlocking('urlInit', (_) {
      final request = _request();
      request.initUrl();
      return request.toJs();
    });
    onBlocking('urlStrResponse', (payload) {
      final args = payload as List;
      final request = _request()..applyJs(args[0]);
      return BlockingCall.run(
        requestResponse(
          request,
          jsStr: args[1] as String?,
          sourceRegex: args[2] as String?,
          useWebView: args[3] != false,
        ),
      );
    });
    onBlocking('urlBytes', (state) {
      final request = _request()..applyJs(state);
      return BlockingCall.run(responseBytes(request));
    });
    runtime.onMessage('urlUserAgent', (state) {
      final request = _request()..applyJs(state);
      return request.getUserAgent();
    });
    runtime.evaluate(_js);
  }

  AnalyzeUrl _request() {
    final rule = ruleContext;
    final request = rule is AnalyzeRule ? rule.urlContext : null;
    if (request == null) {
      throw StateError('只有網址裡的 JS 與登入檢查能用這個請求的方法');
    }
    return request;
  }

  static const String _js = r'''
(function(global) {
  var java = global.java;
  var current = null;
  function state() {
    return { url: String(java.url), headerMap: JSON.parse(JSON.stringify(java.headerMap)) };
  }
  function apply(s) {
    current = s;
    java.url = s.url;
    java.ruleUrl = s.ruleUrl;
    java.headerMap = new Packages.java.util.LinkedHashMap();
    Object.keys(s.headerMap || {}).forEach(function(k) { java.headerMap.put(k, s.headerMap[k]); });
    java.type = s.type;
    java.serverID = s.serverID;
  }
  function okHttpResponse(res) {
    // OkHttp 的 Response：body() 是 ResponseBody，用 string() 讀。
    var text = res.body();
    res.body = function() {
      return {
        string: function() { return text; },
        bytes: function() { return java.strToBytes(text); },
        toString: function() { return text; }
      };
    };
    return res;
  }
  var members = {
    initUrl: function() { apply(__lrWait('urlInit', null)); },
    getStrResponse: function(jsStr, sourceRegex, useWebView) {
      return buildHttpResponse(__lrWait('urlStrResponse', [
        state(),
        jsStr == null ? null : String(jsStr),
        sourceRegex == null ? null : String(sourceRegex),
        useWebView !== false
      ]));
    },
    getResponse: function() {
      return okHttpResponse(buildHttpResponse(__lrWait('urlStrResponse', [state(), null, null, false])));
    },
    getByteArray: function() { return __lrWait('urlBytes', state()); },
    getInputStream: function() {
      return new Packages.java.io.ByteArrayInputStream(this.getByteArray());
    },
    getUserAgent: function() { return sendMessage('urlUserAgent', JSON.stringify(state())); },
    isPost: function() { return current.method === 'POST'; },
    getUrl: function() { return java.url; },
    setUrl: function(value) { java.url = value; },
    getRuleUrl: function() { return java.ruleUrl; },
    setRuleUrl: function(value) { java.ruleUrl = value; },
    getHeaderMap: function() { return java.headerMap; },
    getType: function() { return java.type; },
    setType: function(value) { java.type = value; },
    getServerID: function() { return java.serverID; }
  };
  var fields = ['url', 'ruleUrl', 'headerMap', 'type', 'serverID'];
  global.__lrUseUrl = function(s) {
    if (s == null) {
      if (current == null) return;
      Object.keys(members).concat(fields).forEach(function(k) { delete java[k]; });
      current = null;
      return;
    }
    Object.keys(members).forEach(function(k) { java[k] = members[k]; });
    apply(s);
  };
})(globalThis);
''';
}
