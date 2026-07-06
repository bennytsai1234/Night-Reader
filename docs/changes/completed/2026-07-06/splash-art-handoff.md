# [COMPLETED] 啟動畫面改版：原生 splash 去圖標，全螢幕夜空藝術圖由 Flutter 轉場層接手

## Before

- 7/3 重繪的夜空藝術圖（`assets/splash_landscape.png`）只接到 `background_image`，該機制僅 Android 11 以下生效；Android 12+ 系統啟動畫面只能顯示純色底＋置中 App 圖示（平台硬限制，無法全螢幕鋪圖），使用者點開 App 只看到深棕底＋圖示，藝術圖從未出場。
- Flutter 端無任何啟動轉場：原生 splash 一路撐到書架首批書本載完直接交棒。

## After

- **原生 splash（Android 12+）**：`android_12.image` 塞全透明 960×960 圖（`assets/app_icon/splash_transparent.png`），中間不再有任何圖標，啟動瞬間是一片純深棕 `#1A1612`。
- **Flutter 轉場層**（`lib/features/welcome/main_page.dart`）：首幀以全螢幕夜空藝術圖（`BoxFit.cover`、同深棕底）覆蓋整個畫面；藝術圖預載完成即撤原生 splash（同底色無縫交棒），撐到書架首批書本載完（且至少顯示 1.2 秒，避免一閃而過）後 500ms 淡出到書架。保留 2 秒逾時保險。
- Android 11 以下維持原生全螢幕背景圖，之後同樣接 Flutter 轉場層，視覺一致。
- 測試注入 destinations 的路徑完全跳過轉場層與 platform channel，不影響既有 widget 測試。
- 重跑 `dart run flutter_native_splash:create` 重新生成各解析度 `android12splash.png`（含 night 變體）與 v31 styles。

## 決策備註

- 重開並取代 7/3「原生 splash 撤除後直接交棒書架、不經過場頁」的作法：因 Android 12+ 平台限制，全螢幕啟動圖只能由 Flutter 首幀繪製；使用者明確選擇「原生無圖標＋Flutter 全螢幕藝術圖轉場」。轉場不加人工等待（僅小於 1.2 秒時補足），書架載入期間本來就在等待。

## 驗證結果

- `flutter analyze`：No issues found。
- `flutter test test/features/welcome/`：8/8 通過。
- 全套 `flutter test`：僅 `reader_v2_viewport_window_stress_test.dart` 一項失敗，經 stash 對照確認該失敗來自另一工作階段未提交的新測試（工作樹中的並行 WIP），與本變更無關；HEAD＋本變更下 welcome 全數通過。
