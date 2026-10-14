# Android 只發布 arm64-v8a，iOS 只附未簽章 IPA

夜讀的 Android 版只發布 `arm64-v8a` APK（`android-release.yml` 用 `--split-per-abi --target-platform android-arm64`）。

iOS：2026-10-10 曾移除 `ios/`，因為三個 fork 只剩 Android 實作、CI 也不建 iOS。2026-10-14 推翻這個決定，使用者要在 GitHub 上提供 iOS 版：重建 `ios/`（bundle id `com.inkpage.reader`），三個 fork 補回 iOS 實作，`android-release.yml` 在 APK 之後用 macOS 建一份未簽章的 IPA，發布時掛在同一個 Release，測試建置時存成 artifact。

不簽章，因為沒有 Apple 開發者帳號；有 iPhone 的人自己用 AltStore 或 Sideloadly 以 Apple ID 簽章安裝（免費帳號每 7 天要重簽）。開發者沒有 iPhone，iOS 版只保證 CI 建得起來。

## Consequences

- iOS 的 JS 引擎是系統的 JavaScriptCore（`flutter_js` 的 `getJavascriptRuntime()` 依平台選擇），Android 與測試用 QuickJS；書源 JS 在兩邊的行為差異沒有測試涵蓋。
- iOS 原生端只實作長按斷詞與電量（`ios/Runner/AppDelegate.swift`）。狀態列與挖孔高度不需要：iOS 隱藏狀態列時安全區域不變。App 內更新、分享進 App（需要 Share Extension）與用檔案開啟書籍（需要宣告文件類型）在 iOS 上沒有。
- iOS 建置失敗不會擋下 Android 發布：IPA 排在 APK 之後，Release 已經建立時只是少一個附件。
- 啟動畫面底色在 `ios/Runner/Assets.xcassets/LaunchBackground.colorset` 手動設定，`flutter_native_splash` 的 `ios` 維持 `false`，免得重跑時覆寫。
