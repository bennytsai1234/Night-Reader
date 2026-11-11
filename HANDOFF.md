# 交接：中英混排的英文單字之間空格消失

使用者在《漫威裡的賽亞人》第三章〈雷耶斯集團〉看到英文單字之間的空格不見了，例如 `Lifeitseems`、`willfadeaway`、`Driftingfurthereveryday`、`FadeToBlack`。另一個公開網站的同一章有空格（`Life it seems`、`Fade To Black`），但那個網站擋自動抓取（403），沒對照到。

同一張截圖裡的另一個問題（中文字距被拉開）已經修好，見 PR #319（`fix/reader-kinsoku-latin-spread`），和這件無關。

## 已經查過、排除的

讀程式確認以下幾步都**不會**刪掉兩個英文字母之間的半形空格：

- `HtmlFormatter.format()`（`lib/core/utils/html_formatter.dart`）：`&nbsp;`、`&ensp;`、`&emsp;`、U+00A0 都轉成半形空格。
- `normalizeTypography()`（`lib/features/reader_v2/chapter/reader_v2_content_transformer.dart`）：tab、U+00A0、U+3000 轉成半形空格，連續空格合成一個；`_removeCjkSpaces` 只刪一側是漢字或全形標點的空格。
- 換行與繪製（`VisualLineLayoutEngine`、`ReaderParagraphLayout`）：用截圖工具畫過 `Fade To Black`，空格都在。

## 還沒查的（照順序）

1. 問使用者用的是哪個書源。書源原文的取法見 `docs/agents/phone.md`「書源原文」。
2. 用 `test/live/` 連真網站抓那一章，看書源解析出的正文有沒有空格。
   - 沒有空格：問題在網站或書源規則（例如規則裡的 `##\s` 替換），不在夜讀。
   - 有空格：接著查使用者的替換規則（`_applyRules` 會套用），再查不到就在 `ReaderV2ContentTransformer` 每一步印出這段文字，找出哪一步刪掉的。
3. 查完刪掉本檔。

---

# 交接：選單一律畫出與設計審查（分支 `feat/stable-menus`）

worktree 在 `D:\Migrated\Desktop\Folder\product\Night-Reader-menus`，從 `beta` 開、`--no-track`。開工前 `git branch --show-current` 確認。

## 目標

使用者 2026-11-11 要審查整個 App 的設計一致性與實際體驗：選單不要太長、功能收得合理、簡潔、同一類東西各處一致，另加「狀態檢查」。談定的順序是**先露出，再整理**：先讓每個選單只有一種樣子（不能用的灰掉、不藏），補拍截圖，再和使用者一起整理太長的選單、名稱與狀態用詞。

## 已定案（別再問）

- ADR 0059（`docs/adr/0059-menus-show-every-item.md`）：選單、頁首的鈕與膠囊、狀態列、分段、清單列與播放器的控制鈕、錯誤頁按鈕列，項目一律畫出，不能用的灰掉，**不寫原因**。使用者看過括號原因的候選（換行、第二行、右側、縮短）後說「換行完全沒有美感」「乾脆別加原因」。
- 設定頁依賴開關的子設定照 ADR 0009 隱藏（使用者同意）。
- 不算變形、照舊的清單寫在 ADR 0059「不算變形」。
- 使用者不要功能入口地圖（太麻煩），先不做儀表板；比較圖用 `html_render` 放進對話。

## 做到哪

1. 第一輪已提交、推上（`feat(menus): 選單與頁首的項目一律畫出，不能用的灰掉`）：書架、書籍詳情、搜尋、發現、書源管理、登入、書籤、下載、閱讀器／漫畫／有聲書的「更多」等。
2. 第二輪（使用者選「A 和 B 都做」，把原本列為不算的也露出）：有聲書頭尾的上一集／下一集灰掉、開書失敗頁的「換源」、搜尋的「略過」與失敗書源膠囊（0 個時寫「沒有書源失敗」）、書源管理的搜尋框／校驗狀態列（「還沒校驗過」）／底部工具列一直在（拿掉了 `_chrome` 長出收回動畫）、漫畫目錄的書籤標註分段灰掉（`GlassSegment.enabled`）、換源面板分組列一直在、下載佇列每列控制鈕一直在。規格與 ADR 已同步。看這條分支最新的提交確認有沒有提交。
3. 補拍截圖（下一步，還沒開始寫）：在 `test/screens/app_screens_test.dart` 的 `scenarios` **最後面**加情境（要插本地書的放最後，前面的圖才不受影響）：
   - 書籍詳情「⋯」（`s09` 後點 tooltip「更多」）
   - 書源管理「更多」、第二層「分組與篩選」、書源長按（「筆趣閣」）
   - 搜尋類別膠囊選單（tooltip「搜尋的類別：小說源」）、發現「書源類型」
   - 插一本本地書（`origin: BookType.localOrigin`、`originName: '本地'`）後拍書架長按與書籍詳情「⋯」
   - 漫畫、有聲書：測試資料（`seedLibrary`）只有網路小說，要另外備資料，量大時先問使用者要不要。
   淺色、深色各跑一次：`SHOT_MODE=dark SHOT_ONLY=s20 tool/flutter_test.sh --run-skipped -t screens test/screens/app_screens_test.dart`，圖在 `%TEMP%\night-reader-screens`。
4. 拍完列出每個選單的項目數，挑最長的畫整理候選（照 `docs/agents/candidates.md`，淺深各一）。目前已知最長：書架「整理」15 項加 4 條分隔，手機上幾乎一整個螢幕高；書源管理「更多」15 項、批次「更多」14 項、書源長按 11 項。

## 狀態檢查的發現（還沒改，整理時一起談）

都已對照程式抽查過：

- 同一個「停止」：朗讀是丟掉位置；有聲書圓鈕往下滑是記住進度；AI 修是書源不改；批次修是已修好的照存；搜尋是留下已找到的結果。
- 朗讀有兩種暫停：面板暫停從那個字接（`_tts.pause/resume`），通知、耳機、定時到從那句開頭接（`_pauseAtSentence`），畫面都寫「繼續朗讀」；定時朗讀鍵念著時按是停止（丟位置）；面板第一列有「暫停朗讀／繼續朗讀／從目前位置朗讀」三種字。
- 搜尋「略過」其實是結束整個搜尋（`p.stopSearch`），頁首另有紅色「停止」做同一件事。
- 校驗取消後，詳情對話框寫「已完成」（`source_manager_dialogs.dart`），摘要不標示取消；狀態列寫「取消」、對話框寫「取消校驗」。
- 下載：刪掉書架書的任務，下次開書會自動排回（`decideShelfDownload`）；「暫停全部」只在記憶體，重開 App 失效。
- 「接著做」有三個詞：繼續朗讀、繼續／恢復全部、播放。
- 批次修書源停下後，被打斷的步驟顯示綠勾。
- 規格沒寫：朗讀面板的播放停止列、校驗取消、下載的暫停刪除、搜尋頁首「停止」。
- 建議方向（使用者還沒表態）：「暫停」一定能從同一處接著做；「停止」是結束並說明留下什麼；接著做一律「繼續」。

## 驗證

- 每輪改完：`flutter analyze lib` 與改到的元件測試（`tool/flutter_test.sh --timeout 120s <檔案>`）。第一輪全過；第二輪看提交說明。
- 選單變長後，測試的矮畫面要先 `ensureVisible(find.text(x, skipOffstage: false))` 才點得到下面的項目（書架「整理」的「選取」）。
- 這份交接做完就刪；收尾照 `docs/agents/finish.md`，做到「可以合併」就停。
