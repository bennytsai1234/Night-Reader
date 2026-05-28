import 'package:flutter/services.dart' show rootBundle;

/// ChineseUtils - 純 Dart 簡繁轉換工具
/// 使用 OpenCC 字典資料 (BSD 授權) 做正向最長匹配轉換
/// 字典載入後，轉換為同步操作，微秒級完成
class ChineseUtils {
  ChineseUtils._();

  static bool _initialized = false;

  // 簡→繁
  static final Map<String, String> _s2tPhrases = {};
  static final Map<String, String> _s2tChars = {};
  static int _s2tMaxKeyLen = 1;

  // 繁→簡
  static final Map<String, String> _t2sPhrases = {};
  static final Map<String, String> _t2sChars = {};
  static int _t2sMaxKeyLen = 1;

  static bool get isInitialized => _initialized;

  /// 在 App 啟動時呼叫一次，載入字典到記憶體
  static Future<void> initialize() async {
    if (_initialized) return;

    final results = await Future.wait([
      rootBundle.loadString('assets/opencc/STPhrases.txt'),
      rootBundle.loadString('assets/opencc/STCharacters.txt'),
      rootBundle.loadString('assets/opencc/TSPhrases.txt'),
      rootBundle.loadString('assets/opencc/TSCharacters.txt'),
    ]);

    _s2tMaxKeyLen = _parseDictionary(results[0], _s2tPhrases);
    _parseDictionary(results[1], _s2tChars);
    _t2sMaxKeyLen = _parseDictionary(results[2], _t2sPhrases);
    _parseDictionary(results[3], _t2sChars);

    // 詞彙 maxKeyLen 至少要考慮字元表
    if (_s2tMaxKeyLen < 1) _s2tMaxKeyLen = 1;
    if (_t2sMaxKeyLen < 1) _t2sMaxKeyLen = 1;

    _initialized = true;
  }

  /// 解析 OpenCC 字典檔 (tab-separated: key\tvalue)
  /// 回傳最長 key 的字元數
  static int _parseDictionary(String data, Map<String, String> dict) {
    int maxLen = 0;
    final lines = data.split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      final tabIdx = line.indexOf('\t');
      if (tabIdx < 0) continue;
      final key = line.substring(0, tabIdx);
      // OpenCC 的 value 可能有多個候選 (空格分隔)，取第一個
      final valuePart = line.substring(tabIdx + 1).trimRight();
      final spaceIdx = valuePart.indexOf(' ');
      final value = spaceIdx < 0 ? valuePart : valuePart.substring(0, spaceIdx);
      dict[key] = value;
      if (key.length > maxLen) maxLen = key.length;
    }
    return maxLen;
  }

  /// 簡體轉繁體 (同步)
  static String s2t(String text) {
    if (text.isEmpty || !_initialized) return text;
    return _convert(text, _s2tPhrases, _s2tChars, _s2tMaxKeyLen);
  }

  /// 繁體轉簡體 (同步)
  static String t2s(String text) {
    if (text.isEmpty || !_initialized) return text;
    return _convert(text, _t2sPhrases, _t2sChars, _t2sMaxKeyLen);
  }

  /// 正向最長匹配轉換
  static String _convert(
    String text,
    Map<String, String> phrases,
    Map<String, String> chars,
    int maxKeyLen,
  ) {
    final buf = StringBuffer();
    int i = 0;
    final len = text.length;

    while (i < len) {
      String? match;
      int matchLen = 0;

      // 從最長嘗試到 2 字元 (詞彙匹配)
      final maxTry = (i + maxKeyLen <= len) ? maxKeyLen : len - i;
      for (int tryLen = maxTry; tryLen >= 2; tryLen--) {
        final key = text.substring(i, i + tryLen);
        final value = phrases[key];
        if (value != null) {
          match = value;
          matchLen = tryLen;
          break;
        }
      }

      if (match != null) {
        buf.write(match);
        i += matchLen;
      } else {
        // 單字映射
        final char = text[i];
        final mapped = chars[char];
        buf.write(mapped ?? char);
        i++;
      }
    }

    return buf.toString();
  }
}
