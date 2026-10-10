# 只發布 Android arm64-v8a，不維護 iOS

夜讀只發布 Android `arm64-v8a` APK（`android-release.yml` 用 `--split-per-abi --target-platform android-arm64`）。2026-10-10 移除了 `flutter create` 留下的 `ios/` 專案，`flutter_launcher_icons` 與 `flutter_native_splash` 的 `ios: false` 保留。理由是 `third_party/` 的三個 fork 只剩 Android 實作（ADR 0001），CI 也沒有 iOS 建置，留著 `ios/` 只會讓人以為可以建 iOS。

## Consequences

- 要支援 iOS，得用 `flutter create --platforms=ios .` 重建 `ios/`，並先替三個 fork 補回 iOS 實作。
