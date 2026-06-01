# 應用基礎設施

## 目前職責

所有模組的底層依賴：Drift 資料庫（21 tables、20 DAOs）、HTTP client（Dio + cookie）、GetIt DI 容器、儲存路徑管理、應用啟動（main.dart）、導覽（GoRouter 或 Navigator）、主題、版本更新、深連結、本地網路伺服器（shelf）、桌面小工具（home_widget）。修改 DB schema、新增 DAO、修改啟動流程，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/main.dart` | App 進入點、全域錯誤處理（Flutter & zone）、WorkManager 初始化、啟動後清理舊 artifacts |
| `lib/app_providers.dart` | MultiProvider 全局配置（BookshelfProvider、SettingsProvider、ChangeCoverProvider、DownloadService、TTSService、ExploreProvider）|
| `lib/core/database/app_database.dart` | Drift DB singleton、21 tables、20 DAOs、schema migration（v2+）|
| `lib/core/database/tables/app_tables.dart` | Drift table definitions + TypeConverters（SearchRule、ExploreRule、BookInfoRule、TocRule、ContentRule、ReadConfig）|
| `lib/core/database/dao/` | 20 DAO 檔案（BookDao、ChapterDao、BookSourceDao、BookmarkDao、ReplaceRuleDao、SearchBookDao、ReadRecordDao、CacheDao、CookieDao 等）|
| `lib/core/di/injection.dart` | GetIt singleton 設定（Logger、AppDatabase、全部 DAO、NetworkService、TtsService、CrashHandler）|
| `lib/core/network/` | StrResponse wrapper、AppInterceptor（User-Agent、logging）、LenientCookieManager |
| `lib/core/storage/app_storage_paths.dart` | 集中式路徑管理（documentsDir、temporaryDir、ruleDataDir、imageCacheDir 等）|
| `lib/core/storage/` | AppCache（記憶體快取）、StorageMetrics（儲存用量）、FileDoc（檔案抽象）|
| `lib/core/config/app_config.dart` | 靜態設定鏡像（replaceEnableDefault、readerPageAnim）|
| `lib/core/constant/` | AppConst（全局常數）、AppPattern（regex patterns）、PreferKey（SharedPreferences 鍵名）、BookType、PageAnim、SourceType 枚舉 |
| `lib/core/models/` | 所有 domain model（Book、Chapter、BookSource、Bookmark、ReplaceRule、DownloadTask 等）|
| `lib/core/base/base_provider.dart` | ChangeNotifier 基礎類（統一 loading/error 狀態管理）|
| `lib/core/exception/app_exception.dart` | 自訂異常類層次（AppException 及子類）|
| `lib/core/services/event_bus.dart` | AppEventBus 全域事件流（見 [event_bus](event_bus.md)）|
| `lib/core/services/cookie_store.dart` | Cookie 持久化（Dio + DB）|
| `lib/core/services/http_client.dart` | HTTP 工具函式 |
| `lib/core/services/network_service.dart` | Dio singleton（含 cookie jar、source concurrency locks）|
| `lib/core/services/app_log_service.dart` | 日誌服務 |
| `lib/core/services/crash_handler.dart` | 錯誤回報 |
| `lib/core/services/app_version.dart` | 版本資訊 |
| `lib/core/services/app_permission_service.dart` | 平台權限管理 |
| `lib/core/services/update_service.dart` + `update_ignore_store.dart` | App 更新檢查 |
| `lib/core/services/rate_limiter.dart` | 請求節流 |
| `lib/core/services/default_data.dart` | 內建預設書源 |
| `lib/core/services/resource_service.dart` | Asset 載入 |
| `lib/core/utils/` | 工具函式（string_utils、html_utils、url_util、file_utils、color_utils、time_utils、logger、archive_utils、lru_map 等）|
| `lib/core/widgets/book_cover_widget.dart` | 可重用書籍封面 widget |
| `lib/features/welcome/` | 啟動頁（SplashPage、MainPage 含底部 tab 導覽、ErrorPanel）|
| `lib/features/about/` | 關於頁面、崩潰日誌檢視、更新檢查 |
| `lib/features/association/` | 深連結與檔案關聯處理（AssociationHandlerService）|
| `lib/shared/` | 導覽設定（Navigation）、AppTheme（主題）、可重用 UI widget |

測試：`test/core/database/`、`test/core/models/`、`test/core/network/`、`test/core/services/`（update、permission、cache 等）、`test/features/welcome/`

## 依賴與影響

- 所有模組的底層依賴；這個模組的修改通常會影響所有其他模組
- **重要**：DB schema 變更需要 Drift migration；DAO 介面變更影響所有使用者服務
- **事件**：AppEventBus 是全域 singleton，所有模組都透過它通訊（見 [event_bus](event_bus.md)）

## 關鍵流程

**App 啟動流程**：
```
main() → runZonedGuarded() → _startApp()
  → configureDependencies()（GetIt 注入所有 singleton）
  → runApp(MultiProvider(...))
  → SplashPage → MainPage（底部 tab：書架 / 搜尋 / 探索 / 設定）
  → WidgetsBinding.addPostFrameCallback()
    → WorkManagerService.initialize()
    → 清理舊 artifacts（inkpage_reader.db → night_reader.db 遷移）
```

**DB 存取流程**：
```
服務/Provider → GetIt.I<AppDatabase>()
  → 對應 DAO（lazy singleton）
    → Drift 生成的查詢（.g.dart）
    → SQLite（sqlite3_flutter_libs）
```

**HTTP 請求流程**：
```
服務 → NetworkService.dio
  → AppInterceptor（User-Agent、logging）
  → LenientCookieManager（cookie 讀寫）
  → Dio → HTTP
  → CookieDao（持久化 cookie）
```

## 常見修改入口

- 新增 DB table / DAO → `lib/core/database/tables/app_tables.dart`（table 定義）→ `app_database.dart`（加到 @DriftDatabase）→ 新建 DAO → `injection.dart`（DI 注册）→ **必須新增 schema migration**
- 修改啟動流程 → `lib/main.dart`
- 修改全局 Provider → `lib/app_providers.dart`
- 新增 DI singleton → `lib/core/di/injection.dart`
- 修改路徑管理 → `lib/core/storage/app_storage_paths.dart`

## 修改路線

- **DB schema 變更**（T2 Migration 強制）：table 定義 → DAO → migration（`AppDatabase.schemaVersion++` + `MigrationStrategy.onUpgrade`）→ build_runner 重新生成 `.g.dart` → 執行 `flutter test test/core/database/`
- **新增 DAO**：定義 DAO 類 → `@DriftDatabase(daos: [...])` 加入 → `injection.dart` 注册 lazy singleton → 重新 build_runner
- **修改導覽**：`lib/shared/navigation/` 或 `lib/features/welcome/main_page.dart`

## Known Risks

- **build_runner 生成的 `.g.dart`** 不在版本控制中（依 .gitignore），每次 `flutter pub get` 後需 `flutter pub run build_runner build`；CI 需包含這個步驟
- Drift migration 沒有版本鎖，下降版本（降版 App）會觸發未定義行為
- GetIt 的 lazy singleton 在首次 `getIt<T>()` 時初始化；順序依賴（A 需要 B 存在）需確保 `injection.dart` 的注册順序
- `app_storage_paths.dart` 的路徑在 Android 分區儲存規則變更後可能需要調整（targetSdk 升級時）
- main.dart 的 zone 錯誤處理捕捉了所有未處理異常，若 crash_handler 本身出錯會靜默失敗
- `night_reader.db` 有一次性從 `inkpage_reader.db` 的遷移（已實作）；若使用者跳過版本可能需要額外處理

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要在 DAO 中加業務邏輯（DAO 只做資料存取）
- 不要繞過 GetIt 直接 new Service（破壞 DI 隔離，無法測試）
- 不要修改 `.g.dart` 生成的檔案（每次 build_runner 都會覆蓋）
- 不要在 AppConfig 中存複雜物件（只放靜態基本型別的設定鏡像）
