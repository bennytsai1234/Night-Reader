# 書架

## 職責

擁有書架主頁面和書籍詳情頁面。書架是使用者管理已收藏書籍的核心介面，書籍詳情則展示書籍資訊、章節列表和閱讀入口。

## 範圍

- `lib/features/bookshelf/bookshelf_page.dart` — 書架主頁（約 31KB，最大的頁面檔案）
- `lib/features/bookshelf/bookshelf_provider.dart` — 書架狀態 Provider
- `lib/features/bookshelf/provider/` — 書架子 Provider
- `lib/features/book_detail/` — 書籍詳情頁面
- `lib/features/book_detail/change_cover_provider.dart` — 更換封面 Provider

## 依賴與影響

- **上游**：基礎設施、資料庫與模型（書籍、章節、閱讀進度）、核心服務（封面儲存、書籍儲存、書架狀態追蹤）
- **下游**：閱讀器（從書架進入閱讀）、搜尋與探索（搜尋結果可加入書架）
- **外部依賴**：cached_network_image（封面載入）

## 關鍵流程

- **書架展示**：BookshelfPage → BookshelfProvider → BookDao 查詢 → 顯示網格/列表
- **書籍詳情**：點擊書籍 → BookDetailPage → 載入章節列表 → 顯示書籍資訊
- **加入書架**：搜尋結果 / 探索頁面 → BookDao 寫入 → BookshelfStateTracker 通知 → 書架更新
- **更換封面**：ChangeCoverProvider → 圖片選擇 → BookCoverStorageService → 更新資料庫
- **刪除書籍**：BookshelfPage → 確認對話框 → BookDao 刪除 → 相關檔案清理

## 變更入口與路線

- **修改書架佈局**：編輯 `bookshelf_page.dart`（最大頁面檔案，注意不要讓它繼續膨脹）
- **修改書架狀態**：編輯 `bookshelf_provider.dart` 或 `provider/` 下的子 Provider
- **修改書籍詳情**：編輯 `book_detail/` 下的頁面
- **新增書架排序/分組**：在 `bookshelf_page.dart` 和 `bookshelf_provider.dart` 中協同修改
- **修改封面相關邏輯**：編輯 `change_cover_provider.dart`

## 已知風險

- `bookshelf_page.dart`（~31KB）過於龐大，應考慮拆分為子元件
- 書架狀態需與多個模組保持同步（搜尋、閱讀器、書源管理）
- BookshelfStateTracker 的通知機制可能導致不必要的 UI 重建

## 禁止事項

- 不要在書架頁面中直接發起網路請求——透過核心服務
- 不要在 `bookshelf_page.dart` 中繼續堆積邏輯——新功能應拆分為獨立元件
- 不要繞過 BookshelfStateTracker 直接更新書架狀態
