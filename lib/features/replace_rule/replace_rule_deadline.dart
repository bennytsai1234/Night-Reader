import 'dart:async';

import 'package:night_reader/core/models/replace_rule.dart';

/// 替換規則在另一個 isolate 套用時，主 isolate 替正在跑的那一條計時：那個
/// isolate 每開始一條就說一聲（[start]），跑超過那條的逾時
/// （[ReplaceRule.getValidTimeoutMillisecond]）就呼叫 [onTimeout]，由呼叫端
/// 結束那個 isolate。正則跑到一半只能這樣停下。
///
/// 試跑（`ReplaceRulePreview`）與閱讀器套用正文（內容轉換 worker）共用。
class ReplaceRuleDeadline {
  ReplaceRuleDeadline(this.onTimeout);

  final void Function(ReplaceRule rule) onTimeout;
  Timer? _timer;

  /// 開始套用 [rule]：照它的逾時重新計時。
  void start(ReplaceRule rule) {
    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: rule.getValidTimeoutMillisecond()),
      () {
        _timer = null;
        onTimeout(rule);
      },
    );
  }

  /// 規則都套完了，或那個 isolate 已經結束。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 閱讀器停用跑太久的規則時給讀者的提示，例如「替換規則「去廣告」執行太久，
/// 已停用」。
String replaceRuleDisabledNotice(ReplaceRule rule) {
  final name = rule.name.trim();
  return '替換規則${name.isEmpty ? '' : '「$name」'}執行太久，已停用';
}
