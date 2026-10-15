# 交接（2026-10-15）

只寫從 repo 與 GitHub 查不到的事（ADR 0014）。合併了什麼看 PR 頁面與 `git log`，發版紀錄看 `gh run list --workflow android-release.yml`。

## 進行中

- **`fix/reader-menu-layout`（已推上、未開 PR）**：閱讀選單墊底色、亮度條置中撐長、字號每步 0.5，加上整個 App 截圖掃描後使用者逐項同意的 17 項介面修整（面板開著時選單收起、正文上緣漸隱、朗讀面板卡片化、替換規則面板、書源管理卡片、空白頁按鈕等，細節見分支上 `fix(ui): polish pass…` 的 commit message），以及 `test/screens/` 的整個 App 截圖組。**已兩次併入 `feat/tts-sleep-timer`（最後到 `75f0079`）**：合併時開一個 PR 就好；定時分支之後若再有新提交，先併進這條再開 PR。worktree 在 repo 外的 `../Night-Reader-menu-layout`。
- **`feat/tts-sleep-timer`（已推上、未開 PR）**：朗讀面板的定時（關閉、15～90 分、自訂分鐘數；章末已依使用者要求拿掉；時間到暫停、暫停時倒數停、記住上次選擇），加上閱讀選單上方第 4 顆圓鈕「定時朗讀」（按下照記住的定時開始朗讀、定時關閉時用 30 分，念著時按下停止，鈕上顯示剩餘分鐘）。內容已併進 `fix/reader-menu-layout`，合併時隨那個 PR 一起進、之後刪掉這條分支。worktree 在 repo 外的 `../Night-Reader-tts-timer`。
- **`feat/launch-straight-to-shelf`（已推上、未開 PR）**：拿掉書月亮星星的開場畫面，系統啟動畫面只剩書架底色、跟著風格與深淺（Android 13 起下次開啟生效），第一幀就進書架骨架（ADR 0017）。使用者說合併時照 Git 流程開 PR。worktree 在 repo 外的 `../Night-Reader-launch`。
- **`fix/predictive-back-smoothing`（已推上、未開 PR）**：Android 手勢導覽慢慢返回時，系統送來的進度照 Flutter 觸控重新取樣的做法晚 38ms、逐格內插，不再一頓一頓。使用者說合併時照 Git 流程開 PR。worktree 在 repo 外的 `../Night-Reader-smooth-back`。
- **`fix/reader-open-no-jank`（已推上、未開 PR）**：動畫不和重工作疊在一起（ADR 0018）：開書、書籍詳情、書源管理、搜尋頁等進場動畫播完才載入，回書架等返回動畫播完才重排，載入時排版每幀上限 4ms、目錄分批讀，背景下載與書架檢查更新等「動作閘門」（`MotionGate`）放開才做下一段，主題暈開等重建那一幀畫完才開始。使用者說合併時照 Git 流程開 PR。worktree 在 repo 外的 `../Night-Reader-open-smooth`。從目錄跳章改成目錄與選單馬上收起、等收起與骨架淡入播完才載入（使用者定的設計）。
- **`t3code/smooth-tab-navigation`（已推上、未開 PR）**：點下方分頁直接換過去、不掠過中間分頁，播「外觀與主題 → 換頁動畫」選的那一種（往右像開新頁、往左像返回），手指滑動照舊跟手；「我的」離開後捲回頂端；點搜尋鈕進搜尋頁不再自動叫出鍵盤（使用者 2026-10-15 決定）。使用者說合併時照 Git 流程開 PR。worktree 在 `~/.t3/worktrees/Night-Reader/t3code-d384c4ee`。合併時注意：`fix/reader-open-no-jank` 把搜尋頁的自動聚焦改成進場動畫播完才 `requestFocus()`，跟這次的決定衝突，那一段要拿掉；`feat/launch-straight-to-shelf` 也改了 `main_page.dart`、`fix/predictive-back-smoothing` 也改了 `app_page_transition.dart`，可能要解衝突。
- **`t3code/layout-fractional-pixel-tweaks`（已推上、未開 PR）**：「外觀與排版」拿掉「更多排版」收合、全部直接列出；「版面」新增「左右對齊」開關（預設開），把湊不滿一個字格的空隙攤進字距，正文左右兩緣貼齊頁首頁尾（ADR 0019）。使用者確認頁首頁尾目前的位置是對的，不要動；邊距步進維持 2 px（使用者決定不改成 1／0.5 px）。和 `fix/reader-menu-layout` 都改了 `reader_v2_settings_sections.dart`，合併時要解衝突。worktree 在 `~/.t3/worktrees/Night-Reader/t3code-6836f851`。

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
