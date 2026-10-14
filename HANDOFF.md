# 交接（2026-10-14 11:30）

## 正在做

`fix/progress-remap-and-variant-sources`（等使用者說合併）：#53 合併前審查留下的兩件事已修好——

- 檢查更新與「整本補下載」整份換新目錄時，閱讀進度依目前那一章的網址對到新序號；那一章不在新目錄裡時照標題（繁簡視為相同）、章號與比例估計。
- 換源面板用書名的繁簡兩種寫法搜，比對書名與作者時繁簡視為相同；換源對章節時標題繁簡不同也算同一章。

還沒處理：閱讀器開著時剛好跑完檢查更新、目錄被重新編號，閱讀器手上仍是舊目錄，之後寫回的進度是舊序號。

書源解析搬離主 isolate 的研究在 `docs/research/source-engine-off-main-isolate.md`：兩個效能熱點已修，搜尋頁被整頁蓋住時也會暫停送出書源；搬 isolate 先不做，等實機上還會不會卡再決定。

閱讀器審查清單的「第 2 項」（正文段落要不要各自成一層圖層）已結案：維持 `RenderCachedBlock.isRepaintBoundary => true`。使用者之後若在手機上感覺捲動掉幀，再以那個現象重新開題。

## 注意

- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
