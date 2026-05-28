/// StringUtils - 字符串處理工具 (原 Android utils/StringUtils.kt)
class StringUtils {
  StringUtils._();

  static final Map<String, int> _chnMap = {
    '零': 0,
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
    '十': 10,
    '〇': 0,
    '壹': 1,
    '贰': 2,
    '叁': 3,
    '肆': 4,
    '伍': 5,
    '陆': 6,
    '柒': 7,
    '捌': 8,
    '玖': 9,
    '拾': 10,
    '两': 2,
    '百': 100,
    '佰': 100,
    '千': 1000,
    '仟': 1000,
    '万': 10000,
    '亿': 100000000,
  };

  /// 將半角字元轉為全角
  static String halfToFull(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code == 32) {
        buffer.writeCharCode(12288);
      } else if (code >= 33 && code <= 126) {
        buffer.writeCharCode(code + 65248);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// 將全角字元轉為半角
  static String fullToHalf(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code == 12288) {
        buffer.writeCharCode(32);
      } else if (code >= 65281 && code <= 65374) {
        buffer.writeCharCode(code - 65248);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// 中文大寫數字轉數字 (對標 chineseNumToInt)
  static int chineseNumToInt(String chNum) {
    var result = 0;
    var tmp = 0;
    var billion = 0;

    // 處理 "一零二五" 形式
    if (chNum.length > 1 &&
        RegExp(r'^[〇零一二三四五六七八九壹贰叁肆伍陆柒捌玖]+$').hasMatch(chNum)) {
      final resBuffer = StringBuffer();
      for (var i = 0; i < chNum.length; i++) {
        resBuffer.write(_chnMap[chNum[i]] ?? 0);
      }
      return int.tryParse(resBuffer.toString()) ?? -1;
    }

    // 處理 "一千零二十五" 形式
    try {
      for (var i = 0; i < chNum.length; i++) {
        final val = _chnMap[chNum[i]];
        if (val == null) continue;

        if (val == 100000000) {
          result += tmp;
          result *= val;
          billion = billion * 100000000 + result;
          result = 0;
          tmp = 0;
        } else if (val == 10000) {
          result += tmp;
          result *= val;
          tmp = 0;
        } else if (val >= 10) {
          if (tmp == 0) tmp = 1;
          result += val * tmp;
          tmp = 0;
        } else {
          tmp = tmp * 10 + val;
        }
      }
      return result + tmp + billion;
    } catch (_) {
      return -1;
    }
  }

  /// 字符串轉數字 (支援全半角與中文數字)
  static int stringToInt(String? str) {
    if (str == null) return -1;
    final numStr = fullToHalf(str).replaceAll(RegExp(r'\s+'), '');
    final direct = int.tryParse(numStr);
    if (direct != null) return direct;
    return chineseNumToInt(numStr);
  }

  /// 高效 Trim (包含全角空格)
  static String trim(String s) {
    if (s.isEmpty) return '';
    var start = 0;
    final len = s.length;
    var end = len - 1;
    while (start < end && (s.codeUnitAt(start) <= 0x20 || s[start] == '　')) {
      start++;
    }
    while (start < end && (s.codeUnitAt(end) <= 0x20 || s[end] == '　')) {
      end--;
    }
    return (start > 0 || end < len - 1) ? s.substring(start, end + 1) : s;
  }

  /// 重複字串
  static String repeat(String str, int n) {
    return List.filled(n, str).join();
  }

  /// 格式化字數 (對標 wordCountFormat)
  static String wordCountFormat(dynamic words) {
    if (words == null) return '';
    if (words is String) {
      if (int.tryParse(words) != null) {
        return _formatIntWordCount(int.parse(words));
      }
      return words;
    }
    if (words is num) {
      return _formatIntWordCount(words.toInt());
    }
    return words.toString();
  }

  static String _formatIntWordCount(int words) {
    if (words <= 0) return '';
    if (words > 10000) {
      return '${(words / 10000.0).toStringAsFixed(1)}萬字';
    }
    return '$words字';
  }
}
