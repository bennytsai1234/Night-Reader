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
    // 繁體寫法
    '兩': 2,
    '貳': 2,
    '參': 3,
    '陸': 6,
    '萬': 10000,
    '億': 100000000,
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

  /// 格式化字數 (對標 wordCountFormat)。
  ///
  /// 書源給的字數各寫各的（123456、12.3萬字、56.8万、123.4K、字數：1.2M），
  /// 一律換成同一種寫法：一萬以上「12.3萬字」，一千以上「3.5千字」，再少寫
  /// 「850字」。格式化過的結果再格式化一次不變。讀不出字數（例如書源把更新
  /// 時間放在字數欄）時回傳空字串，不把別的資訊當成字數顯示。
  static String wordCountFormat(dynamic words) {
    if (words == null) return '';
    if (words is num) return _formatIntWordCount(words.round());
    return _formatIntWordCount(_parseWordCount(words.toString()) ?? 0);
  }

  static final _wordCountPattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*(百万|百萬|千万|千萬|万|萬|千|[kKwWmM])?',
  );
  static const _wordCountUnits = {
    '百万': 1000000,
    '百萬': 1000000,
    'm': 1000000,
    '千万': 10000000,
    '千萬': 10000000,
    '万': 10000,
    '萬': 10000,
    'w': 10000,
    '千': 1000,
    'k': 1000,
  };

  /// 日期、時刻與「3 天前」這類更新時間。
  static final _datePattern = RegExp(
    r'\d{4}[-/年]\d{1,2}|\d{4}\.\d{1,2}\.\d{1,2}|\d{1,2}[-/月]\d{1,2}|'
    r'\d{1,2}:\d{2}|'
    r'\d+\s*(?:秒|分钟|分鐘|小时|小時|天|日|周|週|星期|个月|個月|月|年)前|'
    r'刚刚|剛剛|今天|昨天|前天|更新',
  );

  static int? _parseWordCount(String text) {
    final value = fullToHalf(text).replaceAll(RegExp(r'(?<=\d),(?=\d)'), '');
    if (_datePattern.hasMatch(value)) return null;
    final match = _wordCountPattern.firstMatch(value);
    if (match == null) return null;
    final number = double.parse(match.group(1)!);
    final unit = match.group(2)?.toLowerCase();
    return (number * (unit == null ? 1 : _wordCountUnits[unit]!)).round();
  }

  static String _formatIntWordCount(int words) {
    if (words <= 0) return '';
    String oneDecimal(double value) {
      final text = value.toStringAsFixed(1);
      return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    }

    // 9950 以上四捨五入到 0.1 千就是十千，直接寫成萬。
    if (words >= 9950) return '${oneDecimal(words / 10000)}萬字';
    if (words >= 1000) return '${oneDecimal(words / 1000)}千字';
    return '$words字';
  }

  /// 書源的分類拆成標籤，丟掉混進來的日期、更新時間與數字（字數、點擊數），
  /// 重複的只留一個。
  static List<String> kindLabels(String? kind) {
    if (kind == null || kind.trim().isEmpty) return const [];
    final labels = <String>{};
    for (final raw in kind.split(_kindSeparator)) {
      final label = raw.trim();
      if (label.isEmpty || _isKindNoise(label)) continue;
      labels.add(label);
    }
    return labels.toList();
  }

  /// 卡片上的字數：字數欄讀不出來時，再看分類裡有沒有寫成「…字」的標籤
  /// （有些書源把字數放在分類欄）。
  static String displayWordCount(String? wordCount, String? kind) {
    final formatted = wordCountFormat(wordCount);
    if (formatted.isNotEmpty || kind == null) return formatted;
    for (final raw in kind.split(_kindSeparator)) {
      if (!raw.contains('字')) continue;
      final fromKind = wordCountFormat(raw);
      if (fromKind.isNotEmpty) return fromKind;
    }
    return '';
  }

  static final _kindSeparator = RegExp(r'[,，、|｜/／\s]+');
  static final _numericKind = RegExp(
    r'^[\d.,]+\s*(?:百万|百萬|千万|千萬|万|萬|千|[kKwWmM])?\s*字?$',
  );

  static bool _isKindNoise(String label) {
    final value = fullToHalf(label);
    if (_datePattern.hasMatch(value) || _numericKind.hasMatch(value)) {
      return true;
    }
    return value.contains('字') && _parseWordCount(value) != null;
  }
}
