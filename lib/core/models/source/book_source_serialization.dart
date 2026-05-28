import 'dart:convert';
import '../book_source.dart';

class BookSourceSerialization {
  /// 將規則對象轉換為 JSON 字符串
  static String? ruleToString(dynamic rule) {
    if (rule == null) return null;
    try {
      return jsonEncode(rule.toJson());
    } catch (_) {
      return null;
    }
  }

  /// 將規則解析為 Map (支援 String 格式與 Map 格式)
  static Map<String, dynamic> parseRule(dynamic rule) {
    if (rule == null) return {};
    if (rule is Map<String, dynamic>) return rule;
    if (rule is String && rule.isNotEmpty) {
      try {
        return jsonDecode(rule) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  /// 將 BookSource 轉換為 1:1 對標 Android 3.x 的 JSON
  static Map<String, dynamic> sourceToJson(BookSource source) {
    return {
      'bookSourceUrl': source.bookSourceUrl,
      'bookSourceName': source.bookSourceName,
      'bookSourceType': source.bookSourceType,
      'bookSourceGroup': source.bookSourceGroup,
      'bookSourceComment': source.bookSourceComment,
      'loginUrl': source.loginUrl,
      'loginUi': source.loginUi,
      'loginCheckJs': source.loginCheckJs,
      'coverDecodeJs': source.coverDecodeJs,
      'bookUrlPattern': source.bookUrlPattern,
      'header': source.header,
      'variableComment': source.variableComment,
      'customOrder': source.customOrder,
      'weight': source.weight,
      'enabled': source.enabled ? 1 : 0,
      'enabledExplore': source.enabledExplore ? 1 : 0,
      'enabledCookieJar': source.enabledCookieJar ? 1 : 0,
      'lastUpdateTime': source.lastUpdateTime,
      'respondTime': source.respondTime,
      'jsLib': source.jsLib,
      'concurrentRate': source.concurrentRate,
      'exploreUrl': source.exploreUrl,
      'exploreScreen': source.exploreScreen,
      'searchUrl': source.searchUrl,
      'ruleSearch': ruleToString(source.ruleSearch),
      'ruleExplore': ruleToString(source.ruleExplore),
      'ruleBookInfo': ruleToString(source.ruleBookInfo),
      'ruleToc': ruleToString(source.ruleToc),
      'ruleContent': ruleToString(source.ruleContent),
      'ruleReview': ruleToString(source.ruleReview),
    };
  }
}
