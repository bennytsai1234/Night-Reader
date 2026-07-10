# 子系統規格：章節資料與內容轉換（Chapter / Content）

> 2026-07-10 完成歸檔。

負責範圍：`lib/features/reader_v2/chapter/*` 四個檔案 + 其下游依賴
`lib/core/services/reader_chapter_content_store.dart`、
`lib/core/services/reader_chapter_content_storage.dart`、
`lib/core/services/chapter_content_preparation_pipeline.dart`、
`lib/core/database/dao/{chapter_dao,reader_chapter_content_dao}.dart`、
`lib/core/models/{chapter,reader_chapter_content,replace_rule}.dart`。

本文件對應方案 B 文檔 §4.1 `ChapterRepository`（文本層）。**現況與方案 B
的目標介面形狀不同**——現況是「同步目錄 + 非同步整章正文快取」，方案 B 要的是
「±N 章記憶體視窗 + contentHash + events stream」。兩者的落差與接線方式見
第 5 節。

---

## 1. 子系統運作方式（給沒讀過原始碼的實作者）

Reader V2 的「一本書」由三層資料組成：

1. **章節目錄**（`List<BookChapter>`）：一本書全部章節的中繼資料（標題、
   URL、index…），一次性載入，之後常駐記憶體，不分頁、不做視窗管理。
2. **章節正文快取**（SQLite `reader_chapter_contents` 表 + DAO）：每一章
   「原始正文」（尚未套用替換規則/簡繁轉換）的持久化快取，key 是
   `sha1(origin\nbookUrl\nchapterUrl)`。這是唯一跨 App 重啟存活的快取層。
3. **章節正文記憶體快取**（`ReaderV2ChapterRepository._contentCache`）：
   「已轉換完成」（套完 replace rule + 簡繁 + 重分段）的 `ReaderV2Content`
   物件，LRU 上限 20 章，App 存活期間有效，不落地。

三層對應三個不同粒度的「載入」：

- `ChapterRepository.ensureChapters()` 只碰第 1 層：目錄為空時，先查本地
  DB（`ChapterDao.getByBook`），若 DB 也空則呼叫書源服務
  `BookSourceService.getChapterList` 抓目錄並寫回 DB。之後全程只用記憶體中
  的 `_chapters` 列表，`ensureChapters()` 早退。
- `ChapterRepository.loadContent(chapterIndex)` 走第 2、3 層：先查記憶體
  `ReaderV2Content` 快取命中即回傳；否則透過
  `ReaderChapterContentStorage`（內部組裝
  `ChapterContentPreparationPipeline`）查 SQLite 正文快取，命中就直接轉換；
  沒命中則呼叫書源服務（或本地書服務）抓正文、寫回 SQLite、再轉換，轉換結
  果寫回記憶體 LRU。
- 轉換（replace rule + 簡繁 + 重分段）由 `ReaderV2ContentTransformer`
  完成，內部優先送到一個常駐 background isolate（`ReaderV2ContentTransformWorker`），
  isolate 不可用時退回 `compute()` 一次性 isolate；簡繁字典只在主 isolate
  的靜態記憶體，常駐 worker 啟動時會把字典資料轉送一次到 worker 內初始化。

「章節內容更新後如何失效」在現況中**沒有 per-chapter 的 contentHash 比對
機制**：唯一的失效手段是整體 `clearContentCache()`（把 `_contentCache`
整包清空、把 in-flight Future 清空、把 enabled-replace-rules 快取清空、
`_source` 清空），由呼叫端在「使用者變更會影響轉換輸出的設定」時全面觸
發（見第 4 節「contentSettingsGeneration」）。`ReaderV2Content` 本身確實帶
`contentHash` 欄位（sha1），但它只是「轉換後內容的指紋」，用途目前僅供
`ReaderV2LayoutView` 之類消費者判斷內容是否變了；它**不是快取 key 的一部
分**，也**不驅動任何自動失效**——這與方案 B 文檔 §4.1「附帶 contentHash，
作為所有下游快取 key 的一部分」的設計是兩回事，接線時要注意（見第 6 節風
險）。

---

## 2.【精確 API 清單】

### 2.1 `ReaderV2ChapterRepository`（`chapter/reader_v2_chapter_repository.dart`）

```dart
class ReaderV2ChapterRepositoryException implements Exception {
  const ReaderV2ChapterRepositoryException(this.message);
  final String message;
}

class ReaderV2ChapterRepository {
  ReaderV2ChapterRepository({
    required this.book,                                   // Book（不可變更）
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    ReplaceRuleDao? replaceDao,                            // null 時章內替換規則永遠視為空清單
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? contentDao,                   // null 時完全跳過 V2 正文快取管線
    BookSourceService? service,
    int Function()? currentChineseConvert,                 // 每次轉換即時讀取，預設恆回 0（不轉換）
  });

  final Book book;
  final BookDao bookDao;
  final ChapterDao chapterDao;
  final ReplaceRuleDao? replaceDao;
  final BookSourceDao sourceDao;
  final ReaderChapterContentDao? contentDao;
  final BookSourceService service;
  final int Function() currentChineseConvert;

  List<BookChapter> get chapters;         // List<BookChapter>.unmodifiable(_chapters)
  int get chapterCount;

  Future<List<BookChapter>> ensureChapters();
  BookChapter? chapterAt(int chapterIndex);           // 越界回 null
  String titleFor(int chapterIndex);                  // chapterAt(i)?.title ?? ''

  Future<ReaderV2Content> loadContent(int chapterIndex);
  Future<ReaderV2Content?> preloadContent(int chapterIndex); // index 越界回 null；否則等同 loadContent
  ReaderV2Content? cachedContent(int chapterIndex);           // 純讀記憶體 LRU，不觸發載入
  void clearContentCache();                                   // 唯一的整體失效入口
}
```

**呼叫者**（實際使用點，全部在 `lib/features/reader_v2/**`）：

| 成員 | 呼叫者 |
|---|---|
| `chapters` | `ReaderV2Runtime.chapters`（供章節目錄抽屜 `reader_v2_chapters_drawer.dart` 顯示）|
| `chapterCount` | `ReaderV2Runtime`、`ReaderV2Resolver`、`ReaderV2PreloadScheduler`、`ReaderV2NavigationController`、`ReaderV2ProgressController`、`ReaderV2ViewportBridge` —— 幾乎所有上層都要拿章節總數做邊界判斷/正規化 |
| `chapterAt` | `ReaderV2Runtime.chapterAt`（TTS/書籤等經由 runtime 間接呼叫）|
| `titleFor` | `ReaderV2Runtime.titleFor`、`ReaderV2Resolver`（組 `ReaderV2ChapterView`/佔位頁的 title）、`ReaderV2ProgressController`（進度顯示章名）|
| `ensureChapters()` | `ReaderV2Runtime.ensureChapters()`、`ReaderV2Resolver.ensureLayoutAtLeast`/`continueLayoutStep`、`ReaderV2NavigationController`（跳章前確保目錄存在）|
| `loadContent(index)` | `ReaderV2Resolver._stepOnce`（排版引擎的內容輸入）、`ReaderV2NavigationController`（跳章時預取內容）、`ReaderV2Runtime.loadContentForTts`（TTS 朗讀取文字）|
| `preloadContent(index)` | `ReaderV2PreloadScheduler._pumpContent`（背景預載佇列的實際執行動作）|
| `cachedContent(index)` | `ReaderV2PreloadScheduler.scheduleContent`（判斷是否已快取、免重複排隊）|
| `clearContentCache()` | `ReaderV2Runtime.reloadContentPreservingLocation()`（章內替換規則變更 / 簡繁轉換設定變更後的全量重載入口，見第 4 節）|

構造：由 `ReaderV2Dependencies.createChapterRepository()`
（`screen/dependencies/reader_v2_dependencies.dart`）組裝，DAO 皆從
`getIt`（GetIt DI）取得，`currentChineseConvert` 由
`ReaderV2ControllerHost` 綁定為 `() => settings.chineseConvert`。

### 2.2 `ReaderV2Content`（`chapter/reader_v2_content.dart`）— 不可變資料類

```dart
class ReaderV2Content {
  const ReaderV2Content({
    required this.chapterIndex,
    required this.title,
    required this.paragraphs,
    required this.plainText,
    required this.displayText,
    required this.contentHash,
  });

  final int chapterIndex;
  final String title;            // 已 trim
  final List<String> paragraphs; // List<String>.unmodifiable，每則已 trim 且非空
  final String plainText;        // paragraphs.join('\n\n')，不含標題
  final String displayText;      // title 非空時 '$title\n\n$plainText'，否則等於 plainText
  final String contentHash;      // sha1(jsonEncode({chapterIndex,title,paragraphs,displayText}))

  int get bodyStartOffset;       // title 空→0；plainText 空→title.length；否則 title.length+2（跳過 '\n\n'）

  factory ReaderV2Content.fromRaw({
    required int chapterIndex,
    required String title,
    required String rawText,
  });

  static String normalizeRawText(String rawText); // 見 §3.3
}
```

**呼叫者**：`ReaderV2ChapterRepository`（唯一產生者，經
`ReaderV2Content.fromRaw` 建構）；消費者是排版層
`ReaderV2LayoutEngine.layoutStep(content: ...)`（`session/reader_v2_resolver.dart`
呼叫）與 TTS（`ReaderV2Runtime.textFromVisibleLocation` 讀
`content.displayText`）。`bodyStartOffset` 用於「char offset 是否落在標題
內」的判斷（TTS 從可見位置朗讀時跳過標題）。

### 2.3 `ReaderV2ContentTransformer`（`chapter/reader_v2_content_transformer.dart`）

```dart
class ReaderV2ContentTransformer {
  const ReaderV2ContentTransformer();

  Future<ReaderV2ProcessedChapter> process({
    required Book book,
    required BookChapter chapter,
    required String rawContent,
    required List<ReplaceRule> enabledRules,
    required int chineseConvertType,   // 0=不轉換 1=簡轉繁 2=繁轉簡（與 ChineseTextConverter 對齊）
  });
}

// 常駐 worker：純內部實作細節，外部不應直接使用，僅記錄供理解效能特性。
class ReaderV2ContentTransformWorker {
  static final ReaderV2ContentTransformWorker instance;
  Future<Map<String, Object?>?> process(Map<String, Object?> args); // null=worker 不可用，呼叫端退回 compute()
  @visibleForTesting static bool debugDisableWorker;
  @visibleForTesting static Future<List<String>?> Function() dictionaryDataLoader;
  @visibleForTesting void debugReset();
}
```

**唯一呼叫者**：`ReaderV2ChapterRepository._loadViaV2ContentPipeline`。

### 2.4 `ReaderV2ProcessedChapter`（`chapter/reader_v2_processed_chapter.dart`）— 轉換管線的中介輸出

```dart
class ReaderV2ProcessedChapter {
  const ReaderV2ProcessedChapter({
    required this.displayTitle,
    required this.content,                                    // 見 §3.4 段落格式
    this.effectiveReplaceRules = const <ReplaceRule>[],        // 實際造成內容變化的規則子集
    this.sameTitleRemoved = false,                             // 正文開頭重複標題是否被剝除
  });

  final String displayTitle;
  final String content;
  final List<ReplaceRule> effectiveReplaceRules;
  final bool sameTitleRemoved;
}
```

這是 `ReaderV2ContentTransformer.process()` 的回傳型別，也是
`ReaderV2ChapterRepository._loadViaV2ContentPipeline` 的回傳型別；repository
再把它的 `displayTitle`/`content` 塞進 `ReaderV2Content.fromRaw(title:
loaded.displayTitle, rawText: loaded.content)`——**注意此時
`ReaderV2ProcessedChapter.content` 已經是「每行前綴縮排」的段落文字**（見
§3.4），會再被 `ReaderV2Content.fromRaw` 的 `normalizeRawText` +
按 `\n+` 切段 + trim 处理一次；因為縮排字元 `　　`（全形空白 ×2）在
trim 時不受影響（trim 只去 ASCII 空白/換行），所以縮排在最終
`ReaderV2Content.paragraphs` 裡會被保留。

### 2.5 `ReaderChapterContentStore`（`core/services/reader_chapter_content_store.dart`）— SQLite 正文快取的門面

```dart
class ReaderChapterContentStore {
  ReaderChapterContentStore({
    required this.chapterDao,
    required this.contentDao,
    DateTime Function()? now,
  });

  final ChapterDao chapterDao;
  final ReaderChapterContentDao contentDao;

  Future<String?> getRawContent({required Book book, required BookChapter chapter});
  Future<ReaderChapterContentEntry?> getContentEntry({required Book book, required BookChapter chapter});
  Future<bool> hasReadyContent({required Book book, required BookChapter chapter});
  Future<void> saveRawContent({
    required Book book,
    required BookChapter chapter,
    required String content,
    bool saveChapterMetadata = true,   // true 時順手把 chapter 中繼資料 upsert 進 Chapters 表
  });
  Future<void> saveFailure({
    required Book book,
    required BookChapter chapter,
    required String message,
    bool saveChapterMetadata = true,
  });
  Future<void> clearChapter({required Book book, required BookChapter chapter});
  Future<void> saveChapterMetadata(List<BookChapter> chapters);
  Future<Set<int>> storedChapterIndices({required Book book});
  Future<void> deleteStoredContentForBook({required Book book});

  static String contentKeyFor({required Book book, required BookChapter chapter});
  // == ReaderChapterContentDao.contentKey(origin: book.origin, bookUrl: book.bookUrl, chapterUrl: chapter.url)
}
```

**呼叫者**：`ReaderV2ChapterRepository._loadViaV2ContentPipeline`（組裝
`ReaderChapterContentStorage.withMaterializer` 時傳入）、
`ChapterContentPreparationPipeline`（實際讀寫）。此外 `downloads`/快取管
理頁等其他子系統也可能直接用它清書籍快取（不在本次調查範圍，僅提醒接
線時注意此類共用者）。

### 2.6 下游組裝元件（未列在必讀清單但被 repository 直接組裝，需一併理解）

```dart
// core/services/reader_chapter_content_storage.dart
class ReaderChapterContentStorage {
  factory ReaderChapterContentStorage.withMaterializer({
    required Book book,
    required ReaderChapterContentStore contentStore,
    required BookSourceDao sourceDao,
    required BookSourceService service,
    BookSource? Function()? getSource,
    void Function(BookSource source)? setSource,
    String? Function(int chapterIndex)? resolveNextChapterUrl,
  });

  Future<ChapterContentPreparationResult> read({
    required int chapterIndex,
    required BookChapter chapter,
    BookSource? sourceOverride,
    bool forceRefresh = false,
    bool saveChapterMetadata = true,
    int maxAttempts = 1,
  });
  void reset();
}

// core/services/chapter_content_preparation_pipeline.dart
class ChapterContentPreparationResult {
  final String content;                       // ready 時=正文；failed 時=錯誤訊息
  final ReaderChapterContentStatus status;
  final String? failureMessage;
  bool get isReady;
  bool get isFailed;
  factory ChapterContentPreparationResult.ready(String content);
  factory ChapterContentPreparationResult.failed(String message);
}

class ChapterContentPreparationPipeline {
  ChapterContentPreparationPipeline({
    required this.book,
    required this.contentStore,
    required this.sourceDao,
    required this.service,
    this.getSource,
    this.setSource,
    this.resolveNextChapterUrl,
    this.retryDelay = _defaultRetryDelay,     // 預設 500ms * 2^attempt
  });

  Future<ChapterContentPreparationResult> prepare({
    required int chapterIndex,
    required BookChapter chapter,
    BookSource? sourceOverride,
    bool forceRefresh = false,
    bool saveChapterMetadata = true,
    int maxAttempts = 1,                       // repository 呼叫路徑固定傳 1（不重試）
  });
  void reset();
}
```

`ReaderV2ChapterRepository` 目前呼叫 `storage.read(...)` 時
**`maxAttempts` 用預設值 1（不重試）**——網路抓取失敗不會在 repository 層
自動重試，失敗直接以 `ReaderV2ChapterRepositoryException` 拋出給呼叫端
（見 §3.5）。

### 2.7 DAO 層（僅列與本子系統相關的方法簽名）

```dart
// core/database/dao/chapter_dao.dart
class ChapterDao {
  Future<List<BookChapter>> getByBook(String bookUrl);           // ORDER BY index
  Stream<List<BookChapter>> watchByBook(String bookUrl);
  Future<void> insertChapters(List<BookChapter> chapterList);    // insertAllOnConflictUpdate，以 url 為衝突鍵（見 §3.1 風險）
  Future<BookChapter?> getChapter(String bookUrl, int index);
  Future<void> deleteByBook(String bookUrl);
}

// core/database/dao/reader_chapter_content_dao.dart
class ReaderChapterContentDao {
  static String contentKey({required String origin, required String bookUrl, required String chapterUrl});
  Future<String?> getContent({required String contentKey});
  Future<ReaderChapterContentEntry?> getEntry({required String contentKey});
  Future<List<ReaderChapterContentEntry>> getAllEntries();
  Future<List<ReaderChapterContentEntry>> getEntriesByBookUrls(Iterable<String> bookUrls);
  Future<void> upsertEntry(ReaderChapterContentEntry entry);
  Future<bool> hasContent({required String contentKey});
  Future<bool> hasReadyContent({required String contentKey});
  Future<Set<int>> getStoredChapterIndices({required String origin, required String bookUrl});
  Future<void> saveContent({
    required String contentKey, required String origin, required String bookUrl,
    required String chapterUrl, required int chapterIndex, required String content,
    required int updatedAt, ReaderChapterContentStatus status = ReaderChapterContentStatus.ready,
    String? failureMessage,
  });
  Future<void> saveFailure({...}); // 同上但 status 固定 failed
  Future<void> deleteContent({required String contentKey});
  Future<void> deleteByBook(String origin, String bookUrl);
  Future<void> clearAllContent();
  Future<int> getTotalContentSize();
}
```

---

## 3.【資料格式】

### 3.1 章節識別與排序

- **識別鍵**：章節在同一本書內以 **`index`（int，0-based，抓目錄時依序賦
  值 `fetched[i].index = i`）** 為主要定位鍵，`ReaderV2ChapterRepository`
  全部公開 API 都用 `chapterIndex: int` 定址（非 URL、非 id）。
- **章節目錄排序**：`ChapterDao.getByBook` 以 `ORDER BY index` 讀回，因此
  記憶體中的 `_chapters` 陣列順序 = 書內閱讀順序，`_chapters[i].index`
  理論上恆等於 `i`（由 `ensureChapters()` 抓目錄時賦值保證，但**若目錄是
  從本地 DB 讀回，程式不重新驗證 `index` 與陣列下標是否一致**——見 §6 風
  險）。
- **`Chapters` 資料表的實際 PRIMARY KEY 是 `url`（單一欄）**，不是
  `(bookUrl, index)` 複合鍵（見 `core/database/tables/app_tables.dart:233-257`）。
  也就是說 `chapterDao.insertChapters()` 的 `insertAllOnConflictUpdate` 以
  **章節絕對 URL 全域唯一**為衝突判斷依據，理論上兩本不同書若章節 URL 相
  同會互相覆蓋——現況靠書源規則產生的 URL 天然含書籍路徑規避，但這是資料
  模型層的既有事實，換引擎時若要重新設計 chapter identity，必須把這點納
  入考量。
- **正文快取鍵**（`ReaderChapterContentDao.contentKey`）：
  `sha1("$origin\n$bookUrl\n$chapterUrl")`，三段材料以 `\n` 串接後
  UTF-8 → SHA1 hex。三個材料分別是 `book.origin`（書源 URL，本地書固定
  `'local'`）、`book.bookUrl`、`chapter.url`。**這是唯一持久化正文的
  key，不含 index，也不含任何內容指紋**——同一 `(origin, bookUrl,
  chapterUrl)` 永遠指向同一快取列，就算來源網站正文已更新也不會自動失
  效（見 §6 風險）。

### 3.2 正文取得流程與失敗處理（`loadContent` 完整路徑）

```
loadContent(i)
  → ensureChapters()                              // 若目錄空，抓目錄或拋例外
  → safeIndex = clamp(i, 0, chapterCount-1)         // 目錄非空時一定 clamp；目錄空時 i<0 才夾到 0
  → 記憶體 LRU 命中？→ 命中則 touch（LRU 提升）後直接回傳
  → 有 in-flight Future？→ 直接 await 同一個 Future（去重複請求）
  → _loadContentUncached(safeIndex, generation)：
       chapter = chapterAt(safeIndex)；不存在 → throw ReaderV2ChapterRepositoryException('章節內容載入失敗: 找不到章節')
       contentDao == null？
         是 → 走「舊路徑」：直接用 chapter.content（DB 裡若有殘留欄位）trim 後包成 ReaderV2Content（不套 replace/簡繁！）
         否 → 走「V2 管線」_loadViaV2ContentPipeline：
              1. 組 ReaderChapterContentStorage.withMaterializer（見 §2.6）
              2. storage.read(chapterIndex, chapter, saveChapterMetadata: book.origin != 'local', maxAttempts=預設1)
                 a. 若非 forceRefresh：先查 SQLite（getContentEntry）——命中且非失敗、非空 → 直接視為 ready，不再打網路
                 b. 未命中 → 呼叫 ChapterContentPreparationPipeline.prepare()：
                    - book.origin == 'local' → LocalBookService().getContent(book, chapter)
                    - 否則 → 先解出 BookSource（sourceOverride ?? repository 快取的 _source ?? sourceDao.getByUrl(book.origin)）；
                      source 為 null → ChapterContentPreparationResult.failed('加載章節失敗: 找不到書源')
                    - 有 source → BookSourceService.getContent(source, book, chapter, nextChapterUrl: chapterAt(i+1)?.url)
                    - 例外分類：DioException 依 statusCode / timeout / connectionError 轉成中文訊息；其餘 '加載章節失敗: $e'
                    - maxAttempts=1 → 不重試，一次失敗立即視為最終失敗
                    - 結果一律寫回 SQLite（saveRawContent 或 saveFailure），saveChapterMetadata 控制是否順手 upsert 章節中繼資料
                 c. prepare() 完成後再查一次 SQLite（避免併發寫入競態，取最終落地值）
              3. prepared.isFailed → throw ReaderV2ChapterRepositoryException((failureMessage ?? content).trim())
              4. 成功 → _ensureEnabledReplaceRules()（依 book.getUseReplaceRule() 決定要不要查 DB，查到後快取於 _enabledRules）
              5. ReaderV2ContentTransformer.process(...) → ReaderV2ProcessedChapter
       → ReaderV2Content.fromRaw(chapterIndex, title: processed.displayTitle 或 chapter.title, rawText: processed.content 或 chapter.content)
       → 寫入記憶體 LRU（僅當 cacheGeneration 未過期，即中途沒被 clearContentCache() 打斷）
```

失敗一律以拋出 `ReaderV2ChapterRepositoryException`（`implements
Exception`，`toString()` 直接回傳 message）呈現給呼叫端，**沒有「空章佔位
內容」的 fallback**——呼叫端（`ReaderV2Resolver._stepOnce`）目前的處理是
把錯誤訊息記在 `_layoutErrors[chapterIndex]`，並在 `placeholderPageFor`
用「章節載入失敗，翻頁重試」的假頁面呈現（這屬於排版/渲染子系統的行
為，不在本子系統範圍，僅供接線參考）。

**沒有 contentDao 時的舊路徑**完全跳過 SQLite 快取與內容轉換管線
（不套 replace rule、不做簡繁轉換、不做重分段），只是把 `chapter.content`
（DB `Chapters.variable`？不，是 `BookChapter.content` 欄位，來自
`fromJson`/`copyWith`，通常是舊資料格式殘留或本地書直讀）trim 後包裝。這
是相容性 fallback，非主要路徑；生產環境 `contentDao` 一律有值（由
`getIt.isRegistered<ReaderChapterContentDao>()` 判斷）。

### 3.3 `normalizeRawText`（原始正文正規化，`ReaderV2Content` 靜態方法）

```
rawText
  .replaceAll('\r\n', '\n')
  .replaceAll('\r', '\n')
  .replaceAll(RegExp(r'[ \t]+\n'), '\n')      // 行尾空白清掉
  .replaceAll(RegExp(r'\n{3,}'), '\n\n')      // 3+ 連續換行收斂成 2
  .trim()
```

之後以 `RegExp(r'\n+')` 切段、逐段 `trim()`、丟棄空段，得到
`paragraphs: List<String>`。

### 3.4 `ReaderV2ProcessedChapter.content` 的段落格式（`_processContent` 輸出）

轉換管線內部（`ReaderV2ContentTransformer._processContent`，在背景
isolate 執行）對正文做以下**固定順序**的處理：

1. **去重複標題**：以正則
   `^(\s|\p{P}|<書名跳脫>)*<章名跳脫，空白折疊為 \s*>(\s)*`（unicode 模
   式）比對正文開頭，命中則整段剝除，`sameTitleRemoved = true`。若第一次
   （用原始章名）沒命中，且 `useReplaceRules && titleRules 非空`，改用套
   完標題替換規則後的 `displayTitle` 再試一次比對。
2. **重分段**（`reSegmentEnabled` = `book.getReSegment()`，僅在滿足下列
   條件時才觸發）：正規化換行後，若非空行數 `> 1` 或正規化後總長度
   `< 180` 字元，**直接跳過重分段**（視為已經有正常分段或內容太短不值
   得）；否則視為「整章擠成一行/幾乎一行」，依句尾標點
   `。！？!?；;`（其後可再吞掉閉合符號
   `」』"'）)》〉】]`）切成多行。
3. **套用章內替換規則**（僅 `useReplaceRules` 時）：先把每行各自
   `trim()`，再依 `rule.order` 升冪逐條套用；每條規則先判斷
   `rule.appliesToContent(bookName, bookOrigin)`（`scopeContent == true`
   且 `scope` 為空或包含書名/書源），套用時包在 try/catch，套用後若內容
   有變才記入 `effectiveReplaceRules`。
4. **最終分段包裝**：把處理後內容按 `\n` 切行，逐行 `trim()` +
   `replaceAll(' ', ' ')`（NBSP → 一般空白），非空行前綴
   **`'　　'`（全形空白 ×2，中文排版慣用首行縮排）**，再以 `'\n'`
   join 回單一字串，作為 `ReaderV2ProcessedChapter.content`。
5. `displayTitle` 固定回傳 `''`（標題由外層 `_processTitle` 另外算好塞回
   `ReaderV2ProcessedChapter.displayTitle`，見下）。

標題處理（`_processTitle`，與正文處理平行，不受 `reSegmentEnabled` 影
響）：`chapterTitle` 先去掉 `\r`/`\n`，若 `useReplaceRules` 則依序套用
`titleRules`（`scopeTitle == true` 的規則），每條套用後若結果
`trim()` 非空才採用（避免規則把標題整個清空）。

簡繁轉換（`chineseConvertType`）套用在 `displayTitle` 與 `content` **兩
者整體**上，是轉換管線的**最後一步**（無論走 worker 或 compute 退回路
徑）。`ChineseTextConverter.convert(text, convertType:)`：`0`=不轉換、
`1`=簡轉繁、`2`=繁轉簡（本次調查未深入 `ChineseTextConverter` 內部字典
實作，僅記錄呼叫介面）。

### 3.5 `ReaderV2Content.contentHash` 計算材料

```
sha1(utf8.encode(jsonEncode({
  'chapterIndex': chapterIndex,
  'title': normalizedTitle,
  'paragraphs': paragraphs,     // List<String>，即最終段落陣列（含縮排前綴）
  'displayText': displayText,
})))
```

**这是「轉換後」內容的指紋，不是「原始正文」的指紋**，且未被用作任何快
取 key 或失效判斷依據——純粹是資料欄位，供下游（例如排版層）判斷「兩次
`ReaderV2Content` 是否代表相同渲染內容」。

### 3.6 持久化 schema（SQLite，Drift 定義於 `core/database/tables/app_tables.dart`）

```
Chapters（PK: url）
  url TEXT, title TEXT, isVolume BOOL DEFAULT false,
  baseUrl TEXT NULL, bookUrl TEXT, index INT,
  isVip BOOL DEFAULT false, isPay BOOL DEFAULT false,
  resourceUrl TEXT NULL, tag TEXT NULL, wordCount TEXT NULL,
  start INT NULL, end INT NULL,
  startFragmentId TEXT NULL, endFragmentId TEXT NULL,
  variable TEXT NULL     // JSON map，自訂 key-value

ReaderChapterContents（PK: contentKey）
  contentKey TEXT,                      // sha1(origin\nbookUrl\nchapterUrl)
  origin TEXT, bookUrl TEXT, chapterUrl TEXT, chapterIndex INT,
  content TEXT NULL,                    // ready 時=原始正文；failed 時=錯誤訊息
  status INT DEFAULT 1,                 // 0=notReady 1=ready 2=failed（ReaderChapterContentStatus）
  failureMessage TEXT NULL,
  updatedAt INT                         // epoch millis
```

`ReaderChapterContentEntry`（DAO 讀回的值物件）：
`{contentKey, origin, bookUrl, chapterUrl, chapterIndex, status,
content?, failureMessage?, updatedAt}`；`isReady`/`isFailed`/
`hasDisplayContent`（`(content ?? '').trim().isNotEmpty`）為衍生 getter。

**注意：`ReaderChapterContents` 存的是「原始正文」（套用 replace
rule/簡繁轉換之前），不是轉換後結果**——因此章內替換規則或簡繁設定變更
後，SQLite 快取完全不需要動，只要清掉記憶體層（`clearContentCache()`）
重新跑一次轉換即可，這是 `reloadContentPreservingLocation()` 只清記憶體
不動 SQLite 的原因。

### 3.7 邏輯錨點 / 進度格式（`ReaderV2Location`，`session/reader_v2_location.dart`）

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  final int chapterIndex;      // 對應 ReaderV2ChapterRepository 的 chapterIndex
  final int charOffset;        // 偏移量單位是「字元數」，落在 ReaderV2Content.displayText 座標系
  final double visualOffsetPx; // 視覺微調（像素），clamp 在 [-120, 120]

  ReaderV2Location normalized({int? chapterCount, int? chapterLength});
  factory ReaderV2Location.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

`charOffset` 的座標系是 `ReaderV2Content.displayText`（即
`'$title\n\n$plainText'`），**不是段落索引 + 段內偏移**，也不區分「在標
題內」還是「在正文內」——要判斷是否在標題範圍靠
`ReaderV2Content.bodyStartOffset` 自行比較。持久化位置存在 `Book` 模型的
`chapterIndex`/`charOffset`/`visualOffsetPx` 三欄（`core/models/book.dart`），
隨書籍記錄一起存 DB，開書時作為 `ReaderV2Runtime` 的 `initialLocation`。

這與方案 B 文檔 I6「`(chapterId, paraIndex, charOffset)`」的錨點格式**形
狀不同**：現況用 `chapterIndex`（非穩定 id，若章節目錄重新抓取且順序改
變會漂移）而非 `chapterId`；`charOffset` 是整章字元偏移而非「段落索引 +
段內偏移」。詳見第 5、6 節。

### 3.8 章節目錄/正文事件

**現況沒有事件流（Stream）**。`ReaderV2ChapterRepository` 不對外廣播
`loaded`/`evicted`/`invalidated` 之類事件；所有狀態變化靠呼叫端主動查詢
（`cachedContent`）或等待 Future（`loadContent`/`preloadContent`）完
成。唯一的「批次失效通知」是 `clearContentCache()` 呼叫本身（同步方法，
無回呼、無 Stream），呼叫端必須自己知道要在什麼時機呼叫它並接著重新載
入（`ReaderV2Runtime.reloadContentPreservingLocation()` 的模式）。

---

## 4.【行為參數】

| 常數/預設值 | 值 | 位置 | 說明 |
|---|---|---|---|
| `_maxContentCacheSize` | `20` | `ReaderV2ChapterRepository` | 記憶體 `ReaderV2Content` LRU 上限，滿了逐出「最久未 touch」的一章（`_contentCache.keys.first`，Dart `LinkedHashMap` 插入序即 LRU 序，`loadContent` 命中時會 remove+重插做 touch） |
| `currentChineseConvert` 預設 | `() => 0` | 建構子 | 未提供時恆不轉換 |
| replace rule 生效條件 | `book.getUseReplaceRule() == true` 且 `replaceDao != null` | `_ensureEnabledReplaceRules` | 否則永遠回空規則清單（`Future.value(const [])`），且此結果本身不查 DB、不快取 |
| 重分段觸發門檻 | 非空行數 `> 1` **或** 正規化後長度 `< 180` 字元 → 跳過重分段 | `_reSegment` | 只有「幾乎單行且夠長」的章節才會被重新分段 |
| 句界切分字元 | `_sentenceEndChars = '。！？!?；;'` | `ReaderV2ContentTransformer` | 觸發換行的句尾標點 |
| 句尾閉合符延伸字元 | `_sentenceCloseChars = '」』"'）)》〉】]'` | 同上 | 句尾標點後緊跟這些符號會一併吞入同一句再換行 |
| 段落縮排前綴 | `'　　'`（全形空白 ×2） | `_processContent` | 每個非空段落固定加此前綴，屬視覺格式，非資料語意 |
| `_processInBackground` 正則快取上限 | `500`（超過整包清空） | `_getOrCreateRegex` | 純效能快取，非行為參數 |
| retry 延遲公式 | `500ms * 2^attempt` | `ChapterContentPreparationPipeline._defaultRetryDelay` | **repository 目前呼叫路徑 `maxAttempts` 用預設值 `1`，此重試機制實際不會觸發** |
| `contentKey` 雜湊演算法 | SHA1 | `ReaderChapterContentDao.contentKey` / `ReaderChapterContentStore.contentKeyFor` | `sha1(origin\nbookUrl\nchapterUrl)` |
| `ReaderV2Content.contentHash` 雜湊演算法 | SHA1 | `ReaderV2Content.fromRaw` | 見 §3.5 |
| `ReaderV2Location.minVisualOffsetPx` / `maxVisualOffsetPx` | `-120.0` / `120.0` | `reader_v2_location.dart` | 視覺微調鉗制範圍（像素） |
| 章節記憶體視窗（方案 B 目標） | ±2 章（`N=2`） | 方案 B 文檔 §4.1/§6 | **現況未實作**——見第 5、6 節 |

---

## 5.【新引擎接入指引】

方案 B 文檔 §4.1 要的 `ChapterRepository` 介面：

```dart
abstract interface class ChapterRepository {
  Future<ChapterText> load(ChapterId id);   // 冪等、重入安全
  void setPrefetchCenter(ChapterId id);     // 移動 ±N 視窗
  Stream<ChapterEvent> get events;          // loaded / evicted / invalidated
}

final class ChapterText {
  final ChapterId id;
  final String contentHash;
  final List<String> paragraphs;
}
```

現況 `ReaderV2ChapterRepository` **不是**這個介面，但可以在它之上包一層
adapter，不需要重寫本子系統：

1. **`ChapterId` ↔ `chapterIndex`**：直接用現有的 `int chapterIndex` 當
   `ChapterId`（現況本來就以 index 定址，沒有更穩定的 id）。若新引擎堅持
   `ChapterId` 要抵抗目錄重排，需要額外一層「index → url 的穩定映射」，
   但這是新增設計，現況資料模型不提供。

2. **`load(ChapterId id)` = `ReaderV2ChapterRepository.loadContent(index)`
   + 欄位轉換**：`ReaderV2Content` 已經有 `contentHash` 與
   `paragraphs`（見 §2.2、§3.5），可以幾乎原樣映射成方案 B 的
   `ChapterText`：

   ```dart
   ChapterText adaptFrom(ReaderV2Content c) => ChapterText(
     id: c.chapterIndex,             // 或包裝成專屬 ChapterId 型別
     contentHash: c.contentHash,
     paragraphs: c.paragraphs,        // 已含縮排前綴、已去空段
   );
   ```

   注意 `paragraphs` 不含標題——若新引擎的「段落」定義要求標題也是一個
   block，需要 bridge 層自行把 `c.title` 併入陣列第 0 項（現況
   `ReaderV2Content.title` 是獨立欄位，`paragraphs` 純內文）。

3. **`setPrefetchCenter(ChapterId id)` / ±N 視窗** —— **現況完全沒有這個
   機制**。`ReaderV2ChapterRepository._contentCache` 只是一個容量 20 的
   全域 LRU，不感知「當前章」，也不主動釋放視窗外章節（唯一的釋放手段是
   LRU 自然淘汰或 `clearContentCache()` 整包清空）。要接上方案 B 的 ±2
   章視窗語意，bridge 層需要自己維護「當前中心章」並在移動時：
   - 呼叫 `preloadContent(center-2..center+2)` 主動預熱視窗內容；
   - 視窗外章節目前**無法**主動從 `ReaderV2ChapterRepository` 驅逐（沒有
     `evict(index)` 這種 API）——若要嚴格控制記憶體，bridge 層需要繞過
     repository 自己管理一份視窗快取，或者接受「LRU=20 章」當作近似的
     視窗上限（20 遠大於 ±2=5 章，多數情況下等效於不釋放）。
   - 現有 `ReaderV2PreloadScheduler`（`session/reader_v2_preload_scheduler.dart`）
     已經實作了「以當前章為中心、方向感知」的預載排程（`scheduleAround`/
     `scheduleDirectional`/`buildCenteredOrder`），**新引擎可以直接重用
     這個排程器的邏輯模式**（甚至考慮直接沿用該類別）而不必重新發明，只
     是它目前耦合了 `ReaderV2Resolver`（排版層），bridge 時需要解耦或另
     開一個只認 `ChapterRepository` 的精簡版。

4. **`Stream<ChapterEvent> get events`** —— **現況不存在**，需要新增。最
   小可行做法：在 bridge 層包一層 `StreamController<ChapterEvent>`，在
   下列既有時機手動 `add` 事件：
   - `loadContent` 的 Future 成功完成 → 發 `loaded(chapterIndex,
     contentHash)`；
   - `clearContentCache()` 呼叫後 → 對「呼叫前記憶體中所有已快取的
     index」逐一發 `invalidated(chapterIndex)`（現況 `clearContentCache`
     不記錄被清掉的是哪些 index，bridge 層需要在清空前先讀一次
     `_contentCache` 的 key 集合——但 `_contentCache` 是 private，只能
     透過在清空前呼叫 `cachedContent(i)` 逐一探測，或要求對
     `ReaderV2ChapterRepository` 做最小非破壞性擴充：新增一個
     `Set<int> get cachedIndices` getter）；
   - LRU 淘汰目前完全沒有回呼點（`_writeToContentCache` 內部
     `_contentCache.remove(_contentCache.keys.first)` 是 private 邏輯，
     外部無法感知哪一章被淘汰）——若方案 B 的 `evicted` 事件是強需求，這
     裡需要對 `ReaderV2ChapterRepository` 做小幅擴充（加一個 eviction
     callback 或把 LRU 邏輯搬到 bridge 層自己做）。

5. **contentHash 作為快取 key 的一部分**（方案 B 語意）——現況
   `ReaderV2Content.contentHash` 只是內容指紋，不是 key。若新引擎的測量
   層/排版層快取要以 `(chapterId, contentHash)` 為 key（章節文字更新時
   自動失效，方案 B §4.3 失效矩陣「章節文字更新」那一列），bridge 層可
   以直接拿 `ReaderV2Content.contentHash` 塞進新引擎的 key 組成裡——這個
   欄位語意剛好對得上，是現況少數可以直接複用、不需要改造的部分。但要注
   意：**現況原始正文（SQLite 快取）沒有自動偵測「來源網站正文已更新」
   的機制**，`contentHash` 只在「同一份原始正文，經過不同的
   replace-rule/簡繁設定轉換」時才會變化；來源網站真的更新內容後，除非
   使用者手動觸發重新整理章節（不在本子系統範圍），contentHash 不會自
   己變。

6. **章節識別/排序**：新引擎若要 `ChapterId` 獨立於陣列下標，建議接線時
   把 `BookChapter.url`（配合 `bookUrl`）當作穩定 id 素材（`Chapters` 表
   本來就以 `url` 為 PK），而不是直接複用 `chapterIndex`；但這會需要在
   `ReaderV2ChapterRepository` 之上再包一層 `url → index` 查找表，因為現
   況公開 API 全部收 `int chapterIndex`。

7. **建議的介面分層**（不改動現有檔案，純新增 adapter）：

   ```
   方案 B LayoutPump / MeasurementStore
         ↑ ChapterText, ChapterEvent
   [新增] ChapterRepositoryBridge implements ChapterRepository
         ↑ 包裝呼叫
   ReaderV2ChapterRepository（本子系統，原樣保留）
         ↑
   ReaderChapterContentStorage / ChapterDao / ReaderChapterContentDao（原樣保留）
   ```

   `ReaderV2ContentTransformer` 與 `ReaderV2ProcessedChapter` 是 bridge
   內部細節，新引擎不需要直接接觸它們——它們已經被
   `ReaderV2ChapterRepository.loadContent` 封裝完畢，bridge 只需要消費
   `ReaderV2Content`。

---

## 6.【風險】

1. **contentHash 語意落差**：方案 B 假設 contentHash 是下游快取 key 的一
   部分、且能反映「文字更新時全鏈路正確失效」；現況 `contentHash` 只反映
   「轉換後結果」，SQLite 原始正文快取沒有內容版本概念。若新引擎直接假設
   `contentHash` 變了就代表「來源正文變了」，會在使用者切換簡繁/替換規則
   時誤判成「正文更新」而做不必要的重新排版——這其實無害（只是多做一次
   工），但如果新引擎反過來假設「contentHash 不變 = 正文絕對沒變」，會漏
   掉「來源網站正文真的更新但 SQLite 快取未過期」的情況（本來就是現況的
   已知限制，非本次接線引入的新風險，但接線時容易被誤解為「新引擎的
   bug」）。

2. **章節記憶體視窗語意落差**：現況是「全域 LRU 20 章、不感知中心章」，
   方案 B 要「±2 章視窗、超出即釋放」。若 bridge 層只是簡單呼叫
   `preloadContent` 而不做視窗裁剪，長時間閱讀（快速翻越很多章）記憶體佔
   用會被 20 章 LRU 頂住而非嚴格 5 章視窗（±2+中心）——不是無限洩漏，但
   比方案 B 設計值寬鬆 4 倍，需要在 bridge 層額外裁剪或接受此差異。

3. **`clearContentCache()` 是全量失效，沒有單章失效**：章內替換規則/簡繁
   設定變更目前一律清空**整個**記憶體快取（連同 `_enabledRules`、
   `_source`、所有 in-flight Future），並不是只失效受影響的章節。新引擎
   若假設「失效事件是逐章的」（`invalidated` per chapter），bridge 層要
   自己把一次 `clearContentCache()` 展開成「快取中曾經存在的每個 index
   各發一個 invalidated 事件」，而現況沒有 API 能列出「清空前有哪些
   index 在快取裡」（`_contentCache` 是 private），需要對
   `ReaderV2ChapterRepository` 做最小擴充（新增只讀的 `cachedIndices`
   getter）才能精確重建事件列表；否則只能發一個「全域失效」事件，讓新
   引擎自己決定要不要重新排版所有已排版章節。

4. **`chapterIndex` 不是穩定 id**：現況所有 API 用 `int chapterIndex` 定
   址，沒有獨立於陣列位置的 `ChapterId`。如果書源重新抓目錄導致章節數量
   或順序變化（例如原書源在某章之前插入了新章節），舊的持久化位置
   `Book.chapterIndex` 會直接指向錯誤的章節而不會被偵測——這是現況既有
   行為（`ReaderV2Location.normalized` 只做邊界 clamp，不做語意校正），
   新引擎若要更嚴格的 I6「邏輯錨點不漂移」保證，需要在 bridge
   層或更上層引入獨立於 index 的穩定 id（例如章節 URL），現況資料模型可
   以支援（`Chapters` 表以 `url` 為 PK）但目前無人使用它做這件事。

5. **`Chapters` 表以單一 `url` 為 PK，理論上跨書衝突**：`insertChapters`
   使用 `insertAllOnConflictUpdate` 對衝突鍵 `url` 做 upsert，若兩本不同
   書因書源規則產生了相同的章節 URL（理論上不該發生，但沒有資料庫層防
   線），會互相覆蓋章節中繼資料（不含正文，正文另外以
   `(origin,bookUrl,chapterUrl)` 三元組為 key，不受此風險影響）。換引擎
   若引入新的批次寫入路徑，需要留意這個既有 schema 弱點，不要在新代碼裡
   放大它（例如多書並行預抓目錄時）。

6. **`charOffset` 座標系是整章字元偏移，非「段落 index + 段內偏移」**：
   方案 B I6 定義的錨點是 `(chapterId, paraIndex, charOffset)`；現況是
   `(chapterIndex, charOffset-in-displayText)`。兩者換算需要
   `ReaderV2Content.paragraphs` 的長度累加表（bridge 層若要產生
   `paraIndex`，需自行對 `displayText` 做前綴和切分，注意 `displayText`
   的段落分隔符固定是 `'\n\n'` 且標題會佔用 `bodyStartOffset` 之前的區
   段，換算時不能忘記扣掉標題長度）。

7. **常駐 worker isolate 的隱性狀態**：`ReaderV2ContentTransformWorker`
   是一個模組級單例（`static final instance`），字典只在 worker 啟動時
   初始化一次；若新引擎在背景 isolate 架構上另有一套 `TextPreprocessor`
   isolate（方案 B §4.2），需要決定是「沿用/合併」還是「並存」——若並
   存，兩個常駐 isolate 各自佔用記憶體與啟動開銷，且都需要各自載入簡繁
   字典（`ChineseUtils.dictionaryAssetPaths`），是可觀的重複成本，建議
   接線時直接複用現有 worker 或把它的職責併入新的 `TextPreprocessor`。

8. **`maxAttempts` 實際恆為 1，重試機制形同虛設**：
   `ChapterContentPreparationPipeline` 支援指數退避重試，但
   `ReaderV2ChapterRepository` 呼叫 `storage.read(...)` 從未傳
   `maxAttempts` 參數（用預設值 1）。換引擎若假設「內容載入失敗前已經自
   動重試過」，會誤判失敗率或重複觸發使用者可見的重試 UI；接線時應明確
   延續「不重試、失敗立即上拋」的現況行為，除非有意另外設計重試策略。

9. **`preloadContent` 越界靜默回 null，`loadContent` 越界靜默 clamp**：
   兩者對越界 index 的處理不對稱——`preloadContent` 直接回 `null`（不載
   入任何內容），`loadContent`/`chapterAt`/`titleFor` 則各自用
   `_normalizeChapterIndex`/`clamp` 或直接查陣列越界回預設值靜默吞掉錯
   誤，不拋例外。新引擎的 bridge 層若假設「越界即拋錯」以便及早發現呼叫
   端 bug，需要自行在 adapter 層加上顯式邊界檢查，不能依賴底層拋例外。
