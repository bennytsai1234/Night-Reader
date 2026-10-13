# 夜讀 Night Reader

Android 小說閱讀器：從使用者自行匯入的書源搜尋、閱讀、下載網路小說，也能閱讀本地 TXT。

## Language

**夜讀**：
這個 App。程式套件名是 `night_reader`，英文名是 Night Reader。Android 的 applicationId、namespace（`com.inkpage.reader`）與簽章檔名（`inkpage-release.jks`）沿用舊名 inkpage，改掉會讓已安裝的使用者無法升級。
_Avoid_: InkPage、inkpage reader

**測試版**：
CI 在每次推上 `main` 後發的 GitHub 預發布版，tag 形如 `v0.3.4-beta.2`（ADR 0004）。和正式版是同一個 App，使用者在「關於」打開「接收測試版更新」才會收到。
_Avoid_: beta 分支、預覽版、nightly

**更新紀錄**：
「關於夜讀」裡列出各版更新說明的頁面（`ReleaseNotesPage`），資料來自 GitHub Releases；有開「接收測試版更新」才含測試版。更新後不會主動跳出。
_Avoid_: 更新日誌、changelog（指這個頁面時）、這次更新了什麼

**更新說明**：
每一版寫給一般讀者看的中文改動說明，維護在 `CHANGELOG.md`：`## 未發布` 是測試版的說明，`## X.Y.Z` 是正式版的說明（ADR 0009）。CI 發版時拿來當 GitHub Release 說明，更新視窗與更新紀錄顯示的就是它。
_Avoid_: 更新日誌、commit 標題

**書源**：
一份 JSON 規則，描述某個網站怎麼搜尋、怎麼取得書籍詳情、目錄與正文（`BookSource`）。格式相容 Legado 3.0，App 不內建任何書源。
_Avoid_: 來源、站點、source（不指明時）

**書架自動下載**：
書架上的網路書自動整本下載，新章節也跟著下載；不限網路、沒有開關（ADR 0007，`DownloadService.keepShelfBookDownloaded`）。和使用者在書籍詳情或多選工具列手動加入的下載不同：自動下載不會排回使用者暫停的任務，失敗後依重試規則再試。
_Avoid_: 預下載（那是手動選範圍的下載）、自動快取

**Reader V2**：
現行的閱讀器（`lib/features/reader_v2/`），負責分頁、排版、閱讀進度與閱讀選單。
_Avoid_: 新閱讀器、reader

**Layout signature**：
由段落寬度與排版樣式（字級、行高、字距、段距、縮排、粗體等）算出的雜湊（`ReaderV2LayoutSpec.layoutSignature`）。兩次排版的 signature 相同，就代表可以沿用同一份排版與量測快取。
_Avoid_: layout key、排版版本
