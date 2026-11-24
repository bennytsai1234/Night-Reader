import 'js_engine.dart';

/// 替換規則的「替換為」寫 `@js:` 時跑的那段 JS（同 Legado
/// `RegexExtensions.replace`）：對到的字放在 `result`，傳回值轉成字串。每個
/// isolate 留一個引擎重複用（處理正文的背景 isolate、選字建規則與規則試跑
/// 各自的 isolate，它們都沒有 rootBundle，開頭要先設 `fetchPolyfillSource`）。
/// 建不起 JS 引擎、或 JS 沒有傳回值時丟 [StateError]，這條規則不套（Legado
/// 拿到 null 時同樣出錯）。
String runReplacementJs(String code, String matched) {
  final engine = _engine ??= JsEngine();
  if (!engine.isAvailable) throw StateError('JS 引擎不能用');
  final value = engine.evaluate(code, context: {'result': matched});
  if (value == null) throw StateError('JS 沒有傳回值');
  return '$value';
}

JsEngine? _engine;
