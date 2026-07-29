# APK 體積第一階段瘦身

## 現況

- arm64 release APK 在移除 ML Kit 後的實測基線為 31.71 MiB。
- `assets/app_icon/ic_foreground.png` 與 `assets/app-icon.png` 合計約 2.18 MiB，皆被打入 Flutter runtime assets；前者沒有 runtime 使用，後者只在設定頁以小尺寸顯示。
- `drift_flutter` 沒有任何 runtime import。
- CI 只產生 APK，沒有保存 Flutter `--analyze-size` 報告。

## 目標

- 保留 launcher icon 原圖作為建置輸入，但不再放進 Flutter runtime assets。
- 產生小尺寸 WebP 供設定頁使用，維持畫面外觀。
- 移除未使用的 `drift_flutter` 直接依賴並更新 lockfile。
- 讓 Android release CI 產生並保存 size-analysis JSON，供後續分析 `libapp.so`。

## 驗證

- WebP 為 256×256 lossless WebP、69,372 bytes；已與來源圖視覺比對。
- `flutter analyze`：通過，無問題。
- `flutter test`：758 項測試全數通過；設定頁 asset 聚焦測試另行通過。
- pub dependency graph 已不含 `drift_flutter`、`sqlite3_flutter_libs`、`sqlcipher_flutter_libs`。
- workflow YAML 解析成功；CI 實際 size artifact 留待推送後的 workflow 驗證。

## 邊界

- 不啟用 R8／resource shrinking；待第一階段真實產物完成後另案評估。
- 不更動 launcher icon 的品牌圖、Android application ID 或發布觸發條件。

## 結果

- runtime icon assets 由 2,228 KiB 降為 67.7 KiB，靜態淨減少 2.110 MiB。
- launcher icon 原始 PNG 與已產生的 Android mipmap/drawable 均保留。
- `--analyze-size` 報告將以 `night-reader-code-size-<ref>` workflow artifact 保存 30 天。
- 本次未改變模組邊界、所有權或外部 API，Atlas 文件無需更新。
