# 資料庫與模型

## 職責

擁有 Drift (SQLite) 資料庫定義、所有 DAO、資料表結構、以及應用層的資料模型。這是整個 App 的資料層。

## 範圍

- `lib/core/database/app_database.dart` — Drift 資料庫定義（@DriftDatabase）
- `lib/core/database/app_database.g.dart` — Drift 生成程式碼
- `lib/core/database/dao/` — 資料存取物件（BookDao 等）
- `lib/core/database/tables/` — 資料表定義
- `lib/core/models/` — 所有資料模型
  - `book/` — 書籍、章節、書籤、閱讀進度
  - `source/` — 書源相關模型
  - `book_source.dart`、`chapter.dart`、`download_task.dart`、`replace_rule.dart`、`search_book.dart` 等

## 依賴與影響

- **上游**：基礎設施（DI、工具函式）
- **下游**：核心服務（所有服務都使用資料模型）、書架、書源管理、搜尋與探索、閱讀器
- **外部依賴**：drift、drift_flutter、sqlite3、path、path_provider、build_runner、drift_dev

## 關鍵流程

- 資料庫初始化：`AppDatabase` 在建構時開啟 SQLite 資料庫，提供 DAO 存取
- schema 變更：修改 `app_database.dart` 中的資料表定義 → 執行 `dart run build_runner build` → 生成 `.g.dart` → 更新 schema version
- 查詢：所有 DAO 方法回傳 `Future` 或 `Stream`，UI 層透過 Provider 訂閱

## 變更入口與路線

- **新增資料表**：在 `database/tables/` 定義 → 在 `app_database.dart` 加入 getter → 執行 build_runner
- **新增模型**：在 `models/` 建立新檔案 → 可能需要對應的資料表
- **修改查詢**：編輯對應的 DAO
- **Schema 遷移**：修改 `app_database.dart` 中的 `schemaVersion` 和 `onUpgrade`

## 已知風險

- `.g.dart` 生成檔案非常大（~500KB），必須跑 build_runner 才能更新
- schema 遷移若處理不當可能導致資料遺失
- 模型與資料表之間沒有強制的一致性檢查，需手動確保兩者同步
- Drift 的 Stream 查詢在資料變更時自動更新，可能導致 UI 意外重建

## 禁止事項

- 不要在模型中放入業務邏輯——模型只應是資料載體
- 不要手動修改 `.g.dart` 生成檔案
- 不要在 DAO 中直接操作 UI 狀態
