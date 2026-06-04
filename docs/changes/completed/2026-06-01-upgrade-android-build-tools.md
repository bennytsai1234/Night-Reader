# 升級 Android 構建工具版本

## 任務類型
Config + Dependency（T1）

## 確認的之前
- `flutter_native_splash:2.2.16` 編譯失敗：Java 找不到 `android.os.Build`
- Gradle 8.11.1（需 ≥ 8.14.0）
- AGP 8.9.1（需 ≥ 8.11.1）
- Kotlin 2.1.0（需 ≥ 2.2.20）
- NDK 27.0.12077973（jni 套件需 28.2.13676358）

## 確認的之後
- `flutter_native_splash` 升至 `^2.4.8`（已修復 Build 編譯錯誤）
- Gradle 升至 8.14.0
- AGP 升至 8.11.1
- Kotlin 升至 2.2.20
- NDK 升至 28.2.13676358

## 預期檔案範圍
- `pubspec.yaml`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/settings.gradle.kts`
- `android/app/build.gradle.kts`

## 驗證步驟
推 tag 後確認 GitHub Actions `android-release.yml` 構建通過

## 回退路徑
若新版本引入破壞性變更，將各版本固定回原值並重新推送
