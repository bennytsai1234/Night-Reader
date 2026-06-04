# Adaptive icon（棕底）+ Splash 接位優化

## 任務類型

Dependency + Config + 行為變更（T2）：新增 adaptive launcher icon 消除 vivo 開啟動畫白板，並調整 Flutter SplashPage 進場以對齊「點擊放大」的位置/可見性。

## 背景

vivo（及現代桌面）對「無 adaptive icon」的 app 會自動墊一塊白色圓角板 → 開啟動畫出現白框。且放大結束時品牌圖置中、可見，但 Flutter SplashPage 的品牌圖在上半部、且從 `opacity:0`、`scale:0.55`、上滑 32px「彈入」→ 產生位置與可見性的割裂。splash 底色維持原本（淺米 / 深棕，按日夜），**不改 flutter_native_splash 設定**。

## 確認的之前

- 無 adaptive icon（無 `mipmap-anydpi-v26/`），僅舊式 `ic_launcher.png` → 白板。
- SplashPage 品牌圖：`_iconOpacity` 0→1、`_iconScale` 0.55→1.0(easeOutBack)、`_iconTranslateY` 32→0，位於版面上半部 → 接不住放大。

## 確認的之後

1. **Adaptive icon = 深棕 `#1A1612` 底板 + 品牌圖置中**（等比、不變形、不裁切；四角微圓貼合現有觀感）。vivo 改用它、白板消失；放大全程在深色模式為棕色連續。
2. **SplashPage 採方案 2（置中起步→歸位）**：品牌圖第一幀即可見（opacity 從 1 起）、由接近畫面中央的位置（接住放大）平滑上滑歸位、scale 由略大收到 1.0（取代原本從 0.55 彈入）。保留原構圖。

## 預期檔案範圍

- 新增 `assets/app_icon/ic_foreground.png`（品牌圖 72% 置中、圓角、透明邊；adaptive 前景）。
- `pubspec.yaml`：dev_dependencies 新增 `flutter_launcher_icons` + 設定區塊（`adaptive_icon_background:#1A1612`、`adaptive_icon_foreground:該前景圖`、`image_path:assets/app-icon.png`、`min_sdk_android:24`）。
- 生成（`dart run flutter_launcher_icons`）：`mipmap-anydpi-v26/ic_launcher.xml`(+round)、各密度前景圖、`values/colors.xml` 的 `ic_launcher_background`、更新 legacy `ic_launcher.png`。
- `lib/features/welcome/splash_page.dart`：`_iconOpacity`/`_iconScale`/`_iconTranslateY` 進場調整（含以 MediaQuery 推導歸位距離，常數可調）。

## 驗證步驟

- `flutter pub get` 成功；`dart run flutter_launcher_icons` 成功；`mipmap-anydpi-v26/ic_launcher.xml` 出現且指向棕底 + 前景圖。
- `flutter analyze` 通過。
- ⚠ **僅能驗證生成檔與 analyze**。實際「桌面無白板、放大→splash 接位順暢」必須**在 vivo 安裝 APK 冷啟動確認**；前景縮放(72%)、歸位距離、scale 起點等為可調參數，需實機微調。

## 已知取捨

- adaptive 底板固定深棕 `#1A1612`：深色模式下與 splash/系統 splash 全程棕色連續；**淺色模式**桌面圖示為棕板、splash 為米色，放大→splash 會有色差（使用者已接受淺色模式色差）。

## 回退路徑

- `git checkout` 還原 `pubspec.yaml`、`splash_page.dart`、生成的 mipmap/anydpi/colors 資源；刪除 `assets/app_icon/ic_foreground.png`。移除 `flutter_launcher_icons` dev 依賴。
