import 'book_source_base.dart';
import '../../constant/book_type.dart';
import '../../constant/source_type.dart';

const String searchBrokenSourceGroupTag = '搜尋失效';
const String discoveryBrokenSourceGroupTag = '發現失效';
const String discoveryDetailBrokenSourceGroupTag = '發現詳情失效';
const String discoveryTocBrokenSourceGroupTag = '發現目錄失效';
const String discoveryContentBrokenSourceGroupTag = '發現正文失效';
const String detailBrokenSourceGroupTag = '詳情失效';
const String tocBrokenSourceGroupTag = '目錄失效';
const String contentBrokenSourceGroupTag = '正文失效';
const String timeoutSourceGroupTag = '校驗超時';
const String siteBrokenSourceGroupTag = '網站失效';
const String upstreamBlockedSourceGroupTag = '上游異常';
const String downloadOnlySourceGroupTag = '下載站';
const String quarantineSourceGroupTag = '已隔離';
const String nonNovelSourceGroupTag = '非小說源';
const String loginRequiredSourceGroupTag = '需要登入';
const String verificationRequiredSourceGroupTag = '需要在網頁驗證';
const String abnormalSourceGroupTag = '異常';

/// 修復異常書源請 AI 修過、沒修好（ADR 0054）：下次整批修復跳過。不是校驗的
/// 標記，重新校驗不會拿掉；清除校驗標記、修好、改了規則存檔時拿掉。
const String aiUnfixableSourceGroupTag = 'AI 修不好';

/// 「需要登入」是書源的狀態，不是壞掉（ADR 0038）：照樣參加搜尋（很多書源
/// 搜尋不用登入）、照樣能開書，讀到要登入的地方再提示去登入；不列入清理。
/// 登入成功後拿掉這個標記。
const SourceRuntimeHealth loginRequiredSourceHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.loginRequired,
  label: loginRequiredSourceGroupTag,
  description: '需要登入後才能閱讀',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

/// 「需要在網頁驗證」和「需要登入」一樣是狀態（ADR 0038）：書源程式要
/// 使用者驗證（`java.startBrowserAwait`、驗證碼），多半是網站刁難時才走到
/// 的備援，平常照樣能用，所以照樣參加搜尋、照樣能開書，不列入清理。閱讀
/// 時遇到，失敗提示旁有「前往驗證」。
const SourceRuntimeHealth verificationRequiredSourceHealth =
    SourceRuntimeHealth(
      category: SourceHealthCategory.verificationRequired,
      label: verificationRequiredSourceGroupTag,
      description: '網站有時要在網頁上驗證，閱讀時遇到再去驗證',
      allowsSearch: true,
      allowsReading: true,
      cleanupCandidate: false,
      quarantined: false,
    );

const List<String> sourceRuntimeStatusTags = <String>[
  abnormalSourceGroupTag,
  searchBrokenSourceGroupTag,
  discoveryBrokenSourceGroupTag,
  discoveryDetailBrokenSourceGroupTag,
  discoveryTocBrokenSourceGroupTag,
  discoveryContentBrokenSourceGroupTag,
  detailBrokenSourceGroupTag,
  tocBrokenSourceGroupTag,
  contentBrokenSourceGroupTag,
  timeoutSourceGroupTag,
  siteBrokenSourceGroupTag,
  upstreamBlockedSourceGroupTag,
  downloadOnlySourceGroupTag,
  quarantineSourceGroupTag,
  nonNovelSourceGroupTag,
  loginRequiredSourceGroupTag,
  verificationRequiredSourceGroupTag,
];

/// 名稱、分組、說明、網址裡認得出的字樣，分成有聲、漫畫、影視三組；只在
/// 匯入時用來替類型寫 0 的書源補判類型（[classifySourceTypeByMarkers]）。
/// 照這個順序找，同時帶兩組字樣的書源算先找到的那一組。
const List<String> _audioSourceMarkers = <String>[
  '有声',
  '有聲',
  '听书',
  '聽書',
  '音频',
  '音頻',
  '广播剧',
  '廣播劇',
  'podcast',
  'radio',
];

const List<String> _comicSourceMarkers = <String>[
  '漫画',
  '漫畫',
  'manga',
  'manhwa',
  'comic',
  '動漫',
  '动漫',
];

const List<String> _videoSourceMarkers = <String>[
  '番劇',
  '番剧',
  '视频',
  '視頻',
  '影片',
  '影视',
  '影視',
  '电影',
  '電影',
  'm3u8',
];

/// 書源屬於哪一類：只看書源的類型（`bookSourceType`）。類型寫 0 但帶漫畫、
/// 有聲、影視字樣的，匯入與升級時已把類型改掉（[classifySourceTypeByMarkers]）；
/// 校驗再照抓到的正文改（ADR 0051）。聚合源照作者寫的類型，書各自是哪一類
/// 由書源的規則決定（ADR 0056）。
enum BookSourceKind {
  /// 類型 0，文字書源，Reader V2 讀。
  novel,

  /// 類型 2，圖片書源。
  comic,

  /// 類型 1，音訊書源。
  audio,

  /// 夜讀不支援：類型 3（文件）、4（影視）與其他值。匯入時停用、書源管理
  /// 可以清理。
  unsupported;

  /// 給使用者看的類別名稱，例如「漫畫源」。
  String get sourceLabel => switch (this) {
    BookSourceKind.novel => '小說源',
    BookSourceKind.comic => '漫畫源',
    BookSourceKind.audio => '有聲源',
    BookSourceKind.unsupported => '影視、文件源',
  };

  /// 書記在 `type` 的值（[ofBookType] 的反面）：照書源的類型，小說 0、
  /// 有聲 1、漫畫 2。
  int get bookType => switch (this) {
    BookSourceKind.novel => SourceType.book,
    BookSourceKind.comic => SourceType.image,
    BookSourceKind.audio => SourceType.audio,
    BookSourceKind.unsupported => SourceType.file,
  };

  /// 一本書是哪一類，從它的 `type` 看（ADR 0053）。夜讀的書記書源類型
  /// （[bookType]）；從 Legado 備份還原的書記 Legado 的位元（[BookType]，
  /// 文字 8 起跳），兩種都認。認不出來的算小說，交給文字閱讀器。
  static BookSourceKind ofBookType(int type) {
    if (type >= BookType.text) {
      if ((type & BookType.image) != 0) return BookSourceKind.comic;
      if ((type & BookType.audio) != 0) return BookSourceKind.audio;
      return BookSourceKind.novel;
    }
    return switch (type) {
      SourceType.image => BookSourceKind.comic,
      SourceType.audio => BookSourceKind.audio,
      _ => BookSourceKind.novel,
    };
  }

  /// 認書的鍵（同步、閱讀統計、書籤、標註、搜尋合卡）加在書名前面的前綴：
  /// 書名、作者相同的小說、漫畫、有聲是三本不同的書。小說沒有前綴，沿用
  /// 原本的鍵，已存、已同步的資料不用搬（ADR 0053）。
  String get keyPrefix => switch (this) {
    BookSourceKind.comic => 'comic:',
    BookSourceKind.audio => 'audio:',
    BookSourceKind.novel || BookSourceKind.unsupported => '',
  };

  /// 記錄裡的書名（閱讀統計、書籤、標註的 `bookName`）：[keyPrefix] 加書名。
  String recordName(String name) => '$keyPrefix$name';

  /// [recordName] 的反面：記錄裡的書名拆回類別與真正的書名。
  static ({BookSourceKind kind, String name}) splitRecordName(String value) {
    for (final kind in const [BookSourceKind.comic, BookSourceKind.audio]) {
      if (value.startsWith(kind.keyPrefix)) {
        return (kind: kind, name: value.substring(kind.keyPrefix.length));
      }
    }
    return (kind: BookSourceKind.novel, name: value);
  }
}

enum SourceHealthCategory {
  healthy,
  nonNovel,
  loginRequired,
  verificationRequired,
  downloadOnly,
  searchBroken,
  discoveryBroken,
  discoveryDetailBroken,
  discoveryTocBroken,
  discoveryContentBroken,
  detailBroken,
  tocBroken,
  contentBroken,
  upstreamUnstable,
}

class SourceRuntimeHealth {
  final SourceHealthCategory category;
  final String label;
  final String description;
  final bool allowsSearch;
  final bool allowsReading;
  final bool cleanupCandidate;
  final bool quarantined;

  const SourceRuntimeHealth({
    required this.category,
    required this.label,
    required this.description,
    required this.allowsSearch,
    required this.allowsReading,
    required this.cleanupCandidate,
    required this.quarantined,
  });

  static const SourceRuntimeHealth healthy = SourceRuntimeHealth(
    category: SourceHealthCategory.healthy,
    label: '可用',
    description: '目前未發現會阻塞搜尋或閱讀的問題',
    allowsSearch: true,
    allowsReading: true,
    cleanupCandidate: false,
    quarantined: false,
  );
}

RegExp _anyMarker(List<String> markers) =>
    RegExp(markers.map(RegExp.escape).join('|'), caseSensitive: false);

final RegExp _anyAudioMarker = _anyMarker(_audioSourceMarkers);
final RegExp _anyComicMarker = _anyMarker(_comicSourceMarkers);
final RegExp _anyVideoMarker = _anyMarker(_videoSourceMarkers);

/// 只看名稱、分組、網址（ADR 0056）。發現網址：小說站的分類清單本來就有
/// 「动漫衍生」「影视剧本」這類小說分類。搜尋網址常是整段程式，聚合源在裡面
/// 列出「听书」「漫画」這些模式。說明是作者的備註，常寫「会同时搜索小说和
/// 视频」「支持小说/漫画」：源倉庫 2026-11-10 的 424 個漫畫、有聲、影視
/// 相關書源裡，只靠說明比對到的 11 個沒有一個真的是那一類。
List<String?> _markerFields(BookSourceBase source) => <String?>[
  source.bookSourceName,
  source.bookSourceGroup,
  source.bookSourceUrl,
];

bool _fieldsMatch(List<String?> fields, RegExp marker) =>
    fields.any((field) => field != null && marker.hasMatch(field));

/// 書源規則設定書的類型（`book.type = 64`）：聚合源照使用者在登入表單選的
/// 模式，逐本書寫 Legado 的類型（[BookType] 的位元，或蘋果版的 0／1／2）。
final RegExp _bookTypeAssignment = RegExp(r'\bbook\.type\s*=(?!=)');

bool _setsBookType(String? text) =>
    text != null &&
    text.contains('book.type') &&
    _bookTypeAssignment.hasMatch(text);

/// 匯入的書源類型寫 0 時照字樣補判：帶有聲字樣改成 1、漫畫字樣改成 2、影視
/// 字樣改成 4，寫進書源本身（ADR 0051、0056）。只在書源從外面進來時用（匯入、
/// 還原備份、書架交換檔），校驗照正文改過的類型不再被字樣改回去。聚合源照
/// 作者寫的類型：它的名稱與說明本來就列著聽書、漫畫、短劇這些模式。
void classifySourceTypeByMarkers(BookSourceBase source) {
  if (source.bookSourceType != SourceType.book) return;
  if (source.isAggregateSource) return;
  final fields = _markerFields(source);
  if (_fieldsMatch(fields, _anyAudioMarker)) {
    source.bookSourceType = SourceType.audio;
  } else if (_fieldsMatch(fields, _anyComicMarker)) {
    source.bookSourceType = SourceType.image;
  } else if (_fieldsMatch(fields, _anyVideoMarker)) {
    source.bookSourceType = SourceType.video;
  }
}

/// schema 15 的夜讀照字樣分類時把聚合源也改了（多半改成有聲，帶影視字樣的
/// 當成不支援而停用），影視源則每次照字樣認（ADR 0056）。升到 schema 16 時：
/// 聚合源被改成有聲的改回小說（作者寫有聲、又逐本書設類型的聚合源在源倉庫
/// 一個都沒有；改成漫畫的分不出是不是作者寫的，留著）；類型寫 0、帶影視
/// 字樣的記成影視；被說明或搜尋網址的字樣誤判、停用的重新啟用
/// （[upgradeLegacyNonNovelSource]）。沒有標記的不重判漫畫與有聲：校驗照
/// 正文改回小說的書源不被字樣改回去。
void repairSchema15SourceKind(BookSourceBase source) {
  if (source.isAggregateSource) {
    if (source.bookSourceType == SourceType.audio) {
      source.bookSourceType = SourceType.book;
    }
  } else if (source.bookSourceType == SourceType.book &&
      _fieldsMatch(_markerFields(source), _anyVideoMarker)) {
    source.bookSourceType = SourceType.video;
  }
  upgradeLegacyNonNovelSource(source);
}

/// 舊版夜讀把照字樣或正文判成非小說的書源停用，並加上「非小說源」分組：
/// 漫畫、有聲書源，被說明或搜尋網址裡的字樣誤判的聚合源與小說源。照現在的
/// 分類不是影視、文件的，就是要留下的書源，所以補判類型、拿掉這兩個標記並
/// 重新啟用（停用是舊版替使用者做的，不是使用者自己關的；類型不對時校驗照
/// 正文改）。回傳有沒有改。
bool upgradeLegacyNonNovelSource(BookSourceBase source) {
  if (!source.hasGroupTag(nonNovelSourceGroupTag)) return false;
  classifySourceTypeByMarkers(source);
  if (source.sourceKind == BookSourceKind.unsupported) return false;
  source
    ..removeGroup('$nonNovelSourceGroupTag,$abnormalSourceGroupTag')
    ..enabled = true
    ..enabledExplore = true;
  return true;
}

/// 把書源的分組欄位切成各個分組名稱（同 legado）：以半形／全形逗號與分號
/// 分隔，名稱本身可以含空白（例如「🔥 精選」）。所有讀寫分組的地方都用這裡。
Set<String> splitSourceGroups(String? value) {
  if (value == null) return <String>{};
  return value
      .split(RegExp(r'[,;，；]'))
      .map((group) => group.trim())
      .where((group) => group.isNotEmpty)
      .toSet();
}

/// 網站那邊的三種問題，照這個順序認（舊版一次標了好幾個時取前面的）。
const List<String> _upstreamTags = [
  siteBrokenSourceGroupTag,
  upstreamBlockedSourceGroupTag,
  timeoutSourceGroupTag,
];

/// 網站那邊的問題：書源先隔離（排出搜尋與閱讀），[tag] 說是哪一種——
/// 「網站失效」（網域查不到、網站不在了）、「上游異常」（連不上、回錯誤、
/// 擋下夜讀）、「校驗超時」（太慢）。
SourceRuntimeHealth upstreamHealth(String tag) => SourceRuntimeHealth(
  category: SourceHealthCategory.upstreamUnstable,
  label: tag,
  description: switch (tag) {
    siteBrokenSourceGroupTag => '網域查不到或網站已經不在，換了網址才可能恢復',
    timeoutSourceGroupTag => '網站回應太慢，來源先隔離但不視為永久失效',
    _ => '上游暫時不可用，來源先隔離但不視為永久失效',
  },
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

/// BookSource 的業務邏輯擴展
extension BookSourceLogic on BookSourceBase {
  // 分組操作
  void addGroup(String groups) {
    final currentGroups = splitSourceGroups(bookSourceGroup)
      ..addAll(splitSourceGroups(groups));
    bookSourceGroup = currentGroups.isEmpty ? null : currentGroups.join(',');
  }

  void removeGroup(String groups) {
    final currentGroups = splitSourceGroups(bookSourceGroup)
      ..removeAll(splitSourceGroups(groups));
    bookSourceGroup = currentGroups.isEmpty ? null : currentGroups.join(',');
  }

  void removeInvalidGroups() {
    removeGroup(sourceRuntimeStatusTags.join(','));
  }

  /// 校驗的結論 [health] 寫成分組標記：不是可用的都加「異常」，再加這個
  /// 狀態自己的標記（壞掉的目錄、正文、詳情與網站問題另外加「已隔離」）。
  void addHealthGroups(SourceRuntimeHealth health) {
    if (health.category != SourceHealthCategory.healthy) {
      addGroup(abnormalSourceGroupTag);
    }
    final tags = switch (health.category) {
      SourceHealthCategory.healthy => const <String>[],
      SourceHealthCategory.nonNovel => const [nonNovelSourceGroupTag],
      SourceHealthCategory.loginRequired => const [loginRequiredSourceGroupTag],
      SourceHealthCategory.verificationRequired => const [
        verificationRequiredSourceGroupTag,
      ],
      SourceHealthCategory.downloadOnly => const [downloadOnlySourceGroupTag],
      SourceHealthCategory.searchBroken => const [searchBrokenSourceGroupTag],
      SourceHealthCategory.discoveryBroken => const [
        discoveryBrokenSourceGroupTag,
      ],
      SourceHealthCategory.discoveryDetailBroken => const [
        discoveryDetailBrokenSourceGroupTag,
      ],
      SourceHealthCategory.discoveryTocBroken => const [
        discoveryTocBrokenSourceGroupTag,
      ],
      SourceHealthCategory.discoveryContentBroken => const [
        discoveryContentBrokenSourceGroupTag,
      ],
      SourceHealthCategory.detailBroken => const [
        detailBrokenSourceGroupTag,
        quarantineSourceGroupTag,
      ],
      SourceHealthCategory.tocBroken => const [
        tocBrokenSourceGroupTag,
        quarantineSourceGroupTag,
      ],
      SourceHealthCategory.contentBroken => const [
        contentBrokenSourceGroupTag,
        quarantineSourceGroupTag,
      ],
      // 網站那邊的問題分三種，各標各的：網站不在了、連不上或回錯誤、太慢。
      SourceHealthCategory.upstreamUnstable => [
        if (_upstreamTags.contains(health.label))
          health.label
        else
          upstreamBlockedSourceGroupTag,
        quarantineSourceGroupTag,
      ],
    };
    if (tags.isNotEmpty) addGroup(tags.join(','));
  }

  // 註釋與錯誤訊息
  /// 逐行移除 `// Error:` 錯誤行，其他行原樣保留；錯誤行後面接的空行
  /// （addErrorComment 用來和原註解隔開）一起拿掉。
  void removeErrorComment() {
    if (bookSourceComment == null) return;
    final lines = bookSourceComment!.split('\n');
    final kept = lines
        .where((line) => !line.trim().startsWith('// Error:'))
        .toList();
    if (kept.length == lines.length) return;
    bookSourceComment = kept
        .skipWhile((line) => line.trim().isEmpty)
        .join('\n');
  }

  void addErrorComment(String error) {
    removeErrorComment();
    final newErrorLine = '// Error: $error';
    bookSourceComment =
        (bookSourceComment == null || bookSourceComment!.isEmpty)
        ? newErrorLine
        : '$newErrorLine\n\n$bookSourceComment';
  }

  /// 書源從外面進來時（匯入、還原備份、書架交換檔）先整理：類型寫 0 的照
  /// 字樣補判（[classifySourceTypeByMarkers]），舊版加的「非小說源」標記一起
  /// 升級（[upgradeLegacyNonNovelSource]）。
  void prepareIncoming() {
    classifySourceTypeByMarkers(this);
    upgradeLegacyNonNovelSource(this);
  }

  /// 書源屬於哪一類（[BookSourceKind]）。
  BookSourceKind get sourceKind => switch (bookSourceType) {
    SourceType.book => BookSourceKind.novel,
    SourceType.image => BookSourceKind.comic,
    SourceType.audio => BookSourceKind.audio,
    _ => BookSourceKind.unsupported,
  };

  /// 夜讀打得開的書源：小說源給 Reader V2，有聲源給有聲書播放器
  /// （ADR 0055），漫畫源給漫畫閱讀器（ADR 0052）。搜尋、發現、閱讀、
  /// 下載與檢查新章節只用這幾類。
  bool get isOpenableSource => switch (sourceKind) {
    BookSourceKind.novel ||
    BookSourceKind.audio ||
    BookSourceKind.comic => true,
    BookSourceKind.unsupported => false,
  };

  bool get canParticipateInDiscovery =>
      enabled &&
      enabledExplore &&
      hasExploreUrl &&
      isOpenableSource &&
      runtimeHealth.allowsReading;

  /// 聚合源（ADR 0056）：書源的規則逐本書設定書的類型，同一個書源搜得到
  /// 小說、漫畫或有聲書（多半看使用者在登入表單選的模式）。書源類型照作者
  /// 寫的，匯入不照字樣改、校驗不照正文改，書也不跟著書源的類型走；換源時
  /// 每一類的書都列它。要完整的書源（規則）才認得出來，書源清單用的精簡
  /// 書源沒有規則，一律不是。
  bool get isAggregateSource {
    if (_setsBookType(jsLib)) return true;
    for (final rule in <Map<String, dynamic>?>[
      ruleSearch?.toJson(),
      ruleExplore?.toJson(),
      ruleBookInfo?.toJson(),
      ruleToc?.toJson(),
      ruleContent?.toJson(),
    ]) {
      if (rule == null) continue;
      for (final value in rule.values) {
        if (value is String && _setsBookType(value)) return true;
      }
    }
    return false;
  }

  Set<String> get groupTags => splitSourceGroups(bookSourceGroup);

  bool hasGroupTag(String tag) => groupTags.contains(tag);

  SourceRuntimeHealth get runtimeHealth {
    // 分組只切一次，下面逐一比對狀態標記。
    final tags = groupTags;
    bool tagged(String tag) => tags.contains(tag);
    if (sourceKind == BookSourceKind.unsupported ||
        tagged(nonNovelSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.nonNovel,
        label: nonNovelSourceGroupTag,
        description: '夜讀不支援的書源（影視、文件）',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: true,
        quarantined: false,
      );
    }

    if (tagged(downloadOnlySourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.downloadOnly,
        label: downloadOnlySourceGroupTag,
        description: '來源只提供下載，不提供線上正文閱讀',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: true,
        quarantined: false,
      );
    }

    if (tagged(loginRequiredSourceGroupTag)) return loginRequiredSourceHealth;
    if (tagged(verificationRequiredSourceGroupTag)) {
      return verificationRequiredSourceHealth;
    }

    if (tagged(searchBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.searchBroken,
        label: searchBrokenSourceGroupTag,
        description: '搜尋已失效，會自動從預設搜尋池排除',
        allowsSearch: false,
        allowsReading: true,
        cleanupCandidate: false,
        quarantined: false,
      );
    }

    if (tagged(discoveryDetailBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.discoveryDetailBroken,
        label: discoveryDetailBrokenSourceGroupTag,
        description: '發現書籍詳情失效，不影響一般搜尋與閱讀',
        allowsSearch: true,
        allowsReading: true,
        cleanupCandidate: false,
        quarantined: false,
      );
    }

    if (tagged(discoveryTocBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.discoveryTocBroken,
        label: discoveryTocBrokenSourceGroupTag,
        description: '發現書籍目錄失效，不影響一般搜尋與閱讀',
        allowsSearch: true,
        allowsReading: true,
        cleanupCandidate: false,
        quarantined: false,
      );
    }

    if (tagged(discoveryContentBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.discoveryContentBroken,
        label: discoveryContentBrokenSourceGroupTag,
        description: '發現書籍正文失效，不影響一般搜尋與閱讀',
        allowsSearch: true,
        allowsReading: true,
        cleanupCandidate: false,
        quarantined: false,
      );
    }

    if (tagged(discoveryBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.discoveryBroken,
        label: discoveryBrokenSourceGroupTag,
        description: '發現已失效，不影響一般搜尋與閱讀',
        allowsSearch: true,
        allowsReading: true,
        cleanupCandidate: false,
        quarantined: false,
      );
    }

    if (tagged(detailBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.detailBroken,
        label: detailBrokenSourceGroupTag,
        description: '詳情頁失效，來源已隔離',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: false,
        quarantined: true,
      );
    }

    if (tagged(tocBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.tocBroken,
        label: tocBrokenSourceGroupTag,
        description: '目錄失效，來源已隔離',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: false,
        quarantined: true,
      );
    }

    if (tagged(contentBrokenSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.contentBroken,
        label: contentBrokenSourceGroupTag,
        description: '正文失效，來源已隔離',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: false,
        quarantined: true,
      );
    }

    for (final tag in [..._upstreamTags, quarantineSourceGroupTag]) {
      if (tagged(tag)) return upstreamHealth(tag);
    }

    return SourceRuntimeHealth.healthy;
  }

  /// 一般搜尋放行打得開的書源（[isOpenableSource]）；同名不同類的結果分成
  /// 不同的卡（ADR 0053）。
  bool get isSearchEnabledByRuntime =>
      enabled && isOpenableSource && runtimeHealth.allowsSearch;

  /// 能不能拿來搜 [kind] 這一類的書：換源只列和書同一類的書源（ADR 0053）。
  /// [includeAggregates] 時聚合源也算（手動換源，ADR 0056）：它搜到的是哪一
  /// 類要看登入表單選的模式，由使用者看結果挑；自動換源照 Legado 只用同類。
  bool isSearchableFor(BookSourceKind kind, {bool includeAggregates = false}) =>
      enabled &&
      runtimeHealth.allowsSearch &&
      (sourceKind == kind ||
          (includeAggregates && isOpenableSource && isAggregateSource));

  bool get isReadingEnabledByRuntime =>
      enabled && isOpenableSource && runtimeHealth.allowsReading;

  bool get isCleanupCandidate => runtimeHealth.cleanupCandidate;

  bool get isQuarantined => runtimeHealth.quarantined;
}
