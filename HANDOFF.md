# 交接（2026-10-14 16:10）

## 正在做

**PR #57**（分支 `feat/ios-parse-worker-transitions`，三條分支併成一條）等 CI 後合併：

- iOS：Release 另附未簽章 IPA（ADR 0003 已改寫）。`ios/` 用 `flutter create` 重建，三個 fork 補回 iOS，`flutter_js` 在 iOS 用 JavaScriptCore。
- 不帶 JS 的搜尋頁與目錄在常駐背景 isolate 解析（`ParseWorker`）；帶 JS 的仍在主 isolate（研究筆記的後續段落）。
- 封面 Hero 全部移除；全 App 換頁共用一種「換頁動畫」，在「外觀與主題」四選一（預設上浮），返回一律是開啟倒著播（ADR 0012、GLOSSARY）。

Codex 已審過整個 PR，3 項都屬實並在 `634f8bb` 修掉（JavaScriptCore 結果轉 Dart 值、原生回呼依 context 找回所屬引擎、移除只給測試看的計數器），摘要貼在 PR 留言。JavaScriptCore 在 Windows 測試機跑不了，這兩項修正只以程式路徑核對；PR 的 CI 不建 iOS，所以另在這條分支觸發了 `channel=test`（run 38532468822）確認 IPA 仍建得起來。

接手要做的：

1. `gh pr checks 57 --watch` 與 `gh run view 38532468822` 都通過後 `gh pr merge 57 --squash`（標題與說明取 PR 的）。
2. `git pull --ff-only` 更新本機 `main`；刪掉本機分支 `feat/ios-unsigned-ipa`、`perf/parse-worker`、`feat/book-transitions`、`feat/ios-parse-worker-transitions`，以及遠端的前三條（GitHub 只自動刪 PR 本身的分支）；移除 repo 外的 worktree `Night-Reader-ios`、`Night-Reader-worker`、`Night-Reader-motion`。
3. `prototype/book-transitions` 是換頁動畫的網頁原型（使用者看過影片後決定四種都做成設定），留在遠端、不合併。

## 接下來

- **拆 `HybridReaderScreen`**（2547 行；使用者已同意做）：等另一個 session 的 PR #58（`merge/reader-open-and-accent`，含 `fix/reader-open-continuity`，同樣改這個檔案）合併後再開分支，免得大量衝突。先照 `codebase-design` 定切分點，候選是選字與反白（`_selection*`）、版面世代與還原（`_epoch*`、`_restore*`）、排版管線與磁碟快取（`_pump*`、`metricsDiskCache`、`planDiskCache`、`_measurementStore`）；逐段搬，每段跑全套測試。#58 在 #57 之後合併時，`CHANGELOG.md`、主題與 `HANDOFF.md` 可能要解衝突。
- 帶 JS 的書源若在手機上仍會卡，就照研究筆記的阻礙一到五（WebView、資料庫連線、Cookie 擁有者、全域狀態、16 個呼叫端）評估整套搬進背景。
- 閱讀器審查清單的「第 2 項」已結案（維持 `RenderCachedBlock.isRepaintBoundary => true`），使用者之後若在手機上覺得捲動掉幀再重新開題。

## 注意

- 這台機器常有好幾個 session 同時開在同一個資料夾，切分支會影響別人；自己的工作開 repo 外的 worktree 做。Codex 審查的暫存 `%TEMP%\night-reader-codex-out` 也是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。
- 公司網路的 McAfee 有時會擋掉 Codex 最後一次連線，`codex exec` 因此回非零，但報告通常已經寫好；先看報告檔再判斷要不要重跑。
- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。Windows 上 Python 寫檔要給 `newline='\n'`，不然會寫成 CRLF。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
