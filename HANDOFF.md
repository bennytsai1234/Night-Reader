# 交接（2026-10-13 19:40）

## 正在做

沒有進行中的分支。研究文件 `docs/research/flutter-rasterization.md` 已併進 `main`（原分支 `docs/rasterization-research` 已刪除），內容是：Flutter 一幀的流程、Impeller 光柵化做什麼、`isRepaintBoundary` 對兩條執行緒的影響、`FrameTiming` 怎麼讀、模擬器數字為什麼不準，以及 `false` 時正文空白的三個推測。全部以 Flutter 3.47.0 的官方文件與原始碼為據，附行號連結。文件只有 agent 粗看過摘要與模擬器段落，**還沒向使用者講解**；使用者要回家看文件再討論。

題目是審查清單的「第 2 項」：正文段落要不要各自成一層圖層（`RenderCachedBlock.isRepaintBoundary`），也就是光柵化效能那一項。使用者還沒決定要不要動手。

先前說「光柵化 P99 從 118.5ms 降到約 21ms」說過頭了，已跟使用者更正：同一份紀錄裡後來把兩種做法放在一起比的那次量測，兩者都在 120ms 上下，沒有重現這個改善（細節見下方「第 2 項的事實」）。

### 研究文件的重點（細節與來源看文件本身）

- Android 上 Impeller 每幀從頭畫整個畫面，沒有 raster cache，也沒有局部重繪；所以 `true`／`false` 在 raster 執行緒上要畫的文字量一樣，`true` 省的主要是 UI 執行緒（捲動時段落不重跑 `paint`）。從原始碼推論，切換不該讓光柵化時間差好幾倍，跟配對量測沒差別一致；118.5→21ms 那次找不到對應機制。
- 引擎看到模擬器特徵就不用 Vulkan，模擬器一律走 Impeller OpenGL ES，多數手機走 Vulkan；過去在模擬器量的全是另一套後端。
- 過去「Skia 與 Impeller A/B 沒差別」用的關閉設定從未生效，夜讀其實從沒量過 Skia。
- `false` 時空白的三個推測（都未驗證，文件 6.3 節）：`paint` 出錯時 `save`／`clipRect` 沒還原，殘留的裁切範圍蓋掉後面的段落（只在 debug 建置）；`true` 沿用舊圖層，把段落當下沒內容的狀態藏起來；重畫請求在往上層節點傳的時候被吞掉。
- 文件「沒查到定論、或文件與程式碼不一致的地方」一節列了官方文件與程式碼互相矛盾、或沒查到定論的地方。

## 下一步

1. **等使用者看完 `docs/research/flutter-rasterization.md` 回來討論**，回答使用者的問題；使用者要口頭講解時，照文件用白話講，並對到夜讀。
2. 講完後，把下面的事實講清楚，再請使用者決定（見「等使用者決定」）。
3. 使用者若決定追查：照 `diagnosing-bugs` 先在本機 widget 測試重現「`isRepaintBoundary => false` 時朗讀中正文變空白」，找到根因再談要不要改。實機與模擬器量測是使用者的工作（`AGENTS.md`），agent 不跑、也不要求。
4. 已完成（2026-10-13，`4e59082`）：`hybrid_scroll_view.dart` 的過時註解改成說明 `RenderCachedBlock` 自己就是 repaint boundary，程式維持 `true`。

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
- 更新功能（`feat/update-features`）已在 2026-10-13 合併進 `main`。公司電腦（帳號 `045650`）上還留著當時的殘留，在那台電腦接手時收掉：`D:/Migrated/Desktop/Folder/product/` 下的 `Night-Reader-updates`、`Night-Reader-fixa`、`Night-Reader-fixb`、`Night-Reader-fixc` 四個 worktree 與本機分支 `feat/update-features`、`review/fixa|fixb|fixc`（內容都已在 `main` 重做或合併，直接刪），以及暫存 `C:\Users\045650\AppData\Local\Temp\night-reader-codex-out`、`night-reader-render`（移到資源回收筒）。

## 建議技能

- `diagnosing-bugs`：重現並追查 `false` 時的空白正文。
- `domain-modeling`：結論若是刻意保留 `true`，照它判斷要不要寫成 ADR。
- `codex-review`：之後若改了程式，合併前審整條分支。
