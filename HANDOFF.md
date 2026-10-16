# 交接（2026-10-16）

只寫從 repo 與 GitHub 查不到的事（ADR 0014）。合併了什麼看 PR 頁面與 `git log`，發版紀錄看 `gh run list --workflow android-release.yml`。

## 進行中

- **`t3/polish-loading-menu-covers`（做完，等使用者說合併）**：封面拿掉書脊線、檔案封面淡入（ADR 0021）；閱讀選單拿掉 #69 加的閱讀底色墊層、改回玻璃直接浮在正文上，上下與亮度條改成滑入＋淡入、錯開的進場。使用者否決過的選單做法：墊層改深一階、半透明暗幕（全畫面或只在選單區）。

## 等使用者決定或動手

- **網站曝光（#60，只能使用者做，已告知；先擱著）**：使用者說（2026-10-15）自己的閱讀體驗滿意之前不推薦給別人，所以不用提醒。到時要做的是：用自己的 Google 帳號在 Search Console 驗證網站、提交 `https://bennytsai1234.github.io/Night-Reader/sitemap.xml`；到 Legado 社群、PTT、V2EX、Reddit 等發文帶連結。
- **手機上的 profile 版**：使用者手機上還裝著 `com.inkpage.reader.debug`（裡面是還原進去的書架），要不要移除由使用者決定。
- **測試日誌**：`download_service_test` 有一批「`_dio` 尚未初始化」的下載失敗日誌（測試沒準備網路層，只檢查排隊與範圍），不是警告；使用者要的話再補假的網路層。

## 使用者定下、還沒寫進其他文件的事

- **閱讀器載入骨架沒做的一項**（2026-10-15）：骨架第一條照章節標題的字級與留白畫（從章首載入時正文不會往下跳）。使用者沒選也沒否決，之後要做再提。使用者強調別亂改既有行為（例如開書取不到正文時資訊列不畫）。
- **搜尋相關度排序先不改**（2026-10-15）：使用者聽完「完全相符／部分相符／其他結果，段內照書源數」的說明後覺得可能不用改。曾提出但沒做的三個選項：部分相符裡書名命中排在只有作者命中前、同書源數時書名開頭命中優先、空白分開的多個詞各自比對。使用者回報某個關鍵字排序不對時再從這裡挑。
- **搜尋結果不顯示書源名稱**（2026-10-15）：使用者說沒人在乎來源；書名旁的「N 個書源」數量標記保留，使用者沒說要拿掉。
- **別再用使用者的手機量測**（2026-10-14）。之後若使用者同意再量，做法：profile 建置用一個不提交的入口（`main()` 之後把 `developer.Service.getInfo()` 的 ws 位址寫進 `getExternalStorageDirectory()`），因為 vivo 會把 logcat 裡的 VM service 位址遮掉，intent 參數在這個 App 也不生效；電腦用 `vm_service` 連上後 `setFlag('profiler','true')`，收 `Flutter.Frame` 事件與 `getCpuSamples`，把 UI isolate 連續忙碌超過 8 ms 的區段依堆疊歸類。profile 版和正式版並存；vivo 用 adb 安裝會跳確認頁（勾「已瞭解」再按「繼續安裝」）。
- **配色沒有對比度規則**（2026-10-14）：配色手調個大概就好，不行使用者會回報；不要照審查工具的對比度意見調色。還留著 `StylePalette.onPrimary`（主色上的字取紙白或墨色中看得清楚的那個）、`AppTint` 顏料色的兩個對比測試、骨架淡色的深淺測試；使用者若也要拿掉再處理。

## 接下來

- **下一次的研究題目：書源引擎搬進背景 isolate**（使用者 2026-10-15 排定）。照 ADR 0018，帶 JS 的書源在主執行緒一口氣解析，是剩下唯一會把動畫卡掉、又切不開的工作：閱讀時背景下載、書架檢查更新時的流光、開書抓沒下載過的章節都會碰到。之前研究過很久沒做成，起點是 `docs/research/source-engine-off-main-isolate.md` 的阻礙一到五（WebView 只能在主 isolate、資料庫多 isolate 共用連線、Cookie 單一擁有者、16 個呼叫端）。開工前先跟使用者確認範圍。
- 閱讀器審查清單的「第 2 項」已結案（維持 `RenderCachedBlock.isRepaintBoundary => true`），使用者若在手機上覺得捲動掉幀再重新開題。

## 注意

- 這台機器常有好幾個 session 同時開在同一個資料夾，切分支會影響別人；自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被別人佔用時換一個 port，不要結束別人的程序。
- 新開的 worktree 跑 `flutter test` 時，sqlite3 的 native asset 下載可能被公司網路改掉、雜湊不符而失敗；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就會直接用快取。
- Codex 審查的暫存 `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時會擋掉 Codex 最後一次連線，`codex exec` 因此回非零，但報告通常已經寫好；先看報告檔再判斷要不要重跑。
- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。Windows 上 Python 寫檔要給 `newline='\n'`，不然會寫成 CRLF。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- `SwipeActions` 的拖動辨識沒有讀 `MediaQuery` 的觸控門檻（用 Flutter 預設 18，`PageView` 用裝置的，Android 約 8），放進可左右滑動的容器會搶輸搶贏不定；書架因此拿掉了左滑（DESIGN.md）。
