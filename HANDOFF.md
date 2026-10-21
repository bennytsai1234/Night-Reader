# 交接（2026-10-20）

只寫從 repo 與 GitHub 查不到的事（ADR 0014）。合併了什麼看 PR 頁面與 `git log`，發版紀錄看 `gh run list --workflow android-release.yml`。

## 等使用者決定或動手

- **公司那台電腦的殘留**：`prototype/glass-border` 原型使用者說丟掉（2026-10-20），遠端分支已刪；那台若還有 `%TEMP%\nr-border` worktree 與本機分支，直接刪。
- **視覺方向已否決，別再提**：使用者說版型與動畫已經很好（2026-10-20），只要小修。否決過的：三個大改方向（書卷：宋體標題與「正在讀」主卡；極簡現代：黑白清單；夜讀氛圍：深色金色），使用者不要大改；書名與標題改宋體（整個 App 統一用系統字型，混進宋體不如原本）；圖示方塊與進度線改墨色單色（「沒料」）；列高與網格間距重排（「沒意思」）。
- **網站曝光（#60，只能使用者做，已告知；先擱著）**：使用者說（2026-10-15）自己的閱讀體驗滿意之前不推薦給別人，所以不用提醒。到時要做的是：用自己的 Google 帳號在 Search Console 驗證網站、提交 `https://bennytsai1234.github.io/Night-Reader/sitemap.xml`；到 Legado 社群、PTT、V2EX、Reddit 等發文帶連結。
- **手機上的 profile 版**：使用者手機上還裝著 `com.inkpage.reader.debug`（裡面是還原進去的書架），要不要移除由使用者決定。

## 使用者定下、還沒寫進其他文件的事

- **搜尋相關度排序先不改**（2026-10-15）：使用者聽完「完全相符／部分相符／其他結果，段內照書源數」的說明後覺得可能不用改。曾提出但沒做的三個選項：部分相符裡書名命中排在只有作者命中前、同書源數時書名開頭命中優先、空白分開的多個詞各自比對。使用者回報某個關鍵字排序不對時再從這裡挑。
- **搜尋結果不顯示書源名稱**（2026-10-15）：使用者說沒人在乎來源；書名旁的「N 個書源」數量標記保留，使用者沒說要拿掉。
- **別再用使用者的手機量測**（2026-10-14）。之後若使用者同意再量，做法：profile 建置用一個不提交的入口（`main()` 之後把 `developer.Service.getInfo()` 的 ws 位址寫進 `getExternalStorageDirectory()`），因為 vivo 會把 logcat 裡的 VM service 位址遮掉，intent 參數在這個 App 也不生效；電腦用 `vm_service` 連上後 `setFlag('profiler','true')`，收 `Flutter.Frame` 事件與 `getCpuSamples`，把 UI isolate 連續忙碌超過 8 ms 的區段依堆疊歸類。profile 版和正式版並存；vivo 用 adb 安裝會跳確認頁（勾「已瞭解」再按「繼續安裝」）。
- **配色沒有對比度規則**（2026-10-14）：配色手調個大概就好，不行使用者會回報；不要照審查工具的對比度意見調色。頁面、卡片與框線的分層規則（`AppLayers`，2026-10-20）是使用者要的，不在此限。還留著 `StylePalette.onPrimary`（主色上的字取紙白或墨色中看得清楚的那個）、`AppTint` 顏料色的兩個對比測試、骨架淡色的深淺測試；使用者若也要拿掉再處理。

## 接下來

- **五種風格重新設計（2026-10-20 使用者提出，還沒開始）**：紙墨、竹青、石青、茶褐、素色使用者覺得還是不太行，可能要重新設計，要先和使用者談。重新設計時頁面、卡片、玻璃與閱讀選單的底色照 `AppLayers` 的規則算（DESIGN.md「色彩與材質層次」）。
- **選項精簡（2026-10-20 使用者說選項多到控制不完、分級看不懂，交給 agent 自主決定、不再過問）**：全部選項的去留與分級規則在 ADR 0030。把閱讀器面板改成兩層推翻了 10-15 #69「面板所有項目直接列出」的做法，使用者若要面板也看得到全部，再改回。
- **開 App 與轉場掉幀（2026-10-20，#88、#90）**：做法寫在 ADR 0029。量不到手機上的合成（raster）成本；測試的資料庫與書源解析在主執行緒，`test/frame_budget/` 的「幀前」數字比手機上重。閱讀偏好第 0 格約 220–250ms（停在起點，開始得晚）。
- **已知小差距，沒修**：開書時前一章取不到，開書後方先排好的範圍照夾限前的位置算，少了約一百像素，掀紙後會補上。`AppPageTransitionsBuilder` 沒有 `==`，`buildAppTheme` 每次算出的主題都不相等：`SettingsProvider` 每通知一次（例如改「自動刷新」），整個 App 讀 `Theme.of` 的元件（含被蓋住的頁面）都重建一次（2026-10-21 量到，頻率低沒修；檔案當時另一條分支在改）。

## 注意

- 這台機器常有好幾個 session 同時開在同一個資料夾，切分支會影響別人；自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被別人佔用時換一個 port，不要結束別人的程序。
- Claude Code 的子代理用 `isolation: "worktree"` 開的工作樹放在主資料夾的 `.claude/worktrees/` 底下，起點是主資料夾目前的 commit（通常是 `beta`），不是呼叫端所在的分支；要疊在別的分支上，合併時得自己解衝突，或先把那條分支併進 `beta`。
- 2026-10-19 起日常改動進 `beta`（ADR 0027）。這台的主資料夾已切到 `beta`、`origin/HEAD` 指向 `beta`、`core.hooksPath` 是相對的 `.githooks`（每個 worktree 跑自己那份 hook）。另一台電腦的資料夾還停在 `main`：開工前 `git fetch`、`git switch beta`、`git remote set-head origin -a`（T3 的自動拉取只拉預設分支，認的是 `origin/HEAD`）。T3 從 `origin/HEAD` 開 worktree，`git fetch` 不會更新它：這台的 `origin/HEAD` 原本還指向 `main`，#82 因此開在 `main` 上、以 `main` 為目標合併，2026-10-20 已把 `main` 用合併提交併回 `beta`（repo 只允許 squash，走 PR 會失去 `main` 的提交，之後 `main` 就無法快轉），並修正 `origin/HEAD`。`main` 收到不在 `beta` 上的提交時讓 Android Release 失敗的檢查，要等 `main` 第一次快轉到 `beta` 才生效，在那之前推上 `main` 照樣會發版。
- `download_service_test` 有一批「`_dio` 尚未初始化」的下載失敗日誌（測試沒準備網路層，只檢查排隊與範圍），不是警告。
- 新開的 worktree 跑 `flutter test` 時，sqlite3 的 native asset 下載可能被公司網路改掉、雜湊不符而失敗；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就會直接用快取。
- Codex 審查的暫存 `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時會擋掉 Codex 最後一次連線，`codex exec` 因此回非零，但報告通常已經寫好；先看報告檔再判斷要不要重跑。
- Windows 上用 Python 腳本寫檔要給 `newline='\n'`，不然會寫成 CRLF。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 用 `test/screens` 拍閱讀器時，換行結果快取在系統暫存區的 `hybrid_plans`、`hybrid_metrics`（截圖環境把 App 的資料夾指到 `%TEMP%`），換行快取只認 App 版本號；改了換行規則或排版程式卻沒換版號時，先把這兩個資料夾移到垃圾桶再拍，不然拍到的是舊的換行。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- `SwipeActions` 的拖動辨識沒有讀 `MediaQuery` 的觸控門檻（用 Flutter 預設 18，`PageView` 用裝置的，Android 約 8），放進可左右滑動的容器會搶輸搶贏不定；書架因此拿掉了左滑（DESIGN.md）。
