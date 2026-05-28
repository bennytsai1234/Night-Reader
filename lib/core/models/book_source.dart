import 'source/book_source_base.dart';
import 'source/book_source_rules.dart';
import 'source/book_source_serialization.dart';

export 'source/book_source_base.dart';
export 'source/book_source_rules.dart';
export 'source/book_source_logic.dart';

/// BookSource - 書源模型 (重構後)
/// 完整相容 Legado 3.0 JSON 書源格式
/// (原 Android data/entities/BookSource.kt)
class BookSource extends BookSourceBase {
  BookSource({
    String bookSourceUrl = '',
    String bookSourceName = '',
    String? bookSourceGroup,
    int bookSourceType = 0,
    String? bookUrlPattern,
    int customOrder = 0,
    bool enabled = true,
    bool enabledExplore = true,
    String? jsLib,
    bool enabledCookieJar = true,
    String? concurrentRate,
    String? header,
    String? loginUrl,
    String? loginUi,
    String? loginCheckJs,
    String? coverDecodeJs,
    String? bookSourceComment,
    String? variableComment,
    int lastUpdateTime = 0,
    int respondTime = 180000,
    int weight = 0,
    String? exploreUrl,
    String? exploreScreen,
    ExploreRule? ruleExplore,
    String? searchUrl,
    SearchRule? ruleSearch,
    BookInfoRule? ruleBookInfo,
    TocRule? ruleToc,
    ContentRule? ruleContent,
    ReviewRule? ruleReview,
  }) {
    this.bookSourceUrl = bookSourceUrl;
    this.bookSourceName = bookSourceName;
    this.bookSourceGroup = bookSourceGroup;
    this.bookSourceType = bookSourceType;
    this.bookUrlPattern = bookUrlPattern;
    this.customOrder = customOrder;
    this.enabled = enabled;
    this.enabledExplore = enabledExplore;
    this.jsLib = jsLib;
    this.enabledCookieJar = enabledCookieJar;
    this.concurrentRate = concurrentRate;
    this.header = header;
    this.loginUrl = loginUrl;
    this.loginUi = loginUi;
    this.loginCheckJs = loginCheckJs;
    this.coverDecodeJs = coverDecodeJs;
    this.bookSourceComment = bookSourceComment;
    this.variableComment = variableComment;
    this.lastUpdateTime = lastUpdateTime;
    this.respondTime = respondTime;
    this.weight = weight;
    this.exploreUrl = exploreUrl;
    this.exploreScreen = exploreScreen;
    this.ruleExplore = ruleExplore;
    this.searchUrl = searchUrl;
    this.ruleSearch = ruleSearch;
    this.ruleBookInfo = ruleBookInfo;
    this.ruleToc = ruleToc;
    this.ruleContent = ruleContent;
    this.ruleReview = ruleReview;
  }

  factory BookSource.fromJson(Map<String, dynamic> json) {
    return BookSource(
      bookSourceUrl: json['bookSourceUrl'] ?? '',
      bookSourceName: json['bookSourceName'] ?? '',
      bookSourceGroup: json['bookSourceGroup'],
      bookSourceType: json['bookSourceType'] ?? 0,
      bookUrlPattern: json['bookUrlPattern'],
      customOrder: json['customOrder'] ?? 0,
      enabled: json['enabled'] == 1 || json['enabled'] == true,
      enabledExplore:
          json['enabledExplore'] == 1 || json['enabledExplore'] == true,
      jsLib: json['jsLib'],
      enabledCookieJar:
          json['enabledCookieJar'] == 1 || json['enabledCookieJar'] == true,
      concurrentRate: json['concurrentRate']?.toString(),
      header: json['header'],
      loginUrl: json['loginUrl'],
      loginUi: json['loginUi'],
      loginCheckJs: json['loginCheckJs'],
      coverDecodeJs: json['coverDecodeJs'],
      bookSourceComment: json['bookSourceComment'],
      variableComment: json['variableComment'],
      lastUpdateTime: json['lastUpdateTime'] ?? 0,
      respondTime: json['respondTime'] ?? 180000,
      weight: json['weight'] ?? 0,
      exploreUrl: json['exploreUrl'],
      exploreScreen: json['exploreScreen'],
      ruleExplore:
          json['ruleExplore'] != null
              ? ExploreRule.fromJson(
                BookSourceSerialization.parseRule(json['ruleExplore']),
              )
              : null,
      searchUrl: json['searchUrl'],
      ruleSearch:
          json['ruleSearch'] != null
              ? SearchRule.fromJson(
                BookSourceSerialization.parseRule(json['ruleSearch']),
              )
              : null,
      ruleBookInfo:
          json['ruleBookInfo'] != null
              ? BookInfoRule.fromJson(
                BookSourceSerialization.parseRule(json['ruleBookInfo']),
              )
              : null,
      ruleToc:
          json['ruleToc'] != null
              ? TocRule.fromJson(
                BookSourceSerialization.parseRule(json['ruleToc']),
              )
              : null,
      ruleContent:
          json['ruleContent'] != null
              ? ContentRule.fromJson(
                BookSourceSerialization.parseRule(json['ruleContent']),
              )
              : null,
      ruleReview:
          json['ruleReview'] != null
              ? ReviewRule.fromJson(
                BookSourceSerialization.parseRule(json['ruleReview']),
              )
              : null,
    );
  }

  Map<String, dynamic> toJson() => BookSourceSerialization.sourceToJson(this);

  String getCheckKeyword(String defaultValue) {
    return (ruleSearch?.checkKeyWord != null &&
            ruleSearch!.checkKeyWord!.isNotEmpty)
        ? ruleSearch!.checkKeyWord!
        : defaultValue;
  }
}
