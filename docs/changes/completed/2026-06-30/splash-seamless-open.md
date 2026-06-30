# 無縫品牌開啟方案（點圖示 → 動畫 → 書架）

- 日期：2026-06-30
- 層級：T2（foundation 啟動路徑 + Android 原生資源）
- 狀態：**已實作；本機無 Flutter SDK，analyze/test 未能執行（見「驗證狀態」）**

## 目標

讓「點圖示 → 系統 splash → 品牌動畫頁 → 書架」成為一條無縫品牌動線，消除系統 splash 與品牌頁之間的圖示換圖、退場空白幀，並縮短熱啟動停留。

## 已定決策（使用者拍板）

1. 圖示接力＝**品牌頁對齊系統圖示**（不改桌面/launcher 圖示，接受深棕底板，讓 Flutter splash 與系統 splash 圖示同源同形）。
2. Android <12 開場：純色求一致 —— 實查發現 `drawable*/background.png` 皆為 **70 bytes 的純色 PNG**（flutter_native_splash 產生），**<12 早已是純色**，無需改 `launch_background.xml`，決策自動滿足。
3. 退場：純 fade（不縮放）。
4. 書架首幀骨架：先不加（`BookshelfProvider` 於 `runApp` 即建構並 `loadBooks()`，開機即背景載書，首幀多半已有資料）。

## 實作內容（逐檔）

### `lib/features/welcome/splash_page.dart`
- **圖示一致化**：`_IconWithArc` 由「`app-icon.png`＋圓角矩形 r24＋恆顯陰影」改為「**圓形遮罩＋`#1A1612` (AppPalette.ink600) 不透明底板＋`assets/app_icon/ic_foreground.png` (inset 16%)**」，與 adaptive icon / 系統 splash 圖示同源同形同底板。底板直徑 `_plate=120`（對齊系統 splash 視覺尺寸的初值，可實機微調）。
- **去除重複 zoom**：移除 `_iconScale`(1.12→1.0) 與 `_iconOpacity`；圖示第一幀 scale 固定 1.0、置中（接住系統收尾），僅保留 breath 微縮放。
- **陰影淡入**：新增 `_shadowOpacity`，第一幀無陰影、隨定格結束淡入（系統 splash 圖示無投影，避免接力跳階）。
- **動線改「中央展開」**：`iconRise` 由螢幕高 16% 降到 **8.5%**，使第一幀落在螢幕中央、再上滑歸位；arc 環在約 120ms 定格後才掃出。
- **時序壓短**：進場 `_entranceController` 1400ms → **1050ms**，各 `Interval` 重新錨定（定格 0.12 起 → arc/陰影 → 圖示上移 → 標題 → 分隔線 → tagline → 狀態列 0.92 收）。
- **退場單一轉場**：移除 `_exitController`/`_exitFade`/`_exitScale`、180ms 延遲、0.93 縮放與雙段淡入淡出；改為直接 `pushReplacement` 單段 **320ms fade**（書架於同底色上純淡入蓋過品牌頁，無空白幀）。
- **gating 不變但更短**：沿用 `max(進場播完, initEssential 完成)`，淨開場 1400+~1010ms ≈ 2.4s → **1050+320ms ≈ 1.25s**。

### `pubspec.yaml`
- assets 新增 `assets/app_icon/ic_foreground.png`（原僅供 flutter_launcher_icons 在 build 期使用、未進 Flutter 資產包；品牌頁 `Image.asset` 需要它）。

### `android/app/src/main/res/values-v31/styles.xml`
- light `windowSplashScreenIconBackgroundColor` `#F4EFE3` → **`#1A1612`**，與不透明 adaptive 底板同色，消除圓遮罩邊緣奶白殘邊。（dark v31 本已 `#1A1612`。）

### `flutter_native_splash.yaml`
- `android_12.icon_background_color` `#F4EFE3` → **`#1A1612`**（與 v31 styles 同步，保持 yaml 為單一真實來源；未重跑 generator，僅手動對齊）。

## 驗證狀態

- ⚠️ 本 session 環境**未安裝 Flutter SDK**（`android/local.properties` 無 `flutter.sdk`，磁碟無 flutter/dart），`flutter analyze`/`flutter test` **無法於本機執行**。
- CI `android-release.yml` 僅在 `v*` tag 觸發，且 analyze/test 範圍只含 `reader_v2`/`source_manager`，**不涵蓋 welcome**；唯 release `flutter build apk` 會整包編譯到本檔。
- 已做嚴格人工複查：移除欄位無殘留引用、collection-if 與 const 運算式合法、資產路徑存在、`AppPalette.ink600` 存在、無既有 welcome/splash 測試會被破壞。**判定可編譯，但未經編譯器證實。**
- 建議：於具 SDK 的機器執行 `flutter pub get && flutter analyze lib/features/welcome`（或整包 build）做最終確認；圖示 `_plate`/`iconRise` 於實機以截圖疊圖微調至「看不出換圖」。

## 回滾

純前端動畫 + 兩處 res/yaml 色值 + 一行 asset 註冊，無資料/schema 變更，`git revert` 單一 commit 即還原。
