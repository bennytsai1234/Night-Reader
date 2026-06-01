# 2026-06-01 | epub：epubx → archive+xml 自製解析器

## 任務類型
Dependency（套件替換）

## 確認的之前
`epubx: ^4.0.0` 依賴 `image: ^3.0.8`，`flutter_native_splash: ^2.4.x` 要求 `image: ^4.5.4`，兩者不可共存。
`flutter_native_splash` 已從 pubspec.yaml 移除；`main.dart` / `splash_page.dart` 的 `preserve()`/`remove()` 呼叫遺失。

## 確認的之後
移除 `epubx`；在 `epub_service.dart` 用 `archive` + `xml`（均為既有依賴）實作輕量 EPUB 解析器；加回 `flutter_native_splash: ^2.4.8`；恢復四個 Dart 呼叫。

## 預期的檔案範圍
- `pubspec.yaml` — 移除 epubx，新增 flutter_native_splash
- `lib/core/services/epub_service.dart` — 全部重寫（公開 API 不變）
- `lib/main.dart` — 恢復 import + preserve()
- `lib/features/welcome/splash_page.dart` — 恢復 import + remove()

## 驗證步驟
1. `flutter pub get`（確認無 image 版本衝突）
2. `flutter analyze`
3. `flutter test test/core/services/epub_service_test.dart`

## 回退路徑
`git revert`；或重新加回 `epubx: ^4.0.0` 並移除 `flutter_native_splash`。
