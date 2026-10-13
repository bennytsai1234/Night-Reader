# 交接（2026-10-13 16:41）

## 正在做

沒有進行中的修改。閱讀器審查的後續工作已全部合併進 `main`（`25ed851`），分支 `fix/reader-review-followups` 已刪除；`git log 4e16616..25ed851` 是那一批（ADR 0005–0007 也在裡面）。

下一個題目是審查清單的「第 2 項」：正文段落要不要各自成一層圖層（`RenderCachedBlock.isRepaintBoundary`），也就是光柵化效能那一項。使用者要先討論「為什麼退回、要不要再試」，還沒決定要動手。

## 下一步

1. 先跟使用者把下面的事實講清楚，再請他決定（見「等使用者決定」）。注意：上一個對話跟使用者說過「光柵化 P99 從 118.5ms 降到約 21ms」，後來查到同一份紀錄裡的配對量測沒有重現這個改善，要主動更正。
2. 使用者若決定追查：照 `diagnosing-bugs` 先在本機 widget 測試重現「`isRepaintBoundary => false` 時朗讀中正文變空白」，找到根因再談要不要改。實機與模擬器量測是使用者的工作（`AGENTS.md`），agent 不跑、也不要求。
3. 不論結論，`lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart:126` 的註解寫「不建立獨立 repaint boundary」，和 `cached_block_widget.dart:201` 的 `true` 相反，要依結論改掉其中一邊。

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

- `diagnosing-bugs`：重現並追查 `false` 時的空白正文。
- `domain-modeling`：結論若是刻意保留 `true`，照它判斷要不要寫成 ADR。
- `codex-review`：之後若改了程式，合併前審整條分支。
