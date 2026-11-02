# 交接（2026-11-01）

分支上的工作（含還沒開工的計畫）寫在各分支自己的 `HANDOFF.md`，`git branch -a` 列出所有分支；這裡只寫 `beta` 的事。

## 這條分支：多台手機同步第 3 段，Google 雲端硬碟（ADR 0039）

第 1、2 段已合併（#194、#199）。第 4 段（本地書）是 #193，這段做完再和使用者討論。

- 程式已寫：`GoogleSignInDriveAuth`（`google_sign_in` 7）、`GoogleDriveSyncStore`（Drive REST v3、`appDataFolder`）、「同步空間」頁（Google 雲端硬碟／WebDAV，Google 只在 Android）。
- Google Cloud 登記（用使用者平常的瀏覽器 Ego Lite，已登入 bennytsai0711@gmail.com；`ego-browser` 技能，工作空間「夜讀 Google 雲端硬碟登記」）：
  - 已做：建專案 Night Reader Sync（`night-reader-sync`）、啟用 Google Drive API、同意畫面填好（名稱夜讀、對象外部、聯絡信箱）。
  - 等使用者：勾選《Google API 服務：使用者資料政策》→ 繼續 → 建立（用使用者帳號接受條款，交給使用者點；已 `handOff`）。
  - 之後：發布到正式（`drive.appdata` 不敏感，不用送審）；建 Android 用戶端（套件 `com.inkpage.reader`、正式簽章 SHA-1 `B1:73:C4:CF:B5:A2:9D:87:34:A4:A7:E7:42:BC:3D:BB:94:F5:96:B3`，從 v0.3.8-beta.73 的 APK 用 apksigner 讀）與網頁用戶端；網頁用戶端編號填進 `GoogleSignInDriveAuth.serverClientId`。

## 先不做

- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。
- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate：讓量動畫時主執行緒不含資料庫的工作。試過，卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接。試的分支已經不在。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
- Legado 有、夜讀沒有的其他功能逐項分析開成 issue #181–#191（高亮規則、AI 輔助、評分、段評、聽書源、漫畫、網頁服務、MCP、訂閱源、分頁翻頁、眼動翻頁），使用者之後自己挑著做。
