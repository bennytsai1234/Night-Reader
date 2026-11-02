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

  /// 一段連續的中文數字，認得的字就是 [_chnMap] 裡的字：比對與換算用同一份
  /// 對照表，不會有認得換算卻切不出來的字。
  static final RegExp chineseNumberRun = RegExp('[${_chnMap.keys.join()}]+');

  /// 只由個位數字組成（「一零二五」），逐字照寫成阿拉伯數字。
  static final RegExp _digitsOnly = RegExp(
    '^[${[for (final MapEntry(:key, :value) in _chnMap.entries)
      if (value < 10) key].join()}]+\$',
  );

  /// 中文數字轉數字 (對標 Legado StringUtils.chineseNumToInt)：「一零二五」逐字
  /// 照寫；「一千零二十五」照位數算，結尾省略單位的「一千五」是 1500。
  static int chineseNumToInt(String chNum) {
    var result = 0;
    var tmp = 0;
    var billion = 0;

    // 處理 "一零二五" 形式
    if (chNum.length > 1 && _digitsOnly.hasMatch(chNum)) {
      final resBuffer = StringBuffer();
      for (var i = 0; i < chNum.length; i++) {
        resBuffer.write(_chnMap[chNum[i]] ?? 0);
      }
      return int.tryParse(resBuffer.toString()) ?? -1;
    }

    // 處理 "一千零二十五"、"一千五" 形式
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
          final previous = i >= 1 ? _chnMap[chNum[i - 1]] ?? 0 : 0;
          tmp = i >= 2 && i == chNum.length - 1 && previous > 10
              ? val * previous ~/ 10
              : tmp * 10 + val;
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
  /// 「850字」。格式化過的結果再格式化一次不變。整段不是一個字數（例如書源
  /// 把更新時間或章數放在字數欄）時回傳空字串，不把別的資訊當成字數顯示。
  static String wordCountFormat(dynamic words) {
    if (words == null) return '';
    final count = words is num
        ? _wordCountOrNull(words.toDouble())
        : _parseWordCount(words.toString());
    return _formatIntWordCount(count ?? 0);
  }

  /// 一整段就是一個字數：可有「字數：」「共」「約」這類前綴，數字可帶小數，
  /// 後面可接單位、「字」與「+」。
  static final _wordCountPattern = RegExp(
    r'^(?:总字数|總字數|字数|字數|共|大约|大約|约|約)?\s*:?\s*'
    r'(\d+(?:\.\d+)?)\s*(百万|百萬|千万|千萬|万|萬|千|[kwm])?\s*字?\s*\+?$',
    caseSensitive: false,
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

  /// 一兆字：沒有小說這麼長。
  static const _maxWordCount = 1e12;

  /// 數字裡的千分位逗號（後面剛好三位數）。
  static final _thousandsSeparator = RegExp(r'(?<=\d),(?=\d{3}(?!\d))');

  static int? _parseWordCount(String text) {
    final value = fullToHalf(text).trim().replaceAll(_thousandsSeparator, '');
    final match = _wordCountPattern.firstMatch(value);
    if (match == null) return null;
    final number = double.parse(match.group(1)!);
    final unit = match.group(2)?.toLowerCase();
    return _wordCountOrNull(
      number * (unit == null ? 1 : _wordCountUnits[unit]!),
    );
  }

  /// 一長串數字（甚至算成無限大）不是字數；上限也讓後面換算萬、千時不溢位。
  static int? _wordCountOrNull(double words) =>
      words < _maxWordCount ? words.round() : null;

  static String _formatIntWordCount(int words) {
    if (words <= 0) return '';
    // 用整數四捨五入到一位小數：浮點數的 1.15 其實略小於 1.15，
    // toStringAsFixed 會捨成 1.1。
    String oneDecimal(int unit) {
      final tenths = (words * 10 + unit ~/ 2) ~/ unit;
      final whole = tenths ~/ 10;
      final decimal = tenths % 10;
      return decimal == 0 ? '$whole' : '$whole.$decimal';
    }

    // 9950 以上四捨五入到 0.1 千就是十千，直接寫成萬。
    if (words >= 9950) return '${oneDecimal(10000)}萬字';
    if (words >= 1000) return '${oneDecimal(1000)}千字';
    return '$words字';
  }

  /// 日期、時刻與「3 小時前」這類更新時間。
  static final _datePattern = RegExp(
    r'\d{4}\s*[-/年]\s*\d{1,2}|\d{4}\.\d{1,2}\.\d{1,2}|'
    r'\d{1,2}\s*[-/月]\s*\d{1,2}|\d{1,2}:\d{2}|'
    r'\d+\s*(?:秒|分钟|分鐘|小时|小時|天|日|周|週|星期|个月|個月|月|年)前|'
    r'刚刚|剛剛|今天|昨天|前天|更新',
  );

  /// 分類標籤的分隔符；數字裡的千分位逗號不算。
  static final _kindSeparator = RegExp(
    r'(?<!\d)[,，]|[,，](?!\d{3}(?!\d))|[、|｜/／]',
  );

  static Iterable<String> _kindTokens(String kind) => kind
      .split(_kindSeparator)
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty);

  /// 書源的分類拆成標籤，丟掉混進來的日期、更新時間與整段只是數字的標籤
  /// （字數、點擊數），重複的只留一個。含數字的分類（例如「3D文字冒險」）
  /// 照留。
  static List<String> kindLabels(String? kind) {
    if (kind == null || kind.trim().isEmpty) return const [];
    return {
      for (final label in _kindTokens(kind))
        if (!_isKindNoise(label)) label,
    }.toList();
  }

  /// 卡片上的字數：字數欄讀不出來時，再看分類裡有沒有寫成「…字」或
  /// 「字數：…」的標籤（有些書源把字數放在分類欄）。只有數字、沒有「字」
  /// 的標籤可能是點擊數，不拿來當字數。
  static String displayWordCount(String? wordCount, String? kind) =>
      _formatIntWordCount(wordCountValue(wordCount, kind) ?? 0);

  /// [displayWordCount] 讀到的字數，讀不出來時是 null。
  static int? wordCountValue(String? wordCount, String? kind) {
    int? positive(int? words) => words != null && words > 0 ? words : null;
    final direct = positive(
      wordCount == null ? null : _parseWordCount(wordCount),
    );
    if (direct != null || kind == null) return direct;
    for (final label in _kindTokens(kind)) {
      if (!label.contains('字')) continue;
      final fromKind = positive(_parseWordCount(label));
      if (fromKind != null) return fromKind;
    }
    return null;
  }

  static bool _isKindNoise(String label) =>
      _datePattern.hasMatch(fullToHalf(label)) ||
      _parseWordCount(label) != null;
}
