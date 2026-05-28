/// RuleAnalyzer 的基礎狀態與核心掃描定義
abstract class RuleAnalyzerBase {
  final String queue;
  int pos = 0;
  int start = 0;
  int startX = 0;
  final bool isCode;

  List<String> ruleList = [];
  int step = 0;
  String elementsType = '';

  static const int esc = 92;

  RuleAnalyzerBase(this.queue, {this.isCode = false});

  void trim() {
    if (pos < queue.length &&
        (queue[pos] == '@' || queue.codeUnitAt(pos) < 33)) {
      pos++;
      while (_isTrimmable()) {
        pos++;
      }
      start = pos;
      startX = pos;
    }
  }

  bool _isTrimmable() {
    return pos < queue.length &&
        (queue[pos] == '@' || queue.codeUnitAt(pos) < 33);
  }

  void reSetPos() {
    pos = 0;
    startX = 0;
    start = 0;
    ruleList = [];
  }

  bool consumeTo(String seq) {
    start = pos;
    if (pos >= queue.length) {
      return false;
    }
    final offset = queue.indexOf(seq, pos);
    if (offset != -1) {
      pos = offset;
      return true;
    }
    return false;
  }

  bool consumeToAny(List<String> seq) {
    var curPos = pos;
    while (curPos < queue.length) {
      for (final s in seq) {
        if (queue.startsWith(s, curPos)) {
          step = s.length;
          pos = curPos;
          return true;
        }
      }
      curPos++;
    }
    return false;
  }

  int findToAny(List<String> seq) {
    var curPos = pos;
    while (curPos < queue.length) {
      for (final s in seq) {
        if (queue[curPos] == s) {
          return curPos;
        }
      }
      curPos++;
    }
    return -1;
  }
}
