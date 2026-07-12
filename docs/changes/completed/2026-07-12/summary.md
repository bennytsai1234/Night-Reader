# 2026-07-12 工作摘要

- [reader-bottom-menu-scrub-redesign](reader-bottom-menu-scrub-redesign.md) — 閱讀器底部選單重整：主列 5→4 顆（換源移入進階設定）、自動翻頁速度移入進階設定並把下限 8%→2%、拖動條改為章內進度十等份（跨檔位即時預覽、180ms 防抖、放開落定存進度）；analyze/test 全過，待真機回歸。
- [single-phase-native-splash](single-phase-native-splash.md) — 開機畫面改一段式：移除 Flutter 端 `splash_landscape.png` 大圖轉場（main_page.dart 狀態機刪除），原生 splash 改主題色純色底（亮 #F4EFE3／暗 #1A1612）+ Android 12+ 手寫 AVD 動畫圖示（書本描邊 + 彎月 + 星星，1000ms），preserve 撐到書架首批載完（900ms 最短／2s 逾時）才放行首幀；刪 splash_landscape/splash_transparent 資產；analyze/test（722）全過，AVD 效果待 GitHub Actions APK 真機確認。
