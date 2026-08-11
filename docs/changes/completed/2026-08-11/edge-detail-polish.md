# Night Reader 邊緣細節完整精修

層級：T2（橫跨 Reader、Discovery、App Shell、Engine、Data、Services 與 Source Manager）

狀態：已完成

## 目標與邊界

本次完整盤點既有功能的邊緣細節，並修正所有能留在現有責任邊界、可以自動化驗證、不需要擴張產品功能的項目。全程保留：

- feature freeze，沒有新增書籤管理等產品能力。
- Reader hybrid／legacy 雙軌、viewport FIFO command queue 與 Runtime 所有權。
- imperative Navigator、SettingsProvider ↔ AppConfig ↔ PreferKey 同步契約。
- SearchModel 純 Dart、LegadoExploreKindFlow、AppEventBus 與閱讀進度寫入邊界。
- 現有外部 contract、wire format 與資料庫 schema。

`AssociationHandlerService.init()` 未掛接屬於獨立功能缺口，不納入本次既有功能精修。

## 完成內容

### Reader

- 統一觸控與鼠標輸入邊界：以 Flutter touch slop 處理輕微移動，多指、次要按鍵與超界拖曳不再誤觸發翻頁或關閉。
- 關閉控制層時阻擋事件穿透，並保留頂部 system inset 與常駐資訊列的原有互動。
- 章節 Drawer 加入單一 pending ownership：只在跳章成功後關閉，失敗時保留 Drawer、恢復操作並顯示可讀狀態。
- 閱讀器邊界判定不再將尚未 attach／尚未建立 viewport 誤報為書首或書尾；不可移動與邊界 probe 共用 `0.01` logical-pixel epsilon。
- 自動翻頁在 viewport command 失敗時停止並只發出一次通知，控制層隱藏後自動翻頁狀態仍保持可見。
- 排版設定共用 trailing commit，drag end 會落盤最後值；dirty ownership 只提交使用者實際更動的欄位，不覆寫等待期間的外部新值。
- 進度、loading、operation 與可讀狀態的文案與 semantics 收旂，並避免重複 SnackBar。

### Bookshelf、Book Detail、Search 與 Explore

- Explore 的交錯分類請求以 active generation 隔離；舊請求可完成自身快取，但不會覆寫目前書源的可見狀態。
- Explore 分頁暫時失敗後保留 `hasMore`，重試同頁不重複追加，只有空分頁才正式結束。
- Search 在 Provider 邊界 trim 關鍵字，純空白不啟動搜尋、不寫入歷史。
- Book Detail 在遠端資料失敗時保留已儲存內容與降級提示，後續更新成功會清除提示。
- 目錄搜尋支援預填、立即清除與零結果恢復；換封面面板在深淺主題及破圖狀態保持對比。
- 書架批次檢查更新加入單一 in-flight 狀態，防止重複觸發並保留原有計數回饋。
- 書架與探索的狀態同步改用完整書源／book URL identity，避免異源同 URL 誤合併；舊 refresh／initialize 不再覆寫新快照或 callback。

### App Shell 與共用 UI

- Crash log 頁面有明確 loading、empty、loaded 與 error 狀態；複製、清除失敗不誤報成功，dispose 後的延遲讀取不再操作 context。
- About 頁重用現有 App icon，外部連結無法開啟或 URI 不合法時提供複製連結 fallback。
- 點擊區域設定的 reset／儲存繼承深淺主題對比，完成後有一致回饋。
- 設定卡片有完整 Material ink 與圓角裁切；共用 BottomSheet 的標題、關閉操作與大字體不再 overflow。
- 共用書封前景對比、繁中降級文案、Semantics 與重複朗讀排除取得一致。
- Splash 保留原有 900ms／2s 時序，慢書架改由不阻擋導覽的 semantic overlay 接手狀態。

### Engine 與 Data

- `LenientCookieManager` 只依 response origin 儲存 Cookie，不再把 host-only Cookie 複製到跨網域 redirect target，關閉跨網域 Cookie 洩漏路徑。
- 手動 redirect 以 visited URI 防止迴圈，POST 302 轉 GET 與 redirect chain 保持正確；header 合併改為不分大小寫。
- `AppCache` 與 JS 檔案快取以穩定 SHA-256 檔名隔離 key，不再依賴 Dart `hashCode` 或可碰撞 sanitizer。
- Cache DAO 的 deadline 清理納入剛好到期的資料；model 匯入的缺省布林、ID 與非有限數值回到模型定義。
- AppStoragePaths 拒絕 traversal／非單一 path component；ZIP 解壓略過越界 entry，書源匯出名稱清理路徑分隔字、非法字元與 ASCII control characters。
- JS Engine 在所有 async setup gap 後重查 disposed，dispose 會拒絕每一個 pending rule call；取消保留取消語意而不降級為一般失敗。
- AnalyzeRule 的 context／暫存變數、async JS fragment、relative URL、regex `$10` capture 與實際 Legado 規則路徑完成邊界修正。
- BookList fallback 不再暫時改寫共用 source rule，dedupe identity 不會因分隔字碰撞；章節上限對 0 與邊界值有明確語意。
- TXT parser 改為只記錄實際章界與 chunk endpoint 的 byte offset，不再建立全文 code-unit boundary 表；巨型 malformed UTF-8 的分塊仍連續且精確到實體 EOF，避免大檔額外數百 MB 記憶體與重編碼錯位。

### Services

- DownloadScheduler 在第一個 await 前保留 `bookUrl`，併發重複加入只會寫入與排程一次，且以 `finally` 釋放保留。
- 編碼偵測將 HTML `charset` 限定為獨立屬性，不再誤命中 `data-charset`；HTTP charset 接受合法空白與引號。
- 本地 TXT 讀取拒絕起點、反向與終點越過 EOF 的範圍，正文 pipeline 不會把錯誤文字當成正文。
- Restore 只在支援的資料或偏好確實有合法可還原內容時回報成功，同時保留合法空集合／空設定的備份語意。
- App update 略過空值、非 HTTP(S) 與非 APK asset，儲存前正規化下載 URL 的前後空白。
- CacheManager 對舊命名檔進行一次性清理，跨 isolate 同時刪除時容忍「已不存在」競態，其他 I/O 錯誤仍會傳出。
- 書架 refresh／initialize、章節正文 in-flight identity／reset、LRU 計量、速率限制切換、TTS 首分鐘到期與換源作者關閉模式的競態與邊界已收旂。

### Source Manager

- 新增／編輯書源只在儲存成功後回傳 changed 並 reload，取消不做額外查詢，失敗保留編輯頁與可見錯誤。
- toggle 在 DAO await 後依 URL 重新定位，不使用過期 index；批次、單筆、匯入、清理、檢查與群組異動共用 mutation-busy 契約。
- loading／check／mutation 期間的新增、重新命名、刪除、分享、toggle 與工具列會正確停用，避免讀到逐筆群組異動中的混合快照，重複觸發也不再靜默關閉或遺失 Future 錯誤。
- 篩選、域名分組、非手動排序與倒序顯示都不允許將可見順序誤寫回全域 `customOrder`。
- 使用中的群組改名會同步更新 filter；批次選取在延遲操作期間保留新選取狀態。
- 剪貼簿門檻改依 UTF-8 bytes 計算，過大時切換為檔案分享；剪貼簿、分享與 debug 日誌只在 await 成功後回報成功。
- 選取與規則小幫手的點擊區達 48dp，具有穩定 label、button／checked 狀態與 tap action，新測試直接檢查 Flutter semantics tree。
- debug provider 在 pending 期間 dispose 後不再收日誌或 notify listeners；新測試實際留住 Future 再 dispose，不是假綠。

## 獨立強審

四個實作分支完成後，再分別以唯讀 reviewer 複核 Reader／App Shell、Engine／Data、Services 與 Source Manager。強審找到並在交付前修正的重要問題包含：

- P1：redirect 把 host-only Cookie 儲存到另一個 origin。
- P1：TXT parser 為全文每個 code unit 建立 offset list，50 MB ASCII 可額外接近 400 MB。
- P2：malformed UTF-8 chunk 重編碼錯位、AppCache hash 碰撞、JS dispose async gap、不安全匯出檔名。
- P2：Source Manager 倒序／篩選 reorder、busy 契約、過期 index、UTF-8 門檻、async 錯誤與 semantics 測試可信度。
- P2：下載併發加入、`data-charset`、越過 EOF、還原假成功、APK URL 空白與 legacy cache 跨 isolate 競態。
- Reader／App Shell 的 const compile 錯誤、SemanticsHandle 洩漏、fake-async 測試卡住、排版 dirty ownership 與微小 movement dead zone。

所有上述 finding 均有 production 修正與針對性回歸測試；最終沒有未解的 P0、P1 或 P2。

## 驗證

驗證環境：Flutter 3.44.0，Dart 3.12.0（WSL `/home/benny/flutter`）。

- `dart format`：151 個本批 Dart 檔案，0 個需再格式化。
- 核心層聚焦測試：494／494 通過。
- 功能／UI／頂層整合聚焦測試：382／382 通過。
- `flutter analyze`：0 issues。
- 完整 `flutter test --no-pub`：927／927 通過。
- `git diff --check`：通過。

測試實際執行了 QuickJS async／dispose、HTTP redirect／Cookie origin、malformed UTF-8 大檔分塊、《西遊記》本地 TXT 首中末章節位元組整合、Reader 壓力／fuzz、widget semantics 與各類 async 競態，沒有以 skip 或弱化 assertion 取得通過。

## 已知裝置層驗證邊界

以下屬於平台或實機整合，本次只能以結構、狀態與錯誤路徑自動化驗證，不宣稱已完成實機測量：

- Android Clipboard／Binder 實際上限與 SharePlus 檔案分享。
- TalkBack／VoiceOver 的朗讀語順與焦點移動。
- 平台 TTS 音色／定時器整合、WebView 互動驗證、外部 URL launcher。
- 極端超長書源名稱在不同檔案系統的 component-length 上限。路徑 traversal、分隔字、常見非法字元與 ASCII control characters 已阻擋。

## Atlas 影響

本批只修正現有模組內的狀態、驗證、併發、可達性與錯誤回饋；沒有新增模組、改變所有權、修改公開契約或改寫導覽邊界，因此 `docs/night_reader_index.md` 與各模組 Atlas 無需更新。

## 完成紀錄

- 本次沒有 commit、push、tag 或發佈；修正保留在目前 worktree。
- 沒有移除或弱化既有測試，也沒有吞掉非預期例外。
- 本文件由 planning 歸檔到 completed，作為本批修正、強審與驗證的單一交付紀錄。
