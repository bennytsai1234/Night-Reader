# 交接（2026-10-13 21:50）

## 正在做

沒有進行中的工作，也沒有開著的分支。

閱讀器審查清單的「第 2 項」（正文段落要不要各自成一層圖層）已結案：維持 `RenderCachedBlock.isRepaintBoundary => true`，只修正了 `hybrid_scroll_view.dart` 的過時註解。使用者之後若在手機上感覺捲動掉幀，再以那個現象重新開題。

## 注意

- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- 更新功能（`feat/update-features`）已在 2026-10-13 合併進 `main`。公司電腦（帳號 `045650`）上還留著當時的殘留，在那台電腦接手時收掉：`D:/Migrated/Desktop/Folder/product/` 下的 `Night-Reader-updates`、`Night-Reader-fixa`、`Night-Reader-fixb`、`Night-Reader-fixc` 四個 worktree 與本機分支 `feat/update-features`、`review/fixa|fixb|fixc`（內容都已在 `main` 重做或合併，直接刪），以及暫存 `C:\Users\045650\AppData\Local\Temp\night-reader-codex-out`、`night-reader-render`（移到資源回收筒）。
