import 'js_engine.dart';

/// 替換規則的「替換為」寫 `@js:` 時跑的那段 JS（同 Legado
/// `RegexExtensions.replace`）：對到的字放在 `result`，傳回值轉成字串。每個
/// isolate 留一個引擎重複用（處理正文的背景 isolate、規則試跑的主 isolate）。
/// 這個 isolate 建不起 JS 引擎時丟 [StateError]，這條規則不套。
String runReplacementJs(String code, String matched) {
  final engine = _engine ??= JsEngine();
  if (!engine.isAvailable) throw StateError('JS 引擎不能用');
  return '${engine.evaluate(code, context: {'result': matched})}';
}

JsEngine? _engine;
