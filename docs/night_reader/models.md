# models

## Responsibility

- 全 App 的資料契約層：書籍、書源、章節、書籤、替換規則、搜尋結果、下載任務等資料模型，以及 JS 引擎可見的 `RuleDataInterface` 與 `BookExtensions`。
- 未來工作從這裡開始：新增/修改資料欄位、序列化格式、JS `java.*` 可操作的 book 欄位、書源規則資料結構。

## Scope

- `lib/core/models/` 根目錄：`book.dart`、`book_source.dart`、`base_source.dart`、`book_source_part.dart`、`chapter.dart`、`bookmark.dart`、`book_group.dart`、`book_progress.dart`、`book_chapter_review.dart`、`cache.dart`、`cookie.dart`、`dict_rule.dart`、`download_task.dart`、`http_tts.dart`、`read_record.dart`、`reader_chapter_content.dart`、`replace_rule.dart`、`rule_data_interface.dart`、`rule_sub.dart`、`search_book.dart`、`search_keyword.dart`、`server.dart`、`source_subscription.dart`、`txt_toc_rule.dart`。
- `lib/core/models/book/` — `book_base.dart`、`book_extensions.dart`（`BookExtensions`，JS 引擎操作的 Book 擴充方法）、`book_logic.dart`、`book_serialization.dart`。
- `lib/core/models/source/` — `book_source_base.dart`、`book_source_logic.dart`、`book_source_rules.dart`、`book_source_serialization.dart`、`explore_kind.dart`（`ExploreKind`，發現分類）。

## Dependencies & Impact

- 上游：被幾乎所有 core 子模組（engine、database、services）與所有 feature 引用。
- 下游影響：改模型欄位會引發全 App 編譯與 `database` schema/TypeConverter 連動，並影響 `services/backup` 的備份還原相容性、`engine/js` 的 `BookExtensions` 與序列化。
- 相依 `exception`、`utils`（弱相依）。

## Key Flows

- 書源抓取鏈中，`BookSource` 規則 → `AnalyzeRule` 以 `RuleDataInterface` 存取 book/source/chapter/page → `BookExtensions` 暴露給 JS。
- 備份匯出：`Book` / `BookSource` / `ReplaceRule` / `Bookmark` 經各自 serialization 序列化。

## Change Entry Points & Routes

- 新增欄位：改 `book/` 或 `source/` 對應檔 → 同步 `database/tables/app_tables.dart` 與該 DAO → 檢查 `services/backup_service.dart` 匯出/還原 → 檢查 `engine/js/js_extensions.dart` 是否需暴露。
- 序列化：`book_serialization.dart`、`book_source_serialization.dart`。
- JS 可見 book 操作：`book/book_extensions.dart` + `engine/js/js_extensions.dart`。

## Known Risks

- 模型欄位變更若忘記連動 `database` schema 會在升版崩潰。
- `BookExtensions` 是 JS 規則可直接呼叫的 API 表面，改動可能在書源腳本引發非預期行為。
- 序列化格式變更會破壞舊備份還原。

## Do Not Do

- 不要把業務邏輯寫進 model（邏輯放 `*_logic.dart` 或 services）。
- 不要在 model 直接依賴 `database` 或 `dio`（保持契約層單向被依賴）。
