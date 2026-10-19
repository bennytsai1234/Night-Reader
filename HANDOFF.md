# 交接（2026-10-19）

只寫從 repo 與 GitHub 查不到的事（ADR 0014）。合併了什麼看 PR 頁面與 `git log`，發版紀錄看 `gh run list --workflow android-release.yml`。

## 還沒合併的工作

三條分支都已推上、全套測試通過，等使用者說合併。照 AGENTS.md 併成一個以 `beta` 為目標的 PR；三條都改了 `CHANGELOG.md` 的「未發布」，前兩條也改了 `HANDOFF.md`，併的時候要整理成一份。

- **`fix/reader-jump-fails-during-open`**：開書第一次還沒排好就跳到取不到的章節（包括跳章途中又改排版、沿用同一個目標），不再整頁顯示「閱讀內容暫時無法顯示」，改回開書的位置重新開並提示原因，已改好的排版保留（`ReaderV2Runtime._finishContentUnavailable`）。要去的就是開書那一章時照舊標成無法顯示。
- **`t3/reader-background-isolation`**：書源 isolate（ADR 0028）。所有書源工作都由 `BookSourceService` 送進常駐的書源 isolate（閱讀器抓正文、下載、搜尋、檢查更新、換源、換封面、發現與發現分類、匯出、書源除錯），規則在書與章節複本上改的欄位跑完抄回呼叫端；資料庫兩邊連同一個 drift isolate，Cookie 檔、限流與 WebView 由主 isolate 擁有、書源 isolate 經代理使用，記憶體快取兩邊互相轉送寫入。`flutter_js` fork 升到 `nightreader.4`（`fetchPolyfillSource`）。已併入 `beta` 最新的提交。
- **`t3/fix-shelf-transition-jumps`（PR #79）**：開 App 時整個畫面先是骨架，簡繁字典在背景解析，書架一次換場（ADR 0025）。Codex 已審、發現已修。PR 是在 ADR 0027 之前開的，目標還是 `main`，合併時要改成 `beta`（或併進上面那一個 PR）。

## 等使用者決定或動手

- **下載與檢查更新還要不要等動畫播完**（2026-10-19）：ADR 0018 讓背景下載與書架檢查更新在動畫或捲動時停著（`MotionGate`），理由是書源解析在主執行緒。解析搬走後，主 isolate 每一章只剩收正文與寫入。放寬的話一直捲時下載也會繼續；還沒問使用者，也還沒量過剩下的工作多重。`bookshelf_update_mixin.dart` 與 `reader_v2_menu_entrance.dart` 的註解還寫著舊理由，決定後一起改。

- **網站曝光（#60，只能使用者做，已告知；先擱著）**：使用者說（2026-10-15）自己的閱讀體驗滿意之前不推薦給別人，所以不用提醒。到時要做的是：用自己的 Google 帳號在 Search Console 驗證網站、提交 `https://bennytsai1234.github.io/Night-Reader/sitemap.xml`；到 Legado 社群、PTT、V2EX、Reddit 等發文帶連結。
- **手機上的 profile 版**：使用者手機上還裝著 `com.inkpage.reader.debug`（裡面是還原進去的書架），要不要移除由使用者決定。
- **測試日誌**：`download_service_test` 有一批「`_dio` 尚未初始化」的下載失敗日誌（測試沒準備網路層，只檢查排隊與範圍），不是警告；使用者要的話再補假的網路層。

## 使用者定下、還沒寫進其他文件的事

- **搜尋相關度排序先不改**（2026-10-15）：使用者聽完「完全相符／部分相符／其他結果，段內照書源數」的說明後覺得可能不用改。曾提出但沒做的三個選項：部分相符裡書名命中排在只有作者命中前、同書源數時書名開頭命中優先、空白分開的多個詞各自比對。使用者回報某個關鍵字排序不對時再從這裡挑。
- **搜尋結果不顯示書源名稱**（2026-10-15）：使用者說沒人在乎來源；書名旁的「N 個書源」數量標記保留，使用者沒說要拿掉。
- **別再用使用者的手機量測**（2026-10-14）。之後若使用者同意再量，做法：profile 建置用一個不提交的入口（`main()` 之後把 `developer.Service.getInfo()` 的 ws 位址寫進 `getExternalStorageDirectory()`），因為 vivo 會把 logcat 裡的 VM service 位址遮掉，intent 參數在這個 App 也不生效；電腦用 `vm_service` 連上後 `setFlag('profiler','true')`，收 `Flutter.Frame` 事件與 `getCpuSamples`，把 UI isolate 連續忙碌超過 8 ms 的區段依堆疊歸類。profile 版和正式版並存；vivo 用 adb 安裝會跳確認頁（勾「已瞭解」再按「繼續安裝」）。
- **配色沒有對比度規則**（2026-10-14）：配色手調個大概就好，不行使用者會回報；不要照審查工具的對比度意見調色。還留著 `StylePalette.onPrimary`（主色上的字取紙白或墨色中看得清楚的那個）、`AppTint` 顏料色的兩個對比測試、骨架淡色的深淺測試；使用者若也要拿掉再處理。

## 接下來

- **已知小差距，沒修**：開書時前一章取不到，開書後方先排好的範圍照夾限前的位置算，少了約一百像素，掀紙後會補上。
- 閱讀器審查清單的「第 2 項」已結案（維持 `RenderCachedBlock.isRepaintBoundary => true`），使用者若在手機上覺得捲動掉幀再重新開題。

## 注意

- 這台機器常有好幾個 session 同時開在同一個資料夾，切分支會影響別人；自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被別人佔用時換一個 port，不要結束別人的程序。
- Claude Code 的子代理用 `isolation: "worktree"` 開的工作樹放在主資料夾的 `.claude/worktrees/` 底下，起點是主資料夾目前的 commit（通常是 `beta`），不是呼叫端所在的分支；要疊在別的分支上，合併時得自己解衝突，或先把那條分支併進 `beta`。
- 2026-10-19 起日常改動進 `beta`（ADR 0027）。這之前 clone 的資料夾（包括另一台電腦上的）還停在 `main`，開工前先 `git fetch`、`git switch beta`；在 `main` 上提交再推上去，Android Release 會直接失敗。
- 新開的 worktree 跑 `flutter test` 時，sqlite3 的 native asset 下載可能被公司網路改掉、雜湊不符而失敗；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就會直接用快取。
- Codex 審查的暫存 `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時會擋掉 Codex 最後一次連線，`codex exec` 因此回非零，但報告通常已經寫好；先看報告檔再判斷要不要重跑。
- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。Windows 上 Python 寫檔要給 `newline='\n'`，不然會寫成 CRLF。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 用 `test/screens` 拍閱讀器時，換行結果快取在系統暫存區的 `hybrid_plans`、`hybrid_metrics`（截圖環境把 App 的資料夾指到 `%TEMP%`），換行快取只認 App 版本號；改了換行規則或排版程式卻沒換版號時，先把這兩個資料夾移到垃圾桶再拍，不然拍到的是舊的換行。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- `SwipeActions` 的拖動辨識沒有讀 `MediaQuery` 的觸控門檻（用 Flutter 預設 18，`PageView` 用裝置的，Android 約 8），放進可左右滑動的容器會搶輸搶贏不定；書架因此拿掉了左滑（DESIGN.md）。
