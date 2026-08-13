# data

## Responsibility

- 掌管所有持久化儲存（Drift/SQLite 主庫、磁碟檔案快取、快取路徑）與外部網路通訊的原始存取層：`lib/core/database/`（20 張 table、20 個 DAO、schema v2）、`lib/core/models/`（資料契約模型）、`lib/core/network/`（Dio 攔截器）、`lib/core/storage/`（磁碟快取與路徑）。
- 不含業務邏輯與 UI 狀態——業務調度在 `services`、引擎在 `engine`；本模組提供它們的資料出入口。
- 未來工作何時應從這裡開始：改 DB schema/table/DAO、加或改資料模型、改全域網路行為（攔截器/cookie/重定向）、改檔案快取策略或儲存路徑時，先看本文件再動手。
- 注意：`NetworkService`、`HttpClient`、`CacheManager`、`CookieStore` 實體位於 `lib/core/services/`，但屬本模組的網路/快取職責，改動網路或快取行為時它們才是主要著陸點（見 Key Flows）。

## Scope

- **資料庫** `lib/core/database/`
  - `app_database.dart` — `AppDatabase` singleton（`AppDatabase()` factory 回傳 `_instance`；`AppDatabase.forTesting(executor)` 供測試注入 `NativeDatabase.memory()`）。`schemaVersion => 2`。DB 檔案：`getApplicationSupportDirectory()/databases/night_reader.db`，開檔時若不存在會嘗試從舊名 `inkpage_reader.db` rename（app_database.dart:235 `_openConnection()`）。@DriftDatabase 同時列出 20 tables + 20 daos（兩份清單，改動需同步）。migration 含 25 條效能索引（`_performanceIndexStatements`，onCreate 與 `from < 2` 時建立）+ `beforeOpen` 執行 `PRAGMA optimize`。
  - `tables/app_tables.dart` — 20 張 table 定義；檔頭 8 個 TypeConverter：`EmptyStringConverter` + 7 個規則 JSON 轉換器（ReadConfig/SearchRule/ExploreRule/BookInfoRule/TocRule/ContentRule/ReviewRule）。多數 table 掛 `@UseRowClass(模型, generateInsertable: true)`。
  - `dao/*.dart`（20 個，排除 `.g.dart`）— 每個 DAO 對應一張 table；較重者：`book_source_dao.dart`（`_partQuery()` 手寫 SQL 只讀輕量欄位、`adjustSortNumbers()`、`renameGroup()`/`removeGroupLabel()`）、`reader_chapter_content_dao.dart`（contentKey = `sha1(origin\nbookUrl\nchapterUrl)`、狀態碼 0/1/2、多處 `customSelect` 效能查詢）。
  - 生成碼 `*.g.dart` 一律由 build_runner 產生，不手改。
- **模型** `lib/core/models/` — 純資料契約層，多數與 DB row 一對一（`Book`、`BookChapter`、`BookSource`、`BookGroup`、`Bookmark`、`Cookie`、`ReadRecord`、`ReplaceRule`、`DownloadTask`、`SearchBook`、`SearchKeyword`、`Cache`、`Server`、`DictRule`、`HttpTTS`、`TxtTocRule`、`RuleSub`、`KeyboardAssist` 等）。
  - `book/`（book_base/extensions/logic/serialization）與 `source/`（book_source_base/logic/rules/serialization、explore_kind）子目錄拆分重職責模型；`book.dart`/`book_source.dart` 為組合入口並 re-export。
  - `base_source.dart` — `BookSource` 與 `HttpTTS` 的共同抽象（login/cookie/header/variable 快取，對標 Android BaseSource.kt）。
  - `rule_data_interface.dart` — 規則引擎上下文介面（variableMap/putVariable/getVariable）。
- **網路** `lib/core/network/`
  - `interceptors/app_interceptor.dart` — 自動補 Referer/UA/Accept-Language + 手動 3xx 重定向（上限 10 跳、跨 authority 剝 cookie/authorization、用 `extra` 鍵傳遞重定向狀態）。`_manualRedirectChain` 等 extra 鍵同時是 `StrResponse.redirectChain` 的資料來源。
  - `interceptors/lenient_cookie_manager.dart` — 容錯 `expires=session` 等畸形 cookie（`ignoreInvalidCookies` 預設 **true**），含 `parseSetCookieValueLenient`/`sanitizeSetCookieValue` 公用函式（被 `NetworkService`、`HttpClient` 直接引用）。
  - `str_response.dart` — `StrResponse` 封裝 body/headers/raw，並從 raw.extra 讀出 `redirectChain`；由 engine（analyze_url、web_book、js_network_extensions、backstage_webview）消費。
- **儲存** `lib/core/storage/`
  - `app_cache.dart` — `AppCache`（對標 Android ACache.kt）：檔名 sha256(key)，`'<epoch>-<seconds> '` 前綴做過期，`_trimCache()` 依檔案數與總位元組裁切（50MB / 100 萬檔預設）。每個目錄一個 singleton。
  - `app_storage_paths.dart` — 路徑集中管理（documents/ruleData、temporary/libCachedImageData、book_assets、exports、backup 暫存、js_cache）；`MissingPluginException` 時 fallback 到 `Directory.systemTemp/night_reader`；`bookAssetDir` 等有 path component 白名單校驗。
  - `storage_metrics.dart` — `StorageMetrics.directorySize()` 遞迴計算目錄大小（被 `book_cover_storage_service` 使用）。
- **測試**：`test/core/database/`（cache_dao、database_optimization、read_record_dao、replace_rule_dao）、`test/core/models/`、`test/core/network/interceptors/`（app_interceptor、lenient_cookie_manager）+ `post_redirect_test.dart`、`test/core/storage/`（app_cache、app_storage_paths）。真實書源回歸用 `tool/` 腳本（見 DEVELOPMENT.md）。

## Dependencies & Impact

- **上游輸入**：外部套件 `drift`/`sqlite3`/`dio`/`cookie_jar`/`dio_cookie_manager`/`path_provider`/`crypto`/`synchronized`；`shared_preferences` 經由 services 層（非直接）。`lib/core/constant/`（source_type.dart、book_type.dart）被 DAO/模型引用。
- **呼叫者（專案內）**：
  - `lib/core/di/injection.dart` — 啟動時 `registerSingleton<AppDatabase>` + 註冊 **17 個** DAO 為 lazy singleton；`DictRuleDao`/`HttpTtsDao`/`TxtTocRuleDao` 僅列於 `@DriftDatabase` daos 清單，未註冊也未實例化。`AppDatabase` 實例在 `configureDependencies` 即建立，但 DB 連線（開檔）經 `LazyDatabase` 延至首次查詢。
  - 最高耦合 consumer：`backup_service` / `restore_service`（各用 8 個 DAO）、`reader_v2_chapter_repository` + `ReaderChapterContentStore`（chapterDao + contentDao）、`book_storage_service`、`source_switch_service`、`book_detail_provider`、bookshelf providers、`default_data`（啟動維護與預設書源載入）。
  - **背景 isolate 注意**：`source_check_isolate`（校驗 isolate）內 get_it 容器為空、DAO 未註冊；Workmanager 背景任務則會重跑 `configureDependencies()`（main.dart:46）重建 DI，DAO 正常註冊。`CacheManager`/`CookieStore` 一律用 `getIt.isRegistered<CacheDao>()` 退化為記憶體模式，`reader_v2_chapter_repository` 的 contentDao 為可選參數；校驗 isolate 內 `NetworkService.init(ephemeral: true)` 使用記憶體 CookieJar 避開 path_provider。
  - `NetworkService`（services）是 Dio 實例唯一來源：interceptor 加入順序固定為 `LenientCookieManager` → `AppInterceptor`；cookie 持久化於 `documents/.cookies`（PersistCookieJar）。`HttpClient` 僅是薄包裝（`Dio get client => NetworkService().dio`）。
- **下游影響**：models 被 engine（AnalyzeRule 消費 `RuleDataInterface`）與全部 features 使用；`StrResponse` 是 engine 網路層的返回型別；改攔截器/重定向行為會全面影響書源抓取；`AppCache` 目前只有 `explore_url_parser` 使用；`CacheManager` 是 BaseSource login/cookie/header/variable 快取的實作（模型對 services 有反向依賴，見 Known Risks）。

## Key Flows

1. **啟動初始化**：`main.dart` → DI（AppDatabase + DAO 註冊）→ `NetworkService.init()`（首次 HTTP 請求前必須完成）→ `DefaultData.initDeferred()`（welcome/main_page.dart:340；`adjustSortNumbers()`、過期快取清理、首次啟動載入 `assets/default_sources/sources.json`——目前為空陣列占位，不內建書源）。
2. **閱讀進度儲存**：ReaderV2 → `BookDao.updateProgress()`（bookshelf 排序鍵 `durChapterTime`，`visualOffsetPx` 會被 clamp 到 ±120）→ `books` table。bookshelf 清單經 `watchInBookshelf()` 串流驅動。
3. **章節內容快取**：下載完成 → `ReaderChapterContentStore`（services）→ `ReaderChapterContentDao.saveContent()`；contentKey = `sha1('$origin\n$bookUrl\n$chapterUrl')`；狀態 `notReady(0)/ready(1)/failed(2)`；`hasReadyContent`/`getStoredChapterIndices`/`getTotalContentSize` 用 `customSelect` 繞過 Drift 查詢建構器以利效能。
4. **網路請求**：呼叫端（`NetworkService().dio` / `HttpClient().client`）→ `LenientCookieManager`（讀寫 PersistCookieJar）→ `AppInterceptor`（補 header；3xx 時手動重放請求，結果 chain 寫入 extra）→ server。JS 引擎與 WebView 場景經 `StrResponse` 取 body/redirectChain。
5. **書源探索/搜尋**：`BookSourceDao._partQuery()`（`getAllPart`/`watchAllPart`/`getDiscoveryPart`/`watchDiscoveryPart`）手寫 SQL 只讀輕量欄位（排除 rule JSON 欄位與 jsLib 等大欄位），回傳的 `BookSource` 的 rule 欄位為 null——消費端不可假設規則存在。
6. **雙層快取**：`CacheManager`（services）記憶體 LRU → `CacheDao`（DB KV，含 deadline）→ 檔案（js_cache 目錄，sha256 檔名）；背景 isolate 中 DB 層自動降級。`AppCache`（storage）是獨立檔案快取，僅 explore_url_parser 使用。
7. **開發流程（schema 變更）**：改 `tables/app_tables.dart`（+models）→ `app_database.dart` 兩份清單 → `dart run build_runner build --delete-conflicting-outputs` → 新增 DAO 需在 `injection.dart` 註冊 → 有測試則在 `test/core/database/` 補測試。

## Change Entry Points & Routes

| 修改標的 | 起始檔案 | 需注意 |
|---|---|---|
| 新增 table/DAO | `tables/app_tables.dart` → `app_database.dart`（tables 與 daos 兩份清單）→ build_runner → `di/injection.dart` 註冊 | 4 個檔案 + 生成碼；DAO 的 `.g.dart` 由 build_runner 產出 |
| 修改模型欄位 | `models/` → `tables/app_tables.dart` 對應 table → build_runner | Drift 型別轉換器集中於 app_tables.dart 檔頭；`@UseRowClass` 模型與 table 欄位需一致 |
| 書源欄位增減 | `BookSources` table + `BookSource`/`BookSourceBase`/`book_source_serialization.dart` + **`book_source_dao.dart` 的 `_partQuery()` 欄位清單與 `_readPartSource`** | 原始 SQL 欄位清單是重複來源，易漏；Legado JSON 相容欄位名不可亂改（`sourceToJson` 1:1 對標 Android） |
| 修改網路行為 | `network/interceptors/` → `services/network_service.dart`（interceptor 註冊順序） | `parseSetCookieValueLenient` 被 NetworkService/HttpClient 直接引用；`_manualRedirectChain` extra 鍵與 `StrResponse.redirectChain` 綁定 |
| 修改快取策略 | `storage/app_cache.dart` + `database/dao/cache_dao.dart` + `services/cache_manager.dart` | 三層並存：記憶體 → DB → 檔案；改其中一層需同步其他層與 `default_data` 的過期清理 |
| 搬遷 DB 路徑/檔名 | `app_database.dart:getDatabasePath()` + `_openConnection()` | `inkpage_reader.db` 一次性 rename 已存在，勿重複新增 legacy 邏輯 |
| 閱讀進度/書籍排序 | `book_dao.dart:updateProgress/watchInBookshelf` + `models/book/*` | `visualOffsetPx` clamp、`durChapterTime` 排序、`Book.migrateTo`（換源時保留進度） |
| 模型/規則回歸 | `test/core/models/` + `tool/` 真實書源腳本 | 書源規則變更優先用 tool 腳本驗證（DEVELOPMENT.md） |

## Known Risks

- **Migration 只有 `from < 2` 一個分支**（app_database.dart:111）：schema 自 init commit（v0.2.91）起就是 v2，從未有過真正的 v1→v2 表遷移，`onUpgrade` 只補建索引。未來升 v3 必須自行撰寫完整遷移步驟；且 v1 DB 只補索引、不補表（若有 v1 使用者存在，其表結構假設與現行相同——目前無證據可驗證）。
- **`BookSourceDao._partQuery()` 的欄位清單重複**：`_partQuery` 的 SELECT 欄位清單與 `_readPartSource` 是手寫 SQL，新增欄位到 `BookSources` 時極易漏同步；回傳的 part BookSource 規則欄位為 null，任何呼叫端若誤用（如直接拿去跑規則）會靜默失敗。
- **`ReaderChapterContentDao.getTotalContentSize()` / `clearAllContent()` 目前無人消費**（lib/ 內僅 DAO 定義）：疑似預留給快取管理頁，改動前先確認是否為死碼。
- **`DictRules`/`HttpTtsTable`/`TxtTocRules` 三張 table 與對應 DAO 完全沉睡**：只存在於 `@DriftDatabase` 清單與 table 定義，DI 未註冊、lib/ 內無任何消費端；若需啟用要先補 DI 註冊與測試。
- **`BookDao.updateProgress` 的 `visualOffsetPx` clamp 到 ±120**（book_dao.dart:99）、`BookProgress.toJson` 亦 clamp 但範圍不同（-80~120，book_progress.dart:57）：兩處邊界不一致，跨端（WebView 同步、備份）進度若超出範圍會被靜默修正，與 Android 端數值語意須一致。
- **`NetworkService._isInitialized` 單次守衛**：init() 只會執行一次；若首次呼叫發生在背景 isolate（ephemeral 快取 jar），之後主 isolate 拿到的也是記憶體 jar（無持久化）。呼叫時機錯誤的影響是隱性的。
- **模型對 services 的逆向依賴**：`base_source.dart` import `CacheManager`/`CookieStore`（services），`book_extensions.dart` import `AppConfig`（config）與 `BookHelp`（engine）——「model 保持純資料」是理想而非事實；重構 models 時會被這些依賴牽制。
- **`AppCache` 格式相容**：過期前綴 `'<13位epoch>-<秒> '`（`_getDateInfo` 檢查 index 13 的 `-`）是對標 Android ACache.kt 的位元組佈局；若舊裝置殘留舊格式檔案，讀寫邏輯必須維持相容。`_trimCache` 用 Completer 序列化裁切，高頻 put 時可能堆積等待。
- **舊文件誤差**（本次重寫已修正）：舊 data.md 稱 `LenientCookieManager.ignoreInvalidCookies` 預設 false、`_trimCache()` 不檢查總大小——現況皆已相反（預設 true、有檢查），引用舊文件時勿沿用。
- **測試缺口**：20 個 DAO 中僅 cache/read_record/replace_rule + database_optimization 有直接測試；`BookSourceDao._partQuery`/`adjustSortNumbers`、`AppDatabase` migration、DB 檔名搬遷路徑皆無自動測試覆蓋。網路側有 interceptor 測試與 `post_redirect_test`。

## Boundaries

- **schema v2 凍結**：不得直接改 `schemaVersion` 或既有 table 欄位而不寫 migration；`onUpgrade` 需自行處理從舊版本升級的所有步驟（現有分支只補索引）。
- **生成檔紀律**：`*.g.dart` 不手改；改 table/DAO 後必須跑 `dart run build_runner build --delete-conflicting-outputs`（DEVELOPMENT.md 指定命令），否則編譯失敗。
- **多檔同步路徑**：新增 DAO = table（app_tables）+ 模型 + app_database 兩份清單 + DAO 檔案 + injection.dart 註冊，5 處缺一不可。
- **Dio 實例唯一來源**：原則上不直接 `Dio(...)`，一律 `NetworkService().dio`（或 `HttpClient().client`），否則攔截器/cookie 不生效；例外是 `book_cover_storage_service.dart:20` 直接 `Dio()`（書封下載刻意繞過攔截器與 cookie）。Interceptor 順序固定：cookie 先、app 後。
- **DB 檔名與路徑**：`night_reader.db` 於 application-support/databases；`inkpage_reader.db` 一次性 rename 已落地，勿再新增 legacy 分支。cookie 持久化在 `documents/.cookies`（不在 DB 內）。
- **書源 JSON 相容性**：`BookSource` 的 JSON 序列化（`BookSourceSerialization.sourceToJson`）1:1 對標 Legado 3.x；欄位名（bookSourceUrl、ruleSearch 等）是外部生態契約，不得改名。`SourceType`/`BookType` 位元語意（如 `type & BookType.text`、local origin 前綴 `loc_`）由 constant 定義，改動會連鎖影響 models 與 engine。
- **背景 isolate 契約**：校驗 isolate 內無 get_it 容器（Workmanager isolate 則會重跑 `configureDependencies`），所有 DAO 依賴必須走「可選注入或 isRegistered 降級」模式（見 CacheManager/CookieStore/reader_v2_chapter_repository 先例）；新增被 isolate 使用的 DAO 時必須遵守。
- **模型 ≠ 純資料**：`Book`/`BookChapter`/`BookSource` 承載業務方法（migrateTo、getCheckKeyword、variableMap 等），並依賴 services/config/engine——在 models 加新邏輯前先確認是否符合既有拆分（book/、source/ 子目錄）。