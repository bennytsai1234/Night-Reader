import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:reader/core/models/rule_data_interface.dart';
import 'replace_rule.dart';
import '../services/chinese_utils.dart';

/// BookChapter - 章節模型
/// (原 Android data/entities/BookChapter.kt)
class BookChapter implements RuleDataInterface {
  String url; // 章節地址
  String title; // 章節名稱
  bool isVolume; // 是否為卷標題
  String baseUrl; // 基礎 URL (用於拼接相對路徑)
  String bookUrl; // 所屬書籍地址
  int index; // 章節索引
  bool isVip; // 是否為 VIP 章節
  bool isPay; // 是否已購買
  String? resourceUrl; // 音訊或資源真實 URL
  String? tag; // 標籤 (如更新時間)
  String? wordCount; // 本章字數
  int? start; // 文本起始偏移 (針對本地大文件)
  int? end; // 文本終止偏移
  String? startFragmentId; // EPUB 章節 fragmentId
  String? endFragmentId; // EPUB 下一章 fragmentId
  String? variable; // 自定義變量 (JSON)
  String? content; // 章節內容

  BookChapter({
    this.url = '',
    this.title = '',
    this.isVolume = false,
    this.baseUrl = '',
    this.bookUrl = '',
    this.index = 0,
    this.isVip = false,
    this.isPay = false,
    this.resourceUrl,
    this.tag,
    this.wordCount,
    this.start,
    this.end,
    this.startFragmentId,
    this.endFragmentId,
    this.variable,
    this.content,
  });

  // 變量地圖 (原 Android variableMap)
  @override
  Map<String, String> get variableMap {
    if (variable == null || variable!.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(variable!));
    } catch (_) {
      return {};
    }
  }

  @override
  void putVariable(String key, String? value) {
    final map = variableMap;
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    variable = map.isEmpty ? null : jsonEncode(map);
  }

  @override
  String getVariable(String key) => variableMap[key] ?? '';

  /// 獲取顯示標題 (原 Android getDisplayTitle)
  String getDisplayTitle({
    List<ReplaceRule>? replaceRules,
    bool useReplace = true,
    int chineseConvertType = 0, // 0: 不轉換, 1: 簡轉繁, 2: 繁轉簡
  }) {
    var displayTitle = title.replaceAll(RegExp(r'[\r\n]'), '');

    // 繁簡轉換 (純 Dart 同步查表)
    if (chineseConvertType == 1) {
      displayTitle = ChineseUtils.s2t(displayTitle);
    } else if (chineseConvertType == 2) {
      displayTitle = ChineseUtils.t2s(displayTitle);
    }

    // 標題淨化規則
    if (useReplace && replaceRules != null) {
      for (var rule in replaceRules) {
        if (rule.pattern.isNotEmpty) {
          try {
            if (rule.isRegex) {
              displayTitle = displayTitle.replaceAll(
                RegExp(rule.pattern),
                rule.replacement,
              );
            } else {
              displayTitle = displayTitle.replaceAll(
                rule.pattern,
                rule.replacement,
              );
            }
          } catch (e) {
            // 忽略錯誤的正則
          }
        }
      }
    }
    return displayTitle;
  }

  /// 獲取絕對 URL (對標 Android BookChapter.getAbsoluteURL)
  String getAbsoluteURL() {
    if (url.isEmpty) return baseUrl;
    if (url.startsWith(title) && isVolume) return baseUrl;

    // 處理帶有參數的 URL, 例如: "http://xxx.com/page1,{\"headers\":...}"
    // 對標 Android AnalyzeUrl.paramPattern = RegExp(r"\s*,\s*(?=\{)")
    final paramSplitRegex = RegExp(r'\s*,\s*(?=\{)');
    final match = paramSplitRegex.firstMatch(url);

    String urlBefore = match != null ? url.substring(0, match.start) : url;
    String urlAfter = match != null ? url.substring(match.start) : '';

    if (urlBefore.startsWith('http')) {
      return urlBefore + urlAfter;
    }

    try {
      final base = Uri.parse(baseUrl);
      final absolute = base.resolve(urlBefore).toString();
      return absolute + urlAfter;
    } catch (e) {
      return url;
    }
  }

  /// 獲取緩存文件名 (原 Android getFileName)
  String getFileName({String suffix = 'nb'}) {
    final titleMD5 = md5
        .convert(utf8.encode(title))
        .toString()
        .substring(0, 16);
    final idxStr = index.toString().padLeft(5, '0');
    return '$idxStr-$titleMD5.$suffix';
  }

  factory BookChapter.fromJson(Map<String, dynamic> json) {
    return BookChapter(
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      isVolume: json['isVolume'] == 1 || json['isVolume'] == true,
      baseUrl: json['baseUrl'] ?? '',
      bookUrl: json['bookUrl'] ?? '',
      index: json['index'] ?? 0,
      isVip: json['isVip'] == 1 || json['isVip'] == true,
      isPay: json['isPay'] == 1 || json['isPay'] == true,
      resourceUrl: json['resourceUrl'],
      tag: json['tag'],
      wordCount: json['wordCount'],
      start: json['start'],
      end: json['end'],
      startFragmentId: json['startFragmentId']?.toString(),
      endFragmentId: json['endFragmentId']?.toString(),
      variable: json['variable'],
      content: json['content'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'isVolume': isVolume ? 1 : 0,
      'baseUrl': baseUrl,
      'bookUrl': bookUrl,
      'index': index,
      'isVip': isVip ? 1 : 0,
      'isPay': isPay ? 1 : 0,
      'resourceUrl': resourceUrl,
      'tag': tag,
      'wordCount': wordCount,
      'start': start,
      'end': end,
      'startFragmentId': startFragmentId,
      'endFragmentId': endFragmentId,
      'variable': variable,
      'content': content,
    };
  }

  BookChapter copyWith({
    String? url,
    String? title,
    bool? isVolume,
    String? baseUrl,
    String? bookUrl,
    int? index,
    bool? isVip,
    bool? isPay,
    String? resourceUrl,
    String? tag,
    String? wordCount,
    int? start,
    int? end,
    String? startFragmentId,
    String? endFragmentId,
    String? variable,
    String? content,
  }) {
    return BookChapter(
      url: url ?? this.url,
      title: title ?? this.title,
      isVolume: isVolume ?? this.isVolume,
      baseUrl: baseUrl ?? this.baseUrl,
      bookUrl: bookUrl ?? this.bookUrl,
      index: index ?? this.index,
      isVip: isVip ?? this.isVip,
      isPay: isPay ?? this.isPay,
      resourceUrl: resourceUrl ?? this.resourceUrl,
      tag: tag ?? this.tag,
      wordCount: wordCount ?? this.wordCount,
      start: start ?? this.start,
      end: end ?? this.end,
      startFragmentId: startFragmentId ?? this.startFragmentId,
      endFragmentId: endFragmentId ?? this.endFragmentId,
      variable: variable ?? this.variable,
      content: content ?? this.content,
    );
  }
}
