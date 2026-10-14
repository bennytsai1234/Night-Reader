# 交接（2026-10-14 11:30）

## 正在做

`merge/2026-10-14` 把四條分支合成一個 PR（流程改動 #52 併進來後關閉）：測試版改手動發布與 PR 流程（ADR 0014）、檢查更新共用（`fix/update-check-gaps`）、實機回饋與解析引擎（`fix/ui-polish-followup`）、搜尋體驗（`feat/search-experience`），以及合併前 Codex 審查找到的問題修正。合併後要手動發一版測試版：`gh workflow run android-release.yml --ref main -f channel=beta`。

合併前審查找到、這次沒修的兩件事（都不是這批改動帶進來的），等使用者決定要不要開題：

- 目錄重新編號（書源在中間插入或刪除章節）後，閱讀進度仍停在舊的章節序號，重開書會落在錯的章節；要改成依章節網址重新對應進度。
- 搜尋把繁簡兩種寫法併成一張卡後，書籍詳情的換源面板只用原文書名找，列不出另一種寫法的來源。

書源解析搬離主 isolate 的研究在 `docs/research/source-engine-off-main-isolate.md`：兩個效能熱點已修，搜尋頁被整頁蓋住時也會暫停送出書源；搬 isolate 先不做，等實機上還會不會卡再決定。

閱讀器審查清單的「第 2 項」（正文段落要不要各自成一層圖層）已結案：維持 `RenderCachedBlock.isRepaintBoundary => true`。使用者之後若在手機上感覺捲動掉幀，再以那個現象重新開題。

## 注意

- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
