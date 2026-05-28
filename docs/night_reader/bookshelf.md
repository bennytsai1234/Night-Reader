# 書架與書籍

## 現有責任

書架的顯示與管理、書籍加入/移除/分組、書籍詳情（封面、簡介、章節列表、換書源）、閱讀紀錄、書籤（跨書架）、全域替換規則管理。是使用者與書籍資料互動的主要入口。

## 範圍

- **書架**：`lib/features/bookshelf/`（書架頁、provider）
- **書籍詳情**：`lib/features/book_detail/`（詳情頁、provider、換封面）
- **書籤**：`lib/features/bookmark/`（書籤頁、provider）
- **閱讀紀錄**：`lib/features/read_record/`
- **全域替換規則**：`lib/features/replace_rule/replace_rule_provider.dart`
- **書籍模型**：`lib/core/models/book.dart`、`book/`、`bookmark.dart`、`read_record.dart`、`replace_rule.dart`、`book_group.dart`、`book_progress.dart`
- **書籍服務**：`lib/core/services/book_storage_service.dart`、`bookshelf_state_tracker.dart`、`bookshelf_exchange_service.dart`、`book_cover_storage_service.dart`
- **DAO**：`lib/core/database/dao/book_dao.dart`、`bookmark_dao.dart`、`read_record_dao.dart`、`replace_rule_dao.dart`、`book_group_dao.dart`
- **測試**：`test/features/bookshelf/`、`test/features/book_detail/`、`test/core/models/book_mgmt_test.dart`

## 依賴與下游影響

- 上游：**應用基礎設施**（資料庫 DAO）、**書源管理**（書籍綁定書源）、**規則引擎**（換書源時需重新抓取書籍資訊）
- 下游：**閱讀器 V2**（從書架打開書籍）、**搜尋與探索**（加入書架操作）、**下載與快取**（離線下載依賴書架書籍）
- `bookshelf_state_tracker` 透過 event_bus 廣播書籍狀態變更，影響多個畫面

## 關鍵流程

1. 加入書架：書籍詳情頁 → `BookshelfExchangeService.addBook()` → 寫入資料庫 → event_bus 通知 → 書架重新載入
2. 換書源：書籍詳情頁選擇新書源 → 呼叫規則引擎重取書籍資訊 → 更新資料庫
3. 書籤管理：閱讀器 V2 新增書籤 → 寫入 `bookmark_dao` → 書籤頁顯示

## 變更入口

- 書架 UI 或排序：`bookshelf_page.dart`、`bookshelf_provider.dart`
- 書籍資料結構（欄位增減）：`lib/core/models/book/`、`book_dao.dart`
- 書架 exchange 邏輯（加入、移除）：`bookshelf_exchange_service.dart`

## 變更路由

- 書籍模型加欄位：`book_base.dart` → `book_serialization.dart` → `book_dao.dart`（schema 遷移）→ 確認 `bookshelf_exchange_service_test.dart`
- 書架狀態變更：`bookshelf_state_tracker.dart` → 確認 event_bus 訂閱者（閱讀器 V2、下載）未因此出現問題

## 已知風險

- `bookshelf_state_tracker` 的 event_bus 廣播是非同步的；若多個畫面同時監聽，競態條件較難追蹤
- 書籍封面快取存放在本地檔案系統，清除快取後封面需要重新下載
- 換書源後章節對應關係（閱讀進度）可能失效

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在書架層直接執行網路抓取；換書源的網路操作應透過規則引擎的 web_book_service
- 不要在書架模組管理章節快取；那是下載與快取模組的責任
