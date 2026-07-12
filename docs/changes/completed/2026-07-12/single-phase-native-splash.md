# 一段式原生啟動畫面（純色 + AVD 動畫圖示）

## Before

- 開機為二段式：原生純紫 splash（`#261940`，flutter_native_splash 產生）→ Flutter 首幀後
  `main_page.dart` 的轉場層讓 `assets/splash_landscape.png`（約 800KB）淡入、撐到書架首批書
  載完再淡出，狀態機約 100 行。
- 使用者要求改為一段式：整個開機只有一層原生畫面，不要 Flutter 端大圖轉場。

## After

- **原生層**：`flutter_native_splash.yaml` 改為主題色純色底——亮 `#F4EFE3`（paper200）、
  暗 `#1A1612`（ink600），與書架 scaffold 背景一致，硬切交棒無跳色。Android 12+ 的
  `windowSplashScreenAnimatedIcon` 指向手寫 AVD（`drawable/splash_icon_avd.xml` +
  `drawable-night` 變體）：書本線稿 trimPath 展開、彎月升起淡入、三顆星星錯落閃現，約 1000ms。
  Android 11 以下維持純色（windowBackground 無法播動畫）。
- **Flutter 層**：`main.dart` 的 `FlutterNativeSplash.preserve()` 保留（延後首幀 = 撐住原生層）；
  `main_page.dart` 刪除藝術圖 overlay 與狀態機，改為「書架首批載完（或 2s 逾時）→ 補足最短
  顯示時間（讓圖示動畫播完）→ `FlutterNativeSplash.remove()` 放行首幀」。
- **清理**：刪 `assets/splash_landscape.png`、`assets/app_icon/splash_transparent.png` 與
  generated `android12splash.png`；yaml 註記重跑 create 後需手動加回 styles 的 icon 兩行。
- **驗證**：`flutter analyze`、`flutter test`；AVD 無法本機 build 目測，另以 HTML/SVG 重現
  動畫供使用者預覽；APK 實測交 GitHub Actions。

## 風險

- 延後首幀期間畫面由原生層把持：保留 2s 逾時保險，避免書架查詢異常卡開機。
- 原生 splash 跟隨「系統」深淺色而非 App 內主題設定；系統亮 + App 暗時交棒會有一次跳色
  （原生層先天限制，接受）。
- 重跑 `flutter_native_splash:create` 會覆寫 values-v31 styles，需手動補回 AVD 兩行
  （已在 yaml 註解記載）。
