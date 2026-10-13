# 交接（2026-10-13 16:50）

## 更新功能（`feat/update-features`，2026-10-13 18:00 更新）

使用者已說「合併」，正在做合併前審查的修正，修完就推上 `main`。

### 分支內容（都已推上 `origin/feat/update-features`）

- App 更新：自動檢查開關、「稍後提醒」一週、Wi-Fi 下自動下載更新、「關於夜讀 → 更新紀錄」。
- 書架：開 App 自動檢查（`autoRefresh`）、單本「自動檢查更新」開關、檢查後封面角標 `+N`（淺綠）／`!`（淺紅，只在手動下拉），5 秒淡出。
- 書架書自動整本下載與新章節（ADR 0008）、介面不放解釋性文案（ADR 0009）、中文 `CHANGELOG.md` 當 Release 說明並由 hook／CI 強制（ADR 0010）、移除書源訂閱（schema 5）、開關重做為 40×24。
- 已併入最新 `main`（`6d379f7`）；主線新增 ADR 0007，所以這條分支的 ADR 改號為 0008–0010。

### 合併前審查（Codex，7 項全部核對屬實）

報告：`C:\Users\045650\AppData\Local\Temp\night-reader-codex-out\review-report.md`（暫存，收尾時移到資源回收筒）。

| 發現 | 內容 | 狀態 |
|---|---|---|
| 1 高 | 正文下載用舊章節快照 upsert 章節表，把插章後的序號寫回舊值 | `review/fixa` 已提交 `bb74f71`，未合併 |
| 3 中 | `_keepAfterRun` 丟掉 `hasNewChapters`，失敗後不會立即重試 | `review/fixa` 已提交 `63c680b`，未合併 |
| 4 中 | 自動與手動檢查同一本書沒共用進行中請求 | `review/fixb` 已提交 `232c4ce`，未合併 |
| 2 中 | 匯入沒有目錄的書不會自動下載 | `review/fixb` 改到一半、未提交（`download_service.dart`、`bookshelf_exchange_service.dart`、新測試 `shelf_download_missing_toc_test.dart` 等） |
| 7 低 | 殘留「輸入書架 JSON 網址」「輸入分組名稱」「輸入封面 URL」等用途 placeholder | `review/fixb` 尚未開始 |
| 5 中 | 跨版本 APK 下載互刪檔案 | 已修並合併（`review/fixc`） |
| 6 中 | 清空「未發布」可繞過說明檢查 | 已修並合併（`review/fixc`） |

worktree：`Night-Reader-updates`（`feat/update-features`）、`Night-Reader-fixa`、`Night-Reader-fixb`、`Night-Reader-fixc`（都在 `D:/Migrated/Desktop/Folder/product/`）。

### 下一步

1. `review/fixa`：看兩個 commit 與測試，確認發現 1 的根因修法（閱讀器 `reader_v2_chapter_repository.dart` 的同一路徑也要涵蓋），全套 `flutter test` 通過後合進 `feat/update-features`。
2. `review/fixb`：把發現 2 做完（空目錄先取得目錄再排下載，取得失敗要套 ADR 0008 的重試節奏）、做發現 7（全專案掃 `hintText` 一類的「輸入 XX」），各自 commit，全套測試後合併。兩條修正分支都動到 `download_service.dart`，合併時注意衝突。
3. `feat/update-features` 全套測試、推上分支；再 `git push origin feat/update-features:main`（快轉）。pre-push 會檢查 `CHANGELOG.md` 的「未發布」。推完看一次 GitHub Actions 的 Android Release 有開始建置即可。
4. 收尾：刪除 `feat/update-features`、`review/fixa|fixb|fixc` 分支（本機與遠端）與四個 worktree；把 `C:\Users\045650\AppData\Local\Temp\night-reader-codex-out`、`night-reader-render` 移到資源回收筒。

### 注意

- 子代理 fixc 自行決定：換到另一版 APK 下載時會先取消舊版下載；使用者沒表示意見，回報時提一下即可。
- 渲染畫面給使用者看的方法：寫臨時 widget 測試用 `matchesGoldenFile(Uri.file(絕對路徑))` 加 `--update-goldens` 輸出 PNG，字型用 `FontLoader` 把 `C:/Windows/Fonts/msjh.ttc` 載成 `Roboto`、`D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf` 載成 `MaterialIcons`；測試檔放 repo 外（`night-reader-render/src`），跑時才複製進 `test/_render/`，跑完刪掉，避免 pre-push 跑到。
- 使用者這次定下的介面偏好已寫進 ADR 0009 與 DESIGN.md：不放解釋性文案、開關不撐點擊範圍、依賴的開關直接隱藏。

---

以下是閱讀器「第 2 項」的交接（另一個對話）。

## 正在做

沒有進行中的修改。閱讀器審查的後續工作已全部合併進 `main`（`25ed851`），分支 `fix/reader-review-followups` 已刪除；`git log 4e16616..25ed851` 是那一批（ADR 0005–0007 也在裡面）。

下一個題目是審查清單的「第 2 項」：正文段落要不要各自成一層圖層（`RenderCachedBlock.isRepaintBoundary`），也就是光柵化效能那一項。使用者還沒決定要不要動手，下一個對話先做研究。

上一個對話已經跟使用者更正過：先前說「光柵化 P99 從 118.5ms 降到約 21ms」說過頭了，同一份紀錄裡後來把兩種做法放在一起比的那次量測，兩者都在 120ms 上下，沒有重現這個改善（細節見下方「第 2 項的事實」）。

## 下一步

1. **先研究並向使用者說明「光柵化是在幹嘛的」**，這是使用者指定的下一個題目。用使用者聽得懂的話講清楚，並對到這個 App：
   - Flutter 一幀從 build、layout、paint 到 raster（光柵化）各在做什麼，哪些在 UI 執行緒、哪些在 raster 執行緒；Impeller 下光柵化實際做了什麼（把圖層樹轉成 GPU 指令、文字字形、裁切與 saveLayer 的代價）。
   - 圖層（layer）、`RepaintBoundary`／`isRepaintBoundary` 和光柵化成本的關係：每個段落一層、捲動時只是位移圖層，跟全部畫在同一層、捲動時重畫，各自省了什麼、花了什麼。
   - `FrameTiming` 的 build／raster 時間怎麼讀；120Hz 下一幀只有 8.3ms，UI 和 raster 兩條執行緒各自要在期限內完成。
   - 為什麼模擬器上的光柵化數字不能代表手機（同一台模擬器上最簡單的 `ListView` 光柵化 P99 也有 56.5ms）。
   以 Flutter 官方文件與 engine 原始碼等一手資料為準，可以照 `research` 技能把結果寫成 repo 內的文件；講完再進入第 2 步。
2. 研究講完後，把下面的事實講清楚，再請使用者決定（見「等使用者決定」）。
3. 使用者若決定追查：照 `diagnosing-bugs` 先在本機 widget 測試重現「`isRepaintBoundary => false` 時朗讀中正文變空白」，找到根因再談要不要改。實機與模擬器量測是使用者的工作（`AGENTS.md`），agent 不跑、也不要求。
4. 不論結論，`lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart:126` 的註解寫「不建立獨立 repaint boundary」，和 `cached_block_widget.dart:201` 的 `true` 相反，要依結論改掉其中一邊。

### 第 2 項的事實（repo 現況查不到，來自 git 歷史）

- 9 月的量測帳本已從 repo 刪除，用 `git show fcc72d4^:docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md` 讀。
- P4 迭代 1b（09-13，模擬器 120Hz，seed 9132026）：改成 `false`，光柵化 P99 118.5ms → 21ms；同條件重跑（1d）是 40.5ms。
- P4V B3（09-14，seed 9145004）：`false` 時朗讀畫面的固定截圖只剩頁首與標題，正文一片空白，可重現；判定為視覺錯誤並退回 `true`（帳本約 505–560 行）。空白的根因沒有查。
- P4V B5（09-14，seed 9145006，`scroll_slow` 配對）：`true` 與 `false` 的光柵化 P99 是 119.5ms 對 120.5ms，沒有改善。所以 1b 的大幅改善沒有被後來的配對量測重現。
- P4 5b：同一台模擬器上，最簡單的分段 `ListView` 對照組光柵化 P99 也有 56.5ms，模擬器本身的光柵化天花板就很高。
- Skia 與 Impeller 的 A/B 沒有差別；從未生效的 `EnableImpeller=false` 已在 `86b1cd3` 刪除。
- 以上全在 2026-09-18 重建 Hybrid B 繪製與幾何（`1cf0d5d`）之前量的，現在的繪製路徑已不同。
- 量測工具（`integration_test/`、`tool/run_android_reader_workload.ps1` 等）在 `5e33d93`、`5804eb7` 刪除，要用時從 `5e33d93^` 取回；量測產物（`artifacts/`）從未進 repo。

## 等使用者決定

- 第 2 項要不要重開。建議：維持 `true` 結案，只修正 `hybrid_scroll_view.dart` 的過時註解。理由：改善只在模擬器量到一次、配對量測沒重現、模擬器光柵化天花板本身就高、繪製架構之後又重建過；`false` 還有沒查清楚的空白問題。使用者自己在手機上感覺捲動掉幀時，再以那個現象重新開題。

## 注意

- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- 本機另有 `Night-Reader-upd-*` 幾個 worktree（`feat/update-*` 分支），是其他對話的工作，不要動。

## 建議技能

- `research`：查一手資料說明光柵化，結果寫成 repo 內的文件。
- `diagnosing-bugs`：重現並追查 `false` 時的空白正文。
- `domain-modeling`：結論若是刻意保留 `true`，照它判斷要不要寫成 ADR。
- `codex-review`：之後若改了程式，合併前審整條分支。
