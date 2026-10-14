# 交接（2026-10-14 17:00）

## 正在做

**PR #58（分支 `merge/reader-open-and-accent`）**：使用者已說要合併，正在跑合併流程。內容是兩條分支併成一條：

- `fix/reader-open-continuity`：開書不再先閃轉圈。正文區蓋一張閱讀底色的紙（`LoadingVeil`，`lib/features/reader_v2/hybrid/overlay/loading_veil.dart`），排版超過 500ms 才在紙上淡入正文骨架，正文排好後紙淡出；首次開書時頁首頁尾跟著淡入。
- `feat/accent-color`：強調色（「外觀與主題 → 強調色」選單，跟隨主題＋十二色）、五種新風格（胭脂、藕荷、黃卷、琥珀、霜夜）、風格卡改成兩列五張的摺角書頁。風格卡的造型是使用者在三種渲染方案裡挑的（書頁緞帶、精裝書封、摺角頁）。
- 合併流程補了一步（AGENTS.md、ADR 0014）：合併前先把最新的 `main` 併進分支，讓 CI 在合併後的狀態重跑。

合併流程做到哪：PR 已開、Codex 審查已跑完（報告的核對結果見下），「拿掉配色對比度規則」與文件修正已提交推上。因為額度用完先停在這裡，接下來：

1. 修 Codex 第 4、5、6 項（見「Codex 審查的處理」）。
2. 跑全套測試、推上去，用 `gh pr comment 58` 貼審查摘要。
3. 併最新 `main`、等 CI（`gh pr checks 58 --watch`），`gh pr merge 58 --squash`，`git pull --ff-only`，刪本機分支（`fix/reader-open-continuity`、`feat/accent-color`、`merge/reader-open-and-accent`）。

**配色不再有對比度規則（使用者 2026-10-14 決定）**：原本 DESIGN.md 規定新增或調整風格時，每個深淺都要過對比度門檻（正文 7:1、次要文字與主色 4.5:1 等），`test/shared/theme/app_style_test.dart` 會擋下不達標的顏色；強調色也會依風格自動調深或調亮到過門檻。使用者說這不是他定的規則、不知道它要做什麼，配色手調個大概就好，不行他會回報。所以：

- 已拿掉：DESIGN.md 的對比度契約那段、`app_style_test` 裡風格與強調色的對比度門檻測試、`AppStyle.paletteFor` 的自動調明暗（現在強調色直接用 `AppAccent` 設定的淺色／深色兩個值）。
- 還留著：`StylePalette.onPrimary`（主色上的字取紙白或墨色中看得清楚的那個，這是功能不是門檻）、`AppTint` 顏料色的兩個對比測試（列首圖示、滑動動作，不屬於風格配色）、骨架淡色的深淺測試。使用者若也要拿掉再處理。
- 不要照審查工具的意見調色。Codex 第 1 項（閱讀器設定面板的分組卡片上，部分風格的主色文字對比不到 4.5:1，例如霜夜深色 4.28）是在舊規則下提的，使用者說不用照它調；當時改的顏色已全部還原。

**Codex 審查的處理**（報告在 repo 外，已刪；要點如下）：

- 第 2 項，跳章時「取得正文」那段沒有蓋紙：屬實，但這是原本的行為，不是這次造成的。跳章的流程是 runtime 先等正文（`reader_v2_runtime.dart` 的 `_loadContentAt`），拿到後才交給畫面排版；畫面要到排版開始（`_restoreCore` 裡 `_setRestoreCompleted(false)`）才蓋紙。所以網路慢時，按下跳章後舊正文會停在畫面上一段時間、沒有任何提示，正文到了才進入紙面。保留舊正文是刻意的：等待中還能捲動，一捲就取消跳章（`hybrid_reader_interaction_test` 的「dragging while a jump is loading cancels the jump cleanly」鎖著這個行為）。若要改，做法是在跳章操作被接收時就啟動紙與 500ms 計時，用操作識別判斷完成、取消、失敗；取消時掀開紙恢復舊正文。要把「有可恢復的穩定正文」（`hasStableWorld`）和「目前正在顯示載入紙」分成兩個狀態，不能直接把 `hasStableWorld` 設成 false（`a4f96c1` 刻意把進行中的操作和 lifecycle 分開）。要不要改、等待中還能不能捲動取消，先問使用者。
- 第 3 項，跳章與改字號重新排版時，頁首頁尾資訊列不會收掉再淡入：屬實，也是原本的行為。外框 `ReaderV2PageShell` 判斷要不要顯示資訊列用的是 `runtime.state.hasStableWorld`，跳章、重新排版時它一直是 true；畫面自己的「正文排好了沒」（`_initialRestoreCompleted`）沒有傳到外框。所以正文被紙蓋住時，時間、章名、進度還在，排好後也不會重新淡入。改法是跟第 2 項一起，讓正文、紙和資訊列共用同一個「正在載入」狀態。改字號時資訊列留著其實也合理（只有正文在重排），要改哪些情境先問使用者。這兩項目前只把 DESIGN.md、CHANGELOG 的描述改準確（資訊列淡入只寫首次開書）。
- 第 4 項，窄螢幕（320 寬）加兩倍系統字級時，十個風格名稱都被省略成「…」：要修，讓名稱可以換行。
- 第 5 項，載入還沒完成就換 runtime（例如換源）時，紙沿用上一輪的骨架與計時，新的一輪第一幀就看到骨架：要修，換 runtime（epoch 重建）時一律重新蓋紙、重設 500ms。
- 第 6 項，紙在淡出或骨架在淡入時，系統中途改成關閉動畫，動畫不會立刻到位：要修，`reduceMotion` 設成 true 時把進行中的紙與骨架動畫直接跳到終點。

## 最近合併

#55（合併後發了 beta）：下載任務的範圍改記起訖章節網址（`startChapterUrl`／`endChapterUrl`，null 是從第一章／到最後一章），開跑時才對照目錄換算；進度是範圍內每章算一次，已下載的算完成；schema 6 升級時舊任務一律改成整本。規則寫在 ADR 0008。

#54 已合併並發過 beta：#53 合併前審查留下的兩件事，加上討論後延伸的網站改版、故障與付費情況——

- 檢查更新與「整本補下載」換新目錄（`BookTocReplacer`）時，閱讀進度依目前那一章的網址對到新序號；那一章不在新目錄裡時照標題（繁簡視為相同）、章號與比例估計，章內位置只在錨點綁得住原文時保留。
- 書源回空目錄時這次檢查算失敗，只記檢查時間（同其他失敗），目錄、章數、進度不動。書源拿掉的章節裡，已下載或正在讀的留在目錄原位（使用者選了「合併保留」，不整份拒收新目錄，免得真的刪章時目錄永遠卡住）；新目錄有同名章節的不留（書源換網址）。
- 閱讀器開著時目錄被換新：存進度時在同一個交易裡依章節網址換算成資料庫目錄的序號，閱讀器自己仍照開書時的目錄。
- 書源標 `isVip` 且非 `isPay` 的章節不下載、抓到的內容不存（以資料庫目錄的付費標記為準，閱讀器或下載手上的舊快照不會蓋掉），閱讀器目錄與書籍詳情目錄右側顯示鎖頭（目前章節的記號優先）。書源校驗本來就會把測試書目錄裡有鎖章的書源標成「需要登入」排除，鎖頭補的是校驗之後才改付費、或只有部分書付費的書源。
- 換源面板用書名的繁簡兩種寫法搜、各自計時，比對書名與作者時繁簡視為相同；換源對章節時標題繁簡不同也算同一章。

書源解析搬離主 isolate 的研究在 `docs/research/source-engine-off-main-isolate.md`：兩個效能熱點已修，搜尋頁被整頁蓋住時也會暫停送出書源；搬 isolate 先不做，等實機上還會不會卡再決定。

閱讀器審查清單的「第 2 項」（正文段落要不要各自成一層圖層）已結案：維持 `RenderCachedBlock.isRepaintBoundary => true`。使用者之後若在手機上感覺捲動掉幀，再以那個現象重新開題。

## 注意

- 同一個資料夾可能有別的工作階段在用：2026-10-14 另一個工作階段曾在這裡切分支（iOS 那條後來移到 `../Night-Reader-ios` worktree）。開工前先 `git branch --show-current` 確認還在自己的分支；本機預覽伺服器的 port（例如 8765）被別人佔用時換一個 port，不要結束別人的程序。
- 要看 Flutter 實際畫出來的頁面：寫一個暫時的 widget 測試，把頁面包在 `RepaintBoundary` 裡，`pumpAndSettle` 後在 `tester.runAsync` 裡 `toImage` 存成 PNG 到 repo 外，看完刪掉測試檔。測試字型會把字畫成方塊，看的是形狀與顏色。`AppearanceSettingsPage` 用到的 `SettingsProvider` 會在畫完後丟 path_provider 的 `MissingPluginException`，不影響圖片。
- Bash 工具裡用 heredoc 跑的 Python，字串中的 `\n`、`￼` 這類跳脫有時會被換成真的字元，寫進 Dart 檔變成語法錯誤；含反斜線跳脫的內容改用 Write／Edit 工具寫。
- Flutter 測試環境的預設字型每個字一樣寬，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- 重新產生 `NightReaderPunct`：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
