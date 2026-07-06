# [COMPLETED] 啟動轉場重設計：消除「棕色→夜空圖」硬切割裂感

## Before

- v0.2.124 的啟動流程：原生 splash 是深棕 `#1A1612` 純色，藝術圖預載完成後瞬間整張出現。棕色與畫面深紫色調不搭、又是硬切，體感割裂。

## After

- **底色統一改為深紫 `#261940`**（程式取樣藝術圖天空區的平均色），所有 Android 版本的原生 splash 一致（同時移除 Android 11 以下的 `background_image`，避免舊機「原生已見圖→Flutter 又重播淡入」的反效果）。
- **藝術圖改為浮現而非硬切**：原生 splash 撤除後，藝術圖在同色底上以 700ms 淡入＋1100ms 輕微縮放（1.06→1.0）亮起；至少顯示 1.6 秒，書架載完後 500ms 淡出。整段時序：深紫夜色 → 夜空畫面浮現 → 淡出見書架，全程漸變。

## 變更檔案

- `flutter_native_splash.yaml`：改純色 `#261940`、移除 background_image；重跑 `dart run flutter_native_splash:create`。
- `lib/features/welcome/main_page.dart`：轉場層底色改深紫、加入 `_splashArtShown` 淡入＋縮放浮現動畫、最短顯示 1.6s。

## 驗證結果

- `flutter analyze`：No issues found。
- `flutter test test/features/welcome/`：8/8 通過。
