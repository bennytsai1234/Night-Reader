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
  static final Map<int, List<int>> _s2tPhraseLengths = {};

  // 繁→簡
  static final Map<String, String> _t2sPhrases = {};
  static final Map<String, String> _t2sChars = {};
  static final Map<int, List<int>> _t2sPhraseLengths = {};

  static bool get isInitialized => _initialized;

  /// OpenCC 字典 asset 路徑，順序與 [initializeFromDictionaryData] 的參數
  /// 一一對應：STPhrases、STCharacters、TSPhrases、TSCharacters。
  static const List<String> dictionaryAssetPaths = [
    'assets/opencc/STPhrases.txt',
    'assets/opencc/STCharacters.txt',
    'assets/opencc/TSPhrases.txt',
    'assets/opencc/TSCharacters.txt',
  ];

  /// 在 App 啟動時呼叫一次，載入字典到記憶體。載入中再呼叫（例如搜尋要等
  /// 字典）接上同一次，不重複解析；載入失敗時下一次呼叫重試。
  static Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _load().whenComplete(() => _initializing = null);
  }

  static Future<void>? _initializing;

  static Future<void> _load() async {
    final results = await Future.wait(
      dictionaryAssetPaths.map(rootBundle.loadString),
    );
    initializeFromDictionaryData(results);
  }

  /// 用原始字典內容直接初始化。給背景 isolate 用——背景 isolate 拿不到
  /// rootBundle，由主 isolate 把字典原文（rootBundle 已快取）送過去。
  /// [dictionaryData] 順序須與 [dictionaryAssetPaths] 一致。
  static void initializeFromDictionaryData(List<String> dictionaryData) {
    if (_initialized || dictionaryData.length != 4) return;

    _parseDictionary(dictionaryData[0], _s2tPhrases, _s2tPhraseLengths);
    _parseDictionary(dictionaryData[1], _s2tChars, null);
    _parseDictionary(dictionaryData[2], _t2sPhrases, _t2sPhraseLengths);
    _parseDictionary(dictionaryData[3], _t2sChars, null);

    _initialized = true;
  }

  /// 解析 OpenCC 字典檔 (tab-separated: key\tvalue)。給了 [lengthsByFirst]
  /// 時，另外記下每個開頭字元有哪些詞長（由長到短）。
  static void _parseDictionary(
    String data,
    Map<String, String> dict,
    Map<int, List<int>>? lengthsByFirst,
  ) {
    final lengthSets = <int, Set<int>>{};
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
      if (lengthsByFirst != null && key.length >= 2) {
        lengthSets
            .putIfAbsent(key.codeUnitAt(0), () => <int>{})
            .add(key.length);
      }
    }
    if (lengthsByFirst == null) return;
    for (final entry in lengthSets.entries) {
      lengthsByFirst[entry.key] = entry.value.toList()
        ..sort((a, b) => b.compareTo(a));
    }
  }

  /// 簡體轉繁體 (同步)
  static String s2t(String text) {
    if (text.isEmpty || !_initialized) return text;
    return _convert(text, _s2tPhrases, _s2tPhraseLengths, _s2tChars);
  }

  /// 繁體轉簡體 (同步)
  static String t2s(String text) {
    if (text.isEmpty || !_initialized) return text;
    return _convert(text, _t2sPhrases, _t2sPhraseLengths, _t2sChars);
  }

  /// 正向最長匹配轉換。每個位置只試字典裡以這個字開頭的詞長，不從最長詞長
  /// 逐一切子字串：書名、章名在每次重建與每次書架檢查都會轉換，逐一切會在
  /// 畫面執行緒上累積成整幀的停頓。
  static String _convert(
    String text,
    Map<String, String> phrases,
    Map<int, List<int>> phraseLengths,
    Map<String, String> chars,
  ) {
    final buf = StringBuffer();
    int i = 0;
    final len = text.length;

    while (i < len) {
      String? match;
      int matchLen = 0;

      final lengths = phraseLengths[text.codeUnitAt(i)];
      if (lengths != null) {
        for (final tryLen in lengths) {
          if (i + tryLen > len) continue;
          final value = phrases[text.substring(i, i + tryLen)];
          if (value != null) {
            match = value;
            matchLen = tryLen;
            break;
          }
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
