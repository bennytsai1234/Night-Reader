# 交接：書源分類與保留

2026-11-09。分支 `feat/source-kinds`，worktree `D:\Migrated\Desktop\Folder\product\nr-source-kinds`。還在談，沒寫程式。談完開工時把 `beta` 上 `PLAN.md` 的「書源分類與保留」那條搬走，並刪掉本檔。

## 談定的

- 整理書源時讓使用者選要留下哪幾類，例如漫畫源、有聲書源，留給之後的漫畫閱讀器（`feat/images-comics`）與有聲書播放器（`feat/audiobook-player`）用。

## 現況（查過的）

- 判斷：`BookSourceLogic.nonNovelExclusionReason`（`lib/core/models/source/book_source_logic.dart`）。類型（`bookSourceType`）不是 0 文字，或名稱、分組、註解、網址、搜尋網址帶 `_nonNovelSourceMarkers` 裡的字樣（有聲、聽書、廣播劇、podcast、漫畫、manga、comic、動漫、番劇、視頻、影視、電影、m3u8…）就算非小說。字樣只有一張表，不分是漫畫還是有聲。刻意不看發現網址，因為番茄、起點的分類有「动漫衍生」「影视剧本」。
- 匯入：`source_manager_provider.dart` 解析時把非小說書源停用、關掉發現、加「非小說」分組，照樣匯入；匯入完提示「其中 N 個已標記為不支援並停用」。
- 刪除：書源管理的「刪除非小說源」（`source_manager_dialogs.dart`，提示「影音、漫畫、RSS 等非小說源」）全部刪掉；書源校驗把它們標成 `nonNovel`、`cleanupCandidate: true`，所以清理失效書源也會刪（`source_check_isolate.dart` 的 `_resolvePreflightStatus`）。
- 類型值（`lib/core/constant/source_type.dart`、Legado 3.0）：0 文字、1 音訊、2 圖片、3 文件。

## 等使用者決定的（下一步從這裡接）

一次問一件，依序：

1. 分幾類：例如小說、漫畫、有聲、其他（影視、RSS）。類型欄位認得出的直接用；只靠字樣判斷的（類型寫 0 但名稱帶漫畫）要不要也歸進去，誤判了使用者怎麼改。
2. 在哪裡選要留下哪幾類：匯入預覽裡勾、書源管理「刪除非小說源」改成依類別刪，或兩處都有。
3. 留下來、還不能用的類別在書源管理怎麼呈現，校驗與清理失效書源要不要跳過它們。
4. 和漫畫、有聲書播放器的接點：那兩條開工後，對應的類別從「留著」變成「可搜尋、可閱讀／收聽」。
