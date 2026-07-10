# TXT-only reader content pipeline fixes

## Level

T2 — 跨 services、engine、reader、bookshelf、association 與公開文件的功能收斂及資料正確性修正。

## Decision

本地書入口、匯入服務與閱讀流程統一只接受 TXT。既有不支援格式的書架紀錄不自動刪除，開啟時提供明確錯誤。

## Before

- 本地匯入同時接受 TXT 與另一種封裝格式，但後者把標記內容直接送入純文字閱讀管線。
- 並發多頁正文會略過失敗頁，將殘缺內容視為成功並持久化。
- UTF-16LE／BE 雖可被辨識，實際仍以 UTF-8 解碼。
- 缺少正文規則、圖片標籤與純空白正文可能進入最終文字資料。
- 章名去重沒有尾端邊界，可能刪除正文合法前綴。
- 長段落可在 UTF-16 代理對中間切割。

## After

- 本地書檔案選擇、分享匯入、服務解析與文件只提供 TXT。
- 既有不支援格式在進入閱讀器前得到明確提示，資料保留供使用者自行刪除。
- 任一並發正文頁失敗即讓整章失敗，不保存殘缺正文。
- 正文規則輸出為純文字；缺少正文規則與純空白結果皆視為失敗。
- UTF-16LE／BE TXT 可正確建立目錄並按位元組範圍讀取。
- 章名去重要求合法尾端邊界；文字切割避開代理對。

## Work

1. 先加聚焦測試，覆蓋本地格式、UTF-16、正文清理、章名邊界與 Unicode block 切割。
2. 收斂本地書格式與既有書籍的開啟防線，刪除不再使用的解析／資源恢復程式。
3. 修正文規則、多頁抓取、空內容、編碼、章名與切割邏輯。
4. 增量更新架構地圖、README、開發文件與網站文案。
5. 執行格式化、聚焦測試、書源驗證、`flutter analyze` 與完整 `flutter test`。

## Verification Results

- 本次變更的 Dart 檔案已通過 `dart format`。
- 59 個聚焦管線測試、既有不支援格式防線測試與 11 個 hybrid reader screen 測試通過。
- 31 個書源驗證支援測試通過。
- `flutter analyze`：No issues found。
- `flutter test`：694 tests passed。
- 依專案規範未執行本地 build。

## Delivery

No commit。
