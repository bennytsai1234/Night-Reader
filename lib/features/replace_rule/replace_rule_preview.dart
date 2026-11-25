import 'package:flutter_js/flutter_js.dart' show fetchPolyfillSource;
import 'package:night_reader/core/engine/js/replacement_js.dart';

import 'dart:async';
import 'dart:isolate';

import 'package:night_reader/core/chinese/replace_rule_script.dart';
import 'package:night_reader/core/models/replace_rule.dart';

import 'replace_rule_deadline.dart';

/// 一次試跑的結果。
sealed class ReplaceRulePreviewResult {
  const ReplaceRulePreviewResult();

  /// 結果區顯示的字。
  String get display;
}

/// 規則都套用完了，[text] 是套用後的字。
final class ReplaceRulePreviewDone extends ReplaceRulePreviewResult {
  const ReplaceRulePreviewDone(this.text);

  final String text;

  @override
  String get display => text;
}

/// [rule] 跑超過它的執行期限（[ReplaceRule.getValidTimeoutMillisecond]），
/// 已經停掉。
final class ReplaceRulePreviewTimedOut extends ReplaceRulePreviewResult {
  const ReplaceRulePreviewTimedOut(this.rule);

  final ReplaceRule rule;

  /// 例如「規則「去廣告」執行超過 3 秒，已停止」。
  @override
  String get display {
    final ms = rule.getValidTimeoutMillisecond();
    final limit = ms % 1000 == 0 ? '${ms ~/ 1000} 秒' : '$ms 毫秒';
    final name = rule.name.trim();
    return '規則${name.isEmpty ? '' : '「$name」'}執行超過 $limit，已停止';
  }
}

/// 替換規則的試跑：編輯面板的「規則除錯」與替換規則面板的「執行測試」。
///
/// 使用者寫的正則可能回溯很久（`^(a+)+$` 遇到一長串 a 接一個 `!`），所以每次
/// 試跑開一個新的 isolate 依序套用規則，畫面的 isolate 不跑正則、照常回應。
/// 一條規則跑超過它的執行期限就結束那個 isolate（正則跑到一半也停得下來）。
/// 開始下一次試跑或 [cancel] 時，上一次還沒跑完的直接結束、傳回 null，舊的
/// 結果不會晚到蓋掉新的。
class ReplaceRulePreview {
  _PreviewRun? _current;

  /// 依序套用 [rules] 到 [text]；被下一次試跑或 [cancel] 取代時傳回 null。
  /// 規則照閱讀器一樣，字面與轉成 [chineseConvertType] 的寫法都比、每一處
  /// 只換一次（[ReplaceRuleScript.applyMatchingVariants]）：[text] 是轉過
  /// 繁簡的字。
  Future<ReplaceRulePreviewResult?> run(
    List<ReplaceRule> rules,
    String text, {
    int chineseConvertType = 0,
  }) {
    cancel();
    if (rules.isEmpty) return Future.value(ReplaceRulePreviewDone(text));
    final run = _current = _PreviewRun(rules, [
      // 規則的字在這裡轉：試跑的 isolate 沒有繁簡字典。
      for (final rule in rules) rule.matchVariants([chineseConvertType]),
    ], text);
    return run.result;
  }

  /// 停掉還沒跑完的試跑；面板關掉時呼叫。
  void cancel() {
    _current?.finish(null);
    _current = null;
  }
}

class _PreviewRun {
  _PreviewRun(this._rules, List<List<ReplaceRule>> variants, String text) {
    _port.listen(_onMessage);
    Isolate.spawn(
      _previewMain,
      (_port.sendPort, variants, text),
      onExit: _port.sendPort,
      onError: _port.sendPort,
      debugName: 'replace-rule-preview',
    ).then(
      (isolate) {
        if (_completer.isCompleted) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_completer.isCompleted) {
          _completer.completeError(error, stack);
          finish(null);
        }
      },
    );
  }

  final List<ReplaceRule> _rules;
  final ReceivePort _port = ReceivePort();
  final Completer<ReplaceRulePreviewResult?> _completer = Completer();
  Isolate? _isolate;
  late final ReplaceRuleDeadline _deadline = ReplaceRuleDeadline(
    (rule) => finish(ReplaceRulePreviewTimedOut(rule)),
  );

  Future<ReplaceRulePreviewResult?> get result => _completer.future;

  void _onMessage(Object? message) {
    switch (message) {
      case ('rule', final int index):
        _deadline.start(_rules[index]);
      case ('done', final String text):
        finish(ReplaceRulePreviewDone(text));
      // onError 送來 [錯誤, 堆疊]、onExit 送來 null：還沒交回結果就結束了。
      default:
        if (!_completer.isCompleted) {
          _completer.completeError(
            StateError(
              '替換規則試跑意外結束${message is List ? '：${message.first}' : ''}',
            ),
          );
        }
        finish(null);
    }
  }

  /// 交出 [value]（已經交過就不再交），結束 isolate 與計時。
  void finish(ReplaceRulePreviewResult? value) {
    if (!_completer.isCompleted) _completer.complete(value);
    _deadline.stop();
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

/// [variants] 是每條規則要比的寫法（[ReplaceRuleScript.matchVariants]）。
void _previewMain((SendPort, List<List<ReplaceRule>>, String) args) {
  // 這個 isolate 沒有 rootBundle：替換規則的 `@js:` 用不到 fetch。
  fetchPolyfillSource ??= '';
  final (reply, variants, input) = args;
  var text = input;
  for (var i = 0; i < variants.length; i++) {
    reply.send(('rule', i));
    text = applyVariants(text, variants[i], runJs: runReplacementJs);
  }
  disposeReplacementJs();
  reply.send(('done', text));
}
