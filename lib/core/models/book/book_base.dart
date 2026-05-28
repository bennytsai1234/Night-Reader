/// Book - 基礎書籍模型
/// (原 Android data/entities/Book.kt)
class BookBase {
  // --- Constants from Book.kt companion object ---
  static const int hTag = 2;
  static const int rubyTag = 4;
  static const String imgStyleDefault = 'DEFAULT';
  static const String imgStyleFull = 'FULL';
  static const String imgStyleText = 'TEXT';
  static const String imgStyleSingle = 'SINGLE';

  String bookUrl; // 書籍 URL (唯一識別)
  String tocUrl; // 目錄 URL
  String origin; // 書源 URL 或 localTag
  String originName; // 書源名稱或本地檔名
  String name; // 書名
  String author; // 作者
  String? kind; // 分類 (書源獲取)
  String? customTag; // 分類 (用戶修改)
  String? coverUrl; // 封面 URL (書源獲取)
  String? coverLocalPath; // 系統保存的本地封面檔案
  String? customCoverUrl; // 封面 URL (用戶修改)
  String? customCoverLocalPath; // 使用者封面本地化後的檔案
  String? intro; // 簡介 (書源獲取)
  String? customIntro; // 簡介 (用戶修改)
  String? charset; // 自定義字符集 (本地書)
  int type; // 書籍類型 (位運算, 詳見 BookType)
  int group; // 自定義分組索引 (位運算)
  String? latestChapterTitle; // 最新章節標題
  int latestChapterTime; // 最新章節更新時間
  int lastCheckTime; // 最近一次檢查時間
  int lastCheckCount; // 最近一次發現新章節數量
  int totalChapterNum; // 章節總數
  String? durChapterTitle; // 目前章節標題
  int chapterIndex; // 目前章節索引
  int charOffset; // 目前閱讀位置 (首行字索引)
  double visualOffsetPx; // 目前閱讀位置的可視微調位移
  String? readerAnchorJson; // 本機精準閱讀錨點
  int durChapterTime; // 最近一次閱讀時間
  String? wordCount; // 字數
  bool canUpdate; // 是否自動更新
  int order; // 手動排序
  int originOrder; // 書源排序
  String? variable; // 自定義變量
  ReadConfig? readConfig; // 閱讀設置
  int syncTime; // 同步時間
  bool isInBookshelf; // 是否在書架上 (iOS 特有標記)

  // --- Transient Properties (Not persisted, Android parity) ---
  String? infoHtml; // 緩存的書籍詳情 HTML
  String? tocHtml; // 緩存的目錄 HTML

  BookBase({
    this.bookUrl = '',
    this.tocUrl = '',
    this.origin = 'local',
    this.originName = '',
    this.name = '',
    this.author = '',
    this.kind,
    this.customTag,
    this.coverUrl,
    this.coverLocalPath,
    this.customCoverUrl,
    this.customCoverLocalPath,
    this.intro,
    this.customIntro,
    this.charset,
    this.type = 0,
    this.group = 0,
    this.latestChapterTitle,
    this.latestChapterTime = 0,
    this.lastCheckTime = 0,
    this.lastCheckCount = 0,
    this.totalChapterNum = 0,
    this.durChapterTitle,
    this.chapterIndex = 0,
    this.charOffset = 0,
    this.visualOffsetPx = 0.0,
    this.readerAnchorJson,
    this.durChapterTime = 0,
    this.wordCount,
    this.canUpdate = true,
    this.order = 0,
    this.originOrder = 0,
    this.variable,
    this.readConfig,
    this.syncTime = 0,
    this.isInBookshelf = false,
  });
}

/// ReadConfig - 閱讀設置模型 (內嵌於 Book)
class ReadConfig {
  bool reverseToc; // 目錄反序
  int? pageAnim; // 翻頁動畫
  bool reSegment; // 強制分段
  String? imageStyle; // 圖片樣式
  bool? useReplaceRule; // 正文使用淨化規則
  int delTag; // 去除標籤位元
  String? ttsEngine; // TTS 引擎
  bool splitLongChapter; // 拆分超長章節
  bool readSimulating; // 模擬更新
  String? startDate; // 模擬起始日期
  int? startChapter; // 模擬起始章節
  int dailyChapters; // 每日更新章節數

  ReadConfig({
    this.reverseToc = false,
    this.pageAnim,
    this.reSegment = false,
    this.imageStyle,
    this.useReplaceRule,
    this.delTag = 0,
    this.ttsEngine,
    this.splitLongChapter = true,
    this.readSimulating = false,
    this.startDate,
    this.startChapter,
    this.dailyChapters = 3,
  });

  factory ReadConfig.fromJson(Map<String, dynamic> json) {
    return ReadConfig(
      reverseToc: json['reverseToc'] ?? false,
      pageAnim: json['pageAnim'],
      reSegment: json['reSegment'] ?? false,
      imageStyle: json['imageStyle'],
      useReplaceRule: json['useReplaceRule'],
      delTag: json['delTag'] ?? 0,
      ttsEngine: json['ttsEngine'],
      splitLongChapter: json['splitLongChapter'] ?? true,
      readSimulating: json['readSimulating'] ?? false,
      startDate: json['startDate'],
      startChapter: json['startChapter'],
      dailyChapters: json['dailyChapters'] ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reverseToc': reverseToc,
      'pageAnim': pageAnim,
      'reSegment': reSegment,
      'imageStyle': imageStyle,
      'useReplaceRule': useReplaceRule,
      'delTag': delTag,
      'ttsEngine': ttsEngine,
      'splitLongChapter': splitLongChapter,
      'readSimulating': readSimulating,
      'startDate': startDate,
      'startChapter': startChapter,
      'dailyChapters': dailyChapters,
    };
  }
}
