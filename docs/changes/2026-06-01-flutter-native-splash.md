# 2026-06-01 flutter-native-splash 整合

## 任務類型
Dependency + Config（T1）

## 確認的之前
- `launch_background.xml` 硬寫 `@android:color/white`，light mode 與 Flutter scaffold `#F4EFE3` 不符，冷啟動會閃白
- 無 `drawable-night/launch_background.xml`，dark mode 原生 splash 仍為純白，接著 Flutter 渲染深色背景，顏色跳躍極大
- Android 12+ SplashScreen API 未處理
- 無 `preserve()`，引擎初始化期間原生 splash 一結束即消失，可能出現空白幀

## 確認的之後
- `flutter_native_splash` 自動生成 light（`#F4EFE3`）/ dark（`#1A1612`）四份 launch_background.xml
- `preserve()` 在 `main.dart` 啟動時持住原生 splash；`remove()` 在 `SplashPage.initState()` 呼叫，原生 splash 退出與 Flutter 進場動畫同時開始
- 原生 splash 純色背景（不含 icon），消除 icon 消失再重現的跳躍感
- Android 12+ 系統 SplashScreen 背景色對齊，套件處理退出動畫

## 預期檔案範圍
- `pubspec.yaml`：新增 `flutter_native_splash` 至 dependencies
- `flutter_native_splash.yaml`（新建）
- `lib/main.dart`：capture widgetsBinding、加 preserve()
- `lib/features/welcome/splash_page.dart`：initState() 加 remove()
- 自動生成（flutter_native_splash:create）：
  - `android/app/src/main/res/drawable/launch_background.xml`
  - `android/app/src/main/res/drawable-v21/launch_background.xml`
  - `android/app/src/main/res/drawable-night/launch_background.xml`（新）
  - `android/app/src/main/res/drawable-night-v21/launch_background.xml`（新）
  - `android/app/src/main/res/values/styles.xml`
  - `android/app/src/main/res/values-night/styles.xml`
  - 色碼 resource 檔

## 驗證步驟
1. `flutter pub get` 成功
2. `dart run flutter_native_splash:create` 成功，drawable-night/ 目錄出現
3. `flutter analyze` 通過
4. 安裝 apk 冷啟動：light mode 無白閃、dark mode 無白閃

## 回退路徑
1. 移除 `flutter_native_splash` 依賴
2. 恢復 `main.dart` 和 `splash_page.dart` 變更
3. 恢復原始 XML（git checkout）
