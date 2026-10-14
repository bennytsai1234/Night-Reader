# 交接（2026-10-14 16:30）

## 最近合併

**#58**（`merge/reader-open-and-accent`）：開書改成「一張紙接到底」，加上強調色、五種新風格與摺角書頁風格卡。

- 開書、跳章與重新排版時正文區蓋一張閱讀底色的紙（`LoadingVeil`，`lib/features/reader_v2/hybrid/overlay/loading_veil.dart`），紙一蓋上就淡入正文骨架，正文排好後紙淡出；首次開書時頁首頁尾跟著淡入。原本排版超過 500ms 才出骨架，使用者 2026-10-14 改成一律先出骨架（`AppMotion.readerSkeletonDelay` 已移除）；淡出途中再蓋上時骨架不歸零，免得閃一下。
- 強調色（「外觀與主題 → 強調色」，跟隨主題＋十二色）、五種新風格（胭脂、藕荷、黃卷、琥珀、霜夜）、風格卡改成兩列五張的摺角書頁（窄螢幕加大字級時名稱換行）。
- 合併流程補了一步（AGENTS.md、ADR 0014）：合併前先把最新的 `main` 併進分支，讓 CI 在合併後的狀態重跑。

**#57**（`feat/ios-parse-worker-transitions`）：Release 另附未簽章 iOS IPA（ADR 0003 已改寫，`flutter_js` 在 iOS 用 JavaScriptCore）；不帶 JS 的搜尋頁與目錄在常駐背景 isolate 解析（`ParseWorker`）；封面 Hero 全部移除，全 App 換頁共用一種「換頁動畫」，在「外觀與主題」四選一（預設上浮），返回一律是開啟倒著播（ADR 0012、GLOSSARY）。`prototype/book-transitions` 是換頁動畫的網頁原型，留在遠端、不合併。

#55：下載任務的範圍改記起訖章節網址，開跑時才對照目錄換算（ADR 0008）。#54：目錄換新時依章節網址保留進度與已下載章節、付費章節顯示鎖頭、換源繁簡互通。

## 配色不再有對比度規則（使用者 2026-10-14 決定）

DESIGN.md 原本規定每個風格深淺都要過對比度門檻，測試會擋、強調色會自動調明暗。使用者說這不是他定的規則，配色手調個大概就好，不行他會回報。已拿掉 DESIGN.md 那段、`app_style_test` 的門檻測試與 `AppStyle.paletteFor` 的自動調明暗（強調色直接用 `AppAccent` 的淺色／深色兩個值）。還留著：`StylePalette.onPrimary`（主色上的字取紙白或墨色中看得清楚的那個）、`AppTint` 顏料色的兩個對比測試、骨架淡色的深淺測試；使用者若也要拿掉再處理。不要照審查工具的對比度意見調色。

## 接下來

- **#58 審查留下、要先問使用者的兩項**（都是原本的行為，不是 #58 造成的）：
  - 跳章時「取得正文」那段沒有蓋紙：runtime 先等正文（`reader_v2_runtime.dart` 的 `_loadContentAt`），拿到後畫面才排版、才蓋紙（`_restoreCore` 裡 `_setRestoreCompleted(false)`）。網路慢時舊正文停在畫面上、沒有提示。保留舊正文是刻意的：等待中還能捲動，一捲就取消跳章（`hybrid_reader_interaction_test` 的「dragging while a jump is loading cancels the jump cleanly」）。若要改，在跳章操作被接收時就蓋紙，用操作識別判斷完成、取消、失敗，取消時掀開紙；要把「有可恢復的穩定正文」（`hasStableWorld`）和「正在顯示載入紙」分成兩個狀態，不能直接把 `hasStableWorld` 設成 false（`a4f96c1` 刻意把進行中的操作和 lifecycle 分開）。等待中還能不能捲動取消，先問使用者。
  - 跳章與改字號重新排版時，頁首頁尾資訊列不會收掉再淡入：外框 `ReaderV2PageShell` 看的是 `runtime.state.hasStableWorld`，畫面自己的「正文排好了沒」（`_initialRestoreCompleted`）沒傳到外框。改法是跟上一項一起，讓正文、紙和資訊列共用同一個「正在載入」狀態；改字號時資訊列留著也合理，要改哪些情境先問使用者。
- **拆 `HybridReaderScreen`**（約 2550 行；使用者已同意做）：#58 已合併，可以開分支了。先照 `codebase-design` 定切分點，候選是選字與反白（`_selection*`）、版面世代與還原（`_epoch*`、`_restore*`）、排版管線與磁碟快取（`_pump*`、`metricsDiskCache`、`planDiskCache`、`_measurementStore`）；逐段搬，每段跑全套測試。
- 帶 JS 的書源若在手機上仍會卡，就照 `docs/research/source-engine-off-main-isolate.md` 的阻礙一到五（WebView、資料庫連線、Cookie 擁有者、全域狀態、16 個呼叫端）評估整套搬進背景。
- 閱讀器審查清單的「第 2 項」已結案（維持 `RenderCachedBlock.isRepaintBoundary => true`），使用者之後若在手機上覺得捲動掉幀再重新開題。

## 注意

- 這台機器常有好幾個 session 同時開在同一個資料夾，切分支會影響別人；自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被別人佔用時換一個 port，不要結束別人的程序。
- 新開的 worktree 跑 `flutter test` 時，sqlite3 的 native asset 下載可能被公司網路改掉、雜湊不符而失敗；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就會直接用快取。
- Codex 審查的暫存 `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時會擋掉 Codex 最後一次連線，`codex exec` 因此回非零，但報告通常已經寫好；先看報告檔再判斷要不要重跑。
- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。Windows 上 Python 寫檔要給 `newline='\n'`，不然會寫成 CRLF。
- 要看 Flutter 實際畫出來的頁面：寫一個暫時的 widget 測試，把頁面包在 `RepaintBoundary` 裡，`pumpAndSettle` 後在 `tester.runAsync` 裡 `toImage` 存成 PNG 到 repo 外，看完刪掉測試檔。測試字型會把字畫成方塊，看的是形狀與顏色。`AppearanceSettingsPage` 用到的 `SettingsProvider` 會在畫完後丟 path_provider 的 `MissingPluginException`，不影響圖片。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
