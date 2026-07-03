# [COMPLETED] 重新繪製開啟 App 的 Splash 啟動畫面

本計畫旨在更新「夜讀」的開啟啟動畫面（Splash Screen）。我們使用了一張全新繪製的夢幻夜空風景大圖，並將原本的魔法書、城堡、發光樹與彎月等經典品牌元素融合其中，在 Light 與 Dark 模式下均呈現一致的精美視覺體驗。

## 變更項目

### 1. 資產複製 (Assets)
- **[NEW]** 複製生成的 `splash_landscape_1783065815113.png` 至專案目錄：`assets/splash_landscape.png`

### 2. 設定檔修改 (Config)
- **[MODIFY]** `flutter_native_splash.yaml`
  - 移除原有的純色設定，改為指向 `background_image` 與 `background_image_dark` 為新生成的 `assets/splash_landscape.png`。
  - 調整 Android 12+ 的 `color` 與 `color_dark` 設定，對齊新風景圖的深棕色調，以確保 Android 12 系統原生啟動圖的和諧度。

### 3. 原生資產生成 (Generation)
- 執行 `dart run flutter_native_splash:create` 重新產生 Android 各解析度的 Splash 相關資源檔案（Drawable 等）。

### 4. 版本控制 (Release)
- 將 `pubspec.yaml` 版本號由 `0.2.122+136` 升級為 `0.2.123+137`。

---

## 驗證結果

### 自動化測試與靜態分析
- 在本機執行：
  - `flutter analyze` 確保專案語法與相依性正常。 (No issues found!)
  - `flutter test` 確保沒有任何測試因 Splash 變更而受影響。 (661 tests passed!)
