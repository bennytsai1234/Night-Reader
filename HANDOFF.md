# 交接（2026-10-14 22:25）

## 進行中：PR #61（`feat/shelf-check-in-system-tools`，已併入 `refactor/split-hybrid-reader-screen`）

使用者 2026-10-14 說兩條併成一個 PR 合併。內容：

- **設定搬移**：「啟動時檢查書架更新」從「我的」移到「關於夜讀 → 系統工具」；ADR 0015 記下「我的」第一層只放入口、不放開關。
- **掉幀修正（兩個 perf 提交）**：使用者回報開 App 後切頁卡頓，在使用者手機上逐情境量測後修。commit message 有每項的成因與改前改後數字。摘要（超過 16.7 ms 的幀／最慢一幀）：冷啟動切頁 8／36.8 ms → 1／16.9 ms；從備份還原 94／242 ms → 1／17 ms；發現書單 6／28 ms → 3／19 ms；搜尋 29／88 ms → 18／27 ms。主因不是書架重畫，而是背景書架檢查的解析與資料庫工作、書源分類掃整段 JS、繁簡轉換、搜尋合併與 JS 在主 isolate。
- 搜尋剩下的成本主要是搜尋頁本身的重建與 TLS 握手；仍在主 isolate 的 JS 是用到網路、`java.put`、Cookie、快取這類的書源（見 `docs/research/source-engine-off-main-isolate.md` 最後一節）。最後一個建置（顯示文字的繁簡轉換快取）裝上手機了但沒量。
- **拆 `HybridReaderScreen`**（原 `refactor/split-hybrid-reader-screen`）：2651 → 1540 行，行為不變、閱讀器測試全過。拆出 `geometry/text_geometry.dart`（`HybridTextGeometry`：字元 offset 與正文座標互換，選字、反白、朗讀高亮框、閱讀位置）與 `pipeline/`（`HybridLayoutPipeline`：一個排版世代一份，換代就整份 dispose 換新；`HybridLayoutDiskCache`：一本書的磁碟快取）。還原、跳章蓋紙、捲動與翻頁命令、build 刻意留在畫面：它們直接操作捲動控制器與 widget 狀態，再拆只會多一層全是回呼的薄殼。
- 閃退回報（`glass_menu.dart:250` 的 `clamp`）在 #56 已修，beta.103 起就有，這次不用改。

## 手機量測（使用者 2026-10-14 說之後別再用他的手機量）

這次的做法，之後若使用者同意再量時參考：profile 建置用一個不提交的入口（`main()` 之後把 `developer.Service.getInfo()` 的 ws 位址寫進 `getExternalStorageDirectory()`），因為 vivo 會把 logcat 裡的 VM service 位址遮掉，intent 參數在這個 App 也不生效；電腦用 `vm_service` 連上後 `setFlag('profiler','true')`，收 `Flutter.Frame` 事件與 `getCpuSamples`，把 UI isolate 連續忙碌超過 8 ms 的區段依堆疊歸類。profile 版套件名是 `com.inkpage.reader.debug`，和正式版並存；vivo 用 adb 安裝會跳確認頁（勾「已瞭解」再按「繼續安裝」）。使用者手機上還裝著這個 profile 版（裡面是還原進去的書架），要不要移除由使用者決定。

## 今天的 beta

`gh workflow run android-release.yml --ref main -f channel=beta` 發了兩次：run 38536504376（#57、#58）、run 38551518474（#59）。使用者 2026-10-14 說這次先只發測試版，正式版（下一版是 0.3.4，目前正式版 v0.3.3）等使用者再說。

## 最近合併

**#60**（`feat/website-seo`）：網站加 `sitemap.xml`、簡體與 Legado 關鍵字、補齊 `SoftwareApplication` 結構化資料。沒加 `robots.txt`：專案網站在 `github.io/Night-Reader/` 子路徑，爬蟲只讀網域根目錄的 robots.txt，放這裡無效。repo 描述與 topics 也已改好（不用 PR）。**只能使用者做**（已告知）：用自己的 Google 帳號在 Search Console 驗證網站、提交 `https://bennytsai1234.github.io/Night-Reader/sitemap.xml`；到 Legado 社群、PTT、V2EX、Reddit 等發文帶連結。

**#59**（`fix/reader-jump-veil`）：跳章時從按下那一刻就蓋紙（`_jumpVeil`／`_syncJumpVeil`），紙蓋著時不能捲動、不再一捲就取消跳章，只能等正文到或失敗（失敗時掀紙回到舊正文與原位置）；跳到別章時頁首頁尾收起再淡入（`ReaderV2Runtime.isJumpingToAnotherChapter`），同章跳轉與改字號不收（使用者 2026-10-14 決定）。紙下的正文固定在蓋紙那一刻：停住甩動、紙下開始的拖動拉回（`_holdScrollUnderJumpVeil`），翻頁、自動捲動、朗讀跟隨都不動正文（`_captureCommandOwner`），自動捲動這一步跳過、不停。刻意不動 `_initialRestoreCompleted`（它變 false 會拆掉捲動視圖，跳章失敗時位置就丟了）。

**#58**（`merge/reader-open-and-accent`）：開書改成「一張紙接到底」，加上強調色、五種新風格與摺角書頁風格卡。

- 開書、跳章與重新排版時正文區蓋一張閱讀底色的紙（`LoadingVeil`，`lib/features/reader_v2/hybrid/overlay/loading_veil.dart`），紙一蓋上就淡入正文骨架，正文排好後紙淡出；首次開書時頁首頁尾跟著淡入。原本排版超過 500ms 才出骨架，使用者 2026-10-14 改成一律先出骨架（`AppMotion.readerSkeletonDelay` 已移除）；淡出途中再蓋上時骨架不歸零，免得閃一下。
- 強調色（「外觀與主題 → 強調色」，跟隨主題＋十二色）、五種新風格（胭脂、藕荷、黃卷、琥珀、霜夜）、風格卡改成兩列五張的摺角書頁（窄螢幕加大字級時名稱換行）。
- 合併流程補了一步（AGENTS.md、ADR 0014）：合併前先把最新的 `main` 併進分支，讓 CI 在合併後的狀態重跑。

**#57**（`feat/ios-parse-worker-transitions`）：Release 另附未簽章 iOS IPA（ADR 0003 已改寫，`flutter_js` 在 iOS 用 JavaScriptCore）；不帶 JS 的搜尋頁與目錄在常駐背景 isolate 解析（`ParseWorker`）；封面 Hero 全部移除，全 App 換頁共用一種「換頁動畫」，在「外觀與主題」四選一（預設上浮），返回一律是開啟倒著播（ADR 0012、GLOSSARY）。`prototype/book-transitions` 是換頁動畫的網頁原型，留在遠端、不合併。

#55：下載任務的範圍改記起訖章節網址，開跑時才對照目錄換算（ADR 0008）。#54：目錄換新時依章節網址保留進度與已下載章節、付費章節顯示鎖頭、換源繁簡互通。

## 配色不再有對比度規則（使用者 2026-10-14 決定）

DESIGN.md 原本規定每個風格深淺都要過對比度門檻，測試會擋、強調色會自動調明暗。使用者說這不是他定的規則，配色手調個大概就好，不行他會回報。已拿掉 DESIGN.md 那段、`app_style_test` 的門檻測試與 `AppStyle.paletteFor` 的自動調明暗（強調色直接用 `AppAccent` 的淺色／深色兩個值）。還留著：`StylePalette.onPrimary`（主色上的字取紙白或墨色中看得清楚的那個）、`AppTint` 顏料色的兩個對比測試、骨架淡色的深淺測試；使用者若也要拿掉再處理。不要照審查工具的對比度意見調色。

## 接下來

- 只做計算的 JS 已在背景解析；若用到網路、`java.put`、Cookie 的書源在手機上仍會卡，就照 `docs/research/source-engine-off-main-isolate.md` 的阻礙一到五評估整套搬進背景。
- 閱讀器審查清單的「第 2 項」已結案（維持 `RenderCachedBlock.isRepaintBoundary => true`），使用者若在手機上覺得捲動掉幀再重新開題。

## 注意

- 這台機器常有好幾個 session 同時開在同一個資料夾，切分支會影響別人；自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被別人佔用時換一個 port，不要結束別人的程序。
- 新開的 worktree 跑 `flutter test` 時，sqlite3 的 native asset 下載可能被公司網路改掉、雜湊不符而失敗；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就會直接用快取。
- Codex 審查的暫存 `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時會擋掉 Codex 最後一次連線，`codex exec` 因此回非零，但報告通常已經寫好；先看報告檔再判斷要不要重跑。
- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。Windows 上 Python 寫檔要給 `newline='\n'`，不然會寫成 CRLF。
- 要看 Flutter 實際畫出來的頁面：寫一個暫時的 widget 測試，把頁面包在 `RepaintBoundary` 裡，`pumpAndSettle` 後在 `tester.runAsync` 裡 `toImage` 存成 PNG 到 repo 外，看完刪掉測試檔。測試字型會把字畫成方塊，看的是形狀與顏色。`AppearanceSettingsPage` 用到的 `SettingsProvider` 會在畫完後丟 path_provider 的 `MissingPluginException`，不影響圖片。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
