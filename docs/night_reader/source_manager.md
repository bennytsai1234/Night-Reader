# 書源管理

## 目前職責

書源的完整生命週期管理：新增、刪除、匯入（JSON/URL）、匯出、有效性驗證、訂閱更新、偵錯。修改書源管理 UI、書源驗證流程、訂閱更新行為，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/features/source_manager/` | 書源管理 UI（列表頁、偵錯頁、訂閱頁等）、SourceManagerProvider |
| `lib/features/source_manager/views/` | SourceManagerPage、SourceDebugPage、SourceLoginPage、SourceSubscriptionPage 等 |
| `lib/features/source_manager/widgets/` | 書源列表項目、驗證狀態元件 |
| `lib/core/services/book_source_service.dart` | 書源 DAO facade（CRUD 操作）|
| `lib/core/services/check_source_service.dart` | 書源有效性驗證（搜尋+抓取全流程）|
| `lib/core/services/source_check_isolate.dart` | 在獨立 isolate 中執行書源驗證（避免主執行緒阻塞）|
| `lib/core/services/source_check_js_worker_probe.dart` | JS worker 可用性探測 |
| `lib/core/services/source_update_service.dart` | 章節增量更新（已有書籍的更新）|
| `lib/core/services/source_switch_service.dart` | 為已有書籍替換書源 |
| `lib/core/services/source_debug_service.dart` | 規則測試工具（用於偵錯頁）|
| `lib/core/services/source_subscription_service.dart` | 書源訂閱（從 URL 定期同步）|
| `lib/core/database/dao/book_source_dao.dart` | 書源 DAO |
| `lib/core/models/book_source.dart` + `source/` | BookSource 模型（規則、設定、Legado 相容序列化）|

測試：`test/features/source_manager/`、`test/core/services/check_source_service_test.dart`、`test/core/engine/web_book_service_test.dart`

## 依賴與影響

- **上游**：規則引擎（WebBookService 執行書源規則）、瀏覽器驗證（HeadlessWebViewService 供 JS 重型書源使用）
- **下游**：書架（書源切換影響書籍資料）、搜尋與探索（直接呼叫書源搜尋和探索）、下載與快取（DownloadService 呼叫書源抓取章節）
- **事件**：發出 `sourceChanged`、`checkSource`、`checkSourceDone`（見 [event_bus](event_bus.md)）
- **外部**：網路（HTTP 請求到真實書源網站）、WebView（JS 重型書源）

## 關鍵流程

**書源驗證流程**：
```
SourceManagerPage → CheckSourceService.check()
  → source_check_isolate（在 isolate 中執行）
    → WebBookService.searchBookAwait（搜尋測試）
    → WebBookService.getBookInfoAwait（書籍資訊測試）
    → WebBookService.getChapterListAwait（目錄測試）
    → WebBookService.getContentAwait（章節內容測試）
  → 回傳結果，發 checkSource / checkSourceDone 事件
```

**書源匯入流程**：
```
使用者輸入 JSON 字串 / URL
  → SourceManagerPage → BookSourceService.importSources()
    → 解析 JSON → BookSource.fromJson()
    → BookSourceDao.insertOrUpdate()
  → 發 sourceChanged 事件
```

**訂閱更新流程**：
```
SourceSubscriptionPage → SourceSubscriptionService
  → 定期 fetch URL → 解析 BookSource 列表
  → BookSourceDao.insertOrUpdate（增量更新）
```

## 常見修改入口

- 書源列表 UI → `lib/features/source_manager/views/source_manager_page.dart`
- 偵錯功能 → `lib/features/source_manager/views/source_debug_page.dart` + `lib/core/services/source_debug_service.dart`
- 驗證邏輯 → `lib/core/services/check_source_service.dart`
- 書源模型/序列化 → `lib/core/models/source/book_source_rules.dart`、`book_source_serialization.dart`
- 訂閱更新 → `lib/core/services/source_subscription_service.dart`（若存在）

## 修改路線

- 修改 BookSource 模型（新增欄位）：需同步 `book_source_base.dart`、`book_source_serialization.dart`（Legado JSON 相容）、`BookSourceDao`（DB schema + migration）
- 修改驗證流程：`check_source_service.dart` 與 `source_check_isolate.dart` 須同步（isolate 跨越序列化邊界）
- 修改書源 CRUD：BookSourceDao 變更會影響 SourceManagerProvider 和 BookSourceService

## Known Risks

- 書源驗證在 isolate 中執行，傳遞的物件必須可序列化，複雜物件（如 WebView handle）無法傳入 isolate
- 書源 JSON 格式需維持 Legado 相容性；修改 `fromJson`/`toJson` 可能破壞使用者匯入的書源
- `concurrentRate` 限制書源的並發請求數；CheckSourceService 並行驗證多書源時要注意全局連線池
- JS 重型書源需要 HeadlessWebViewService 預熱；冷啟動驗證可能超時
- SourceLoginPage（互動式登入）尚未完整實作（見瀏覽器驗證模組）

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要在主執行緒上執行完整的書源驗證（改用 isolate）
- 不要修改 BookSource JSON 序列化以破壞 Legado 書源匯入相容性
- 不要為尚未實作的互動式 WebView 登入新增 UI 流程（直接回報錯誤即可）
