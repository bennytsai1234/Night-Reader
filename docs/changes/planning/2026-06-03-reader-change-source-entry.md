# 閱讀器換源入口(給書架的書)

> 狀態:**設計計畫草稿(尚未實作)**。經設計訪談逐題確認。

## 任務類型 / 紀律等級
Feature(Reader V2 新增換源入口 + 接線進度對齊換源),**T2**——改到 Reader V2(release 重點回歸區)、執行期換書換源重載、需完整測試,配 TDD。

## 確認的之前(現況實作)
換源功能(`ChangeSourceSheet` + `BookDetailChangeSourceProvider`,並行 `preciseSearch` 其他源)**只活在 `BookDetailPage`**。而詳情頁只有兩個入口,都在發現流程:
- `search/widgets/search_result_item.dart:210`(搜尋結果)
- `explore/widgets/explore_book_item.dart:186`(探索)

書架點書(`bookshelf_page.dart:553 onTap → _openBook :791`)**直接進 ReaderV2**;長按(`:548`)只進多選模式;閱讀器選單無換源(`reader_v2/` 內無 `換源`/`changeSource`)。
→ **結論**:書進書架後,換源完全搆不到(入口斷點)。另有 `SourceSwitchService`(含進度對齊 `resolveSwitch`/`autoResolveSwitch`)**無任何 UI 呼叫**,正為此預留卻未接線。

## 確認的之後
閱讀器底部選單新增「換源」,點開後彈出來源清單(並行搜其他源),選一個 → 換源並**自動對齊到目前章節** → 在新源重載續讀。換源結果持久化(重開仍是新源)。

## 設計決策(訪談結果)
1. **入口位置**:閱讀器底部選單加「換源」項(`reader_v2/features/menu/reader_v2_bottom_menu.dart`,與目錄/設定/替換規則同級)。
2. **操作流程**:手動選源清單 + 進度對齊。
   - 複用 `ChangeSourceSheet` 的清單 UI 與 `BookDetailChangeSourceProvider`(並行 `preciseSearch`、checkAuthor 開關、書源分組 filter、進度條)。
   - 選源後走 `SourceSwitchService.resolveSwitch(currentBook, candidate, 目前章節)` 做進度對齊與目標內容驗證(**非**詳情頁的 `changeSource`)。

## 流程
```
閱讀器底部選單「換源」
  → ChangeSourceSheet(複用):BookDetailChangeSourceProvider.startSearch() 並行搜其他源
  → 使用者點選一個源
      → SourceSwitchService.resolveSwitch:getBookInfo + getChapterList → migrateTo 對齊章節(clamp) → 驗證目標可讀
      → 持久化:更新 Book.origin/來源 + 新章節列表入 DB
  → 閱讀器以新來源在「對齊後章節」重載
```

## 邊界情況
| 情境 | 處理 |
|---|---|
| 找不到其他可用源 | 面板空狀態(既有 `sources.isEmpty` 已處理) |
| 章節結構不同(分卷/合併致對齊偏移) | `resolveSwitch` 以索引對齊 + clamp + 標題輔助;極端差一兩章,屬已知限制 |
| 目標章節內容不可讀 | `resolveSwitch` 丟 `StateError('目標章節內容不可讀')` → 提示失敗,停留原源 |
| 新源沒有目錄 | `StateError('新來源沒有可用目錄')` → 同上 |
| 舊源已下載快取 | 換源後屬不同來源,不沿用;新源內容按需重抓(失效屬預期) |
| 持久化 | 寫回 Book.origin + 新章節列表,重開仍是新源 |

## 預期檔案範圍
- `lib/features/reader_v2/features/menu/reader_v2_bottom_menu.dart` — 加「換源」選單項
- `lib/features/reader_v2/`(runtime/application 層)— 接收 `SourceSwitchResolution` → live 切換 book/源/章節列表並在對齊章節重載(**主要技術風險**)
- `lib/features/book_detail/widgets/change_source_sheet.dart` — item `onTap`/切換行為**參數化**,讓閱讀器情境改走 `SourceSwitchService`
- `lib/core/services/source_switch_service.dart` — 接線;可能需補「持久化遷移結果」的呼叫端
- `test/` — 換源對齊、目標不可讀、無其他源、章節數不同對齊、持久化

## 驗證步驟
- `flutter test`(新增換源對齊/失敗路徑測試;Reader V2 既有測試全綠)
- `flutter analyze` 通過
- 手動:書架開書 → 閱讀器換源 → 選源 → 在同一章續讀;測無其他源、目標不可讀的提示

## 回退路徑
`git revert`。換源失敗時停留原源、不破壞既有閱讀狀態為硬性要求。

## atlas 影響
實作後在 `docs/night_reader/reader_v2.md` 與 `docs/night_reader/bookshelf.md` 補記:閱讀器新增換源入口、`SourceSwitchService` 由閱讀器接線。書架「每源獨立」儲存不變(換源 = 把這本書遷移到另一個當前源,仍一本書一個當前源)。

## 與另一份計畫的關係
與 `2026-06-03-search-cross-source-merge.md` **互相獨立、不同頁面**,可分開實作。
