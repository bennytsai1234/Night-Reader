# 移除標點子集字型與日文翻譯

層級：T2（跨 Reader、設定、服務、資產與相依套件）

## Before

- Reader V2 以 `NightReaderPunct.ttf` 強制破折號與省略號使用全形字格，並以排版快取簽名隔離量測結果。
- 日文自動翻譯包含 ML Kit 模型、偵測器、章節翻譯 pass、設定與偏好資料流。
- 簡繁轉換會用日文偵測器跳過日文段落。

## After

- 完整刪除 `NightReaderPunct.ttf`、產生工具、字型註冊、排版引用及舊快取簽名。
- 正文與標題回到平台系統字型 fallback；標點文字正規化保留。
- 完整刪除日文偵測、翻譯服務、章節 pass、模型設定 UI、偏好資料流、ML Kit 相依與測試。
- 簡繁轉換不再特判日文段落。

## 驗證

- `dart format`：完成。
- `flutter pub get`：完成，移除 `google_mlkit_translation` 與
  `google_mlkit_commons`。
- `flutter analyze`：0 issues。
- `flutter test`：758/758 通過。
- 搜尋確認 production/test/dependency 中無標點子集字型、日文翻譯或
  ML Kit translation 程式殘留。

## 完成紀錄

- 決策：依使用者確認完整移除兩條功能鏈，不保留相容開關或替代實作。
- 模組邊界：Reader Content 不再包含日文翻譯 pass；Services 不再擁有日文
  偵測與翻譯服務，相關 Atlas 文件已同步更新。
- 已知取捨：歧義寬度標點改由平台系統字型 fallback；簡繁轉換不再跳過
  含假名段落。
- 偏好儲存中的舊 key 不再有任何程式讀寫路徑，不新增一次性 migration。
