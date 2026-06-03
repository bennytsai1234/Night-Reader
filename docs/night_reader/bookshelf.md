# 書架與書籍

## 目前職責

書架顯示（書籍列表、分組、排序）、書籍詳情（元資料、封面修改、書源切換）、閱讀紀錄、書籤管理、全域替換規則。修改書架 UI、書籍資料結構、閱讀進度，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/features/bookshelf/` | 書架主頁（BookshelfPage）、BookshelfProvider |
| `lib/features/book_detail/` | 書籍詳情頁（BookDetailPage）、ChangeCoverProvider、書源選擇 |
| `lib/features/replace_rule/` | 全域替換規則 UI（ReplaceRulePage）、ReplaceRuleProvider |
| `lib/core/services/book_storage_service.dart` | 書籍元資料持久化（Book 的 CRUD） |
| `lib/core/services/book_cover_storage_service.dart` | 封面圖片下載與快取 |
| `lib/core/services/bookshelf_state_tracker.dart` | 書架同步狀態追蹤（記錄哪些書籍的章節資料是最新的） |
| `lib/core/services/replace_rule.dart` | 替換規則業務邏輯 |
| `lib/core/database/dao/book_dao.dart` | Book DAO |
| `lib/core/database/dao/bookmark_dao.dart` | Bookmark DAO |
| `lib/core/database/dao/read_record_dao.dart` | ReadRecord DAO |
| `lib/core/database/dao/replace_rule_dao.dart` | ReplaceRule DAO |
| `lib/core/models/book.dart` + `book/` | Book 模型（BookBase、BookContent、BookExtensions、BookLogic、BookSerialization） |
| `lib/core/models/bookmark.dart` | Bookmark 模型 |
| `lib/core/models/read_record.dart` | ReadRecord 模型 |
| `lib/core/models/replace_rule.dart` | ReplaceRule 模型 |

測試：`test/features/bookshelf/`、`test/features/book_detail/`、`test/core/models/book_mgmt_test.dart`、`test/core/database/read_record_dao_test.dart`、`test/core/database/replace_rule_dao_test.dart`

## 依賴與影響

- **上游**：書源管理（SourceSwitchService 切換書籍書源）、下載與快取（取得章節列表與內容）
- **下游**：閱讀器 V2（讀取書籍和閱讀進度；回寫進度）
- **事件**：監聽 `upBookshelf`、`bookshelfRefreshStart`、`bookshelfRefreshEnd`；發出 `upBookshelf`（見 [event_bus](event_bus.md)）
- **注意**：BookGroup（書架分組）目前用 DB 持久化，但 UI 尚不完整

## 關鍵流程

**書架載入流程**：
```
BookshelfPage → BookshelfProvider
  → BookDao.getAll()（Drift stream，自動 reactive）
  → BookshelfPage 重建列表
```

**書籍詳情流程**：
```
BookshelfPage → BookDetailPage
  → BookDetailProvider（載入書籍元資料、章節列表）
    → BookStorageService（書籍資料）
    → BookSourceService（書源驗證狀態）
  → 使用者操作：更新書源（SourceSwitchService）、換封面（ChangeCoverProvider）、加書籤
```

**閱讀進度回寫**：
```
閱讀器 V2（runtime/）→ 讀取/寫入 ReadRecord
  → ReadRecordDao.upsert()
  → 發 upBookshelf 事件 → BookshelfProvider 更新書架顯示
```

## 常見修改入口

- 書架 UI（排序、分組、顯示樣式）→ `lib/features/bookshelf/bookshelf_page.dart`
- 書架狀態管理 → `lib/features/bookshelf/provider/bookshelf_provider.dart`
- 書籍詳情 → `lib/features/book_detail/`
- 全域替換規則 → `lib/features/replace_rule/` + `lib/core/services/replace_rule.dart`
- Book 模型欄位 → `lib/core/models/book/book_base.dart`（新增欄位需同步 DB schema）
- 換源面板 UI（共用詳情頁與閱讀器）→ `lib/features/book_detail/widgets/change_source_sheet.dart`（`onSelectSource` 回呼參數化：不傳 = 詳情頁 `changeSource`；傳入 = 閱讀器走 `SourceSwitchService`）

## 修改路線

- 新增 Book 模型欄位：需同步 `BookBase`、`BookSerialization`（fromJson/toJson）、`Books` Drift table（schema migration）、`BookDao`
- 修改書架排序/分組：BookshelfProvider 控制查詢邏輯，Drift stream 自動 reactive
- 修改替換規則：ReplaceRule 同時被 Reader V2（content 層）和 replace_rule feature 使用；修改後確認閱讀器側行為

## Known Risks

- Book 模型的 `fromJson`/`toJson` 需維持 Legado 格式相容性（備份還原時使用）
- BookDao 的 Drift stream 會在書架有任何變更時觸發全量重建；書架很大時有效能問題
- 閱讀進度（ReadRecord）與 Chapter 的同步依賴 `durChapterIndex`；書源切換後 index 可能失效
- BookshelfStateTracker 的同步邏輯尚未完整文件化
- 換源儲存為「每源獨立」：一本書始終只有一個當前來源（origin + bookUrl）。換源 = 把這本書遷移到另一個當前源；`SourceSwitchService.persistSwitch` 在遷移到不同 `bookUrl` 時刪除舊 row + 舊章節，避免書架出現重複項。此模型不因「閱讀器新增換源入口」而改變（2026-06：詳情頁與閱讀器共用同一遷移語意，閱讀器側透過 `SourceSwitchService.resolveSwitch`/`persistSwitch` + pushReplacement 重載；詳情頁側維持 `BookDetailProvider.changeSource`）。

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要在 BookshelfProvider 中做網路請求（只能讀取 DB）
- 不要直接修改 Book 的持久化欄位而不同步 DB schema migration
- 不要把書架分組（BookGroup）相關的 UI 做到不可逆（功能尚未完整）
