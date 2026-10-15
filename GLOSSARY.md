# 夜讀 Night Reader

Android 小說閱讀器：從使用者自行匯入的書源搜尋、閱讀、下載網路小說，也能閱讀本地 TXT。

## Language

**夜讀**：
這個 App。程式套件名是 `night_reader`，英文名是 Night Reader。Android 的 applicationId、namespace（`com.inkpage.reader`）與簽章檔名（`inkpage-release.jks`）沿用舊名 inkpage，改掉會讓已安裝的使用者無法升級。
_Avoid_: InkPage、inkpage reader

**測試版**：
維護者手動觸發時，把 `main` 上一個發布之後累積的改動發成的 GitHub 預發布版，tag 形如 `v0.3.4-beta.2`（ADR 0004、0014）。和正式版是同一個 App，使用者在「關於」打開「接收測試版更新」才會收到。
_Avoid_: beta 分支、預覽版、nightly

**換頁動畫**：
App 裡所有換頁共用的轉場，使用者在「外觀與主題」的選單從八種選一種（`AppPageTransition`）：上浮、平移（預設，Telegram iOS）、俐落平移（Telegram iOS 26）、滑入（Telegram Android）、推進（Android 系統）、覆蓋（Legado）、縮放（Material 共享 Z 軸）、展開（iOS 18 縮放）。返回不是開啟倒著播，一律先快後慢；往右拖返回與點主頁分頁也照選的那一種（ADR 0020）。
_Avoid_: 轉場效果、頁面動畫、Hero（封面共享元素轉場已移除）

**更新紀錄**：
「關於夜讀」裡列出各版更新說明的頁面（`ReleaseNotesPage`），資料來自 GitHub Releases；有開「接收測試版更新」才含測試版。更新後不會主動跳出。
_Avoid_: 更新日誌、changelog（指這個頁面時）、這次更新了什麼

**更新說明**：
每一版寫給一般讀者看的中文改動說明，維護在 `CHANGELOG.md`：`## 未發布` 是測試版的說明，`## X.Y.Z` 是正式版的說明（ADR 0010）。CI 發版時拿來當 GitHub Release 說明，更新視窗與更新紀錄顯示的就是它。
_Avoid_: 更新日誌、commit 標題

**書源**：
一份 JSON 規則，描述某個網站怎麼搜尋、怎麼取得書籍詳情、目錄與正文（`BookSource`）。格式相容 Legado 3.0，App 不內建任何書源。
_Avoid_: 來源、站點、source（不指明時）

**書架自動下載**：
書架上的網路書自動整本下載，新章節也跟著下載；不限網路、沒有開關（ADR 0008，`DownloadService.keepShelfBookDownloaded`）。和使用者在書籍詳情或多選工具列手動加入的下載不同：自動下載不會排回使用者暫停的任務，失敗後依重試規則再試。
_Avoid_: 預下載（那是手動選範圍的下載）、自動快取

**風格**：
一套同時套到 App 介面、閱讀正文與閱讀選單的配色，各有淺色與深色（`AppStyle`）。使用者在「外觀與主題」或閱讀器的「外觀與排版」選。
_Avoid_: 主題（指配色組時）、閱讀主題、皮膚

**強調色**：
開關、選取、勾勾、強調按鈕與純文字動作用的顏色，也就是主色（`AppAccent`）。預設「跟隨主題」，用風格自己的主色；其他顏色各有一個淺色、一個深色版本，不分風格。
_Avoid_: 按鈕顏色、主題色（指使用者選的顏色時）、自訂色

**Reader V2**：
現行的閱讀器（`lib/features/reader_v2/`），負責分頁、排版、閱讀進度與閱讀選單。
_Avoid_: 新閱讀器、reader

**字格**：
正文排版的寬度單位，一個漢字（含字距）的寬度。漢字、全形標點與 emoji 各佔一格；連續的英文、數字與半形符號合成一段，佔半格的整數倍（ADR 0007）。
_Avoid_: em 網格

**Layout signature**：
由段落寬度與排版樣式（字級、行高、字距、段距、縮排、粗體等）算出的雜湊（`ReaderV2LayoutSpec.layoutSignature`）。兩次排版的 signature 相同，就代表可以沿用同一份排版與量測快取。
_Avoid_: layout key、排版版本
