# 交接（2026-11-18 14:10）

## 正在做

使用者要全面打磨夜讀的視覺。已合併兩個 PR：#417（彈出層與遮罩）、#418（面板與按鈕）。剩下的寫在 `beta` 的 `PLAN.md`「視覺打磨接下來的兩個 PR」：提示框，再來卡片與底色。

這條分支 `fix/alert-dialogs` 做「提示框」，從 `beta` 的 `3b79524b` 開、沒有上游、還沒有任何程式改動。worktree 在 `C:\Users\045650\.t3\worktrees\Night-Reader\fix-alert-dialogs`。目前只盤到：提示框（`showAppAlert`、`showAppConfirm`、`showStatefulAppAlert`）在 `lib/` 有 64 個呼叫處，其中帶自訂內容的 `showStatefulAppAlert` 20 處。

## 下一步

1. 照 App 的預設（`docs/agents/candidates.md`）拍三類提示框的現況，淺色、深色各一張：只有一句話加兩顆鈕的、帶輸入框的、帶選項的（書源管理「按標籤刪除」，`test/screens/app_screens_test.dart` 的 `m10_sources_delete`）。
2. 畫候選、排成一頁放進對話（淺色深色並排、標出推薦的那個），一次只問一件。使用者看過文字版的方向、回「可以」，還沒看過圖：
   - 所有提示框只留兩種字級：標題與按鈕 17、其餘 15。現在是標題 17、說明 13（八成濃度）、區塊標籤 13、選項 15、按鈕 17。
   - 說明用正常濃度：現在最重要的「無法復原」是全框最小最淡的字。
   - 框加寬（現在固定 290），說明不要斷出只剩一兩個字的最後一行。`lib/shared/widgets/app_state_view.dart` 已有「多行說明各行排得一樣寬」的做法，先看能不能共用。
   - 帶選項、要勾選的（「按標籤刪除」這種其實是表單）改用底部面板：裡面是和設定頁一樣的分組卡片，最下面一顆主要動作。提示框只問一句話、給兩顆鈕。其餘 19 處 `showStatefulAppAlert` 逐個看是哪一種，列表給使用者。
3. 使用者選定後寫進 `docs/design/components.md`「選單與提示」，實作、補測試，照 `docs/agents/finish.md` 收尾（Codex 審查）、`docs/agents/merge.md` 合併，結果寫在對話裡。
4. 合併後另開 worktree 做「卡片與底色」（開分支加 `--no-track`），範圍在 `PLAN.md`。

## 談定與否決

- 使用者：「因為我也不會設計 只能靠你了」。每件事直接給建議與理由，候選圖照畫但標出推薦；他指出哪裡不舒服先當線索去量、去拍圖查證。
- 使用者對提示框的原話：「彈窗也是 沒有設計好 包括說太多小字 以及 資訊層級 還有字的大小不對」。
- 邊界對齊的原則（使用者沒反對，還沒寫進規格）：對齊畫面上固定的線（頁面左右邊距 16），不對齊底下碰巧有的內容。選單的寬度跟著自己的字，不拉成卡片寬；提示框置中，不需要貼邊。
- 按鈕只留兩種（使用者沒反對，面板頁首已照做，其餘還沒動）：浮在頁面上的 44 圓、有陰影；長在面板或卡片裡的 32、不畫陰影。
- 書架不好看的是顏色（底色偏灰、卡片厚重）；卡片上的內容「還好」，形狀與排法「不用」動。
- 換源面板沒有把控制項併成一排：併排要改操作方式，超出小修，已告訴使用者。
- 淺色朗讀面板的高亮預覽和卡片同是紙色、看不出方塊邊界：已告訴使用者，他沒回。不加細邊線（卡片與玻璃的框線是否決過的方向）。
- 不做：單獨調模糊、全面掃動畫（ADR 0036）；開 App 加速卡在 `PLAN.md`「開 App 的底色不等朗讀引擎」，等使用者回家用手機量。

## 注意

- 另一個對話的候選圖曾把面板底畫成卡片的顏色，使用者因此以為按鈕和面板底分不開。畫候選一律用 App 真的畫面或真的主題，不自己指定底色。
- 改 `ReaderV2MenuStyle`（`reader_v2_menu_palette.dart`）會連帶動到目錄、上下選單、漫畫閱讀器選單，它們都經 `toSheetTheme`。改前改後各拍一次、用 PIL 的 `ImageChops.difference` 逐像素比，才知道有沒有動到不該動的。
- 測試裡連續用不同主題 `pumpWidget(MaterialApp(theme: …))`，主題會漸變，下一幀讀到的還是上一組配色；給 `themeAnimationDuration: Duration.zero`。
- 用 Python 腳本批次改檔時，`dart format` 之後縮排會變，比對字串的 `assert` 一失敗整個腳本都不寫檔。改完看 `git diff`，或直接用編輯工具。
- 提示框的底色、分隔線已經有專用的取色：`AppChrome.popupTint()`、`popupSeparator`、`barrier`（`lib/shared/theme/app_chrome.dart`）。提示框一律照 App 的配色，不跟著打開它的面板（`docs/design/appearance.md`「層次」）。
- 上一個對話的 worktree `C:\Users\045650\.t3\worktrees\Night-Reader\fix-visual-glass-polish` 停在 `beta`、沒有分支也沒有未提交的改動，可以刪。

## 開工先載入

先載入 `git-flow` 與 `prototype` 技能，讀 `docs/agents/candidates.md`、`docs/design/components.md`「選單與提示」、`docs/design/appearance.md`「層次」，再開始拍現況。改 `docs/design/` 前載入 `writing-for-agents`；收尾時載入 `codex-review` 與 `pr`。
