import 'book_source_base.dart';
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
const String abnormalSourceGroupTag = '異常';

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
];

const List<String> _nonNovelSourceMarkers = <String>[
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
  '漫画',
  '漫畫',
  'manga',
  'manhwa',
  'comic',
  '動漫',
  '动漫',
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

enum SourceHealthCategory {
  healthy,
  nonNovel,
  loginRequired,
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

/// 任一非小說標記（不分大小寫）；只用來快速判斷「都沒有」，有的話再照
/// [_nonNovelSourceMarkers] 的順序找出是哪一個。
final RegExp _anyNonNovelMarker = RegExp(
  _nonNovelSourceMarkers.map(RegExp.escape).join('|'),
  caseSensitive: false,
);

String? _findNonNovelMarker(List<String?> fields) {
  final present = fields.whereType<String>().where(_anyNonNovelMarker.hasMatch);
  if (present.isEmpty) return null;
  final haystack = present.join('\n').toLowerCase();
  for (final marker in _nonNovelSourceMarkers) {
    if (haystack.contains(marker.toLowerCase())) return marker;
  }
  return null;
}

/// 依書源網址記下判斷結果。每次搜尋、每次書源清單更新都會從資料庫讀出新
/// 的書源物件，記在物件上幾乎都用不到；比對欄位內容是否相同比重新找標記
/// 便宜得多。項目數就是用過、還沒刪掉的書源數（[forgetNonNovelMarkers]）。
final Map<String, _NonNovelMarkerCache> _nonNovelMarkerCache = {};

/// 書源刪掉後放掉記下的判斷結果，連同它保留的發現、搜尋網址。
void forgetNonNovelMarkers(Iterable<String> sourceUrls) {
  for (final url in sourceUrls) {
    _nonNovelMarkerCache.remove(url);
  }
}

class _NonNovelMarkerCache {
  _NonNovelMarkerCache(this.fields, this.marker);

  final List<String?> fields;
  final String? marker;

  bool matches(List<String?> current) {
    for (var i = 0; i < fields.length; i++) {
      if (fields[i] != current[i]) return false;
    }
    return true;
  }
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

  bool get isNovelTextSource => nonNovelExclusionReason == null;

  bool get isReaderSupportedSourceType => bookSourceType == SourceType.book;

  bool get canParticipateInDiscovery =>
      enabled &&
      enabledExplore &&
      hasExploreUrl &&
      isNovelTextSource &&
      runtimeHealth.allowsReading;

  String? get nonNovelExclusionReason {
    if (!isReaderSupportedSourceType) {
      return 'sourceType:$bookSourceType';
    }
    final marker = detectedNonNovelMarker;
    if (marker != null) {
      return 'marker:$marker';
    }
    return null;
  }

  /// 發現、搜尋範圍與書源管理每次重建都會對每個書源問一次，搜尋網址常是
  /// 整段 JS，所以結果依書源記下來，欄位內容變了才重算。
  ///
  /// 不看發現網址：小說站的分類清單本來就有「动漫衍生」「影视剧本」這類小說
  /// 分類，番茄、起點會因此被當成非小說停用；漫畫、聽書、影音書源靠書源類型
  /// 與名稱、分組、網址就認得出來。
  String? get detectedNonNovelMarker {
    final fields = <String?>[
      bookSourceName,
      bookSourceGroup,
      bookSourceComment,
      bookSourceUrl,
      searchUrl,
    ];
    final cached = _nonNovelMarkerCache[bookSourceUrl];
    if (cached != null && cached.matches(fields)) return cached.marker;
    final marker = _findNonNovelMarker(fields);
    _nonNovelMarkerCache[bookSourceUrl] = _NonNovelMarkerCache(fields, marker);
    return marker;
  }

  Set<String> get groupTags => splitSourceGroups(bookSourceGroup);

  bool hasGroupTag(String tag) => groupTags.contains(tag);

  SourceRuntimeHealth get runtimeHealth {
    // 分組只切一次，下面逐一比對狀態標記。
    final tags = groupTags;
    bool tagged(String tag) => tags.contains(tag);
    if (!isNovelTextSource || tagged(nonNovelSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.nonNovel,
        label: nonNovelSourceGroupTag,
        description: '來源不是純文字小說書源',
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

    if (tagged(timeoutSourceGroupTag) ||
        tagged(siteBrokenSourceGroupTag) ||
        tagged(upstreamBlockedSourceGroupTag) ||
        tagged(quarantineSourceGroupTag)) {
      return const SourceRuntimeHealth(
        category: SourceHealthCategory.upstreamUnstable,
        label: quarantineSourceGroupTag,
        description: '上游暫時不可用，來源先隔離但不視為永久失效',
        allowsSearch: false,
        allowsReading: false,
        cleanupCandidate: false,
        quarantined: true,
      );
    }

    return SourceRuntimeHealth.healthy;
  }

  bool get isSearchEnabledByRuntime => enabled && runtimeHealth.allowsSearch;

  bool get isReadingEnabledByRuntime => enabled && runtimeHealth.allowsReading;

  bool get isCleanupCandidate => runtimeHealth.cleanupCandidate;

  bool get isQuarantined => runtimeHealth.quarantined;
}
