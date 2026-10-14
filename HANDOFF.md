# 交接（2026-10-14 11:30）

## 正在做

`fix/progress-remap-and-variant-sources`（等使用者說合併）：#53 合併前審查留下的兩件事，加上討論後延伸的網站改版、故障與付費情況——

- 檢查更新與「整本補下載」換新目錄（`BookTocReplacer`）時，閱讀進度依目前那一章的網址對到新序號；那一章不在新目錄裡時照標題（繁簡視為相同）、章號與比例估計。
- 書源回空目錄時這次檢查算失敗，什麼都不寫。書源拿掉的章節裡，已下載或正在讀的留在目錄原位（使用者選了「合併保留」，不整份拒收新目錄，免得真的刪章時目錄永遠卡住）；新目錄有同名章節的不留（書源換網址）。
- 閱讀器開著時目錄被換新：存進度時依章節網址換算成資料庫目錄的序號，閱讀器自己仍照開書時的目錄。
- 書源標 `isVip` 且非 `isPay` 的章節不下載、抓到的內容不存；目錄要不要顯示鎖頭還沒定。
- 換源面板用書名的繁簡兩種寫法搜，比對書名與作者時繁簡視為相同；換源對章節時標題繁簡不同也算同一章。

書源解析搬離主 isolate 的研究在 `docs/research/source-engine-off-main-isolate.md`：兩個效能熱點已修，搜尋頁被整頁蓋住時也會暫停送出書源；搬 isolate 先不做，等實機上還會不會卡再決定。

閱讀器審查清單的「第 2 項」（正文段落要不要各自成一層圖層）已結案：維持 `RenderCachedBlock.isRepaintBoundary => true`。使用者之後若在手機上感覺捲動掉幀，再以那個現象重新開題。

## 注意

- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
