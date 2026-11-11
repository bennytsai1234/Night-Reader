import '../base_source.dart';
import 'book_source_rules.dart';

/// BookSource 的基礎屬性與欄位定義
abstract class BookSourceBase extends BaseSource {
  String bookSourceUrl = ''; // 書源 URL (唯一識別)
  String bookSourceName = ''; // 書源名稱
  String? bookSourceGroup; // 書源分組
  int bookSourceType = 0; // 類型 (0: 文本, 1: 音訊, 2: 圖片, 3: 文件)
  String? bookUrlPattern; // 詳情頁 URL 正則
  int customOrder = 0; // 手動排序
  bool enabled = true; // 是否啟用
  bool enabledExplore = true; // 啟用發現

  @override
  String? jsLib;
  @override
  bool enabledCookieJar = true;
  @override
  String? concurrentRate;
  @override
  String? header;
  @override
  String? loginUrl;
  @override
  String? loginUi;
  @override
  String? loginCheckJs;
  String? coverDecodeJs;

  String? bookSourceComment; // 註釋
  String? variableComment; // 變量說明
  int lastUpdateTime = 0; // 最後更新時間
  int respondTime = 180000; // 響應時間

  /// 上次校驗書源的時間（毫秒）；0 是沒有紀錄。只存在這台手機，不進書源
  /// JSON：書源被匯入、同步或編輯蓋過時歸零，整批修復就會重新校驗它
  /// （ADR 0054）。
  int lastCheckTime = 0;
  int weight = 0; // 權重
  String? exploreUrl; // 發現 URL
  String? exploreScreen; // 發現篩選規則

  ExploreRule? ruleExplore;
  String? searchUrl;
  SearchRule? ruleSearch;
  BookInfoRule? ruleBookInfo;
  TocRule? ruleToc;
  ContentRule? ruleContent;
  ReviewRule? ruleReview;

  // --- 規則別名補全 ---
  SearchRule? get ruleSearchV2 => ruleSearch;
  ExploreRule? get ruleExploreV2 => ruleExplore;
  BookInfoRule? get ruleBookInfoV2 => ruleBookInfo;
  TocRule? get ruleTocV2 => ruleToc;
  ContentRule? get ruleContentV2 => ruleContent;

  String? get ruleBookName => ruleSearch?.name;
  String? get ruleBookAuthor => ruleSearch?.author;
  String? get ruleBookKind => ruleSearch?.kind;
  String? get ruleBookLastChapter => ruleSearch?.lastChapter;
  String? get ruleBookCoverUrl => ruleSearch?.coverUrl;
  String? get ruleBookIntro => ruleSearch?.intro;
  String? get ruleBookUrl => ruleSearch?.bookUrl;

  @override
  String getTag() => bookSourceName;
  @override
  String getKey() => bookSourceUrl;

  // --- 便利布林 getter ---
  bool get hasSearchUrl => searchUrl != null && searchUrl!.isNotEmpty;
  bool get hasExploreUrl => exploreUrl != null && exploreUrl!.isNotEmpty;
  bool get hasBookInfoRule => ruleBookInfo != null;
  bool get hasTocRule => ruleToc != null;
  bool get hasContentRule => ruleContent != null;
}
