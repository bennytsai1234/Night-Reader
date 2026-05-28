import 'rule_analyzer_base.dart';

/// RuleAnalyzer 的括號匹配邏輯擴展
mixin RuleAnalyzerMatch on RuleAnalyzerBase {
  bool chompCodeBalanced(String open, String close) {
    var curPos = pos;
    var depth = 0;
    var otherDepth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    final openChar = open[0];
    final closeChar = close[0];

    do {
      if (curPos >= queue.length) {
        break;
      }
      final c = queue[curPos++];
      if (c.codeUnitAt(0) != RuleAnalyzerBase.esc) {
        if (c == "'" && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (c == '"' && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }

        if (inSingleQuote || inDoubleQuote) {
          continue;
        }

        if (c == '[') {
          depth++;
        } else if (c == ']') {
          depth--;
        } else if (depth == 0) {
          if (c == openChar) {
            otherDepth++;
          } else if (c == closeChar) {
            otherDepth--;
          }
        }
      } else if (curPos < queue.length) {
        curPos++;
      }
    } while (depth > 0 || otherDepth > 0);

    if (depth > 0 || otherDepth > 0) {
      return false;
    }
    pos = curPos;
    return true;
  }

  bool chompRuleBalanced(String open, String close) {
    var curPos = pos;
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    final openChar = open[0];
    final closeChar = close[0];

    do {
      if (curPos >= queue.length) {
        break;
      }
      final c = queue[curPos++];
      if (c == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (c == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      }

      if (inSingleQuote || inDoubleQuote) {
        continue;
      } else if (c == r'\') {
        if (curPos < queue.length) {
          curPos++;
        }
        continue;
      }
      if (c == openChar) {
        depth++;
      } else if (c == closeChar) {
        depth--;
      }
    } while (depth > 0);

    if (depth > 0) {
      return false;
    }
    pos = curPos;
    return true;
  }

  bool chompBalanced(String open, String close) {
    return isCode
        ? chompCodeBalanced(open, close)
        : chompRuleBalanced(open, close);
  }
}
