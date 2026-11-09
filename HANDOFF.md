# 交接：漫畫（A）與本地漫畫（D）

2026-11-09。分支 `feat/images-comics`，worktree `D:\Migrated\Desktop\Folder\product\Night-Reader-images-comics`。還在談，沒寫程式。談完開工時把 `beta` 上 `PLAN.md` 的「漫畫」那條搬走，並刪掉本檔。

## 談定的

- 「圖片與漫畫」拆成兩條，兩個都做：
  - **漫畫**（本分支）：另做一個專給圖片的閱讀器，和 Reader V2 分開（使用者：本質不同）。先做漫畫書源（搜尋、加書架、下載、閱讀）。
  - **本地漫畫**（D：CBZ、ZIP、圖片資料夾）：A 做完再加，共用同一個閱讀器；藍圖現在就一起談。
  - **文字書的插圖**（B）：網路書正文 `<img>` 與 EPUB 插圖，預設關閉。另一個對話在談，這裡不碰。
- `beta` 的 `PLAN.md` 已拆成「漫畫」與「文字書的插圖」兩條。

## 現況（查過的）

- 圖片書源（Legado `bookSourceType` 2）：書源校驗（`lib/core/services/source_check_isolate.dart`）標成「不提供純文字正文」；`BookSourceLogic.nonNovelExclusionReason`（`lib/core/models/source/book_source_logic.dart`）因類型或名稱、分組、網址帶漫畫字樣而排除，不能搜尋與閱讀。
- Legado 對照（`D:\Migrated\Desktop\Folder\product\legado`）：
  - 漫畫閱讀器 `ui/book/manga/ReadMangaActivity.kt`，邏輯在 `model/ReadManga.kt`，和文字閱讀器分開；預設直向捲動，可切左右翻頁，有縮放、自動捲動、濾色、電子紙模式等選單項（`res/menu/book_manga.xml`）。
  - 正文規則回傳一串 `<img>`，圖片網址可帶請求標頭；`ContentRule.imageDecode` 是圖片 bytes 的解密 JS；`imageStyle` 管圖片大小。
  - 快取：`BookHelp` 依 `AppConfig.imageRetainNum` 往前保留幾章、依 `preDownloadNum` 往後預下載幾章，其餘清掉。

## 藍圖草稿（已給使用者看，還沒逐項談定）

1. 書源：放行圖片書源；名稱帶漫畫的文字書源改認成漫畫。
2. 正文 → 圖片清單：在書源 isolate 解析與解密。
3. 圖片抓取與快取：網路 isolate 帶標頭抓圖、存磁碟、限流。
4. 「圖從哪裡來」介面：給第 N 章回一串圖；網路書源與本地漫畫檔是兩種實作（D 的接點）。
5. 漫畫閱讀器：直向捲動或左右翻頁、縮放、閱讀選單、目錄；進度記章、第幾張、捲動位置。閱讀方式與轉場畫候選圖給使用者選。
6. 書架、下載、同步：書卡與詳情沿用；下載、同步的進度格式要認得漫畫。
7. D：匯入 CBZ／ZIP／資料夾，用原檔指紋，走「同步本地書」（ADR 0039）。

## 等使用者決定的（下一步從這裡接）

**漫畫要不要照書架自動下載（ADR 0008：整本、不限網路、沒有開關）？** 漫畫一章常幾 MB，整部可能幾 GB（量級是估的，沒量）。

- A1（建議）：只預載前後幾章、讀過的舊章自動清（同 Legado），離線靠手動選範圍下載；要寫 ADR 說明漫畫不適用 ADR 0008。
- A2：照 ADR 0008 整本下載。
- A3：整本下載但只在 Wi-Fi（在 ADR 0008 上開例外）。

已提議：從源倉庫抓兩三個漫畫書源實量一章大小再決定，使用者還沒回。之後依序談藍圖其他項，一次問一件。
