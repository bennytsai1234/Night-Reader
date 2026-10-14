# 交接（2026-10-14 09:40）

## 正在做

三條分支已推上 GitHub，等使用者說合併：

- `fix/ui-polish-followup`：照實機看 beta 的意見拿掉大標題、捲動收起分頁列與書架開書的封面放大（ADR 0011、0012），以及開書等閱讀設定載入完才排版。
- `feat/search-experience`：使用者開始捲動後搜尋結果順序不再變動；離開搜尋時清掉暫存的搜尋結果。
- `fix/update-check-gaps`：書籍詳情的「檢查更新」與書架共用進行中的檢查（新的 `BookUpdateService`），書源刪掉的章節會從目錄移除；拿掉最後兩個說明欄位用途的 placeholder。

閱讀器審查清單的「第 2 項」（正文段落要不要各自成一層圖層）已結案：維持 `RenderCachedBlock.isRepaintBoundary => true`，只修正了 `hybrid_scroll_view.dart` 的過時註解。使用者之後若在手機上感覺捲動掉幀，再以那個現象重新開題。

## 注意

- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- `fix/ui-polish-followup` 與 `feat/search-experience` 還沒寫 `CHANGELOG.md`，合併前要補，否則推 `main` 時 pre-push 與 CI 的更新說明檢查會擋下。`fix/ui-polish-followup` 也要改掉「未發布」裡已經拿掉的大標題、分頁列自動讓出畫面、封面放大翻開成閱讀頁那幾條。
