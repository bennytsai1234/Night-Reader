# 夜讀 Night Reader

Android 小說閱讀器：從使用者自行匯入的書源搜尋、閱讀、下載網路小說，也能閱讀本地 TXT。

## Language

**夜讀**：
這個 App。程式套件名是 `night_reader`，英文名是 Night Reader。Android 的 applicationId、namespace（`com.inkpage.reader`）與簽章檔名（`inkpage-release.jks`）沿用舊名 inkpage，改掉會讓已安裝的使用者無法升級。
_Avoid_: InkPage、inkpage reader

**書源**：
一份 JSON 規則，描述某個網站怎麼搜尋、怎麼取得書籍詳情、目錄與正文（`BookSource`）。格式相容 Legado 3.0，App 不內建任何書源。
_Avoid_: 來源、站點、source（不指明時）

**Reader V2**：
現行的閱讀器（`lib/features/reader_v2/`），負責分頁、排版、閱讀進度與閱讀選單。
_Avoid_: 新閱讀器、reader

**Layout signature**：
由段落寬度與排版樣式（字級、行高、字距、段距、縮排、粗體等）算出的雜湊（`ReaderV2LayoutSpec.layoutSignature`）。兩次排版的 signature 相同，就代表可以沿用同一份排版與量測快取。
_Avoid_: layout key、排版版本
