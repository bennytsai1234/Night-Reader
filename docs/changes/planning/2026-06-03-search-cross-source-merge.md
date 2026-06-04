# 搜尋結果:同名跨源合併顯示

> 狀態:**設計計畫草稿(尚未實作)**。經設計訪談逐題確認。

## 任務類型 / 紀律等級
Feature(改搜尋核心演算法 + 呈現層),**T2**——跨呈現/模型層、有漸進式時序行為、需完整測試,配 TDD。

## 確認的之前
搜尋引擎只合併「同一書源內」的重複(`search_model.dart:40` `_isSameSourceDuplicate` 在 `a.origin != b.origin` 時回 false),導致同一本小說在多個書源各佔一張卡;`SearchBook.origins`/`addOrigin`/`sourceLabels`、「書源數」排序、書源 filter 全是死碼(origins 恆為 1)。

## 確認的之後
同名同作者的書跨源**合併成一張卡**(僅呈現層;書架儲存仍每源獨立),顯示「N 個書源」badge;既有的書源數排序、`sourceLabels`、書源 filter 自然生效。

## 設計決策(訪談結果)
1. **顯示模型**:合併成一張卡(presentation-only;儲存每源獨立不變)。
2. **主來源(representative)**:群組內 `customOrder`(`originOrder`)最前、**優先有封面**者;無封面則退回最前者。決定卡片封面/最新章 + 點擊/加書架預設源。
3. **合併判定鍵**:`normalizeSearchText` 的書名 + 作者(全形→半形、去空白、小寫),與 `preciseSearch(checkAuthor)`、既有 `_isSameSourceDuplicate` 一致。
4. **作者缺失 = 書名唯一時也合併**(每次更新從頭重算,唯一性反映當下整個結果集):
   - 書名只對應 **1 個**作者 → 缺作者同名書**併入**該作者群組。
   - 書名**完全沒人**有作者 → 同名缺作者書**併成一張「作者不詳」卡**。
   - 書名有 **≥2 個**不同作者 → 缺作者同名書**退出、單獨成「作者不詳」卡**,不硬塞任一作者。
5. **互動**:複用既有換源(零新儲存);合併卡的 origins 為呈現用,不持久化候選源。

## 演算法(關鍵改變:由漸進併入改為重算式)
現行 `_mergeItems` 漸進併入既有聚合、從不回頭重算,無法支援「唯一性隨結果集變動」。改為:
- 新增 `_rawBooks: List<SearchBook>`,保存「每源、同源內已去重」的原始結果。
- 每個源回傳 → append 到 `_rawBooks` → **整個 `_searchBooks` 從頭重建**:
  1. 同源去重(沿用既有 bookUrl / 同名同作者)。
  2. 有作者的書按 `(正規化書名, 正規化作者)` 分組。
  3. 統計每個書名的相異作者數。
  4. 依決策 4 安置缺作者的書。
  5. 每組選 representative(決策 2)。
  6. 三級相關度排序(完全 > 包含 > 其他)+ 組內按 `origins.length` 降序。
- 結果集至多數百筆,整體重算 O(n),效能無虞。

## 邊界情況
| 情境 | 處理 |
|---|---|
| 作者缺失 | 決策 4 三分支 |
| 漸進更新分組變動 | 每次從頭重算,正確性優先;搜尋過程中卡片可能跳動/拆併,完成後即穩定(已接受) |
| 同名同作者實為不同書 | 仍會誤合一張,與既有換源判斷一致,可接受 |
| 精準搜尋 | 三級排序不變;完全匹配級內 `origins.length` 降序此時真正生效 |
| 書源 filter | `_sourceLabelsFor` 已支援一卡多標籤、filter 用 `any` → 自動相容 |
| 同源重複 | 既有 bookUrl / 同名同作者同源去重照舊,群組內同源只算一個 origin |

## 預期檔案範圍
- `lib/features/search/search_model.dart` — `_isSameSourceDuplicate`/`_mergeIntoList`/`_mergeItems`:重算式跨源合併 + representative 選擇(**主改**)
- `lib/core/models/search_book.dart` — representative 選擇 helper(欄位已齊)
- `lib/features/search/widgets/search_result_item.dart` — 「N 個書源」badge
- `test/` — 跨源合併、作者缺失三情況、唯一性轉換(唯一→多作者退出)、representative 選擇、漸進重算

## 驗證步驟
- `flutter test`(新增搜尋合併測試 + 既有 `search` 測試全綠)
- `flutter analyze` 通過
- 手動:多源搜熱門書 → 一張卡 + 「N 個書源」;搜缺作者書驗證三分支

## 回退路徑
`git revert`。純呈現/引擎邏輯,無資料遷移;書架儲存模型未動。

## atlas 影響
實作後更新:`search_model.dart:273-274` 註解(由「不合併跨源」改為「呈現層合併、儲存每源獨立」)、`docs/night_reader/search_explore.md` 描述。書架「每源獨立」儲存邊界不變,無跨模組決策衝突。

## 與另一份計畫的關係
與 `2026-06-03-reader-change-source-entry.md` **互相獨立、不同頁面**,可分開實作。本計畫的「合併卡 → 點擊進詳情頁複用換源」與該計畫的「閱讀器換源入口」共同構成完整的多書源體驗。
