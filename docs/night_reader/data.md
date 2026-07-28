# data — 資料存取層

## 1. Responsibility

封裝所有持久化儲存與外部網路通訊的原始存取，向上層（service / feature）提供統一的資料出入口。不包含業務邏輯或 UI 狀態。

## 2. Scope

| 子層 | 位置 | 說明 |
|---|---|---|
| **Database** | `lib/core/database/` | Drift ORM：20 張 table、20 個 DAO，schema v2，含效能索引。Singleton `AppDatabase`，DB 檔案位於 `getApplicationSupportDirectory()/databases/night_reader.db`。支援從舊名 `inkpage_reader.db` 自動搬遷。 |
| **Models** | `lib/core/models/` | 純資料類別，與 DB row 一對一對應。`Book` 與 `BookSource` 因職責較重各自拆分為 `book/`、`source/` 子目錄。`BaseSource` 是 `BookSource` 與 `HttpTTS` 的共同抽象。 |
| **Network** | `lib/core/network/` | Dio interceptor 管線：`AppInterceptor`（自動補 Referer/UA/Accept-Language + 手動 3xx 重定向）、`LenientCookieManager`（容許 `expires=session` 等畸形 cookie）。請求出口為 `NetworkService` singleton。 |
| **Storage** | `lib/core/storage/` | 磁碟快取 `AppCache`（類 Android `ACache`）、路徑集中管理 `AppStoragePaths`、用量統計 `StorageMetrics`。 |

## 3. Dependencies & Impact

- **被依賴方（外部套件）：** `drift` / `sqlite3` / `dio` / `cookie_jar` / `path_provider`
- **消費者（專案內）：** 幾乎所有 `lib/core/services/` 與 `lib/features/` 都透過 DAO 讀寫資料。最高耦合的 consumer：`backup_service`、`restore_service`、`reader_v2_dependencies`（各使用 7+ DAO）。
- **初始化順序限制：** `NetworkService.init()` 需在首次 HTTP 請求前呼叫（`main.dart` 啟動時完成）；`AppDatabase` 為 lazy singleton，首次存取時才開檔。

## 4. Key Flows

1. **閱讀進度儲存：** `ReaderV2ProgressController` → `BookDao.updateProgress()` → `books` table。軌跡欄位：`chapterIndex`、`charOffset`、`visualOffsetPx`、`readerAnchorJson`。
2. **章節內容快取：** 下載完成 → `ReaderChapterContentDao.saveContent()` → `reader_chapter_contents` table。content key 為 `sha1(origin\nbookUrl\nchapterUrl)`。
3. **網路請求：** `HttpClient` → `NetworkService.dio` → `LenientCookieManager`（讀寫 `PersistCookieJar`）→ `AppInterceptor`（header 補全 + 手動 redirect）→ server。
4. **書源探索/搜尋：** `BookSourceDao._partQuery()` 只讀輕量欄位（排除 rule JSON 欄位），避免反序列化全部規則。

## 5. Change Entry Points & Routes

| 修改標的 | 起始檔案 | 需注意 |
|---|---|---|
| 新增 table/DAO | `app_tables.dart` → `app_database.dart` → `drift_dev build` | 同步更新 2 處 table list + 2 處 dao list |
| 修改 model 欄位 | `models/` → 對應 `app_tables.dart` table → 重跑 build | Drift 型別轉換器集中在 `app_tables.dart` 檔頭 |
| 修改網路行為 | `network/interceptors/` → `network_service.dart` | interceptor 加入順序：cookie 先、app 後 |
| 修改快取策略 | `storage/app_cache.dart` + `database/dao/cache_dao.dart` | 兩層並存；`CacheDao` 存 DB KV，`AppCache` 存檔案 |
| 搬遷 DB 路徑 | `app_database.dart:getDatabasePath()` + `_openConnection()` | 需確保舊 DB 搬遷邏輯 |

## 6. Known Risks

- **DB schema migration 只有 `from < 2` 一個分支：** 若未來新增 v3，`onUpgrade` 現有結構不會補建 v1→v2 的索引（已存在則 `IF NOT EXISTS` 安全，但語意混淆）。
- **`_trimCache()` 未真正限制容量：** `AppCache._trimCache()` 只以檔案數量裁切，完全不檢查總大小（`maxSize = 50MB` 形同虛設）。
- **`LenientCookieManager` 對畸形 cookie 的寬容度：** `ignoreInvalidCookies` 預設 `false`，若某書源送出無法解析的 cookie 會 throw，使該請求整個失敗。
- **`AppDatabase` 全域 singleton + `forTesting` 建構子：** 測試若未隔離實例，跨測試共用 DB 連線可能造成狀態汙染。

## 7. Do Not Do

- 不要在 `models/` 中加入資料庫查詢邏輯或網路呼叫；model 必須保持純資料。
- 不要在 DAO 外部手寫 SQL 繞過 Drift 查詢建構器（除非 `ReaderChapterContentDao` 已有先例的複雜查詢）。
- 不要直接實例化 `Dio`；一律透過 `NetworkService().dio` 取得統一實例，確保 interceptor 生效。
- 不要在 DAO 中直接使用 `AppDatabase._instance`；應透過建構子注入（便於測試替換）。
