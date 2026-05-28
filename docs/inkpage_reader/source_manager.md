# 書源管理

## 現有責任

書源的完整生命週期管理：新增、刪除、編輯、分組、啟用/停用、網路/本地匯入、匯出、書源有效性檢查、書源訂閱（自動更新）與書源偵錯。是使用者控制內容來源的核心功能。

## 範圍

- **UI**：`lib/features/source_manager/`（書源列表、編輯器、偵錯頁、分組管理、訂閱頁、探索書源頁）
- **Provider**：`lib/features/source_manager/source_manager_provider.dart`
- **書源服務**：`lib/core/services/book_source_service.dart`（CRUD 操作）
- **書源切換**：`lib/core/services/source_switch_service.dart`
- **書源訂閱**：`lib/core/services/source_update_service.dart`、`lib/core/models/source_subscription.dart`
- **書源驗證/檢查**：`lib/core/services/check_source_service.dart`、`source_verification_service.dart`、`source_validation_context.dart`、`source_debug_service.dart`
- **JS Worker 探針**：`lib/core/services/source_check_js_worker_probe.dart`
- **資料模型**：`lib/core/models/book_source.dart`、`book_source_part.dart`、`source/`
- **DAO**：`lib/core/database/dao/book_source_dao.dart`、`source_subscription_dao.dart`
- **測試**：`test/features/source_manager/`、`test/core/services/book_source_service_test.dart`、`check_source_service_test.dart`

## 依賴與下游影響

- 上游：**規則引擎**（執行書源規則）、**瀏覽器驗證**（需要 WebView 驗證的書源）、**應用基礎設施**（資料庫 DAO、HTTP client）
- 下游：**搜尋與探索**（使用已啟用書源）、**書架與書籍**（書源停用影響已加書架書籍）、**下載與快取**（章節抓取依賴書源）
- 書源規則格式變更會波及所有依賴書源抓取的功能

## 關鍵流程

1. 網路匯入書源：使用者輸入 URL → `book_source_service.importFromUrl()` → 解析 JSON → 寫入資料庫
2. 書源有效性檢查：`check_source_service.checkSource()` → 呼叫規則引擎執行搜尋/章節流程 → 回報通過/失敗
3. 訂閱更新：`source_update_service.updateSubscriptions()` → 從訂閱 URL 拉取最新書源 JSON → 比對版本 → 更新資料庫
4. 書源偵錯：`source_debug_service` → 逐步執行書源規則 → 顯示每個步驟的中間結果

## 變更入口

- 書源列表 UI：`source_manager_page.dart`、`source_manager_provider.dart`
- 書源驗證邏輯：`source_verification_service.dart`、`check_source_service.dart`
- 書源資料模型（欄位增減）：`lib/core/models/source/`、`book_source_dao.dart`

## 變更路由

- 新增書源欄位：`book_source_base.dart` → `book_source_serialization.dart` → `book_source_dao.dart`（schema 遷移）→ 更新相關解析器
- 修改匯入邏輯：`book_source_service.dart` → `test/core/services/book_source_service_test.dart`
- 修改驗證流程：`source_verification_service.dart` → `test/core/services/source_verification_service_test.dart`

## 已知風險

- 書源 JSON 格式沒有版本管理，新欄位需要向後相容的 null-safe 處理
- `check_source_service` 並行執行多個書源檢查，大量書源時可能消耗大量記憶體與網路資源
- 書源訂閱自動更新可能覆蓋使用者手動修改的書源
- 書源驗證涉及真實網路請求，測試難以在 CI 環境中穩定重現

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在書源管理層直接執行 HTML 解析；應透過規則引擎
- 不要讓書源管理快取閱讀器的章節內容；那是下載與快取模組的責任
