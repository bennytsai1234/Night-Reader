# 夜讀 Night Reader Atlas Index

本索引用來判斷變更由哪個模組負責；進入模組文件後可確認邊界、關鍵流程與修改路徑，精確符號與呼叫點再交由即時搜尋處理。

Atlas built: 2026-09-07 · from commit 56dd0c8 · format 6

## Module List

- [應用殼層 (app_shell)](night_reader/app_shell.md) — 應用啟動、DI、全域狀態、導航、主題與外部關聯入口。
- [規則引擎 (engine)](night_reader/engine.md) — 書源規則語法、解析後端、JavaScript 與抓取編排。
- [資料持久化 (data)](night_reader/data.md) — Drift、領域模型、本地書與檔案／度量快取。
- [書源與網路 (source_network)](night_reader/source_network.md) — HTTP 出口、Cookie、書源生命週期、校驗與換源。
- [圖書館 (library)](night_reader/library.md) — 書架、搜尋、發現、書籍詳情與本地書入口。
- [閱讀器 (reader)](night_reader/reader.md) — Reader V2 會話、正文、位置、排版、視口與閱讀輔助功能。
- [營運能力 (operations)](night_reader/operations.md) — 設定、備份／還原、下載、快取、TTS 與橫切工具。

## Module Summaries

### 應用殼層 (app_shell)

擁有 App 生命週期與全域組裝。啟動時序、GetIt 或 Provider 註冊、Material 主題、主導航、深連結、分享接收與關於／更新入口應從此模組開始。

### 規則引擎 (engine)

擁有 Legado 類型書源規則的語意與執行。規則切割、CSS／XPath／JSONPath／Regex、URL 編譯、JavaScript bridge 或搜尋／詳情／目錄／正文抓取邏輯應從此模組開始。

### 資料持久化 (data)

擁有結構化資料與本機內容儲存的契約。資料表、DAO、模型欄位、schema migration、本地 TXT、儲存路徑或持久快取應從此模組開始。

### 書源與網路 (source_network)

擁有所有書源 HTTP、Cookie 與書源管理生命週期。傳輸攔截、書源匯入／編輯／校驗、執行健康狀態、限流或換源應從此模組開始。

### 圖書館 (library)

擁有使用者找書、收書與進入書籍的流程。書架、聯邦搜尋、發現分類、書籍詳情、本地書匯入或書架交換應從此模組開始。

### 閱讀器 (reader)

擁有唯一的正文閱讀會話與呈現管線。內容變換、閱讀位置、排版快取、Hybrid viewport、翻頁、TTS 跟隨、書籤或閱讀設定應從此模組開始。

### 營運能力 (operations)

擁有 App 的設定與資料維運閉環。主題偏好、備份／還原、下載佇列、內容快取、TTS 服務、日誌或其他跨功能工具應從此模組開始。
