# 哪些工作佔主執行緒

判斷掉幀是誰造成的、說某件工作會不會卡動畫之前先看這份。只有在主執行緒（主 isolate）上跑的工作會讓動畫掉幀；在背景 isolate 跑的再重也不會，除了它把結果送回主執行緒的那一段。

「背景」有兩種意思，要分清楚：在**背景 isolate** 跑，和在主執行緒上用 `Future`、`unawaited` 不等它跑。後者只是不擋住呼叫的人，計算照樣佔主執行緒，照樣會卡動畫。

## 在背景 isolate（不會卡動畫）

- **書源 isolate**（ADR 0028、0034）：書源的網路、解析、規則 JS。**檢查書架更新**整段（含目錄比對與寫回，`BookUpdateService`）。**書架自動下載**與手動下載的規劃、抓章、存正文（`download_executor.dart` 的 `…InSourceIsolate`）。搜尋、換源、發現的抓取也在這裡。
- **網路 isolate**（`SourceIo`，ADR 0034）：替停住的書源 isolate 發請求、讀快取。
- **資料庫 isolate**（drift 的 `DriftIsolate`）：SQL 本身。
- **一次性的 `Isolate.run`／`compute`**：正文前處理、規則階段的正文替換、排版快取讀寫、繁簡字典解析、EPUB 解析、還原備份解碼、匯入書源解析、字型雜湊。

## 在主執行緒（會卡動畫）

- **畫面**：建構、排版、繪製；閱讀器的分頁與量字（要用 `dart:ui`）。
- **多台手機同步**（`SyncService`）：除了等網路與 SQL，解 JSON、算指紋、比對、套用都在主執行緒（2026-11-03 的狀態）。
- **背景工作送回主執行緒的那一段**：收到的結果要複製進來（上千章的目錄、正文）；資料表改了，`watch()` 重查的結果要轉成物件、畫面跟著重建；`AppEventBus` 的 `upBookshelf` 會讓書架重讀。這幾件通常很小，懷疑它們之前先量。
- Cookie 檔與限流、WebView（書源 isolate 經代理用主 isolate 的）；合併搜尋結果、寫搜尋快取（ADR 0028）。

## 怎麼確認

- 讀程式：找 `SourceIsolate.run`、`Isolate.run`、`compute`。呼叫端自己的流程不會因為裡面呼叫了 `BookSourceService` 就跟著搬過去，要整段寫成背景 isolate 的工作才算（ADR 0028；2026-10-19 下載曾經漏在這裡）。
- 量：用幀預算（`tool/frame_budget_compare.sh`）看超過上限的那幾幀是誰在重建、主執行緒在做什麼，不要只憑推測。
